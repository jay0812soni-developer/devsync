import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';

enum FileCategory {
  code,
  documents,
  images,
  media,
  archives,
  other;

  String get folderName {
    switch (this) {
      case FileCategory.code:
        return AppConstants.codeFolder;
      case FileCategory.documents:
        return AppConstants.documentsFolder;
      case FileCategory.images:
        return AppConstants.imagesFolder;
      case FileCategory.media:
        return AppConstants.mediaFolder;
      case FileCategory.archives:
        return AppConstants.archivesFolder;
      case FileCategory.other:
        return 'Other';
    }
  }
}

class FileCategorizer {
  FileCategorizer._();

  static const Set<String> _codeExtensions = {
    'dart', 'js', 'jsx', 'ts', 'tsx', 'py', 'go', 'rs', 'java', 'kt', 'c', 'cpp',
    'h', 'hpp', 'cs', 'html', 'css', 'scss', 'json', 'yaml', 'yml', 'xml', 'sh',
    'bash', 'bat', 'ps1', 'sql', 'env', 'toml', 'lua', 'swift', 'php', 'rb', 'r',
    'proto', 'gradle', 'properties', 'dockerfile', 'makefile'
  };

  static const Set<String> _docExtensions = {
    'pdf', 'doc', 'docx', 'txt', 'md', 'markdown', 'csv', 'xlsx', 'xls', 'pptx',
    'ppt', 'rtf', 'odt', 'ods', 'odp'
  };

  static const Set<String> _imageExtensions = {
    'png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'bmp', 'ico', 'tiff', 'heic'
  };

  static const Set<String> _mediaExtensions = {
    'mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', 'mp3', 'wav', 'aac', 'flac',
    'ogg', 'm4a', 'wma'
  };

  static const Set<String> _archiveExtensions = {
    'zip', 'tar', 'gz', 'tgz', '7z', 'rar', 'bz2', 'xz', 'apk', 'dmg', 'exe',
    'msi', 'iso', 'deb', 'rpm'
  };

  /// Categorizes a filename into its respective FileCategory
  static FileCategory categorize(String filename) {
    var ext = p.extension(filename).toLowerCase();
    if (ext.startsWith('.')) {
      ext = ext.substring(1);
    }

    if (_codeExtensions.contains(ext) ||
        filename.toLowerCase() == 'dockerfile' ||
        filename.toLowerCase() == 'makefile') {
      return FileCategory.code;
    }
    if (_docExtensions.contains(ext)) {
      return FileCategory.documents;
    }
    if (_imageExtensions.contains(ext)) {
      return FileCategory.images;
    }
    if (_mediaExtensions.contains(ext)) {
      return FileCategory.media;
    }
    if (_archiveExtensions.contains(ext)) {
      return FileCategory.archives;
    }
    return FileCategory.other;
  }

  /// Returns programming language identifier for syntax highlighting if code file
  static String? detectLanguage(String filename) {
    var ext = p.extension(filename).toLowerCase();
    if (ext.startsWith('.')) ext = ext.substring(1);

    switch (ext) {
      case 'dart':
        return 'dart';
      case 'js':
      case 'jsx':
        return 'javascript';
      case 'ts':
      case 'tsx':
        return 'typescript';
      case 'py':
        return 'python';
      case 'go':
        return 'go';
      case 'rs':
        return 'rust';
      case 'java':
        return 'java';
      case 'kt':
        return 'kotlin';
      case 'c':
      case 'h':
        return 'c';
      case 'cpp':
      case 'hpp':
        return 'cpp';
      case 'cs':
        return 'csharp';
      case 'html':
        return 'html';
      case 'css':
      case 'scss':
        return 'css';
      case 'json':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'xml':
        return 'xml';
      case 'sh':
      case 'bash':
        return 'bash';
      case 'sql':
        return 'sql';
      case 'md':
      case 'markdown':
        return 'markdown';
      default:
        return null;
    }
  }

  static bool isCodeFile(String filename) => categorize(filename) == FileCategory.code;
  static bool isImageFile(String filename) => categorize(filename) == FileCategory.images;
}
