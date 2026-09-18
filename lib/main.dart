import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/storage/database_service.dart';
import 'core/storage/local_file_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize persistent Hive storage
  await DatabaseService.instance.initialize();

  // Initialize DevSync organized directory hierarchy (Code, Images, Documents, Media, Archives)
  await LocalFileManager.instance.initialize();

  runApp(
    const ProviderScope(
      child: DevSyncApp(),
    ),
  );
}
