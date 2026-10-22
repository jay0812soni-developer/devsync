import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_theme.dart';
import '../../../../core/storage/database_service.dart';
import '../../../../core/storage/local_file_manager.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../transfer/domain/file_transfer_model.dart';
import '../../../transfer/transfer_providers.dart';
import '../../domain/message_model.dart';
import 'in_app_media_viewer.dart';
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

  bool _isImage(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  bool _isTextDocument(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.json') ||
        lower.endsWith('.dart') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.js') ||
        lower.endsWith('.py') ||
        lower.endsWith('.html') ||
        lower.endsWith('.css') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml') ||
        lower.endsWith('.xml') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.log');
  }

  Uint8List? _getDecodedBytes(String content) {
    try {
      if (content.startsWith('[File]')) return null;
      return base64Decode(content.trim());
    } catch (_) {
      return null;
    }
  }

  Widget _buildThumbnail(Uint8List? bytes, String? localPath) {
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }
    if (localPath != null && !kIsWeb && File(localPath).existsSync()) {
      return Image.file(
        File(localPath),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _handleDownload(BuildContext context, WidgetRef ref) async {
    final meta = message.fileMetadata;
    try {
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
        return;
      }

      final bytes = _getDecodedBytes(message.content);
      if (bytes != null && bytes.isNotEmpty) {
        final savedPath = await LocalFileManager.instance.saveIncomingBytes(
          originalFilename: meta?.fileName ?? 'downloaded_file',
          bytes: bytes,
        );

        await DatabaseService.instance.updateFileAttachmentDownloaded(message.id, savedPath);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded: ${meta?.fileName}'),
              action: SnackBarAction(
                label: 'Open',
                onPressed: () => _openMedia(context, ref, savedPath),
              ),
            ),
          );
        }
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File content already saved or transfer pending')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  void _openMedia(BuildContext context, WidgetRef ref, [String? overridePath]) {
    final meta = message.fileMetadata;
    final fileName = meta?.fileName ?? 'File';
    final path = overridePath ?? meta?.localPath;
    final bytes = _getDecodedBytes(message.content);

    if (_isImage(fileName)) {
      InAppImageViewerDialog.show(
        context,
        imageBytes: bytes,
        localPath: path,
        fileName: fileName,
      );
    } else if (_isTextDocument(fileName)) {
      String textContent = '';
      if (bytes != null) {
        try {
          textContent = utf8.decode(bytes);
        } catch (_) {}
      }
      if (textContent.isEmpty && path != null && !kIsWeb && File(path).existsSync()) {
        try {
          textContent = File(path).readAsStringSync();
        } catch (_) {}
      }
      if (textContent.isNotEmpty) {
        InAppTextViewerDialog.show(
          context,
          title: fileName,
          content: textContent,
        );
        return;
      }
      if (path != null) {
        LocalFileManager.instance.openFile(path);
      }
    } else {
      if (path != null) {
        LocalFileManager.instance.openFile(path);
      } else {
        _handleDownload(context, ref);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = message.fileMetadata;
    final isOutgoing = message.isOutgoing;
    final transfers = ref.watch(transferProvider);

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

    final hasLocalBytes = _getDecodedBytes(message.content) != null;
    final hasLocalFile = meta?.localPath != null && !kIsWeb && File(meta!.localPath!).existsSync();
    final isDownloaded = meta?.isDownloaded == true || activeTransfer.status == TransferStatus.completed || hasLocalFile;
    final isDownloading = activeTransfer.status == TransferStatus.transferring;

    final fileName = meta?.fileName ?? 'File';
    final isImageFile = _isImage(fileName);
    final rawBytes = _getDecodedBytes(message.content);

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
              // Image Thumbnail Preview (if image)
              if (isImageFile && (rawBytes != null || hasLocalFile)) ...[
                GestureDetector(
                  onTap: () => _openMedia(context, ref),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    constraints: const BoxConstraints(maxHeight: 180),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: DevSyncColors.surfaceVariant,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildThumbnail(rawBytes, meta?.localPath),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.fullscreen_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

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
                          fileName,
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
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: DevSyncColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Download Progress Bar (when transferring)
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

              const SizedBox(height: 10),

              // Action Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // View / Open button
                      ElevatedButton.icon(
                        onPressed: () => _openMedia(context, ref),
                        icon: Icon(
                          isImageFile
                              ? Icons.visibility_rounded
                              : (_isTextDocument(fileName) ? Icons.article_rounded : Icons.open_in_new_rounded),
                          size: 14,
                        ),
                        label: Text(
                          isImageFile ? 'View' : (_isTextDocument(fileName) ? 'View Doc' : 'Open'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DevSyncColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),

                      // Download button if not downloaded or if raw bytes available to save to disk
                      if (!isDownloaded || (hasLocalBytes && !hasLocalFile)) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _handleDownload(context, ref),
                          icon: const Icon(Icons.download_rounded, size: 14),
                          label: const Text('Download', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: DevSyncColors.secondary,
                            side: const BorderSide(color: DevSyncColors.secondary),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ],
                  ),

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
