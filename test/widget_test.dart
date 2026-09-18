import 'package:devsync/features/chat/domain/message_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageModel Tests', () {
    test('Serializes and deserializes text message accurately', () {
      final msg = MessageModel(
        id: 'msg-123',
        senderDeviceId: 'DEV-A1B2',
        recipientDeviceId: 'DEV-C3D4',
        content: 'console.log("hello")',
        type: MessageType.code,
        status: MessageStatus.sent,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1726665000000),
        isOutgoing: true,
        codeLanguage: 'javascript',
      );

      final json = msg.toJson();
      final restored = MessageModel.fromJson(json);

      expect(restored.id, equals('msg-123'));
      expect(restored.senderDeviceId, equals('DEV-A1B2'));
      expect(restored.recipientDeviceId, equals('DEV-C3D4'));
      expect(restored.type, equals(MessageType.code));
      expect(restored.codeLanguage, equals('javascript'));
      expect(restored.status, equals(MessageStatus.sent));
    });

    test('Serializes file attachment metadata accurately', () {
      final fileMeta = FileAttachmentMetadata(
        fileName: 'patch.dart',
        fileSize: 4096,
        fileCategory: 'Code',
        sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        directDownloadUrl: 'http://192.168.1.50:42042/files/download/token-1',
        isDownloaded: true,
      );

      final msg = MessageModel(
        id: 'file-msg-1',
        senderDeviceId: 'DEV-A1B2',
        recipientDeviceId: 'DEV-C3D4',
        content: 'http://192.168.1.50:42042/files/download/token-1',
        type: MessageType.file,
        status: MessageStatus.delivered,
        timestamp: DateTime.now(),
        isOutgoing: false,
        fileMetadata: fileMeta,
      );

      final json = msg.toJson();
      final restored = MessageModel.fromJson(json);

      expect(restored.fileMetadata, isNotNull);
      expect(restored.fileMetadata!.fileName, equals('patch.dart'));
      expect(restored.fileMetadata!.fileSize, equals(4096));
      expect(restored.fileMetadata!.fileCategory, equals('Code'));
      expect(restored.fileMetadata!.isDownloaded, isTrue);
    });
  });
}
