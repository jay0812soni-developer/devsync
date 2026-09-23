import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/network/relay_api_service.dart';
import '../../../core/storage/database_service.dart';
import 'device_providers.dart';
import 'qr_scanner_sheet.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final myState = ref.read(myDeviceProvider);
      if (myState.identity != null) {
        RelayApiService.instance.registerDevice(
          myState.identity!,
          lanIp: myState.localIp,
          lanPort: myState.lanPort,
        );
      }
    });
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
    final connectionCode = DatabaseService.instance.getConnectionCode();

    final pairingPayload = jsonEncode({
      'type': 'devsync_pair',
      'code': connectionCode ?? '',
      'connectionCode': connectionCode ?? '',
      'id': identity?.deviceId ?? '',
      'name': identity?.deviceName ?? '',
      'platform': identity?.platform ?? '',
      'signingPublicKey': identity?.signingPublicKeyBase64 ?? '',
      'exchangePublicKey': identity?.exchangePublicKeyBase64 ?? '',
      'lanIp': myState.localIp,
      'lanPort': myState.lanPort,
    });

    return Container(
      height: 540,
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
                SingleChildScrollView(
                  child: Column(
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
                          size: 190,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (connectionCode != null && connectionCode.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Connection Code: ',
                              style: TextStyle(fontSize: 13, color: DevSyncColors.textSecondary),
                            ),
                            Text(
                              connectionCode,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: 2,
                                color: DevSyncColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        identity?.deviceName ?? identity?.deviceId ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
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
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () async {
                          final newCode = await RelayApiService.instance.generateSingleUsePairingCode();
                          if (newCode != null && context.mounted) {
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('New single-use code generated: $newCode (valid for 5 mins)')),
                            );
                          }
                        },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Generate Fresh Single-Use Code'),
                      ),
                    ],
                  ),
                ),

                // Tab 2: Manual Pairing / Scan QR / Paste Payload
                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Direct Scan QR Button
                      SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await QrScannerSheet.show(context);
                            if (result != null && context.mounted) {
                              if (result.peer != null) {
                                ref.read(peersProvider.notifier).addOrUpdatePeer(result.peer!);
                                ref.read(peersProvider.notifier).pairDevice(result.peer!.id);
                                await DatabaseService.instance.savePeer(result.peer!);
                              }
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result.peer != null
                                        ? 'Successfully paired with ${result.peer!.name}!'
                                        : 'Pairing code ${result.code} detected!',
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                          label: const Text('Scan Peer QR Code', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DevSyncColors.primary,
                            foregroundColor: DevSyncColors.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Expanded(child: Divider(color: DevSyncColors.border)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              'OR PASTE TOKEN / CODE',
                              style: TextStyle(fontSize: 11, color: DevSyncColors.textMuted, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Expanded(child: Divider(color: DevSyncColors.border)),
                        ],
                      ),
                      const SizedBox(height: 14),

                      TextField(
                        controller: _pasteController,
                        maxLines: 3,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Paste pairing JSON token or 6-digit code...',
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
                        onPressed: () async {
                          final parsed = PairingScanResult.parse(_pasteController.text);
                          if (parsed.peer != null) {
                            ref.read(peersProvider.notifier).addOrUpdatePeer(parsed.peer!);
                            ref.read(peersProvider.notifier).pairDevice(parsed.peer!.id);
                            await DatabaseService.instance.savePeer(parsed.peer!);
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Successfully paired with ${parsed.peer!.name}!')),
                            );
                          } else if (parsed.code != null) {
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Detected code: ${parsed.code}. Use in Login tab to pair.')),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Invalid pairing token or code.')),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: const Text('Pair Device'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DevSyncColors.secondary,
                          foregroundColor: DevSyncColors.onPrimary,
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
