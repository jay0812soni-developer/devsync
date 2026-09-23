import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../crypto/device_identity.dart';
import '../../features/devices/domain/device_model.dart';
import '../storage/database_service.dart';
import 'persistent_ws_client.dart';

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

  // --- Auth & Multi-Device Mesh APIs ---

  /// Safely attempts a POST to the primary route, automatically falling back to an alternative route
  /// if the primary route fails with an exception (e.g. CORS preflight 404 in Flutter Web) or 404/405.
  Future<http.Response> _postWithFallback({
    required String primaryPath,
    required String fallbackPath,
    required Map<String, dynamic> primaryBody,
    required Map<String, dynamic> fallbackBody,
    Map<String, String>? headers,
  }) async {
    final reqHeaders = {
      'Content-Type': 'application/json',
      ...?headers,
    };

    http.Response? response;
    Object? lastError;

    // Try primary path first
    try {
      final res = await _client.post(
        Uri.parse('$_baseUrl$primaryPath'),
        headers: reqHeaders,
        body: jsonEncode(primaryBody),
      );
      if (res.statusCode != 404 && res.statusCode != 405) {
        return res;
      }
      response = res;
    } catch (e) {
      lastError = e;
      debugPrint('[RelayApiService] Primary endpoint $primaryPath failed ($e), falling back to $fallbackPath');
    }

    // Try fallback path
    try {
      final res = await _client.post(
        Uri.parse('$_baseUrl$fallbackPath'),
        headers: reqHeaders,
        body: jsonEncode(fallbackBody),
      );
      return res;
    } catch (e) {
      if (response != null) return response;
      throw lastError ?? e;
    }
  }

  /// Requests a 6-digit OTP sent via Nodemailer to the user's email
  Future<Map<String, dynamic>> sendRegistrationOtp({
    required String email,
    required String phone,
    String? name,
  }) async {
    try {
      final body = {
        'email': email.trim(),
        'phone': phone.trim(),
        'name': ?name,
      };

      final response = await _postWithFallback(
        primaryPath: '/api/v1/auth/request-otp',
        fallbackPath: '/api/auth/register-otp',
        primaryBody: body,
        fallbackBody: body,
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && (data['success'] == true || data['message'] != null)) {
        return {'success': true, 'message': data['message'] ?? 'OTP sent'};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to send OTP'};
      }
    } catch (e) {
      debugPrint('sendRegistrationOtp error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Verifies the 6-digit OTP, registers device in mesh, saves JWT session, and opens WebSocket
  Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
    required DeviceIdentity identity,
    String? phone,
    String? lanIp,
    int? lanPort,
  }) async {
    try {
      final primaryBody = {
        'email': email.trim(),
        'otp': otp.trim(),
        'phone': phone?.trim(),
        'deviceId': identity.deviceId,
        'deviceName': identity.deviceName,
        'platform': identity.platform,
        'signingPublicKey': identity.signingPublicKeyBase64,
        'exchangePublicKey': identity.exchangePublicKeyBase64,
        'lanIp': lanIp,
        'lanPort': lanPort,
      };

      final fallbackBody = {
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
      };

      final response = await _postWithFallback(
        primaryPath: '/api/v1/auth/verify-otp',
        fallbackPath: '/api/auth/verify-otp',
        primaryBody: primaryBody,
        fallbackBody: fallbackBody,
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        final token = data['token'] as String?;
        if (token != null) {
          await DatabaseService.instance.setAuthToken(token);
        }

        final group = data['group'] as Map<String, dynamic>?;
        if (group != null && group['id'] != null) {
          await DatabaseService.instance.setGroupId(group['id'] as String);
        }

        final connectionCode = (group != null ? group['connectionCode'] : data['connectionCode']) as String? ?? '';
        if (connectionCode.isNotEmpty) {
          await DatabaseService.instance.setConnectionCode(connectionCode);
        }

        // Connect persistent WebSocket gateway
        PersistentWsClient.instance.connect(
          token: token,
          deviceId: identity.deviceId,
        );

        return {
          'success': true,
          'connectionCode': connectionCode,
          'user': data['user'],
          'token': token,
        };
      } else {
        return {'success': false, 'error': data['error'] ?? 'Verification failed'};
      }
    } catch (e) {
      debugPrint('verifyOtp error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Pairs this device with an existing personal mesh network using the 6-digit Connection Code
  Future<Map<String, dynamic>> pairWithConnectionCode({
    required String connectionCode,
    required DeviceIdentity identity,
    String? lanIp,
    int? lanPort,
  }) async {
    try {
      final primaryBody = {
        'connectionCode': connectionCode.trim(),
        'deviceId': identity.deviceId,
        'deviceName': identity.deviceName,
        'platform': identity.platform,
        'signingPublicKey': identity.signingPublicKeyBase64,
        'exchangePublicKey': identity.exchangePublicKeyBase64,
        'lanIp': lanIp,
        'lanPort': lanPort,
      };

      final fallbackBody = {
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
      };

      final response = await _postWithFallback(
        primaryPath: '/api/v1/devices/pair-request',
        fallbackPath: '/api/auth/pair-device',
        primaryBody: primaryBody,
        fallbackBody: fallbackBody,
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        final token = data['token'] as String?;
        if (token != null) {
          await DatabaseService.instance.setAuthToken(token);
        }

        final group = data['group'] as Map<String, dynamic>?;
        if (group != null && group['id'] != null) {
          await DatabaseService.instance.setGroupId(group['id'] as String);
        }

        // Process discovered peers
        final peersList = <DeviceModel>[];
        if (data['peers'] is List) {
          for (final p in (data['peers'] as List)) {
            if (p is Map<String, dynamic>) {
              peersList.add(DeviceModel(
                id: p['deviceId'] as String,
                name: p['deviceName'] as String? ?? 'Mesh Peer',
                platform: p['platform'] as String? ?? 'unknown',
                signingPublicKey: p['signingPublicKey'] as String? ?? '',
                exchangePublicKey: p['exchangePublicKey'] as String? ?? '',
                lanIp: p['lanIp'] as String?,
                lanPort: p['lanPort'] as int?,
                isOnline: p['isOnline'] == true,
                isLanAvailable: false,
                lastSeen: DateTime.now(),
              ));
            }
          }
        } else if (data['pairedDevice'] != null) {
          final pd = data['pairedDevice'] as Map<String, dynamic>;
          peersList.add(DeviceModel(
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
          ));
        }

        // Save peers to database
        for (final peer in peersList) {
          await DatabaseService.instance.savePeer(peer);
        }

        // Connect persistent WebSocket gateway
        PersistentWsClient.instance.connect(
          token: token,
          deviceId: identity.deviceId,
        );

        return {
          'success': true,
          'message': data['message'],
          'connectionCode': data['connectionCode'] ?? (group != null ? group['connectionCode'] : null),
          'user': data['user'],
          'pairedDevice': peersList.isNotEmpty ? peersList.first : null,
          'peers': peersList,
        };
      } else {
        return {'success': false, 'error': data['error'] ?? 'Pairing failed'};
      }
    } catch (e) {
      debugPrint('pairWithConnectionCode error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Fetches all active devices in this user's personal mesh network
  Future<List<DeviceModel>> fetchGroupMembers() async {
    final token = DatabaseService.instance.getAuthToken();
    if (token == null || token.isEmpty) return [];

    try {
      final url = Uri.parse('$_baseUrl/api/v1/devices/group-members');
      final response = await _client.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final members = data['members'] as List<dynamic>? ?? [];
        final list = <DeviceModel>[];
        for (final m in members) {
          if (m is Map<String, dynamic>) {
            final model = DeviceModel(
              id: m['deviceId'] as String,
              name: m['deviceName'] as String? ?? 'Dev Device',
              platform: m['platform'] as String? ?? 'unknown',
              signingPublicKey: m['signingPublicKey'] as String? ?? '',
              exchangePublicKey: m['exchangePublicKey'] as String? ?? '',
              lanIp: m['lanIp'] as String?,
              lanPort: m['lanPort'] as int?,
              isOnline: m['isOnline'] == true,
              isLanAvailable: false,
              lastSeen: DateTime.fromMillisecondsSinceEpoch(m['lastSeenAt'] as int? ?? DateTime.now().millisecondsSinceEpoch),
            );
            list.add(model);
            await DatabaseService.instance.savePeer(model);
          }
        }
        return list;
      }
    } catch (e) {
      debugPrint('fetchGroupMembers error: $e');
    }
    return [];
  }

  /// Revokes an authorized device from the personal mesh
  Future<bool> revokeDevice(String deviceId) async {
    final token = DatabaseService.instance.getAuthToken();
    if (token == null || token.isEmpty) return false;

    try {
      final url = Uri.parse('$_baseUrl/api/v1/devices/$deviceId/revoke');
      final response = await _client.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        await DatabaseService.instance.deletePeer(deviceId);
        return true;
      }
    } catch (e) {
      debugPrint('revokeDevice error: $e');
    }
    return false;
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

  /// Fetches short-lived ephemeral TURN & STUN ICE credentials from the backend
  Future<List<Map<String, dynamic>>?> fetchTurnCredentials() async {
    final token = DatabaseService.instance.getAuthToken();
    if (token == null || token.isEmpty) return null;

    try {
      final url = Uri.parse('$_baseUrl/api/v1/network/turn-credentials');
      final response = await _client.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['iceServers'] is List) {
          return List<Map<String, dynamic>>.from(
            (data['iceServers'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
          );
        }
      }
    } catch (e) {
      debugPrint('fetchTurnCredentials error: $e');
    }
    return null;
  }

  /// Generates a fresh, single-use, 5-minute pairing code for this group
  Future<String?> generateSingleUsePairingCode() async {
    final token = DatabaseService.instance.getAuthToken();
    if (token == null || token.isEmpty) return null;

    try {
      final url = Uri.parse('$_baseUrl/api/v1/devices/pairing-code');
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['connectionCode'] != null) {
          final code = data['connectionCode'] as String;
          await DatabaseService.instance.setConnectionCode(code);
          return code;
        }
      }
    } catch (e) {
      debugPrint('generateSingleUsePairingCode error: $e');
    }
    return null;
  }
}
