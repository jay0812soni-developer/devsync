import 'dart:async';
import '../crypto/device_identity.dart';
import '../../features/devices/domain/device_model.dart';

class LanDiscoveryService {
  static LanDiscoveryService? _instance;
  static LanDiscoveryService get instance => _instance ??= LanDiscoveryService._();

  LanDiscoveryService._();

  final _peerDiscoveredController = StreamController<DeviceModel>.broadcast();
  Stream<DeviceModel> get onPeerDiscovered => _peerDiscoveredController.stream;

  String? get localIp => null;

  Future<void> start({
    required DeviceIdentity identity,
    required int lanServerPort,
  }) async {}

  void stop() {
    _peerDiscoveredController.close();
  }
}
