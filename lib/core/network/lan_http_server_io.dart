import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import '../crypto/device_identity.dart';

typedef OnDirectMessageReceived = void Function(Map<String, dynamic> messageData);

class RegisteredFile {
  final String token;
  final String filePath;
  final String fileName;
  final int fileSize;
  final String mimeType;

  RegisteredFile({
    required this.token,
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
  });
}

class LanHttpServer {
  static LanHttpServer? _instance;
  static LanHttpServer get instance => _instance ??= LanHttpServer._();

  HttpServer? _server;
  int _port = AppConstants.defaultLanPort;
  final Map<String, RegisteredFile> _sharedFiles = {};
  OnDirectMessageReceived? onDirectMessageReceived;

  LanHttpServer._();

  int get port => _port;
  bool get isRunning => _server != null;

  /// Decommissioned: Unauthenticated HTTP server is disabled to eliminate LAN security exposure.
  /// All messaging and file transfer traffic flows strictly through authenticated WebRTC or persistent WebSocket.
  Future<int> start(DeviceIdentity identity, {int preferredPort = AppConstants.defaultLanPort}) async {
    debugPrint('[LanHttpServer] DECOMMISSIONED: Unauthenticated LAN HTTP server disabled for security.');
    _server = null;
    _port = 0;
    return 0;
  }

  /// Decommissioned: Plaintext HTTP file sharing is disabled for security.
  String registerShareableFile({
    required String filePath,
    required String fileName,
    required int fileSize,
    String mimeType = 'application/octet-stream',
  }) {
    return '';
  }

  void revokeSharedFile(String token) {
    _sharedFiles.remove(token);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _sharedFiles.clear();
  }
}
