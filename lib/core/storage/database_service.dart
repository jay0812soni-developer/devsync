import 'package:hive_flutter/hive_flutter.dart';
import '../constants/app_constants.dart';
import '../../features/devices/domain/device_model.dart';
import '../../features/chat/domain/message_model.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static DatabaseService get instance => _instance ??= DatabaseService._();

  late Box _settingsBox;
  late Box _peersBox;
  late Box _messagesBox;

  DatabaseService._();

  Future<void> initialize() async {
    await Hive.initFlutter();
    _settingsBox = await Hive.openBox(AppConstants.boxSettings);
    _peersBox = await Hive.openBox(AppConstants.boxPeers);
    _messagesBox = await Hive.openBox(AppConstants.boxMessages);
  }

  // --- Devices / Peers Management ---

  List<DeviceModel> getAllPeers() {
    final list = <DeviceModel>[];
    for (final raw in _peersBox.values) {
      if (raw is Map) {
        try {
          list.add(DeviceModel.fromJson(Map<String, dynamic>.from(raw)));
        } catch (_) {}
      }
    }
    return list;
  }

  DeviceModel? getPeer(String deviceId) {
    final raw = _peersBox.get(deviceId);
    if (raw is Map) {
      try {
        return DeviceModel.fromJson(Map<String, dynamic>.from(raw));
      } catch (_) {}
    }
    return null;
  }

  Future<void> savePeer(DeviceModel peer) async {
    await _peersBox.put(peer.id, peer.toJson());
  }

  Future<void> deletePeer(String deviceId) async {
    await _peersBox.delete(deviceId);
  }

  // --- Messages Management ---

  List<MessageModel> getMessagesForConversation(String myDeviceId, String peerDeviceId) {
    final messages = <MessageModel>[];
    for (final raw in _messagesBox.values) {
      if (raw is Map) {
        try {
          final msg = MessageModel.fromJson(Map<String, dynamic>.from(raw));
          if ((msg.senderDeviceId == myDeviceId && msg.recipientDeviceId == peerDeviceId) ||
              (msg.senderDeviceId == peerDeviceId && msg.recipientDeviceId == myDeviceId)) {
            messages.add(msg);
          }
        } catch (_) {}
      }
    }
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  MessageModel? getMessage(String messageId) {
    final raw = _messagesBox.get(messageId);
    if (raw is Map) {
      try {
        return MessageModel.fromJson(Map<String, dynamic>.from(raw));
      } catch (_) {}
    }
    return null;
  }

  Future<void> saveMessage(MessageModel message) async {
    await _messagesBox.put(message.id, message.toJson());
  }

  Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    final msg = getMessage(messageId);
    if (msg != null) {
      final updated = msg.copyWith(status: status);
      await saveMessage(updated);
    }
  }

  Future<void> updateFileAttachmentDownloaded(String messageId, String localPath) async {
    final msg = getMessage(messageId);
    if (msg != null && msg.fileMetadata != null) {
      final updated = msg.copyWith(
        fileMetadata: msg.fileMetadata!.copyWith(
          localPath: localPath,
          isDownloaded: true,
        ),
      );
      await saveMessage(updated);
    }
  }

  // --- Settings ---

  String getRelayUrl() {
    final saved = _settingsBox.get('relay_url', defaultValue: AppConstants.defaultRelayUrl) as String;
    if (saved.isEmpty || saved == 'https://devsync-relay.vercel.app') {
      return AppConstants.defaultRelayUrl;
    }
    return saved;
  }

  Future<void> setRelayUrl(String url) async {
    await _settingsBox.put('relay_url', url);
  }

  bool getAutoDownloadLan() {
    return _settingsBox.get('auto_download_lan', defaultValue: true) as bool;
  }

  Future<void> setAutoDownloadLan(bool enabled) async {
    await _settingsBox.put('auto_download_lan', enabled);
  }

  // --- Auth & Multi-Device Connection Code ---

  String? getConnectionCode() {
    return _settingsBox.get('connection_code') as String?;
  }

  Future<void> setConnectionCode(String code) async {
    await _settingsBox.put('connection_code', code);
  }

  String? getUserEmail() {
    return _settingsBox.get('user_email') as String?;
  }

  Future<void> setUserEmail(String email) async {
    await _settingsBox.put('user_email', email);
  }

  String? getUserPhone() {
    return _settingsBox.get('user_phone') as String?;
  }

  Future<void> setUserPhone(String phone) async {
    await _settingsBox.put('user_phone', phone);
  }

  bool isAuthenticated() {
    return _settingsBox.get('is_authenticated', defaultValue: false) as bool;
  }

  Future<void> setAuthenticated(bool auth) async {
    await _settingsBox.put('is_authenticated', auth);
  }
}
