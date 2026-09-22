import 'package:flutter/material.dart';

/// Warm ink palette. One clay accent, no neon, no second brand color.
class DevSyncColors {
  DevSyncColors._();

  static const Color background = Color(0xFF1B1916);
  static const Color surface = Color(0xFF24211C);
  static const Color surfaceVariant = Color(0xFF2E2A24);
  static const Color card = Color(0xFF26231E);
  static const Color border = Color(0xFF3E382F);

  static const Color primary = Color(0xFFC4622D);
  static const Color primaryVariant = Color(0xFFA04E22);
  static const Color onPrimary = Color(0xFFFFF6EE);
  static const Color secondary = Color(0xFF8F9A7B);
  static const Color accent = Color(0xFFC4B49A);
  static const Color warning = Color(0xFFC4922A);
  static const Color error = Color(0xFFC4503E);
  static const Color success = Color(0xFF6E8B62);

  static const Color bubbleSent = Color(0xFF3A2C22);
  static const Color bubbleReceived = Color(0xFF2A261F);
  static const Color codeBackground = Color(0xFF141210);

  static const Color textPrimary = Color(0xFFF3EDE4);
  static const Color textSecondary = Color(0xFFB7AA9A);
  static const Color textMuted = Color(0xFF8A7E70);
}

class DevSyncTheme {
  DevSyncTheme._();

  static const _text = TextStyle(
    color: DevSyncColors.textPrimary,
    fontFamily: 'Segoe UI',
  );

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: DevSyncColors.background,
      colorScheme: const ColorScheme.dark(
        primary: DevSyncColors.primary,
        onPrimary: DevSyncColors.onPrimary,
        secondary: DevSyncColors.secondary,
        surface: DevSyncColors.surface,
        error: DevSyncColors.error,
        onSecondary: DevSyncColors.background,
        onSurface: DevSyncColors.textPrimary,
        onError: DevSyncColors.onPrimary,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: DevSyncColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        titleMedium: TextStyle(
          color: DevSyncColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        bodyMedium: TextStyle(
          color: DevSyncColors.textPrimary,
          fontSize: 14,
          height: 1.4,
        ),
        bodySmall: TextStyle(
          color: DevSyncColors.textSecondary,
          fontSize: 13,
          height: 1.4,
        ),
        labelSmall: TextStyle(
          color: DevSyncColors.textMuted,
          fontSize: 12,
        ),
      ).apply(fontFamily: 'Segoe UI'),
      appBarTheme: const AppBarTheme(
        backgroundColor: DevSyncColors.surface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Segoe UI',
          color: DevSyncColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: DevSyncColors.textSecondary),
      ),
      cardTheme: CardThemeData(
        color: DevSyncColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: DevSyncColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DevSyncColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: DevSyncColors.border),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: DevSyncColors.surfaceVariant,
        contentTextStyle: TextStyle(color: DevSyncColors.textPrimary, fontSize: 13),
        behavior: SnackBarBehavior.floating,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DevSyncColors.primary,
          foregroundColor: DevSyncColors.onPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: _text.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DevSyncColors.textPrimary,
          side: const BorderSide(color: DevSyncColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: _text.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DevSyncColors.surfaceVariant,
        hintStyle: const TextStyle(color: DevSyncColors.textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: DevSyncColors.textSecondary, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: DevSyncColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: DevSyncColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: DevSyncColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      dividerTheme: const DividerThemeData(
        color: DevSyncColors.border,
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: DevSyncColors.onPrimary,
        unselectedLabelColor: DevSyncColors.textSecondary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),
    );
  }
}
