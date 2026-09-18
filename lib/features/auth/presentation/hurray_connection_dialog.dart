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
      backgroundColor: const Color(0xFF0D1117),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: DevSyncColors.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Celebratory Animated Glow Badge
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFF00F5D4), Color(0xFF7B2CBF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00F5D4).withValues(alpha: 0.4),
                    blurRadius: 30,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 46,
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              '🎉 Hurray! Complete!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Connection Established Successfully',
              style: TextStyle(
                fontSize: 14,
                color: DevSyncColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 16),

            // Paired Device Details Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF21262D),
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
                color: const Color(0xFF101622),
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
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Start Syncing Worldwide',
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
