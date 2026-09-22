import '../crypto/device_identity.dart';

typedef OnDirectMessageReceived = void Function(Map<String, dynamic> messageData);

class LanHttpServer {
  static LanHttpServer? _instance;
  static LanHttpServer get instance => _instance ??= LanHttpServer._();

  LanHttpServer._();

  int get port => 0;
  bool get isRunning => false;
  OnDirectMessageReceived? onDirectMessageReceived;

  Future<int> start(DeviceIdentity identity, {int preferredPort = 42042}) async => 0;

  String registerShareableFile({
    required String filePath,
    required String fileName,
    required int fileSize,
    String mimeType = 'application/octet-stream',
  }) =>
      '';

  void revokeSharedFile(String token) {}

  Future<void> stop() async {}
}
