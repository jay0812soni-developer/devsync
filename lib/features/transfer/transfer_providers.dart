import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/storage/file_categorizer.dart';
import '../../core/storage/local_file_manager.dart';
import '../../core/storage/database_service.dart';
import '../../shared/utils/formatters.dart';
import '../chat/domain/message_model.dart';
import 'domain/file_transfer_model.dart';

class TransferNotifier extends StateNotifier<Map<String, FileTransferModel>> {
  final Dio _dio = Dio();

  TransferNotifier() : super({});

  /// Initiates a high-speed chunked LAN download
  Future<void> downloadFile({
    required MessageModel message,
    required String downloadUrl,
    void Function(String localPath)? onComplete,
  }) async {
    final meta = message.fileMetadata;
    if (meta == null) return;

    final transferId = const Uuid().v4();
    final category = FileCategorizer.categorize(meta.fileName);
    final targetDir = await LocalFileManager.instance.getCategoryDirectory(category);
    final savePath = await LocalFileManager.instance.resolveUniquePath(targetDir.path, meta.fileName);

    state = {
      ...state,
      transferId: FileTransferModel(
        transferId: transferId,
        messageId: message.id,
        fileName: meta.fileName,
        totalBytes: meta.fileSize,
        isIncoming: true,
        status: TransferStatus.transferring,
      ),
    };

    final startTime = DateTime.now();

    try {
      await _dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          final now = DateTime.now();
          final elapsed = now.difference(startTime);
          final speed = Formatters.formatSpeed(received, elapsed);
          final progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;

          final current = state[transferId];
          if (current != null) {
            state = {
              ...state,
              transferId: current.copyWith(
                transferredBytes: received,
                progress: progress,
                speedFormatted: speed,
              ),
            };
          }
        },
      );

      // Verify checksum if available
      final downloadedFile = File(savePath);
      if (meta.sha256 != null && meta.sha256!.isNotEmpty) {
        final actualSha = await LocalFileManager.instance.calculateChecksum(downloadedFile);
        if (actualSha.toLowerCase() != meta.sha256!.toLowerCase()) {
          state = {
            ...state,
            transferId: state[transferId]!.copyWith(
              status: TransferStatus.failed,
              errorMessage: 'Checksum verification failed',
            ),
          };
          return;
        }
      }

      // Mark complete in database
      await DatabaseService.instance.updateFileAttachmentDownloaded(message.id, savePath);

      state = {
        ...state,
        transferId: state[transferId]!.copyWith(
          status: TransferStatus.completed,
          progress: 1.0,
          localFilePath: savePath,
        ),
      };

      onComplete?.call(savePath);
    } catch (e) {
      state = {
        ...state,
        transferId: state[transferId]!.copyWith(
          status: TransferStatus.failed,
          errorMessage: e.toString(),
        ),
      };
    }
  }

  void clearTransfer(String transferId) {
    final updated = Map<String, FileTransferModel>.from(state);
    updated.remove(transferId);
    state = updated;
  }
}

final transferProvider = StateNotifierProvider<TransferNotifier, Map<String, FileTransferModel>>((ref) {
  return TransferNotifier();
});
