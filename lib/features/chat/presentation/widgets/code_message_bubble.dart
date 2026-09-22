import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import '../../../../core/constants/app_theme.dart';
import '../../../../shared/utils/formatters.dart';
import '../../domain/message_model.dart';
import 'status_tick_icon.dart';

class CodeMessageBubble extends StatelessWidget {
  final MessageModel message;
  final VoidCallback? onLongPress;

  const CodeMessageBubble({super.key, required this.message, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final language = message.codeLanguage ?? 'dart';
    final isOutgoing = message.isOutgoing;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: Language badge + Copy button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(11),
                  topRight: Radius.circular(11),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.code, size: 14, color: DevSyncColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    language.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: DevSyncColors.accent,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied $language snippet to clipboard'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_rounded, size: 13, color: DevSyncColors.textSecondary),
                          SizedBox(width: 4),
                          Text(
                            'Copy',
                            style: TextStyle(fontSize: 11, color: DevSyncColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Highlighted Code Block
            ClipRRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(10),
                child: HighlightView(
                  message.content,
                  language: language,
                  theme: atomOneDarkTheme,
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ),

            // Footer: Timestamp & Delivery Status
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6, top: 2),
              child: Row(
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
            ),
          ],
        ),
      ),
      ),
    );
  }
}
