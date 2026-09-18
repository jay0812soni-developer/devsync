import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_theme.dart';
import '../domain/device_model.dart';
import 'device_providers.dart';

class QrPairSheet extends ConsumerStatefulWidget {
  const QrPairSheet({super.key});

  @override
  ConsumerState<QrPairSheet> createState() => _QrPairSheetState();
}

class _QrPairSheetState extends ConsumerState<QrPairSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _pasteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myState = ref.watch(myDeviceProvider);
    final identity = myState.identity;

    final pairingPayload = jsonEncode({
      'id': identity?.deviceId ?? '',
      'name': identity?.deviceName ?? '',
      'platform': identity?.platform ?? '',
      'signingPublicKey': identity?.signingPublicKeyBase64 ?? '',
      'exchangePublicKey': identity?.exchangePublicKeyBase64 ?? '',
      'lanIp': myState.localIp,
      'lanPort': myState.lanPort,
    });

    return Container(
      height: 520,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: DevSyncColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: DevSyncColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          TabBar(
            controller: _tabController,
            indicatorColor: DevSyncColors.primary,
            labelColor: DevSyncColors.primary,
            unselectedLabelColor: DevSyncColors.textMuted,
            tabs: const [
              Tab(text: 'My Device QR', icon: Icon(Icons.qr_code_rounded, size: 20)),
              Tab(text: 'Pair with Peer', icon: Icon(Icons.link_rounded, size: 20)),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Show My QR Code
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: pairingPayload,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      identity?.deviceId ?? '',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: DevSyncColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: pairingPayload));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pairing payload copied to clipboard')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy Pairing Token'),
                    ),
                  ],
                ),

                // Tab 2: Manual Pairing / Paste Payload
                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Pair with another developer device without scanning. Paste the device pairing token or enter details below:',
                        style: TextStyle(color: DevSyncColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pasteController,
                        maxLines: 4,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Paste pairing JSON from another device...',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.paste, size: 18),
                            onPressed: () async {
                              final data = await Clipboard.getData(Clipboard.kTextPlain);
                              if (data?.text != null) {
                                _pasteController.text = data!.text!;
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: () {
                          try {
                            final raw = jsonDecode(_pasteController.text) as Map<String, dynamic>;
                            final peer = DeviceModel(
                              id: raw['id'] as String,
                              name: raw['name'] as String? ?? 'Paired Device',
                              platform: raw['platform'] as String? ?? 'unknown',
                              signingPublicKey: raw['signingPublicKey'] as String? ?? '',
                              exchangePublicKey: raw['exchangePublicKey'] as String? ?? '',
                              lanIp: raw['lanIp'] as String?,
                              lanPort: raw['lanPort'] as int?,
                              isOnline: true,
                              isLanAvailable: raw['lanIp'] != null,
                              lastSeen: DateTime.now(),
                              isPaired: true,
                            );

                            ref.read(peersProvider.notifier).addOrUpdatePeer(peer);
                            ref.read(peersProvider.notifier).pairDevice(peer.id);
                            Navigator.of(context).pop();

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Successfully paired with ${peer.name}!')),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Invalid pairing token: $e')),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: const Text('Pair Device'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DevSyncColors.secondary,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
