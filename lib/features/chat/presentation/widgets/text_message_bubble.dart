import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_theme.dart';
import '../../../../shared/utils/formatters.dart';
import '../../domain/message_model.dart';
import 'status_tick_icon.dart';

class TextMessageBubble extends StatelessWidget {
  final MessageModel message;

  const TextMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: message.content));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message copied to clipboard'),
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
              SelectableText(
                message.content,
                style: const TextStyle(
                  fontSize: 14,
                  color: DevSyncColors.textPrimary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
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
        ),
      ),
    );
  }
}
