import 'package:devsync/core/constants/app_constants.dart';
import 'package:devsync/core/storage/file_categorizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileCategorizer Tests', () {
    test('Correctly identifies code files and assigns to Code category', () {
      expect(FileCategorizer.categorize('main.dart'), equals(FileCategory.code));
      expect(FileCategorizer.categorize('api_server.py'), equals(FileCategory.code));
      expect(FileCategorizer.categorize('index.ts'), equals(FileCategory.code));
      expect(FileCategorizer.categorize('package.json'), equals(FileCategory.code));
      expect(FileCategorizer.categorize('docker-compose.yaml'), equals(FileCategory.code));
      expect(FileCategorizer.categorize('Dockerfile'), equals(FileCategory.code));
      expect(FileCategorizer.categorize('Makefile'), equals(FileCategory.code));
      expect(FileCategorizer.categorize('query.sql'), equals(FileCategory.code));
      expect(FileCategorizer.categorize('main.rs'), equals(FileCategory.code));
      expect(FileCategorizer.categorize('server.go'), equals(FileCategory.code));
    });

    test('Correctly identifies documents', () {
      expect(FileCategorizer.categorize('specs.pdf'), equals(FileCategory.documents));
      expect(FileCategorizer.categorize('README.md'), equals(FileCategory.documents));
      expect(FileCategorizer.categorize('notes.txt'), equals(FileCategory.documents));
      expect(FileCategorizer.categorize('data.csv'), equals(FileCategory.documents));
    });

    test('Correctly identifies images', () {
      expect(FileCategorizer.categorize('screenshot.png'), equals(FileCategory.images));
      expect(FileCategorizer.categorize('avatar.jpg'), equals(FileCategory.images));
      expect(FileCategorizer.categorize('logo.svg'), equals(FileCategory.images));
    });

    test('Correctly identifies archives', () {
      expect(FileCategorizer.categorize('build.zip'), equals(FileCategory.archives));
      expect(FileCategorizer.categorize('release.tar.gz'), equals(FileCategory.archives));
      expect(FileCategorizer.categorize('app.apk'), equals(FileCategory.archives));
    });

    test('Detects programming languages for syntax highlighting', () {
      expect(FileCategorizer.detectLanguage('app.dart'), equals('dart'));
      expect(FileCategorizer.detectLanguage('script.py'), equals('python'));
      expect(FileCategorizer.detectLanguage('component.tsx'), equals('typescript'));
      expect(FileCategorizer.detectLanguage('config.json'), equals('json'));
      expect(FileCategorizer.detectLanguage('service.yaml'), equals('yaml'));
    });

    test('Category folder names match AppConstants', () {
      expect(FileCategory.code.folderName, equals(AppConstants.codeFolder));
      expect(FileCategory.documents.folderName, equals(AppConstants.documentsFolder));
      expect(FileCategory.images.folderName, equals(AppConstants.imagesFolder));
      expect(FileCategory.media.folderName, equals(AppConstants.mediaFolder));
      expect(FileCategory.archives.folderName, equals(AppConstants.archivesFolder));
    });
  });
}
