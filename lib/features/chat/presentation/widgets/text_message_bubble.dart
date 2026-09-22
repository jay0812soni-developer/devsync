import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_theme.dart';
import '../../../../shared/utils/formatters.dart';
import '../../domain/message_model.dart';
import 'status_tick_icon.dart';

class TextMessageBubble extends StatelessWidget {
  final MessageModel message;
  final VoidCallback? onLongPress;

  const TextMessageBubble({super.key, required this.message, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        onLongPress: onLongPress ??
            () {
              Clipboard.setData(ClipboardData(text: message.content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message copied'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
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
              color: DevSyncColors.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.replyPreview != null && message.replyPreview!.isNotEmpty && !message.isDeleted)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: DevSyncColors.background.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(4),
                    border: const Border(left: BorderSide(color: DevSyncColors.primary, width: 3)),
                  ),
                  child: Text(
                    message.replyPreview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: DevSyncColors.textSecondary),
                  ),
                ),
              Text(
                message.isDeleted ? 'This message was deleted' : message.content,
                style: TextStyle(
                  fontSize: 14.5,
                  color: message.isDeleted ? DevSyncColors.textMuted : DevSyncColors.textPrimary,
                  fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (message.isStarred) ...[
                    const Icon(Icons.star_rounded, size: 12, color: DevSyncColors.warning),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    Formatters.formatClock(message.timestamp),
                    style: const TextStyle(fontSize: 11, color: DevSyncColors.textMuted),
                  ),
                  if (isOutgoing) ...[
                    const SizedBox(width: 4),
                    StatusTickIcon(status: message.status),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
