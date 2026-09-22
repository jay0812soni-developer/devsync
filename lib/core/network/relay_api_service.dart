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
  Future<bool> registerDevice(
    DeviceIdentity identity, {
    String? lanIp,
    int? lanPort,
    String? connectionCode,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/devices/register');
      final code = connectionCode ?? DatabaseService.instance.getConnectionCode();
      final body = jsonEncode({
        'deviceId': identity.deviceId,
        'deviceName': identity.deviceName,
        'platform': identity.platform,
        'signingPublicKey': identity.signingPublicKeyBase64,
        'exchangePublicKey': identity.exchangePublicKeyBase64,
        'lanIp': lanIp,
        'lanPort': lanPort,
        if (code != null && code.trim().isNotEmpty)
          'connectionCode': code.replaceAll(RegExp(r'[^0-9]'), '').trim(),
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

  // --- Auth & Connection Code Pairing APIs ---

  /// Requests a 6-digit OTP sent via Nodemailer to the user's email
  Future<Map<String, dynamic>> sendRegistrationOtp({
    required String email,
    required String phone,
    String? name,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/auth/register-otp');
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'phone': phone.trim(),
          'name': name,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to send OTP'};
      }
    } catch (e) {
      debugPrint('sendRegistrationOtp error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Verifies the 6-digit OTP, registers the user, and links this device
  Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
    required DeviceIdentity identity,
    String? phone,
    String? lanIp,
    int? lanPort,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/auth/verify-otp');
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'otp': otp.trim(),
          'phone': phone?.trim(),
          'device': {
            'deviceId': identity.deviceId,
            'deviceName': identity.deviceName,
            'platform': identity.platform,
            'signingPublicKey': identity.signingPublicKeyBase64,
            'exchangePublicKey': identity.exchangePublicKeyBase64,
            'lanIp': lanIp,
            'lanPort': lanPort,
          },
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'connectionCode': data['connectionCode'],
          'user': data['user'],
        };
      } else {
        return {'success': false, 'error': data['error'] ?? 'Verification failed'};
      }
    } catch (e) {
      debugPrint('verifyOtp error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Pairs this device with an existing user/primary device using the 6-digit Connection Code
  Future<Map<String, dynamic>> pairWithConnectionCode({
    required String connectionCode,
    required DeviceIdentity identity,
    String? lanIp,
    int? lanPort,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/auth/pair-device');
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'connectionCode': connectionCode.trim(),
          'device': {
            'deviceId': identity.deviceId,
            'deviceName': identity.deviceName,
            'platform': identity.platform,
            'signingPublicKey': identity.signingPublicKeyBase64,
            'exchangePublicKey': identity.exchangePublicKeyBase64,
            'lanIp': lanIp,
            'lanPort': lanPort,
          },
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        DeviceModel? pairedModel;
        if (data['pairedDevice'] != null) {
          final pd = data['pairedDevice'] as Map<String, dynamic>;
          pairedModel = DeviceModel(
            id: pd['deviceId'] as String,
            name: pd['deviceName'] as String? ?? 'Primary Device',
            platform: pd['platform'] as String? ?? 'unknown',
            signingPublicKey: pd['signingPublicKey'] as String? ?? '',
            exchangePublicKey: pd['exchangePublicKey'] as String? ?? '',
            lanIp: pd['lanIp'] as String?,
            lanPort: pd['lanPort'] as int?,
            isOnline: true,
            isLanAvailable: false,
            lastSeen: DateTime.now(),
          );
        }

        return {
          'success': true,
          'message': data['message'],
          'connectionCode': data['connectionCode'],
          'user': data['user'],
          'pairedDevice': pairedModel,
        };
      } else {
        return {'success': false, 'error': data['error'] ?? 'Pairing failed'};
      }
    } catch (e) {
      debugPrint('pairWithConnectionCode error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Rotates the 6-digit connection code for this user
  Future<String?> regenerateConnectionCode({
    String? email,
    required String deviceId,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/auth/regenerate-code');
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          'deviceId': deviceId,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        return data['connectionCode'] as String?;
      }
    } catch (e) {
      debugPrint('regenerateConnectionCode error: $e');
    }
    return null;
  }
}
