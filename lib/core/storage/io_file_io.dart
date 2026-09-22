import 'dart:io';
import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:path_provider/path_provider.dart';

class IoFile {
  static Future<bool> exists(String path) => File(path).exists();

  static Future<int> length(String path) => File(path).length();

  static Future<String> checksum(String path) async {
    final digest = await dart_crypto.sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  static Future<void> writeBytes(String path, List<int> bytes) {
    return File(path).writeAsBytes(bytes);
  }

  static Future<void> ensureDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  static Future<int> treeSize(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  static Future<String?> downloadsPath() async {
    final dir = await getDownloadsDirectory();
    return dir?.path;
  }

  static Future<String?> documentsPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }
}
