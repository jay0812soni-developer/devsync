import 'package:flutter/material.dart';

class DevSyncColors {
  DevSyncColors._();

  // Background & Surfaces
  static const Color background = Color(0xFF0D1117);
  static const Color surface = Color(0xFF161B22);
  static const Color surfaceVariant = Color(0xFF21262D);
  static const Color card = Color(0xFF1C2128);
  static const Color border = Color(0xFF30363D);

  // Accents
  static const Color primary = Color(0xFF58A6FF);
  static const Color primaryVariant = Color(0xFF388BFD);
  static const Color secondary = Color(0xFF7EE787);
  static const Color accent = Color(0xFFD2A8FF);
  static const Color warning = Color(0xFFF0883E);
  static const Color error = Color(0xFFF85149);

  // Message Bubbles
  static const Color bubbleSent = Color(0xFF1A3B5C);
  static const Color bubbleReceived = Color(0xFF21262D);
  static const Color codeBackground = Color(0xFF0D1117);

  // Text
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF6E7681);
}

class DevSyncTheme {
  DevSyncTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: DevSyncColors.background,
      colorScheme: const ColorScheme.dark(
        primary: DevSyncColors.primary,
        secondary: DevSyncColors.secondary,
        surface: DevSyncColors.surface,
        error: DevSyncColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: DevSyncColors.textPrimary,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: DevSyncColors.surface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: DevSyncColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: DevSyncColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: DevSyncColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: DevSyncColors.border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DevSyncColors.surfaceVariant,
        hintStyle: const TextStyle(color: DevSyncColors.textMuted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DevSyncColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DevSyncColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DevSyncColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      dividerTheme: const DividerThemeData(
        color: DevSyncColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
