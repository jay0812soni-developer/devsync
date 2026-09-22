import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_theme.dart';
import '../../../../core/storage/local_file_manager.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../transfer/domain/file_transfer_model.dart';
import '../../../transfer/transfer_providers.dart';
import '../../domain/message_model.dart';
import 'status_tick_icon.dart';

class FileMessageBubble extends ConsumerWidget {
  final MessageModel message;
  final VoidCallback? onLongPress;

  const FileMessageBubble({super.key, required this.message, this.onLongPress});

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'code':
        return Icons.code_rounded;
      case 'images':
        return Icons.image_rounded;
      case 'media':
        return Icons.movie_rounded;
      case 'archives':
        return Icons.folder_zip_rounded;
      case 'documents':
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'code':
        return DevSyncColors.secondary;
      case 'images':
        return DevSyncColors.primary;
      case 'media':
        return DevSyncColors.warning;
      case 'archives':
        return DevSyncColors.accent;
      default:
        return DevSyncColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = message.fileMetadata;
    final isOutgoing = message.isOutgoing;
    final transfers = ref.watch(transferProvider);

    // Find active transfer for this message
    final activeTransfer = transfers.values.firstWhere(
      (t) => t.messageId == message.id,
      orElse: () => FileTransferModel(
        transferId: '',
        messageId: message.id,
        fileName: meta?.fileName ?? '',
        totalBytes: meta?.fileSize ?? 0,
        isIncoming: !isOutgoing,
        status: meta?.isDownloaded == true ? TransferStatus.completed : TransferStatus.idle,
        localFilePath: meta?.localPath,
      ),
    );

    final isDownloaded = meta?.isDownloaded == true || activeTransfer.status == TransferStatus.completed;
    final isDownloading = activeTransfer.status == TransferStatus.transferring;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isOutgoing ? DevSyncColors.bubbleSent : DevSyncColors.bubbleReceived,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isOutgoing ? 12 : 2),
            bottomRight: Radius.circular(isOutgoing ? 2 : 12),
          ),
          border: Border.all(
            color: DevSyncColors.border.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Category Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _getCategoryColor(meta?.fileCategory ?? '').withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getCategoryIcon(meta?.fileCategory ?? ''),
                    color: _getCategoryColor(meta?.fileCategory ?? ''),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // File info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta?.fileName ?? 'File',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DevSyncColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            Formatters.formatBytes(meta?.fileSize ?? 0),
                            style: const TextStyle(fontSize: 12, color: DevSyncColors.textMuted),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: DevSyncColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (meta?.fileCategory ?? 'Other').toUpperCase(),
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: DevSyncColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Download Progress Bar (when downloading)
            if (isDownloading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: activeTransfer.progress > 0 ? activeTransfer.progress : null,
                backgroundColor: DevSyncColors.surfaceVariant,
                valueColor: const AlwaysStoppedAnimation<Color>(DevSyncColors.primary),
                borderRadius: BorderRadius.circular(4),
                minHeight: 6,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(activeTransfer.progress * 100).toStringAsFixed(0)}% • ${activeTransfer.speedFormatted}',
                    style: const TextStyle(fontSize: 11, color: DevSyncColors.primary),
                  ),
                  Text(
                    '${Formatters.formatBytes(activeTransfer.transferredBytes)} / ${Formatters.formatBytes(activeTransfer.totalBytes)}',
                    style: const TextStyle(fontSize: 11, color: DevSyncColors.textMuted),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8),

            // Action Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (!isOutgoing && !isDownloaded && !isDownloading)
                  ElevatedButton.icon(
                    onPressed: () {
                      if (meta?.directDownloadUrl != null) {
                        ref.read(transferProvider.notifier).downloadFile(
                              message: message,
                              downloadUrl: meta!.directDownloadUrl!,
                              onComplete: (savedPath) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Saved to DevSync/${meta.fileCategory}/${meta.fileName}'),
                                    action: SnackBarAction(
                                      label: 'Open',
                                      onPressed: () => LocalFileManager.instance.openFile(savedPath),
                                    ),
                                  ),
                                );
                              },
                            );
                      }
                    },
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Download', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DevSyncColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                else if (isDownloaded)
                  OutlinedButton.icon(
                    onPressed: () {
                      final path = meta?.localPath ?? activeTransfer.localFilePath;
                      if (path != null) {
                        LocalFileManager.instance.openFile(path);
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('Open File', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DevSyncColors.secondary,
                      side: const BorderSide(color: DevSyncColors.secondary),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                else
                  const SizedBox.shrink(),

                // Timestamp & status
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      Formatters.formatTimestamp(message.timestamp),
                      style: const TextStyle(fontSize: 10, color: DevSyncColors.textMuted),
                    ),
                    if (isOutgoing) ...[
                      const SizedBox(width: 4),
                      StatusTickIcon(status: message.status),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}
