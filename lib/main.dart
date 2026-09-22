import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/storage/database_service.dart';
import 'core/storage/local_file_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await DatabaseService.instance.initialize();
    if (!kIsWeb) {
      await LocalFileManager.instance.initialize();
    }

    runApp(
      const ProviderScope(
        child: DevSyncApp(),
      ),
    );
  } catch (error, stack) {
    debugPrint('DevSync failed to start: $error\n$stack');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText('DevSync could not start.\n\n$error'),
            ),
          ),
        ),
      ),
    );
  }
}
