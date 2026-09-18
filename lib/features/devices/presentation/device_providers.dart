import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/crypto/device_identity.dart';
import '../../../core/network/lan_discovery_service.dart';
import '../../../core/network/lan_http_server.dart';
import '../../../core/network/relay_api_service.dart';
import '../../../core/network/sse_relay_client.dart';
import '../../../core/storage/database_service.dart';
import '../domain/device_model.dart';

// --- My Device Identity Provider ---

class MyDeviceState {
  final DeviceIdentity? identity;
  final String? localIp;
  final int lanPort;
  final bool isRelayConnected;

  MyDeviceState({
    this.identity,
    this.localIp,
    this.lanPort = 42042,
    this.isRelayConnected = false,
  });

  MyDeviceState copyWith({
    DeviceIdentity? identity,
    String? localIp,
    int? lanPort,
    bool? isRelayConnected,
  }) {
    return MyDeviceState(
      identity: identity ?? this.identity,
      localIp: localIp ?? this.localIp,
      lanPort: lanPort ?? this.lanPort,
      isRelayConnected: isRelayConnected ?? this.isRelayConnected,
    );
  }
}

class MyDeviceNotifier extends StateNotifier<MyDeviceState> {
  final DeviceIdentityManager _identityManager;

  MyDeviceNotifier(this._identityManager) : super(MyDeviceState()) {
    init();
  }

  Future<void> init() async {
    final identity = await _identityManager.getOrCreateIdentity();
    final lanServer = LanHttpServer.instance;
    final port = await lanServer.start(identity);

    final discovery = LanDiscoveryService.instance;
    await discovery.start(identity: identity, lanServerPort: port);

    state = state.copyWith(
      identity: identity,
      localIp: discovery.localIp,
      lanPort: port,
    );

    // Register with Vercel relay
    await RelayApiService.instance.registerDevice(
      identity,
      lanIp: discovery.localIp,
      lanPort: port,
    );

    // Start SSE stream
    SseRelayClient.instance.startListening(identity.deviceId);

    // Re-register heartbeat every 60s
    Timer.periodic(const Duration(seconds: 60), (_) {
      if (state.identity != null) {
        RelayApiService.instance.registerDevice(
          state.identity!,
          lanIp: state.localIp,
          lanPort: state.lanPort,
        );
      }
    });
  }

  Future<void> renameDevice(String newName) async {
    await _identityManager.updateDeviceName(newName);
    if (state.identity != null) {
      final updated = _identityManager.identity;
      state = state.copyWith(identity: updated);
      if (updated != null) {
        await RelayApiService.instance.registerDevice(
          updated,
          lanIp: state.localIp,
          lanPort: state.lanPort,
        );
      }
    }
  }
}

final myDeviceProvider = StateNotifierProvider<MyDeviceNotifier, MyDeviceState>((ref) {
  return MyDeviceNotifier(DeviceIdentityManager());
});

// --- Peers Provider (Discovered & Paired Devices) ---

class PeersNotifier extends StateNotifier<List<DeviceModel>> {
  StreamSubscription? _discoverySub;

  PeersNotifier() : super([]) {
    _loadStoredPeers();
    _listenToLanDiscovery();
  }

  void _loadStoredPeers() {
    state = DatabaseService.instance.getAllPeers();
  }

  void _listenToLanDiscovery() {
    _discoverySub = LanDiscoveryService.instance.onPeerDiscovered.listen((discovered) {
      addOrUpdatePeer(discovered);
    });
  }

  void addOrUpdatePeer(DeviceModel peer) {
    final existingIndex = state.indexWhere((p) => p.id == peer.id);
    if (existingIndex >= 0) {
      final current = state[existingIndex];
      final updated = current.copyWith(
        name: peer.name.isNotEmpty ? peer.name : current.name,
        platform: peer.platform.isNotEmpty ? peer.platform : current.platform,
        lanIp: peer.lanIp ?? current.lanIp,
        lanPort: peer.lanPort ?? current.lanPort,
        isLanAvailable: peer.isLanAvailable,
        isOnline: true,
        lastSeen: DateTime.now(),
        signingPublicKey: peer.signingPublicKey.isNotEmpty ? peer.signingPublicKey : current.signingPublicKey,
        exchangePublicKey: peer.exchangePublicKey.isNotEmpty ? peer.exchangePublicKey : current.exchangePublicKey,
      );

      final newList = List<DeviceModel>.from(state);
      newList[existingIndex] = updated;
      state = newList;
      DatabaseService.instance.savePeer(updated);
    } else {
      // New device discovered
      state = [...state, peer];
      DatabaseService.instance.savePeer(peer);
    }
  }

  Future<void> pairDevice(String deviceId) async {
    final index = state.indexWhere((p) => p.id == deviceId);
    if (index >= 0) {
      final updated = state[index].copyWith(isPaired: true);
      final newList = List<DeviceModel>.from(state);
      newList[index] = updated;
      state = newList;
      await DatabaseService.instance.savePeer(updated);
    }
  }

  Future<void> removePeer(String deviceId) async {
    state = state.where((p) => p.id != deviceId).toList();
    await DatabaseService.instance.deletePeer(deviceId);
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    super.dispose();
  }
}

final peersProvider = StateNotifierProvider<PeersNotifier, List<DeviceModel>>((ref) {
  return PeersNotifier();
});

// Currently selected peer in chat view
final selectedPeerProvider = StateProvider<DeviceModel?>((ref) => null);
