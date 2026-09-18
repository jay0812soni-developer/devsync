import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_theme.dart';
import 'features/chat/presentation/chat_screen.dart';
import 'features/devices/presentation/device_list_screen.dart';
import 'features/devices/presentation/device_providers.dart';

class DevSyncApp extends ConsumerWidget {
  const DevSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'DevSync',
      debugShowCheckedModeBanner: false,
      theme: DevSyncTheme.darkTheme,
      home: const DevSyncHomeScaffold(),
    );
  }
}

class DevSyncHomeScaffold extends ConsumerWidget {
  const DevSyncHomeScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPeer = ref.watch(selectedPeerProvider);
    final isWideScreen = MediaQuery.of(context).size.width > 750;

    if (!isWideScreen) {
      // Mobile Single-Pane Navigation
      if (selectedPeer != null) {
        return ChatScreen(peer: selectedPeer);
      }
      return const DeviceListScreen();
    }

    // Desktop / Tablet Dual-Pane Layout (WhatsApp Web Style)
    return Scaffold(
      body: Row(
        children: [
          // Left Pane: Device List
          const SizedBox(
            width: 360,
            child: DeviceListScreen(),
          ),
          const VerticalDivider(width: 1),

          // Right Pane: Active Chat or Empty State
          Expanded(
            child: selectedPeer != null
                ? ChatScreen(key: ValueKey(selectedPeer.id), peer: selectedPeer)
                : Container(
                    color: DevSyncColors.background,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: DevSyncColors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: DevSyncColors.border),
                            ),
                            child: const Icon(
                              Icons.devices_rounded,
                              size: 48,
                              color: DevSyncColors.primary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'DevSync Multi-Device Peer System',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: DevSyncColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Select a device to start exchanging code, files, or messages.\nDirect high-speed transfer on LAN with zero-retention cloud fallback.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: DevSyncColors.textMuted, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
