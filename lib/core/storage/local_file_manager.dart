import 'dart:io';
import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../constants/app_constants.dart';
import 'file_categorizer.dart';

class LocalFileManager {
  static LocalFileManager? _instance;
  static LocalFileManager get instance => _instance ??= LocalFileManager._();

  Directory? _baseStorageDir;

  LocalFileManager._();

  /// Initializes base DevSync storage directories
  Future<void> initialize() async {
    final baseDir = await _getBaseDirectory();
    _baseStorageDir = Directory(p.join(baseDir.path, AppConstants.rootFolder));

    if (!await _baseStorageDir!.exists()) {
      await _baseStorageDir!.create(recursive: true);
    }

    // Ensure all subfolders exist
    for (final cat in FileCategory.values) {
      final subDir = Directory(p.join(_baseStorageDir!.path, cat.folderName));
      if (!await subDir.exists()) {
        await subDir.create(recursive: true);
      }
    }
  }

  /// Gets the user's primary downloads / documents directory based on platform
  Future<Directory> _getBaseDirectory() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } else if (Platform.isAndroid) {
      // In Android, try public downloads or external storage directory
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        // Points towards /storage/emulated/0/Download if available
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) return downloadDir;
        return ext;
      }
    }
    return await getApplicationDocumentsDirectory();
  }

  /// Returns the category subdirectory (DevSync/Code, etc.)
  Future<Directory> getCategoryDirectory(FileCategory category) async {
    if (_baseStorageDir == null) await initialize();
    final dir = Directory(p.join(_baseStorageDir!.path, category.folderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Resolves non-colliding filename in target directory
  Future<String> resolveUniquePath(String targetDir, String originalFilename) async {
    var destPath = p.join(targetDir, originalFilename);
    if (!await File(destPath).exists()) {
      return destPath;
    }

    final ext = p.extension(originalFilename);
    final nameWithoutExt = p.basenameWithoutExtension(originalFilename);
    int counter = 1;

    while (await File(destPath).exists()) {
      destPath = p.join(targetDir, '$nameWithoutExt ($counter)$ext');
      counter++;
    }
    return destPath;
  }

  /// Saves incoming byte stream with live progress tracking
  Future<File> saveIncomingStream({
    required String originalFilename,
    required Stream<List<int>> stream,
    required int expectedSize,
    void Function(int bytesReceived, int totalBytes)? onProgress,
  }) async {
    final category = FileCategorizer.categorize(originalFilename);
    final targetDir = await getCategoryDirectory(category);
    final finalPath = await resolveUniquePath(targetDir.path, originalFilename);

    final file = File(finalPath);
    final sink = file.openWrite();
    int received = 0;

    try {
      await for (final chunk in stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null) {
          onProgress(received, expectedSize);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    return file;
  }

  /// Saves bytes directly to appropriate category directory
  Future<File> saveIncomingBytes({
    required String originalFilename,
    required List<int> bytes,
  }) async {
    final category = FileCategorizer.categorize(originalFilename);
    final targetDir = await getCategoryDirectory(category);
    final finalPath = await resolveUniquePath(targetDir.path, originalFilename);

    final file = File(finalPath);
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Calculates SHA-256 checksum of a file
  Future<String> calculateChecksum(File file) async {
    final stream = file.openRead();
    final digest = await dart_crypto.sha256.bind(stream).first;
    return digest.toString();
  }

  /// Opens the file using the native default app (VS Code, viewer, Photos, etc.)
  Future<OpenResult> openFile(String filePath) async {
    return await OpenFilex.open(filePath);
  }

  /// Returns total storage usage in DevSync
  Future<int> getTotalDevSyncStorageBytes() async {
    if (_baseStorageDir == null) await initialize();
    int total = 0;
    if (await _baseStorageDir!.exists()) {
      await for (final entity in _baseStorageDir!.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    }
    return total;
  }
}
