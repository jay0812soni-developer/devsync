import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../core/crypto/device_identity.dart';
import '../../../core/crypto/e2ee_cipher.dart';
import '../../../core/network/persistent_ws_client.dart';
import '../../../core/network/relay_api_service.dart';
import '../../../core/network/sse_relay_client.dart';
import '../../../core/network/webrtc_service.dart';
import '../../../core/storage/database_service.dart';
import '../../../core/storage/file_categorizer.dart';
import '../../../core/storage/io_file.dart';
import '../../../core/storage/local_file_manager.dart';
import '../../devices/domain/device_model.dart';
import '../../devices/presentation/device_providers.dart';
import '../domain/message_model.dart';

class ChatNotifier extends StateNotifier<List<MessageModel>> {
  final Ref _ref;
  final E2eeCipher _cipher = E2eeCipher();
  StreamSubscription? _sseSub;
  StreamSubscription? _wsSub;
  StreamSubscription? _webrtcSub;

  ChatNotifier(this._ref) : super([]) {
    _initMessageListeners();
  }

  void _initMessageListeners() {
    // 1. Persistent WebSocket incoming message receiver
    _wsSub = PersistentWsClient.instance.incomingMessageStream.listen((data) {
      _handleIncomingRawPayload(data, isFromLan: false);
    });

    // 3. WebRTC direct DataChannel incoming message receiver
    _webrtcSub = WebRtcService.instance.incomingDataStream.listen((event) {
      final payload = event['payload'] as Map<String, dynamic>?;
      if (payload != null) {
        _handleIncomingRawPayload(payload, isFromLan: true);
      }
    });

    // 4. Vercel SSE message receiver (legacy fallback)
    _sseSub = SseRelayClient.instance.onMessageReceived.listen((data) {
      _handleIncomingRawPayload(data, isFromLan: false);
    });
  }

  /// Reloads message list for the active conversation
  Future<void> loadConversation(String peerDeviceId) async {
    final myDevice = _ref.read(myDeviceProvider).identity;
    if (myDevice == null) return;
    final messages = DatabaseService.instance.getMessagesForConversation(myDevice.deviceId, peerDeviceId);
    state = messages;
    await DatabaseService.instance.clearUnread(peerDeviceId);

    final peers = _ref.read(peersProvider);
    DeviceModel? peer;
    for (final p in peers) {
      if (p.id == peerDeviceId) peer = p;
    }
    if (peer == null) {
      _touch();
      return;
    }

    for (final message in messages) {
      if (!message.isOutgoing && message.status != MessageStatus.read && !message.isDeleted) {
        final read = message.copyWith(status: MessageStatus.read);
        await DatabaseService.instance.saveMessage(read);
        await _sendControl(peer, myDevice, 'read|${message.id}');
      }
    }
    state = DatabaseService.instance.getMessagesForConversation(myDevice.deviceId, peerDeviceId);
    _touch();
  }

  /// Handles incoming encrypted messages from either LAN or Vercel
  Future<void> _handleIncomingRawPayload(Map<String, dynamic> data, {required bool isFromLan}) async {
    try {
      final myIdentity = _ref.read(myDeviceProvider).identity;
      if (myIdentity == null) return;

      final messageId = data['id'] as String;
      final senderId = data['senderDeviceId'] as String;
      final recipientId = data['recipientDeviceId'] as String;

      if (recipientId != myIdentity.deviceId) return;

      final typeStrEarly = data['type'] as String? ?? 'text';
      if (typeStrEarly == 'device_paired') return;

      // Find sender peer
      final peers = _ref.read(peersProvider);
      var peer = peers.firstWhere(
        (p) => p.id == senderId,
        orElse: () => DeviceModel(
          id: senderId,
          name: 'Device $senderId',
          platform: 'unknown',
          signingPublicKey: '',
          exchangePublicKey: '',
          lastSeen: DateTime.now(),
        ),
      );

      // If peer is missing exchange public key, try querying relay
      if (peer.exchangePublicKey.isEmpty) {
        final fetched = await RelayApiService.instance.fetchDevice(senderId);
        if (fetched != null) {
          peer = fetched;
          _ref.read(peersProvider.notifier).addOrUpdatePeer(peer);
        }
      }

      String decryptedContent = '';
      if (peer.exchangePublicKey.isNotEmpty) {
        final sharedKey = await _cipher.deriveSharedKey(
          myKeyPair: myIdentity.exchangeKeyPair,
          peerPublicKeyBase64: peer.exchangePublicKey,
        );

        final encryptedPayload = EncryptedPayload(
          cipherTextBase64: data['cipherText'] as String,
          nonceBase64: data['nonce'] as String,
          macBase64: data['mac'] as String,
        );

        decryptedContent = await _cipher.decrypt(
          payload: encryptedPayload,
          secretKey: sharedKey,
        );
      } else {
        decryptedContent = '[Encrypted payload - Peer key unknown]';
      }

      final typeStr = typeStrEarly;
      if (typeStr == 'status' || typeStr == 'status_update') {
        await _applyControl(decryptedContent);
        _touch();
        return;
      }

      if (DatabaseService.instance.getMessage(messageId) != null) return;

      final type = MessageType.values.firstWhere((e) => e.name == typeStr, orElse: () => MessageType.text);

      FileAttachmentMetadata? fileMeta;
      if (type == MessageType.file && data['fileName'] != null) {
        fileMeta = FileAttachmentMetadata(
          fileName: data['fileName'] as String,
          fileSize: data['fileSize'] as int? ?? 0,
          fileCategory: FileCategorizer.categorize(data['fileName'] as String).folderName,
          sha256: data['sha256'] as String?,
          directDownloadUrl: decryptedContent.startsWith('http') ? decryptedContent : null,
          isDownloaded: false,
        );
      }

      final incomingMessage = MessageModel(
        id: messageId,
        senderDeviceId: senderId,
        recipientDeviceId: recipientId,
        content: decryptedContent,
        type: type,
        status: MessageStatus.delivered,
        timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        isOutgoing: false,
        codeLanguage: data['codeLanguage'] as String?,
        fileMetadata: fileMeta,
      );

      // Save to database
      await DatabaseService.instance.saveMessage(incomingMessage);

      // Acknowledge delivery to purge from Vercel queue
      if (!isFromLan) {
        await RelayApiService.instance.acknowledgeMessage(
          messageId: messageId,
          recipientDeviceId: recipientId,
          status: 'delivered',
        );
      }

      final currentPeer = _ref.read(selectedPeerProvider);
      final chatIsOpen = currentPeer?.id == senderId;
      if (chatIsOpen) {
        final read = incomingMessage.copyWith(status: MessageStatus.read);
        await DatabaseService.instance.saveMessage(read);
        state = [...state, read];
        await _sendControl(peer, myIdentity, 'read|$messageId');
      } else if (!DatabaseService.instance.isMuted(senderId)) {
        await DatabaseService.instance.incrementUnread(senderId);
      } else {
        await DatabaseService.instance.incrementUnread(senderId);
      }

      await _sendControl(peer, myIdentity, 'delivered|$messageId');
      _touch();
    } catch (e) {
      debugPrint('Error processing incoming message: $e');
    }
  }

  Future<void> _applyControl(String content) async {
    final parts = content.split('|');
    if (parts.length != 2) return;
    final action = parts[0];
    final targetId = parts[1];
    final existing = DatabaseService.instance.getMessage(targetId);
    if (existing == null) return;

    if (action == 'delete') {
      final updated = existing.copyWith(isDeleted: true, content: '');
      await DatabaseService.instance.saveMessage(updated);
      state = [
        for (final m in state)
          if (m.id == targetId) updated else m,
      ];
      return;
    }

    MessageStatus? next;
    if (action == 'delivered' && existing.status == MessageStatus.sent) {
      next = MessageStatus.delivered;
    } else if (action == 'read' && existing.status != MessageStatus.read) {
      next = MessageStatus.read;
    }
    if (next == null) return;
    final updated = existing.copyWith(status: next);
    await DatabaseService.instance.saveMessage(updated);
    state = [
      for (final m in state)
        if (m.id == targetId) updated else m,
    ];
  }

  void _touch() {
    _ref.read(conversationTickProvider.notifier).state++;
  }

  /// Sends a plaintext message
  Future<void> sendTextMessage(String text, {MessageModel? replyTo}) async {
    final currentPeer = _ref.read(selectedPeerProvider);
    final myState = _ref.read(myDeviceProvider);
    if (currentPeer == null || myState.identity == null || text.trim().isEmpty) return;

    await _dispatchMessage(
      content: text.trim(),
      type: MessageType.text,
      peer: currentPeer,
      myIdentity: myState.identity!,
      replyToId: replyTo?.id,
      replyPreview: replyTo == null ? null : _preview(replyTo),
    );
  }

  Future<void> sendTextToPeer(DeviceModel peer, String text) async {
    final myState = _ref.read(myDeviceProvider);
    if (myState.identity == null || text.trim().isEmpty) return;
    await _dispatchMessage(
      content: text.trim(),
      type: MessageType.text,
      peer: peer,
      myIdentity: myState.identity!,
    );
  }

  Future<void> toggleStar(MessageModel message) async {
    final updated = message.copyWith(isStarred: !message.isStarred);
    await DatabaseService.instance.saveMessage(updated);
    state = [
      for (final m in state)
        if (m.id == message.id) updated else m,
    ];
    _touch();
  }

  Future<void> deleteForMe(MessageModel message) async {
    await DatabaseService.instance.deleteMessage(message.id);
    state = state.where((m) => m.id != message.id).toList();
    _touch();
  }

  Future<void> deleteForEveryone(MessageModel message) async {
    final peer = _ref.read(selectedPeerProvider);
    final me = _ref.read(myDeviceProvider).identity;
    final updated = message.copyWith(isDeleted: true, content: '');
    await DatabaseService.instance.saveMessage(updated);
    state = [
      for (final m in state)
        if (m.id == message.id) updated else m,
    ];
    if (peer != null && me != null) {
      await _sendControl(peer, me, 'delete|${message.id}');
    }
    _touch();
  }

  String _preview(MessageModel message) {
    if (message.isDeleted) return 'This message was deleted';
    switch (message.type) {
      case MessageType.file:
        return message.fileMetadata?.fileName ?? 'File';
      case MessageType.code:
        return 'Code';
      case MessageType.status:
        return '';
      case MessageType.text:
        final text = message.content.replaceAll('\n', ' ');
        return text.length > 80 ? '${text.substring(0, 80)}…' : text;
    }
  }

  /// Sends a syntax-highlighted code snippet
  Future<void> sendCodeSnippet({required String code, required String language}) async {
    final currentPeer = _ref.read(selectedPeerProvider);
    final myState = _ref.read(myDeviceProvider);
    if (currentPeer == null || myState.identity == null || code.trim().isEmpty) return;

    await _dispatchMessage(
      content: code,
      type: MessageType.code,
      peer: currentPeer,
      myIdentity: myState.identity!,
      codeLanguage: language,
    );
  }

  /// Shares a file with peer (using local LAN streaming when available)
  Future<void> sendFile(String filePath) async {
    final currentPeer = _ref.read(selectedPeerProvider);
    final myState = _ref.read(myDeviceProvider);
    if (currentPeer == null || myState.identity == null) return;

    if (!await IoFile.exists(filePath)) return;

    final fileName = p.basename(filePath);
    final fileSize = await IoFile.length(filePath);
    final sha256 = await LocalFileManager.instance.calculateChecksumOfPath(filePath);
    final category = FileCategorizer.categorize(fileName);

    final fileMeta = FileAttachmentMetadata(
      fileName: fileName,
      fileSize: fileSize,
      localPath: filePath,
      fileCategory: category.folderName,
      sha256: sha256,
      directDownloadUrl: null,
      isDownloaded: true,
    );

    await _dispatchMessage(
      content: '[File] $fileName (${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB)',
      type: MessageType.file,
      peer: currentPeer,
      myIdentity: myState.identity!,
      fileName: fileName,
      fileSize: fileSize,
      sha256: sha256,
      fileMetadata: fileMeta,
    );
  }

  /// Shares a file using raw bytes (used on Web where filesystem paths are not accessible)
  Future<void> sendFileBytes({
    required String fileName,
    required List<int> bytes,
  }) async {
    final currentPeer = _ref.read(selectedPeerProvider);
    final myState = _ref.read(myDeviceProvider);
    if (currentPeer == null || myState.identity == null) return;

    final fileSize = bytes.length;
    final sha256Digest = dart_crypto.sha256.convert(bytes).toString();
    final category = FileCategorizer.categorize(fileName);

    final fileMeta = FileAttachmentMetadata(
      fileName: fileName,
      fileSize: fileSize,
      fileCategory: category.folderName,
      sha256: sha256Digest,
      isDownloaded: true,
    );

    final base64Content = base64Encode(bytes);

    await _dispatchMessage(
      content: base64Content,
      type: MessageType.file,
      peer: currentPeer,
      myIdentity: myState.identity!,
      fileName: fileName,
      fileSize: fileSize,
      sha256: sha256Digest,
      fileMetadata: fileMeta,
    );
  }

  /// Internal dispatch engine: chooses LAN direct or Vercel relay
  Future<void> _sendControl(DeviceModel peer, DeviceIdentity myIdentity, String content) {
    return _dispatchMessage(
      content: content,
      type: MessageType.status,
      peer: peer,
      myIdentity: myIdentity,
      visible: false,
    );
  }

  Future<void> _dispatchMessage({
    required String content,
    required MessageType type,
    required DeviceModel peer,
    required DeviceIdentity myIdentity,
    String? codeLanguage,
    String? fileName,
    int? fileSize,
    String? sha256,
    FileAttachmentMetadata? fileMetadata,
    String? replyToId,
    String? replyPreview,
    bool visible = true,
  }) async {
    final messageId = const Uuid().v4();

    final message = MessageModel(
      id: messageId,
      senderDeviceId: myIdentity.deviceId,
      recipientDeviceId: peer.id,
      content: content,
      type: type,
      status: MessageStatus.pending,
      timestamp: DateTime.now(),
      isOutgoing: true,
      codeLanguage: codeLanguage,
      fileMetadata: fileMetadata,
      replyToId: replyToId,
      replyPreview: replyPreview,
    );

    final viewing = _ref.read(selectedPeerProvider)?.id == peer.id;
    if (visible) {
      await DatabaseService.instance.saveMessage(message);
      if (viewing) {
        state = [...state, message];
      }
      _touch();
    }

    // Encrypt payload for peer
    if (peer.exchangePublicKey.isEmpty) {
      debugPrint('Warning: Peer public key is missing');
      return;
    }

    final sharedKey = await _cipher.deriveSharedKey(
      myKeyPair: myIdentity.exchangeKeyPair,
      peerPublicKeyBase64: peer.exchangePublicKey,
    );

    final encrypted = await _cipher.encrypt(
      plainText: content,
      secretKey: sharedKey,
    );

    final packet = {
      'id': messageId,
      'senderDeviceId': myIdentity.deviceId,
      'recipientDeviceId': peer.id,
      'type': type.name,
      'cipherText': encrypted.cipherTextBase64,
      'nonce': encrypted.nonceBase64,
      'mac': encrypted.macBase64,
      'codeLanguage': codeLanguage,
      'fileName': fileName,
      'fileSize': fileSize,
      'sha256': sha256,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    bool delivered = false;

    // 1. Try direct WebRTC DataChannel first (P2P-first)
    if (WebRtcService.instance.isPeerConnected(peer.id)) {
      final ok = WebRtcService.instance.sendData(peer.id, packet);
      if (ok) {
        delivered = true;
        if (visible) {
          await DatabaseService.instance.updateMessageStatus(messageId, MessageStatus.delivered);
          _updateMessageStatusInState(messageId, MessageStatus.delivered);
        }
      }
    }

    // 2. Try persistent WebSocket delivery next
    if (!delivered && PersistentWsClient.instance.status == WsConnectionStatus.authenticated) {
      PersistentWsClient.instance.sendEncryptedPayload(
        messageId: messageId,
        recipientDeviceId: peer.id,
        messageType: type.name,
        cipherText: encrypted.cipherTextBase64,
        nonce: encrypted.nonceBase64,
        mac: encrypted.macBase64,
        codeLanguage: codeLanguage,
        fileName: fileName,
        fileSize: fileSize,
        sha256: sha256,
      );
      delivered = true;
      await DatabaseService.instance.updateMessageStatus(messageId, MessageStatus.delivered);
      _updateMessageStatusInState(messageId, MessageStatus.delivered);
    }


    // 4. Fallback to REST relay if still not delivered
    if (!delivered) {
      final queued = await RelayApiService.instance.sendEncryptedMessage(
        messageId: messageId,
        senderDeviceId: myIdentity.deviceId,
        recipientDeviceId: peer.id,
        type: type.name,
        cipherText: encrypted.cipherTextBase64,
        nonce: encrypted.nonceBase64,
        mac: encrypted.macBase64,
        codeLanguage: codeLanguage,
        fileName: fileName,
        fileSize: fileSize,
        sha256: sha256,
      );
      if (visible && queued) {
        await DatabaseService.instance.updateMessageStatus(messageId, MessageStatus.sent);
        _updateMessageStatusInState(messageId, MessageStatus.sent);
      }
    }
  }

  void _updateMessageStatusInState(String messageId, MessageStatus status) {
    state = state.map((m) {
      if (m.id == messageId) {
        return m.copyWith(status: status);
      }
      return m;
    }).toList();
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _wsSub?.cancel();
    _webrtcSub?.cancel();
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, List<MessageModel>>((ref) {
  return ChatNotifier(ref);
});

final conversationTickProvider = StateProvider<int>((ref) => 0);
