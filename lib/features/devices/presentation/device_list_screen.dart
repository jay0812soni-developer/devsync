import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/storage/database_service.dart';
import '../domain/device_model.dart';
import 'device_providers.dart';
import 'qr_pair_sheet.dart';

class DeviceListScreen extends ConsumerStatefulWidget {
  const DeviceListScreen({super.key});

  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'windows':
        return Icons.window_rounded;
      case 'macos':
        return Icons.apple_rounded;
      case 'linux':
        return Icons.terminal_rounded;
      case 'android':
        return Icons.android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  void _showRenameDialog(BuildContext context, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DevSyncColors.surface,
        title: const Text('Rename This Device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Workstation PC, M3 Mac...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(myDeviceProvider.notifier).renameDevice(controller.text);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: DevSyncColors.primary),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    final relayController = TextEditingController(text: DatabaseService.instance.getRelayUrl());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DevSyncColors.surface,
        title: const Text('Network & Relay Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vercel Message Relay URL:',
              style: TextStyle(fontSize: 13, color: DevSyncColors.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: relayController,
              decoration: const InputDecoration(
                hintText: 'https://devsync-backend.vercel.app',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Local LAN Direct transfers do not use bandwidth from this server.',
              style: TextStyle(fontSize: 11, color: DevSyncColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newUrl = relayController.text.trim();
              Navigator.of(ctx).pop();
              await DatabaseService.instance.setRelayUrl(newUrl);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Relay settings saved')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: DevSyncColors.primary),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myState = ref.watch(myDeviceProvider);
    final peers = ref.watch(peersProvider);

    final lanPeers = peers.where((p) => p.isLanAvailable).toList();
    final otherPeers = peers.where((p) => !p.isLanAvailable).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.sync_alt_rounded, color: DevSyncColors.primary),
            SizedBox(width: 8),
            Text(
              'DevSync',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Pair Device',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (ctx) => const QrPairSheet(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => _showSettingsDialog(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. "This Device" Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: DevSyncColors.primary.withValues(alpha: 0.15),
                        child: Icon(
                          _getPlatformIcon(myState.identity?.platform ?? ''),
                          color: DevSyncColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  myState.identity?.deviceName ?? 'This Device',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: DevSyncColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () {
                                    if (myState.identity != null) {
                                      _showRenameDialog(context, myState.identity!.deviceName);
                                    }
                                  },
                                  child: const Icon(Icons.edit, size: 14, color: DevSyncColors.textMuted),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              myState.identity?.deviceId ?? 'Generating ID...',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: DevSyncColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_2_rounded, color: DevSyncColors.textSecondary),
                        tooltip: 'Show Pairing QR',
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => const QrPairSheet(),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (kIsWeb) ...[
                        const Row(
                          children: [
                            Icon(Icons.cloud_done_rounded, size: 14, color: DevSyncColors.primary),
                            SizedBox(width: 6),
                            Text(
                              'Cloud Relay Mode',
                              style: TextStyle(fontSize: 12, color: DevSyncColors.textSecondary),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: DevSyncColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Web Instance',
                            style: TextStyle(fontSize: 10, color: DevSyncColors.primary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            const Icon(Icons.wifi_rounded, size: 14, color: DevSyncColors.secondary),
                            const SizedBox(width: 6),
                            Text(
                              'LAN: ${myState.localIp ?? "Detecting..."}:${myState.lanPort}',
                              style: const TextStyle(fontSize: 12, color: DevSyncColors.textSecondary),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: DevSyncColors.secondary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'HTTP Server Active',
                            style: TextStyle(fontSize: 10, color: DevSyncColors.secondary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Backend Relay Configuration Helper Banner
          if (DatabaseService.instance.getRelayUrl().isEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DevSyncColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DevSyncColors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, size: 22, color: DevSyncColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Connect Backend Relay',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: DevSyncColors.warning),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Click Configure to set your deployed devsync-backend Vercel URL.',
                          style: TextStyle(fontSize: 11, color: DevSyncColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _showSettingsDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DevSyncColors.warning,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Configure', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20),

          // 2. Discovered Devices (Local Wi-Fi)
          Row(
            children: [
              const Icon(Icons.radar_rounded, size: 18, color: DevSyncColors.secondary),
              const SizedBox(width: 6),
              const Text(
                'DISCOVERED ON LOCAL WI-FI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: DevSyncColors.textMuted,
                ),
              ),
              const Spacer(),
              if (lanPeers.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: DevSyncColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${lanPeers.length}',
                    style: const TextStyle(fontSize: 11, color: DevSyncColors.secondary, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (lanPeers.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DevSyncColors.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DevSyncColors.border.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: DevSyncColors.secondary),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Scanning local network via UDP beacon... Open DevSync on other devices on the same Wi-Fi.',
                      style: TextStyle(fontSize: 12, color: DevSyncColors.textMuted),
                    ),
                  ),
                ],
              ),
            )
          else
            ...lanPeers.map((peer) => _buildPeerTile(context, peer)),

          const SizedBox(height: 24),

          // 3. Paired & Remote Devices
          Row(
            children: [
              const Icon(Icons.devices_other_rounded, size: 18, color: DevSyncColors.primary),
              const SizedBox(width: 6),
              const Text(
                'PAIRED & REMOTE DEVICES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: DevSyncColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (otherPeers.isEmpty && lanPeers.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: DevSyncColors.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DevSyncColors.border.withValues(alpha: 0.4)),
              ),
              child: const Center(
                child: Text(
                  'No other devices added yet.\nScan pairing QR code or connect devices to the same Wi-Fi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: DevSyncColors.textMuted),
                ),
              ),
            )
          else
            ...otherPeers.map((peer) => _buildPeerTile(context, peer)),
        ],
      ),
    );
  }

  Widget _buildPeerTile(BuildContext context, DeviceModel peer) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: DevSyncColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DevSyncColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: DevSyncColors.surfaceVariant,
              child: Icon(_getPlatformIcon(peer.platform), color: DevSyncColors.primary, size: 20),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: peer.isLanAvailable ? DevSyncColors.secondary : DevSyncColors.primary,
                  border: Border.all(color: DevSyncColors.surface, width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Text(
              peer.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: DevSyncColors.textPrimary),
            ),
            const SizedBox(width: 8),
            if (peer.isLanAvailable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: DevSyncColors.secondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'LAN Direct',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: DevSyncColors.secondary),
                ),
              ),
          ],
        ),
        subtitle: Text(
          peer.id,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: DevSyncColors.textMuted),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: DevSyncColors.textMuted),
        onTap: () {
          ref.read(selectedPeerProvider.notifier).state = peer;
        },
      ),
    );
  }
}
