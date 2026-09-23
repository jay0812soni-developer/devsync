import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/crypto/device_identity.dart';
import '../../../core/network/lan_discovery_service.dart';
import '../../../core/network/relay_api_service.dart';
import '../../../core/network/sse_relay_client.dart';
import '../../../core/network/persistent_ws_client.dart';
import '../../../core/network/webrtc_service.dart';
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
    DeviceIdentity identity;
    try {
      identity = await _identityManager.getOrCreateIdentity();
    } catch (e) {
      debugPrint('Device identity failed: $e');
      return;
    }
    
    int port = 0;
    String? localIp;

    if (!kIsWeb) {
      final discovery = LanDiscoveryService.instance;
      await discovery.start(identity: identity, lanServerPort: 0);
      localIp = discovery.localIp;
    } else {
      localIp = 'Web Client';
    }

    state = state.copyWith(
      identity: identity,
      localIp: localIp,
      lanPort: port,
    );

    // Initialize WebRTC Service
    WebRtcService.instance.initialize(identity.deviceId);

    // Connect Persistent WebSocket Gateway
    PersistentWsClient.instance.connect(
      deviceId: identity.deviceId,
    );

    // Register with relay
    await RelayApiService.instance.registerDevice(
      identity,
      lanIp: localIp,
      lanPort: port,
    );

    // Start SSE stream for legacy fallback
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
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    if (state.identity == null) {
      final identity = await _identityManager.getOrCreateIdentity();
      state = state.copyWith(identity: identity);
    }
    await _identityManager.updateDeviceName(trimmed);
    final updated = _identityManager.identity;
    if (updated == null) return;
    state = MyDeviceState(
      identity: updated,
      localIp: state.localIp,
      lanPort: state.lanPort,
      isRelayConnected: state.isRelayConnected,
    );
    await RelayApiService.instance.registerDevice(
      updated,
      lanIp: state.localIp,
      lanPort: state.lanPort,
    );
  }
}

final myDeviceProvider = StateNotifierProvider<MyDeviceNotifier, MyDeviceState>((ref) {
  return MyDeviceNotifier(DeviceIdentityManager());
});

// --- Peers Provider (Discovered & Paired Devices in Mesh) ---

class PeersNotifier extends StateNotifier<List<DeviceModel>> {
  StreamSubscription? _discoverySub;
  StreamSubscription? _presenceSub;
  StreamSubscription? _deviceJoinedSub;
  Timer? _meshRefreshTimer;

  PeersNotifier() : super([]) {
    _loadStoredPeers();
    _listenToLanDiscovery();
    _listenToMeshEvents();
    refreshMeshPeers();
    // Periodically refresh personal mesh peers every 10 seconds
    // so all secondary and primary devices auto-discover the entire group
    _meshRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      refreshMeshPeers();
    });
  }

  void _loadStoredPeers() {
    final myId = DatabaseService.instance.readIdentityField('device_id');
    final allPeers = DatabaseService.instance.getAllPeers();
    state = allPeers.where((p) => myId == null || p.id != myId).toList();
  }

  void _listenToLanDiscovery() {
    _discoverySub = LanDiscoveryService.instance.onPeerDiscovered.listen((discovered) {
      addOrUpdatePeer(discovered);
    });
  }

  void _listenToMeshEvents() {
    _presenceSub = PersistentWsClient.instance.presenceStream.listen((data) {
      final devId = data['deviceId'] as String?;
      final isOnline = data['isOnline'] as bool? ?? false;
      if (devId != null) {
        updatePeerPresence(devId, isOnline);
      }
    });

    _deviceJoinedSub = PersistentWsClient.instance.deviceJoinedStream.listen((data) {
      final devData = data['device'] as Map<String, dynamic>?;
      if (devData != null) {
        final devId = devData['deviceId'] as String?;
        final myId = DatabaseService.instance.readIdentityField('device_id');
        if (devId == null || (myId != null && devId == myId)) return;

        final peer = DeviceModel(
          id: devId,
          name: devData['deviceName'] as String? ?? 'Mesh Peer',
          platform: devData['platform'] as String? ?? 'unknown',
          signingPublicKey: devData['signingPublicKey'] as String? ?? '',
          exchangePublicKey: devData['exchangePublicKey'] as String? ?? '',
          lanIp: devData['lanIp'] as String?,
          lanPort: devData['lanPort'] as int?,
          isOnline: true,
          isLanAvailable: false,
          lastSeen: DateTime.now(),
        );
        addOrUpdatePeer(peer);
      }
    });
  }

  Future<void> refreshMeshPeers() async {
    final myId = DatabaseService.instance.readIdentityField('device_id');
    final list = await RelayApiService.instance.fetchGroupMembers();
    if (list.isNotEmpty) {
      for (final p in list) {
        if (myId == null || p.id != myId) {
          addOrUpdatePeer(p);
        }
      }
    }
  }

  void updatePeerPresence(String deviceId, bool isOnline) {
    final idx = state.indexWhere((p) => p.id == deviceId);
    if (idx >= 0) {
      final updated = state[idx].copyWith(isOnline: isOnline);
      final newList = List<DeviceModel>.from(state);
      newList[idx] = updated;
      state = newList;
      DatabaseService.instance.savePeer(updated);
    }
  }

  void addOrUpdatePeer(DeviceModel peer) {
    final myId = DatabaseService.instance.readIdentityField('device_id');
    if (myId != null && peer.id == myId) {
      return; // Never display local device in remote peer list
    }

    final existingIndex = state.indexWhere((p) => p.id == peer.id);
    if (existingIndex >= 0) {
      final current = state[existingIndex];
      final updated = current.copyWith(
        name: peer.name.isNotEmpty ? peer.name : current.name,
        platform: peer.platform.isNotEmpty ? peer.platform : current.platform,
        lanIp: peer.lanIp ?? current.lanIp,
        lanPort: peer.lanPort ?? current.lanPort,
        isLanAvailable: peer.isLanAvailable,
        isOnline: peer.isOnline,
        lastSeen: DateTime.now(),
        signingPublicKey: peer.signingPublicKey.isNotEmpty ? peer.signingPublicKey : current.signingPublicKey,
        exchangePublicKey: peer.exchangePublicKey.isNotEmpty ? peer.exchangePublicKey : current.exchangePublicKey,
      );

      final newList = List<DeviceModel>.from(state);
      newList[existingIndex] = updated;
      state = newList;
      DatabaseService.instance.savePeer(updated);
    } else {
      // New device discovered in mesh
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
    _meshRefreshTimer?.cancel();
    _discoverySub?.cancel();
    _presenceSub?.cancel();
    _deviceJoinedSub?.cancel();
    super.dispose();
  }
}

final peersProvider = StateNotifierProvider<PeersNotifier, List<DeviceModel>>((ref) {
  return PeersNotifier();
});

// Currently selected peer in chat view
final selectedPeerProvider = StateProvider<DeviceModel?>((ref) => null);
