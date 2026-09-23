import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:devsync/core/crypto/device_identity.dart';
import 'package:devsync/core/network/file_transfer_engine.dart';
import 'package:devsync/core/network/lan_http_server.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('devsync_unit_test');
    FileTransferEngine.instance.stagingDirOverride = tempDir;
  });

  group('FileTransferEngine Tests', () {
    test('Checkpoint serialization and deserialization preserves verified chunks', () {
      final checkpoint = TransferCheckpoint(
        transferId: 'test-transfer-1234',
        fileName: 'sample_video.mp4',
        fileSize: 1024 * 1024 * 10, // 10 MB
        chunkSize: 64 * 1024,
        totalChunks: 160,
        expectedSha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        verifiedChunks: {0, 1, 2, 3, 50, 51},
        lastUpdated: 1790144000,
      );

      final json = checkpoint.toJson();
      final restored = TransferCheckpoint.fromJson(json);

      expect(restored.transferId, equals('test-transfer-1234'));
      expect(restored.totalChunks, equals(160));
      expect(restored.verifiedChunks.contains(50), isTrue);
      expect(restored.verifiedChunks.contains(4), isFalse);
    });

    test('Incoming offer initializes resume state calculation correctly', () async {
      final engine = FileTransferEngine.instance;
      final transferId = 'transfer_${DateTime.now().millisecondsSinceEpoch}';
      const fileName = 'document.pdf';
      const fileSize = 1024 * 512; // 512 KB = 8 chunks of 64KB
      final sha = dart_crypto.sha256.convert(utf8.encode('dummy-content')).toString();

      final res = await engine.handleIncomingOffer(
        transferId: transferId,
        fileName: fileName,
        fileSize: fileSize,
        expectedSha256: sha,
      );

      expect(res['type'], equals('transfer_resume_ack'));
      expect(res['transferId'], equals(transferId));
      expect(res['canResume'], isFalse);
      expect((res['neededChunks'] as List).length, equals(8));
    });

    test('Binary chunk 32-byte packet header encoding, CRC-32 integrity, and decoding', () {
      const transferId = 'xfr-uuid-998877';
      const chunkIndex = 42;
      const totalChunks = 100;
      final payload = Uint8List.fromList(utf8.encode('DevSync chunk payload bytes'));
      final chunkChecksum = calculateCrc32(payload);

      final header = Uint8List(32);
      final idBytes = utf8.encode(transferId);
      header.setRange(0, idBytes.length, idBytes);

      final byteData = ByteData.sublistView(header);
      byteData.setUint32(16, chunkIndex);
      byteData.setUint32(20, totalChunks);
      byteData.setUint32(24, payload.length);
      byteData.setUint32(28, chunkChecksum);

      final packet = Uint8List(header.length + payload.length)
        ..setRange(0, header.length, header)
        ..setRange(header.length, header.length + payload.length, payload);

      // Verify packet extraction
      final decodedId = utf8.decode(packet.sublist(0, 16).takeWhile((b) => b != 0).toList());
      final decodedByteData = ByteData.sublistView(packet);
      final decodedIndex = decodedByteData.getUint32(16);
      final decodedTotal = decodedByteData.getUint32(20);
      final decodedLength = decodedByteData.getUint32(24);
      final decodedChecksum = decodedByteData.getUint32(28);
      final decodedPayload = packet.sublist(32);

      expect(decodedId, equals(transferId));
      expect(decodedIndex, equals(42));
      expect(decodedTotal, equals(100));
      expect(decodedLength, equals(payload.length));
      expect(decodedChecksum, equals(chunkChecksum));
      expect(calculateCrc32(decodedPayload), equals(chunkChecksum));
      expect(utf8.decode(decodedPayload), equals('DevSync chunk payload bytes'));
    });
  });

  group('LAN HTTP Decommission Security Tests', () {
    test('LanHttpServer start is decommissioned and returns port 0 without binding socket', () async {
      final server = LanHttpServer.instance;
      final manager = DeviceIdentityManager();
      final identity = await manager.getOrCreateIdentity();

      final port = await server.start(identity);
      expect(port, equals(0));
      expect(server.port, equals(0));
      expect(server.isRunning, isFalse);
    });

    test('LanHttpServer registerShareableFile is disabled and returns empty token', () {
      final server = LanHttpServer.instance;
      final token = server.registerShareableFile(
        filePath: '/test/dummy.txt',
        fileName: 'dummy.txt',
        fileSize: 100,
      );
      expect(token, isEmpty);
    });
  });
}
