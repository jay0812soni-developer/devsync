import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';
import 'file_categorizer.dart';
import 'io_file.dart';

class LocalFileManager {
  static LocalFileManager? _instance;
  static LocalFileManager get instance => _instance ??= LocalFileManager._();

  String? _basePath;

  LocalFileManager._();

  Future<void> initialize() async {
    if (kIsWeb) return;
    final baseDir = await _baseDirectoryPath();
    if (baseDir == null) return;
    _basePath = p.join(baseDir, AppConstants.rootFolder);
    await IoFile.ensureDir(_basePath!);
    for (final cat in FileCategory.values) {
      await IoFile.ensureDir(p.join(_basePath!, cat.folderName));
    }
  }

  Future<String?> _baseDirectoryPath() async {
    if (kIsWeb) return null;
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux) {
      final downloads = await IoFile.downloadsPath();
      if (downloads != null) return downloads;
    }
    return IoFile.documentsPath();
  }

  Future<String> getCategoryDirectory(FileCategory category) async {
    if (_basePath == null) await initialize();
    final dir = p.join(_basePath ?? '', category.folderName);
    await IoFile.ensureDir(dir);
    return dir;
  }

  Future<String> resolveUniquePath(String targetDir, String originalFilename) async {
    var destPath = p.join(targetDir, originalFilename);
    if (!await IoFile.exists(destPath)) return destPath;

    final ext = p.extension(originalFilename);
    final nameWithoutExt = p.basenameWithoutExtension(originalFilename);
    var counter = 1;
    while (await IoFile.exists(destPath)) {
      destPath = p.join(targetDir, '$nameWithoutExt ($counter)$ext');
      counter++;
    }
    return destPath;
  }

  Future<String> saveIncomingBytes({
    required String originalFilename,
    required List<int> bytes,
  }) async {
    final category = FileCategorizer.categorize(originalFilename);
    final targetDir = await getCategoryDirectory(category);
    final finalPath = await resolveUniquePath(targetDir, originalFilename);
    await IoFile.writeBytes(finalPath, bytes);
    return finalPath;
  }

  Future<String> calculateChecksumOfPath(String path) => IoFile.checksum(path);

  Future<String> checksumBytes(List<int> bytes) async {
    return dart_crypto.sha256.convert(bytes).toString();
  }

  Future<OpenResult> openFile(String filePath) async {
    if (kIsWeb) return OpenResult(type: ResultType.done);
    return OpenFilex.open(filePath);
  }

  Future<int> getTotalDevSyncStorageBytes() async {
    if (kIsWeb || _basePath == null) return 0;
    return IoFile.treeSize(_basePath!);
  }
}
