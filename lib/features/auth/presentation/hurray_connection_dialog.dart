import 'package:flutter/material.dart';
import '../../../app.dart';
import '../../../core/constants/app_theme.dart';
import '../../devices/domain/device_model.dart';

class HurrayConnectionDialog extends StatelessWidget {
  final DeviceModel? pairedDevice;
  final String connectionCode;
  final String? userEmail;

  const HurrayConnectionDialog({
    super.key,
    required this.pairedDevice,
    required this.connectionCode,
    this.userEmail,
  });

  static Future<void> show(
    BuildContext context, {
    required DeviceModel? pairedDevice,
    required String connectionCode,
    String? userEmail,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => HurrayConnectionDialog(
        pairedDevice: pairedDevice,
        connectionCode: connectionCode,
        userEmail: userEmail,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devName = pairedDevice?.name ?? 'Secondary Device';
    final devPlatform = pairedDevice?.platform ?? 'Remote';

    return Dialog(
      backgroundColor: DevSyncColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: DevSyncColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DevSyncColors.surfaceVariant,
                border: Border.all(color: DevSyncColors.border),
              ),
              child: const Center(
                child: Icon(
                  Icons.check_rounded,
                  color: DevSyncColors.primary,
                  size: 28,
                ),
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Connected',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: DevSyncColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'This device is on the account.',
              style: TextStyle(
                fontSize: 14,
                color: DevSyncColors.textSecondary,
              ),
            ),

            const SizedBox(height: 16),

            // Paired Device Details Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DevSyncColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DevSyncColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: DevSyncColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.devices_rounded,
                      color: DevSyncColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          devName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: DevSyncColors.secondary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                devPlatform.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: DevSyncColors.secondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'E2EE Paired',
                              style: TextStyle(fontSize: 11, color: DevSyncColors.success),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Connection Code Indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: DevSyncColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Network Code: ',
                    style: TextStyle(fontSize: 12, color: DevSyncColors.textSecondary),
                  ),
                  Text(
                    connectionCode,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      fontFamily: 'monospace',
                      color: DevSyncColors.primary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const DevSyncHomeScaffold()),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: DevSyncColors.primary,
                  foregroundColor: DevSyncColors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Open devices',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
