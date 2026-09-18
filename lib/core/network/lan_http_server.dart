import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';
import '../crypto/device_identity.dart';

typedef OnDirectMessageReceived = void Function(Map<String, dynamic> messageData);

class RegisteredFile {
  final String token;
  final String filePath;
  final String fileName;
  final int fileSize;
  final String mimeType;

  RegisteredFile({
    required this.token,
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
  });
}

class LanHttpServer {
  static LanHttpServer? _instance;
  static LanHttpServer get instance => _instance ??= LanHttpServer._();

  HttpServer? _server;
  int _port = AppConstants.defaultLanPort;
  final Map<String, RegisteredFile> _sharedFiles = {};
  OnDirectMessageReceived? onDirectMessageReceived;
  DeviceIdentity? _identity;

  LanHttpServer._();

  int get port => _port;
  bool get isRunning => _server != null;

  /// Starts the embedded shelf server
  Future<int> start(DeviceIdentity identity, {int preferredPort = AppConstants.defaultLanPort}) async {
    _identity = identity;
    if (_server != null) return _port;

    final app = Router();

    // 1. Health check & device info
    app.get('/health', (Request request) {
      return Response.ok(
        jsonEncode({
          'status': 'online',
          'deviceId': _identity?.deviceId,
          'deviceName': _identity?.deviceName,
          'platform': _identity?.platform,
          'port': _port,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // 2. Direct P2P message delivery on LAN
    app.post('/messages/direct', (Request request) async {
      try {
        final body = await request.readAsString();
        final json = jsonDecode(body) as Map<String, dynamic>;
        onDirectMessageReceived?.call(json);
        return Response.ok(
          jsonEncode({'received': true, 'timestamp': DateTime.now().millisecondsSinceEpoch}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    // 3. Resumable Chunked File Download endpoint
    app.get('/files/download/<token>', (Request request, String token) async {
      final fileInfo = _sharedFiles[token];
      if (fileInfo == null) {
        return Response.notFound(jsonEncode({'error': 'File not found or expired'}));
      }

      final file = File(fileInfo.filePath);
      if (!await file.exists()) {
        return Response.notFound(jsonEncode({'error': 'File does not exist on host'}));
      }

      final fileSize = await file.length();
      final rangeHeader = request.headers['range'];

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        // Handle HTTP Range header for resumable downloads
        final rangeParts = rangeHeader.substring(6).split('-');
        final start = int.tryParse(rangeParts[0]) ?? 0;
        final end = (rangeParts.length > 1 && rangeParts[1].isNotEmpty)
            ? (int.tryParse(rangeParts[1]) ?? fileSize - 1)
            : fileSize - 1;

        if (start >= fileSize || end >= fileSize || start > end) {
          return Response(416, headers: {'Content-Range': 'bytes */$fileSize'});
        }

        final length = end - start + 1;
        final stream = file.openRead(start, end + 1);

        return Response(
          206, // Partial Content
          body: stream,
          headers: {
            'Content-Type': fileInfo.mimeType,
            'Content-Length': length.toString(),
            'Content-Range': 'bytes $start-$end/$fileSize',
            'Accept-Ranges': 'bytes',
            'Content-Disposition': 'attachment; filename="${fileInfo.fileName}"',
          },
        );
      }

      // Standard full file download
      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': fileInfo.mimeType,
          'Content-Length': fileSize.toString(),
          'Accept-Ranges': 'bytes',
          'Content-Disposition': 'attachment; filename="${fileInfo.fileName}"',
        },
      );
    });

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(app.call);

    // Try binding to preferred port, fallback to ephemeral port if occupied
    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, preferredPort);
      _port = _server!.port;
    } catch (_) {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
      _port = _server!.port;
    }

    return _port;
  }

  /// Registers a local file to be served directly to peers over LAN
  String registerShareableFile({
    required String filePath,
    required String fileName,
    required int fileSize,
    String mimeType = 'application/octet-stream',
  }) {
    final token = const Uuid().v4();
    _sharedFiles[token] = RegisteredFile(
      token: token,
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
    );
    return token;
  }

  void revokeSharedFile(String token) {
    _sharedFiles.remove(token);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _sharedFiles.clear();
  }
}
