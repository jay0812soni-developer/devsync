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
    return messages.where((m) => m.type != MessageType.status).toList();
  }

  MessageModel? getLastMessage(String myDeviceId, String peerDeviceId) {
    final messages = getMessagesForConversation(myDeviceId, peerDeviceId);
    if (messages.isEmpty) return null;
    return messages.last;
  }

  List<MessageModel> getStarredMessages() {
    final messages = <MessageModel>[];
    for (final raw in _messagesBox.values) {
      if (raw is Map) {
        try {
          final msg = MessageModel.fromJson(Map<String, dynamic>.from(raw));
          if (msg.isStarred && !msg.isDeleted && msg.type != MessageType.status) {
            messages.add(msg);
          }
        } catch (_) {}
      }
    }
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
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

  Future<void> deleteMessage(String messageId) async {
    await _messagesBox.delete(messageId);
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

  bool _isBoxReady() {
    try {
      _settingsBox;
      return true;
    } catch (_) {
      return false;
    }
  }

  String? readIdentityField(String key) {
    if (!_isBoxReady()) return null;
    try {
      return _settingsBox.get('identity_$key') as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeIdentityField(String key, String value) async {
    if (!_isBoxReady()) return;
    try {
      await _settingsBox.put('identity_$key', value);
    } catch (_) {}
  }

  List<String> _idList(String key) {
    final raw = _settingsBox.get(key);
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  Future<void> _toggleId(String key, String id, bool enabled) async {
    final list = _idList(key);
    if (enabled) {
      if (!list.contains(id)) list.add(id);
    } else {
      list.remove(id);
    }
    await _settingsBox.put(key, list);
  }

  bool isPinned(String deviceId) => _idList('chat_pins').contains(deviceId);
  bool isMuted(String deviceId) => _idList('chat_mutes').contains(deviceId);
  bool isArchived(String deviceId) => _idList('chat_archives').contains(deviceId);

  Future<void> setPinned(String deviceId, bool value) => _toggleId('chat_pins', deviceId, value);
  Future<void> setMuted(String deviceId, bool value) => _toggleId('chat_mutes', deviceId, value);
  Future<void> setArchived(String deviceId, bool value) => _toggleId('chat_archives', deviceId, value);

  int unreadCount(String deviceId) {
    final raw = _settingsBox.get('chat_unread');
    if (raw is Map && raw[deviceId] is int) return raw[deviceId] as int;
    return 0;
  }

  Future<void> incrementUnread(String deviceId) async {
    final raw = _settingsBox.get('chat_unread');
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    map[deviceId] = (map[deviceId] as int? ?? 0) + 1;
    await _settingsBox.put('chat_unread', map);
  }

  Future<void> clearUnread(String deviceId) async {
    final raw = _settingsBox.get('chat_unread');
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    map.remove(deviceId);
    await _settingsBox.put('chat_unread', map);
  }

  Future<void> clearConversation(String myDeviceId, String peerDeviceId) async {
    final ids = <dynamic>[];
    for (final key in _messagesBox.keys) {
      final raw = _messagesBox.get(key);
      if (raw is Map) {
        final sender = raw['senderDeviceId'];
        final recipient = raw['recipientDeviceId'];
        final inThread = (sender == myDeviceId && recipient == peerDeviceId) ||
            (sender == peerDeviceId && recipient == myDeviceId);
        if (inThread) ids.add(key);
      }
    }
    await _messagesBox.deleteAll(ids);
    await clearUnread(peerDeviceId);
  }

  // --- Session & Mesh Identity ---

  String? getAuthToken() {
    if (!_isBoxReady()) return null;
    return _settingsBox.get('auth_token') as String?;
  }

  Future<void> setAuthToken(String token) async {
    if (!_isBoxReady()) return;
    await _settingsBox.put('auth_token', token);
  }

  String? getGroupId() {
    if (!_isBoxReady()) return null;
    return _settingsBox.get('group_id') as String?;
  }

  Future<void> setGroupId(String groupId) async {
    if (!_isBoxReady()) return;
    await _settingsBox.put('group_id', groupId);
  }

  String? getMyRole() {
    if (!_isBoxReady()) return null;
    return _settingsBox.get('device_role') as String?;
  }

  Future<void> setMyRole(String role) async {
    if (!_isBoxReady()) return;
    await _settingsBox.put('device_role', role);
  }
}
