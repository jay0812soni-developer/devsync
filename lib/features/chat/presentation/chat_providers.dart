import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../core/crypto/device_identity.dart';
import '../../../core/crypto/e2ee_cipher.dart';
import '../../../core/network/lan_http_server.dart';
import '../../../core/network/relay_api_service.dart';
import '../../../core/network/sse_relay_client.dart';
import '../../../core/storage/database_service.dart';
import '../../../core/storage/file_categorizer.dart';
import '../../../core/storage/local_file_manager.dart';
import '../../devices/domain/device_model.dart';
import '../../devices/presentation/device_providers.dart';
import '../domain/message_model.dart';

class ChatNotifier extends StateNotifier<List<MessageModel>> {
  final Ref _ref;
  final E2eeCipher _cipher = E2eeCipher();
  StreamSubscription? _sseSub;

  ChatNotifier(this._ref) : super([]) {
    _initMessageListeners();
  }

  void _initMessageListeners() {
    // 1. Direct LAN message receiver
    LanHttpServer.instance.onDirectMessageReceived = (data) {
      _handleIncomingRawPayload(data, isFromLan: true);
    };

    // 2. Vercel SSE message receiver
    _sseSub = SseRelayClient.instance.onMessageReceived.listen((data) {
      _handleIncomingRawPayload(data, isFromLan: false);
    });
  }

  /// Reloads message list for the active conversation
  void loadConversation(String peerDeviceId) {
    final myDevice = _ref.read(myDeviceProvider).identity;
    if (myDevice == null) return;
    state = DatabaseService.instance.getMessagesForConversation(myDevice.deviceId, peerDeviceId);
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

      final typeStr = data['type'] as String? ?? 'text';
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

      // If viewing this conversation, update active state
      final currentPeer = _ref.read(selectedPeerProvider);
      if (currentPeer?.id == senderId) {
        state = [...state, incomingMessage];
      }
    } catch (e) {
      debugPrint('Error processing incoming message: $e');
    }
  }

  /// Sends a plaintext message
  Future<void> sendTextMessage(String text) async {
    final currentPeer = _ref.read(selectedPeerProvider);
    final myState = _ref.read(myDeviceProvider);
    if (currentPeer == null || myState.identity == null || text.trim().isEmpty) return;

    await _dispatchMessage(
      content: text.trim(),
      type: MessageType.text,
      peer: currentPeer,
      myIdentity: myState.identity!,
    );
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

    final file = File(filePath);
    if (!await file.exists()) return;

    final fileName = p.basename(filePath);
    final fileSize = await file.length();
    final sha256 = await LocalFileManager.instance.calculateChecksum(file);
    final category = FileCategorizer.categorize(fileName);

    // Register on local HTTP server for LAN direct streaming
    final downloadToken = LanHttpServer.instance.registerShareableFile(
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
    );

    final myLanIp = myState.localIp ?? '127.0.0.1';
    final downloadUrl = 'http://$myLanIp:${myState.lanPort}/files/download/$downloadToken';

    final fileMeta = FileAttachmentMetadata(
      fileName: fileName,
      fileSize: fileSize,
      localPath: filePath,
      fileCategory: category.folderName,
      sha256: sha256,
      directDownloadUrl: downloadUrl,
      isDownloaded: true,
    );

    await _dispatchMessage(
      content: downloadUrl,
      type: MessageType.file,
      peer: currentPeer,
      myIdentity: myState.identity!,
      fileName: fileName,
      fileSize: fileSize,
      sha256: sha256,
      fileMetadata: fileMeta,
    );
  }

  /// Internal dispatch engine: chooses LAN direct or Vercel relay
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
  }) async {
    final messageId = const Uuid().v4();

    // Local model
    final message = MessageModel(
      id: messageId,
      senderDeviceId: myIdentity.deviceId,
      recipientDeviceId: peer.id,
      content: content,
      type: type,
      status: MessageStatus.sent,
      timestamp: DateTime.now(),
      isOutgoing: true,
      codeLanguage: codeLanguage,
      fileMetadata: fileMetadata,
    );

    // Save and display immediately
    await DatabaseService.instance.saveMessage(message);
    state = [...state, message];

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

    // 1. Try Direct LAN delivery if peer is on the same local network
    if (peer.isLanAvailable && peer.lanIp != null && peer.lanPort != null) {
      try {
        final directUrl = Uri.parse('http://${peer.lanIp}:${peer.lanPort}/messages/direct');
        final response = await http
            .post(
              directUrl,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(packet),
            )
            .timeout(const Duration(seconds: 2));

        if (response.statusCode == 200) {
          delivered = true;
          await DatabaseService.instance.updateMessageStatus(messageId, MessageStatus.delivered);
          _updateMessageStatusInState(messageId, MessageStatus.delivered);
        }
      } catch (_) {
        // Fallback to Vercel relay
      }
    }

    // 2. Fallback to Vercel relay if not delivered via LAN
    if (!delivered) {
      await RelayApiService.instance.sendEncryptedMessage(
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
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, List<MessageModel>>((ref) {
  return ChatNotifier(ref);
});
