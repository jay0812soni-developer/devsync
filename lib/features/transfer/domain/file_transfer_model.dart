enum TransferStatus { idle, queued, transferring, completed, failed, paused }

class FileTransferModel {
  final String transferId;
  final String messageId;
  final String fileName;
  final int totalBytes;
  final int transferredBytes;
  final double progress;
  final String speedFormatted;
  final TransferStatus status;
  final bool isIncoming;
  final String? localFilePath;
  final String? errorMessage;

  FileTransferModel({
    required this.transferId,
    required this.messageId,
    required this.fileName,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.progress = 0.0,
    this.speedFormatted = '0 KB/s',
    this.status = TransferStatus.queued,
    required this.isIncoming,
    this.localFilePath,
    this.errorMessage,
  });

  FileTransferModel copyWith({
    int? transferredBytes,
    double? progress,
    String? speedFormatted,
    TransferStatus? status,
    String? localFilePath,
    String? errorMessage,
  }) {
    return FileTransferModel(
      transferId: transferId,
      messageId: messageId,
      fileName: fileName,
      totalBytes: totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      progress: progress ?? this.progress,
      speedFormatted: speedFormatted ?? this.speedFormatted,
      status: status ?? this.status,
      isIncoming: isIncoming,
      localFilePath: localFilePath ?? this.localFilePath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
