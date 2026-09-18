enum MessageType { text, code, file, status }

enum MessageStatus { pending, sent, delivered, read }

class FileAttachmentMetadata {
  final String fileName;
  final int fileSize;
  final String? localPath;
  final String fileCategory;
  final String? sha256;
  final String? directDownloadUrl;
  final bool isDownloaded;

  FileAttachmentMetadata({
    required this.fileName,
    required this.fileSize,
    this.localPath,
    required this.fileCategory,
    this.sha256,
    this.directDownloadUrl,
    this.isDownloaded = false,
  });

  FileAttachmentMetadata copyWith({
    String? localPath,
    bool? isDownloaded,
    String? directDownloadUrl,
  }) {
    return FileAttachmentMetadata(
      fileName: fileName,
      fileSize: fileSize,
      localPath: localPath ?? this.localPath,
      fileCategory: fileCategory,
      sha256: sha256,
      directDownloadUrl: directDownloadUrl ?? this.directDownloadUrl,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'fileSize': fileSize,
        'localPath': localPath,
        'fileCategory': fileCategory,
        'sha256': sha256,
        'directDownloadUrl': directDownloadUrl,
        'isDownloaded': isDownloaded,
      };

  factory FileAttachmentMetadata.fromJson(Map<String, dynamic> json) {
    return FileAttachmentMetadata(
      fileName: json['fileName'] as String,
      fileSize: json['fileSize'] as int? ?? 0,
      localPath: json['localPath'] as String?,
      fileCategory: json['fileCategory'] as String? ?? 'other',
      sha256: json['sha256'] as String?,
      directDownloadUrl: json['directDownloadUrl'] as String?,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
    );
  }
}

class MessageModel {
  final String id;
  final String senderDeviceId;
  final String recipientDeviceId;
  final String content;
  final MessageType type;
  final MessageStatus status;
  final DateTime timestamp;
  final bool isOutgoing;
  final String? codeLanguage;
  final FileAttachmentMetadata? fileMetadata;

  MessageModel({
    required this.id,
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.content,
    required this.type,
    this.status = MessageStatus.pending,
    required this.timestamp,
    required this.isOutgoing,
    this.codeLanguage,
    this.fileMetadata,
  });

  MessageModel copyWith({
    String? content,
    MessageStatus? status,
    FileAttachmentMetadata? fileMetadata,
    bool? isOutgoing,
  }) {
    return MessageModel(
      id: id,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
      content: content ?? this.content,
      type: type,
      status: status ?? this.status,
      timestamp: timestamp,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      codeLanguage: codeLanguage,
      fileMetadata: fileMetadata ?? this.fileMetadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderDeviceId': senderDeviceId,
        'recipientDeviceId': recipientDeviceId,
        'content': content,
        'type': type.name,
        'status': status.name,
        'timestamp': timestamp.toIso8601String(),
        'isOutgoing': isOutgoing,
        'codeLanguage': codeLanguage,
        'fileMetadata': fileMetadata?.toJson(),
      };

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as String,
      senderDeviceId: json['senderDeviceId'] as String,
      recipientDeviceId: json['recipientDeviceId'] as String,
      content: json['content'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.pending,
      ),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      isOutgoing: json['isOutgoing'] as bool? ?? false,
      codeLanguage: json['codeLanguage'] as String?,
      fileMetadata: json['fileMetadata'] != null
          ? FileAttachmentMetadata.fromJson(json['fileMetadata'] as Map<String, dynamic>)
          : null,
    );
  }
}
