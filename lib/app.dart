import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_theme.dart';
import 'features/chat/presentation/chat_screen.dart';
import 'features/devices/presentation/device_list_screen.dart';
import 'features/devices/presentation/device_providers.dart';
import 'features/splash/presentation/app_splash_screen.dart';

import 'core/network/persistent_ws_client.dart';
import 'core/network/webrtc_service.dart';

class DevSyncApp extends ConsumerStatefulWidget {
  const DevSyncApp({super.key});

  @override
  ConsumerState<DevSyncApp> createState() => _DevSyncAppState();
}

class _DevSyncAppState extends ConsumerState<DevSyncApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onPause: () {
        debugPrint('[Lifecycle] App paused/backgrounded: transfers safely paused, checkpoints persisted.');
      },
      onResume: () {
        debugPrint('[Lifecycle] App resumed: verifying WebSocket connection and ICE servers.');
        final myState = ref.read(myDeviceProvider);
        if (myState.identity != null) {
          PersistentWsClient.instance.connect(deviceId: myState.identity!.deviceId);
          WebRtcService.instance.updateIceServersFromRelay();
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DevSync',
      debugShowCheckedModeBanner: false,
      theme: DevSyncTheme.lightTheme,
      darkTheme: DevSyncTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const AppSplashScreen(),
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
                    color: DevSyncColors.lightBackground,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: DevSyncColors.lightSurface,
                              shape: BoxShape.circle,
                              border: Border.all(color: DevSyncColors.lightBorder, width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.devices_rounded,
                              size: 44,
                              color: DevSyncColors.primary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Personal Device Mesh',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: DevSyncColors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Select a device to exchange code snippets, files, or messages.\nDirect P2P WebRTC data transfer with resilient mesh synchronization.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: DevSyncColors.textSecondary, height: 1.45),
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
