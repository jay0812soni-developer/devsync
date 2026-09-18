import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../storage/database_service.dart';

typedef OnRelayMessageCallback = void Function(Map<String, dynamic> rawMessage);

class SseRelayClient {
  static SseRelayClient? _instance;
  static SseRelayClient get instance => _instance ??= SseRelayClient._();

  http.Client? _client;
  bool _isConnected = false;
  bool _shouldRun = false;
  String? _deviceId;
  Timer? _reconnectTimer;
  Timer? _pollingFallbackTimer;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessageReceived => _messageController.stream;

  SseRelayClient._();

  bool get isConnected => _isConnected;

  String get _baseUrl => DatabaseService.instance.getRelayUrl().replaceAll(RegExp(r'/+$'), '');

  /// Starts listening to the real-time SSE stream for this device
  void startListening(String deviceId) {
    _deviceId = deviceId;
    _shouldRun = true;
    _connectSse();

    // Secondary polling backup every 10 seconds to catch offline delivered messages
    _pollingFallbackTimer?.cancel();
    _pollingFallbackTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _pollMessages();
    });
  }

  Future<void> _connectSse() async {
    if (!_shouldRun || _deviceId == null) return;

    _client?.close();
    _client = http.Client();

    final url = Uri.parse('$_baseUrl/api/events?deviceId=$_deviceId');
    final request = http.Request('GET', url)
      ..headers['Accept'] = 'text/event-stream'
      ..headers['Cache-Control'] = 'no-cache';

    try {
      final response = await _client!.send(request);

      if (response.statusCode == 200) {
        _isConnected = true;

        String currentEvent = '';

        response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            if (line.startsWith('event: ')) {
              currentEvent = line.substring(7).trim();
            } else if (line.startsWith('data: ')) {
              final dataStr = line.substring(6).trim();
              if (currentEvent == 'message' && dataStr.isNotEmpty) {
                try {
                  final json = jsonDecode(dataStr) as Map<String, dynamic>;
                  _messageController.add(json);
                } catch (e) {
                  debugPrint('Error decoding SSE message data: $e');
                }
              }
            } else if (line.isEmpty) {
              currentEvent = '';
            }
          },
          onError: (err) {
            _handleDisconnect();
          },
          onDone: () {
            _handleDisconnect();
          },
          cancelOnError: true,
        );
      } else {
        _handleDisconnect();
      }
    } catch (_) {
      _handleDisconnect();
    }
  }

  /// Periodic polling backup
  Future<void> _pollMessages() async {
    if (_deviceId == null || _baseUrl.isEmpty) return;

    try {
      final url = Uri.parse('$_baseUrl/api/events?deviceId=$_deviceId');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final messages = json['messages'] as List<dynamic>?;
        if (messages != null) {
          for (final raw in messages) {
            if (raw is Map<String, dynamic>) {
              _messageController.add(raw);
            }
          }
        }
      }
    } catch (_) {}
  }

  void _handleDisconnect() {
    _isConnected = false;
    if (_shouldRun) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 4), () {
        _connectSse();
      });
    }
  }

  void stop() {
    _shouldRun = false;
    _isConnected = false;
    _reconnectTimer?.cancel();
    _pollingFallbackTimer?.cancel();
    _client?.close();
    _client = null;
  }
}
