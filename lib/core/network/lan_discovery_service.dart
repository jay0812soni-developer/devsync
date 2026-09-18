import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import '../crypto/device_identity.dart';
import '../../features/devices/domain/device_model.dart';

class LanDiscoveryService {
  static LanDiscoveryService? _instance;
  static LanDiscoveryService get instance => _instance ??= LanDiscoveryService._();

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  DeviceIdentity? _identity;
  int _lanServerPort = AppConstants.defaultLanPort;
  String? _cachedLocalIp;

  final _peerDiscoveredController = StreamController<DeviceModel>.broadcast();
  Stream<DeviceModel> get onPeerDiscovered => _peerDiscoveredController.stream;

  LanDiscoveryService._();

  String? get localIp => _cachedLocalIp;

  /// Starts the UDP discovery beacon and listener
  Future<void> start({
    required DeviceIdentity identity,
    required int lanServerPort,
  }) async {
    _identity = identity;
    _lanServerPort = lanServerPort;

    await _resolveLocalIp();

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.defaultDiscoveryPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _socket?.broadcastEnabled = true;

      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            _handleIncomingPacket(datagram);
          }
        }
      });

      // Broadcast beacon immediately and every 4 seconds
      _broadcastBeacon();
      _beaconTimer = Timer.periodic(const Duration(seconds: 4), (_) => _broadcastBeacon());
    } catch (e) {
      debugPrint('LanDiscoveryService bind error: $e');
    }
  }

  /// Broadcasts our device presence beacon to 255.255.255.255
  void _broadcastBeacon() {
    if (_socket == null || _identity == null) return;

    try {
      final packet = {
        'type': 'devsync_beacon',
        'id': _identity!.deviceId,
        'name': _identity!.deviceName,
        'platform': _identity!.platform,
        'signingPublicKey': _identity!.signingPublicKeyBase64,
        'exchangePublicKey': _identity!.exchangePublicKeyBase64,
        'port': _lanServerPort,
      };

      final data = utf8.encode(jsonEncode(packet));
      _socket?.send(data, InternetAddress('255.255.255.255'), AppConstants.defaultDiscoveryPort);
    } catch (e) {
      debugPrint('Broadcast error: $e');
    }
  }

  /// Handles incoming datagrams from other peers
  void _handleIncomingPacket(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data);
      final json = jsonDecode(text) as Map<String, dynamic>;

      if (json['type'] == 'devsync_beacon' || json['type'] == 'devsync_reply') {
        final peerId = json['id'] as String?;
        if (peerId == null || peerId == _identity?.deviceId) {
          // Ignore own broadcasts
          return;
        }

        final senderIp = datagram.address.address;
        final peerPort = (json['port'] as int?) ?? AppConstants.defaultLanPort;

        final device = DeviceModel(
          id: peerId,
          name: (json['name'] as String?) ?? 'Discovered Device',
          platform: (json['platform'] as String?) ?? 'unknown',
          signingPublicKey: (json['signingPublicKey'] as String?) ?? '',
          exchangePublicKey: (json['exchangePublicKey'] as String?) ?? '',
          lanIp: senderIp,
          lanPort: peerPort,
          isOnline: true,
          isLanAvailable: true,
          lastSeen: DateTime.now(),
        );

        _peerDiscoveredController.add(device);

        // If it was a beacon, reply directly to sender so they discover us immediately
        if (json['type'] == 'devsync_beacon') {
          _sendDirectReply(datagram.address, datagram.port);
        }
      }
    } catch (e) {
      debugPrint('Error handling incoming datagram: $e');
    }
  }

  void _sendDirectReply(InternetAddress address, int port) {
    if (_socket == null || _identity == null) return;
    try {
      final packet = {
        'type': 'devsync_reply',
        'id': _identity!.deviceId,
        'name': _identity!.deviceName,
        'platform': _identity!.platform,
        'signingPublicKey': _identity!.signingPublicKeyBase64,
        'exchangePublicKey': _identity!.exchangePublicKeyBase64,
        'port': _lanServerPort,
      };
      final data = utf8.encode(jsonEncode(packet));
      _socket?.send(data, address, port);
    } catch (_) {}
  }

  /// Inspects network interfaces to find the active Wi-Fi / Ethernet IPv4 address
  Future<String?> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254.')) {
            _cachedLocalIp = addr.address;
            return _cachedLocalIp;
          }
        }
      }
    } catch (e) {
      debugPrint('Error listing network interfaces: $e');
    }
    return null;
  }

  void stop() {
    _beaconTimer?.cancel();
    _socket?.close();
    _socket = null;
  }
}
