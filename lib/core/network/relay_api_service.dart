import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../crypto/device_identity.dart';
import '../../features/devices/domain/device_model.dart';
import '../storage/database_service.dart';

class RelayApiService {
  static RelayApiService? _instance;
  static RelayApiService get instance => _instance ??= RelayApiService._();

  final http.Client _client = http.Client();

  RelayApiService._();

  String get _baseUrl => DatabaseService.instance.getRelayUrl().replaceAll(RegExp(r'/+$'), '');

  /// Registers this device's public keys and presence with the Vercel relay
  Future<bool> registerDevice(DeviceIdentity identity, {String? lanIp, int? lanPort}) async {
    try {
      final url = Uri.parse('$_baseUrl/api/devices/register');
      final body = jsonEncode({
        'deviceId': identity.deviceId,
        'deviceName': identity.deviceName,
        'platform': identity.platform,
        'signingPublicKey': identity.signingPublicKeyBase64,
        'exchangePublicKey': identity.exchangePublicKeyBase64,
        'lanIp': lanIp,
        'lanPort': lanPort,
      });

      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Relay register error: $e');
      return false;
    }
  }

  /// Sends an encrypted message packet through the Vercel relay
  Future<bool> sendEncryptedMessage({
    required String messageId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required String type,
    required String cipherText,
    required String nonce,
    required String mac,
    String? codeLanguage,
    String? fileName,
    int? fileSize,
    String? sha256,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/messages/send');
      final payload = {
        'id': messageId,
        'senderDeviceId': senderDeviceId,
        'recipientDeviceId': recipientDeviceId,
        'type': type,
        'cipherText': cipherText,
        'nonce': nonce,
        'mac': mac,
        'codeLanguage': codeLanguage,
        'fileName': fileName,
        'fileSize': fileSize,
        'sha256': sha256,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Relay send message error: $e');
      return false;
    }
  }

  /// Confirms message delivery and triggers deletion from server queue
  Future<bool> acknowledgeMessage({
    required String messageId,
    required String recipientDeviceId,
    String status = 'delivered',
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/messages/ack');
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'messageId': messageId,
          'recipientDeviceId': recipientDeviceId,
          'status': status,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Relay ack error: $e');
      return false;
    }
  }

  /// Queries peer device registration details (public keys, LAN IP)
  Future<DeviceModel?> fetchDevice(String deviceId) async {
    try {
      final url = Uri.parse('$_baseUrl/api/devices/register?deviceId=$deviceId');
      final response = await _client.get(url);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['device'] as Map<String, dynamic>?;
        if (data != null) {
          return DeviceModel(
            id: data['deviceId'] as String,
            name: data['deviceName'] as String? ?? 'Remote Device',
            platform: data['platform'] as String? ?? 'unknown',
            signingPublicKey: data['signingPublicKey'] as String? ?? '',
            exchangePublicKey: data['exchangePublicKey'] as String? ?? '',
            lanIp: data['lanIp'] as String?,
            lanPort: data['lanPort'] as int?,
            isOnline: true,
            isLanAvailable: false,
            lastSeen: DateTime.now(),
          );
        }
      }
    } catch (e) {
      debugPrint('Relay fetch device error: $e');
    }
    return null;
  }
}
