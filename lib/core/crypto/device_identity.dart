import 'dart:convert';
import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../storage/database_service.dart';

/// Represents this physical device's sovereign cryptographic identity.
class DeviceIdentity {
  final String deviceId;
  final String deviceName;
  final String platform;
  final String signingPublicKeyBase64; // Ed25519 public key
  final String exchangePublicKeyBase64; // X25519 public key
  final SimpleKeyPair signingKeyPair;
  final SimpleKeyPair exchangeKeyPair;

  DeviceIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.signingPublicKeyBase64,
    required this.exchangePublicKeyBase64,
    required this.signingKeyPair,
    required this.exchangeKeyPair,
  });

  Map<String, dynamic> toPublicJson({String? lanIp, int? lanPort}) {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform,
      'signingPublicKey': signingPublicKeyBase64,
      'exchangePublicKey': exchangePublicKeyBase64,
      'lanIp': lanIp,
      'lanPort': lanPort,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }
}

class DeviceIdentityManager {
  static const _keyDeviceId = 'devsync_device_id';
  static const _keyDeviceName = 'devsync_device_name';
  static const _keySigningPrivateKey = 'devsync_signing_private_key';
  static const _keyExchangePrivateKey = 'devsync_exchange_private_key';

  final FlutterSecureStorage _storage;
  final Ed25519 _ed25519 = Ed25519();
  final X25519 _x25519 = X25519();

  DeviceIdentity? _cachedIdentity;

  DeviceIdentityManager({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  DeviceIdentity? get identity => _cachedIdentity;

  Future<String?> _read(String key) async {
    try {
      final secure = await _storage.read(key: key);
      if (secure != null && secure.isNotEmpty) return secure;
    } catch (e) {
      debugPrint('Secure storage read failed for $key: $e');
    }
    return DatabaseService.instance.readIdentityField(key);
  }

  Future<void> _write(String key, String value) async {
    await DatabaseService.instance.writeIdentityField(key, value);
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('Secure storage write failed for $key: $e');
    }
  }

  /// Loads the existing device identity from secure storage, or creates one on first boot.
  Future<DeviceIdentity> getOrCreateIdentity() async {
    if (_cachedIdentity != null) return _cachedIdentity!;

    final existingDeviceId = await _read(_keyDeviceId);
    final existingSigningPriv = await _read(_keySigningPrivateKey);
    final existingExchangePriv = await _read(_keyExchangePrivateKey);
    final existingName = await _read(_keyDeviceName);

    if (existingDeviceId != null &&
        existingSigningPriv != null &&
        existingExchangePriv != null) {
      // Reconstruct existing key pairs
      final signingPrivBytes = base64Decode(existingSigningPriv);
      final signingKeyPair = await _ed25519.newKeyPairFromSeed(signingPrivBytes);
      final signingPubKey = await signingKeyPair.extractPublicKey();

      final exchangePrivBytes = base64Decode(existingExchangePriv);
      final exchangeKeyPair = await _x25519.newKeyPairFromSeed(exchangePrivBytes);
      final exchangePubKey = await exchangeKeyPair.extractPublicKey();

      _cachedIdentity = DeviceIdentity(
        deviceId: existingDeviceId,
        deviceName: existingName ?? _getDefaultDeviceName(),
        platform: _detectPlatform(),
        signingPublicKeyBase64: base64Encode(signingPubKey.bytes),
        exchangePublicKeyBase64: base64Encode(exchangePubKey.bytes),
        signingKeyPair: signingKeyPair,
        exchangeKeyPair: exchangeKeyPair,
      );
      return _cachedIdentity!;
    }

    // First time launch: Generate fresh sovereign identity
    final signingSeed = List<int>.generate(32, (i) => (DateTime.now().microsecondsSinceEpoch + i * 31) % 256);
    final signingKeyPair = await _ed25519.newKeyPairFromSeed(signingSeed);
    final signingPubKey = await signingKeyPair.extractPublicKey();

    final exchangeSeed = List<int>.generate(32, (i) => (DateTime.now().microsecondsSinceEpoch + i * 47) % 256);
    final exchangeKeyPair = await _x25519.newKeyPairFromSeed(exchangeSeed);
    final exchangePubKey = await exchangeKeyPair.extractPublicKey();

    // Deterministic Device ID: DEV-[First 8 hex chars of SHA-256 of signing public key]
    final hash = dart_crypto.sha256.convert(signingPubKey.bytes).toString();
    final deviceId = 'DEV-${hash.substring(0, 8).toUpperCase()}';
    final deviceName = _getDefaultDeviceName();

    await _write(_keyDeviceId, deviceId);
    await _write(_keyDeviceName, deviceName);
    await _write(_keySigningPrivateKey, base64Encode(signingSeed));
    await _write(_keyExchangePrivateKey, base64Encode(exchangeSeed));

    _cachedIdentity = DeviceIdentity(
      deviceId: deviceId,
      deviceName: deviceName,
      platform: _detectPlatform(),
      signingPublicKeyBase64: base64Encode(signingPubKey.bytes),
      exchangePublicKeyBase64: base64Encode(exchangePubKey.bytes),
      signingKeyPair: signingKeyPair,
      exchangeKeyPair: exchangeKeyPair,
    );

    return _cachedIdentity!;
  }

  /// Updates the friendly name of this device (e.g., "Jay's MacBook Pro M3").
  Future<void> updateDeviceName(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    _cachedIdentity ??= await getOrCreateIdentity();
    await _write(_keyDeviceName, trimmed);
    _cachedIdentity = DeviceIdentity(
      deviceId: _cachedIdentity!.deviceId,
      deviceName: trimmed,
      platform: _cachedIdentity!.platform,
      signingPublicKeyBase64: _cachedIdentity!.signingPublicKeyBase64,
      exchangePublicKeyBase64: _cachedIdentity!.exchangePublicKeyBase64,
      signingKeyPair: _cachedIdentity!.signingKeyPair,
      exchangeKeyPair: _cachedIdentity!.exchangeKeyPair,
    );
  }

  String _getDefaultDeviceName() {
    if (kIsWeb) return 'Browser';
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.macOS:
        return 'Mac';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iPhone';
      default:
        return 'This device';
    }
  }

  String _detectPlatform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'unknown';
    }
  }
}
