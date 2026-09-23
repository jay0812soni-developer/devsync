import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../storage/database_service.dart';

enum WsConnectionStatus {
  disconnected,
  connecting,
  connected,
  authenticated,
}

class PersistentWsClient {
  static PersistentWsClient? _instance;
  static PersistentWsClient get instance => _instance ??= PersistentWsClient._();

  PersistentWsClient._();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  WsConnectionStatus _status = WsConnectionStatus.disconnected;
  WsConnectionStatus get status => _status;

  int _reconnectAttempts = 0;
  bool _isDisposed = false;

  // Event Streams
  final _statusController = StreamController<WsConnectionStatus>.broadcast();
  Stream<WsConnectionStatus> get statusStream => _statusController.stream;

  final _presenceController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get presenceStream => _presenceController.stream;

  final _incomingMessageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incomingMessageStream => _incomingMessageController.stream;

  final _webrtcSignalController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get webrtcSignalStream => _webrtcSignalController.stream;

  final _deviceJoinedController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get deviceJoinedStream => _deviceJoinedController.stream;

  final _revokedController = StreamController<String>.broadcast();
  Stream<String> get revokedStream => _revokedController.stream;

  /// Connects to the persistent Fastify WebSocket gateway
  void connect({String? customUrl, String? token, String? deviceId}) {
    if (_status == WsConnectionStatus.connecting || _status == WsConnectionStatus.authenticated) {
      return;
    }

    _isDisposed = false;
    _setStatus(WsConnectionStatus.connecting);

    final rawBaseUrl = customUrl ?? DatabaseService.instance.getRelayUrl();
    final cleanUrl = rawBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final wsUrl = cleanUrl.startsWith('https://')
        ? cleanUrl.replaceFirst('https://', 'wss://')
        : cleanUrl.replaceFirst('http://', 'ws://');

    final uri = Uri.parse('$wsUrl/ws');
    debugPrint('[PersistentWS] Connecting to: $uri');

    try {
      _channel = WebSocketChannel.connect(uri);
      _setStatus(WsConnectionStatus.connected);
      _reconnectAttempts = 0;

      // Authenticate with Bearer token & Device ID
      final effectiveToken = token ?? DatabaseService.instance.getAuthToken();
      if (effectiveToken != null && effectiveToken.isNotEmpty) {
        sendAuth(effectiveToken, deviceId);
      }

      _subscription = _channel!.stream.listen(
        (dynamic raw) {
          _handleMessage(raw);
        },
        onError: (err) {
          debugPrint('[PersistentWS] Stream error: $err');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[PersistentWS] Connection closed by remote');
          _handleDisconnect();
        },
      );

      _startPing();
    } catch (e) {
      debugPrint('[PersistentWS] Connect exception: $e');
      _handleDisconnect();
    }
  }

  void _handleMessage(dynamic raw) {
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final data = jsonDecode(text) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'auth_success':
          debugPrint('[PersistentWS] Authenticated successfully: ${data['deviceId']}');
          _setStatus(WsConnectionStatus.authenticated);
          break;

        case 'auth_error':
          debugPrint('[PersistentWS] Auth error: ${data['error']}');
          _setStatus(WsConnectionStatus.disconnected);
          break;

        case 'presence_update':
          _presenceController.add(data);
          break;

        case 'message_incoming':
          final msg = data['message'] as Map<String, dynamic>?;
          if (msg != null) {
            _incomingMessageController.add(msg);
            // Automatically ACK delivery back to server
            final msgId = msg['id'] as String?;
            if (msgId != null) {
              sendAck(msgId);
            }
          }
          break;

        case 'offline_messages':
          final list = data['messages'] as List<dynamic>? ?? [];
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              _incomingMessageController.add(item);
              final msgId = item['id'] as String?;
              if (msgId != null) {
                sendAck(msgId);
              }
            }
          }
          break;

        case 'webrtc_signal':
          _webrtcSignalController.add(data);
          break;

        case 'device_joined':
          _deviceJoinedController.add(data);
          break;

        case 'revoked':
          _revokedController.add(data['reason'] as String? ?? 'Revoked');
          disconnect();
          break;
      }
    } catch (e) {
      debugPrint('[PersistentWS] Failed to parse incoming message: $e');
    }
  }

  void sendAuth(String token, String? deviceId) {
    final payload = <String, dynamic>{
      'type': 'auth',
      'token': token,
    };
    if (deviceId != null) {
      payload['deviceId'] = deviceId;
    }
    send(payload);
  }

  void sendAck(String messageId) {
    send({
      'type': 'ack',
      'messageId': messageId,
    });
  }

  void sendWebRtcSignal({
    required String recipientDeviceId,
    required String signalType, // 'offer' | 'answer' | 'candidate'
    required dynamic data,
  }) {
    send({
      'type': 'webrtc_signal',
      'recipientDeviceId': recipientDeviceId,
      'signalType': signalType,
      'data': data,
    });
  }

  void sendEncryptedPayload({
    required String messageId,
    required String recipientDeviceId,
    required String messageType,
    required String cipherText,
    required String nonce,
    required String mac,
    String? codeLanguage,
    String? fileName,
    int? fileSize,
    String? sha256,
    Map<String, dynamic>? metadata,
  }) {
    final payload = <String, dynamic>{
      'type': 'message',
      'id': messageId,
      'recipientDeviceId': recipientDeviceId,
      'messageType': messageType,
      'cipherText': cipherText,
      'nonce': nonce,
      'mac': mac,
    };
    if (codeLanguage != null) payload['codeLanguage'] = codeLanguage;
    if (fileName != null) payload['fileName'] = fileName;
    if (fileSize != null) payload['fileSize'] = fileSize;
    if (sha256 != null) payload['sha256'] = sha256;
    if (metadata != null) payload['metadata'] = metadata;
    send(payload);
  }

  void send(Map<String, dynamic> payload) {
    if (_channel == null || _status == WsConnectionStatus.disconnected) {
      debugPrint('[PersistentWS] Cannot send; socket not connected');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('[PersistentWS] Error sending payload: $e');
    }
  }

  void _setStatus(WsConnectionStatus s) {
    _status = s;
    if (!_statusController.isClosed) {
      _statusController.add(s);
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_status == WsConnectionStatus.authenticated || _status == WsConnectionStatus.connected) {
        send({'type': 'ping'});
      }
    });
  }

  void _handleDisconnect() {
    _subscription?.cancel();
    _subscription = null;
    _pingTimer?.cancel();
    _channel = null;

    _setStatus(WsConnectionStatus.disconnected);

    if (_isDisposed) return;

    // Exponential Backoff Reconnection: 1s, 2s, 4s, 8s, max 30s
    _reconnectTimer?.cancel();
    final delaySeconds = (_reconnectAttempts < 5) ? (1 << _reconnectAttempts) : 30;
    _reconnectAttempts++;

    debugPrint('[PersistentWS] Reconnecting in $delaySeconds seconds (attempt $_reconnectAttempts)...');
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      connect();
    });
  }

  void disconnect() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setStatus(WsConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _presenceController.close();
    _incomingMessageController.close();
    _webrtcSignalController.close();
    _deviceJoinedController.close();
    _revokedController.close();
  }
}
