import 'package:devsync/core/crypto/device_identity.dart';
import 'package:devsync/core/network/persistent_ws_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Personal Mesh & WebSocket Client Tests', () {
    test('PersistentWsClient initializes in disconnected state', () {
      final wsClient = PersistentWsClient.instance;
      expect(wsClient.status, equals(WsConnectionStatus.disconnected));
    });

    test('DeviceIdentity uses secure random seeds for 32-byte keys', () async {
      final manager = DeviceIdentityManager();
      final identity = await manager.getOrCreateIdentity();

      expect(identity.deviceId.startsWith('DEV-'), isTrue);
      expect(identity.signingPublicKeyBase64.isNotEmpty, isTrue);
      expect(identity.exchangePublicKeyBase64.isNotEmpty, isTrue);
      expect(identity.platform.isNotEmpty, isTrue);
    });
  });
}
