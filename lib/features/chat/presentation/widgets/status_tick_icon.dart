import 'package:flutter/material.dart';
import '../../../../core/constants/app_theme.dart';
import '../../domain/message_model.dart';

class StatusTickIcon extends StatelessWidget {
  final MessageStatus status;

  const StatusTickIcon({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.pending:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: DevSyncColors.textMuted,
          ),
        );
      case MessageStatus.sent:
        return const Icon(
          Icons.check,
          size: 14,
          color: DevSyncColors.textSecondary,
        );
      case MessageStatus.delivered:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check, size: 13, color: DevSyncColors.textSecondary),
            Transform.translate(
              offset: const Offset(-6, 0),
              child: const Icon(Icons.check, size: 13, color: DevSyncColors.textSecondary),
            ),
          ],
        );
      case MessageStatus.read:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check, size: 13, color: DevSyncColors.primary),
            Transform.translate(
              offset: const Offset(-6, 0),
              child: const Icon(Icons.check, size: 13, color: DevSyncColors.primary),
            ),
          ],
        );
    }
  }
}
