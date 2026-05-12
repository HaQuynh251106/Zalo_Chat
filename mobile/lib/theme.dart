import 'package:flutter/material.dart';

/// Modern, friendly palette intentionally distinct from Zalo's blue (#0084FF).
/// Primary: Indigo → Violet gradient. Accent: warm Coral. Surface: soft cream.
class AppLayout {
  /// Max width of the chat content column on wide viewports.
  static const double chatContentMaxWidth = 760;
  /// Max width of a single message bubble, regardless of viewport.
  static const double bubbleMaxWidth = 520;
}

class AppPalette {
  static const indigo = Color(0xFF6366F1);
  static const violet = Color(0xFF8B5CF6);
  static const lavender = Color(0xFFC4B5FD);
  static const coral = Color(0xFFF472B6);
  static const peach = Color(0xFFFB923C);
  static const mint = Color(0xFF34D399);

  static const bgLight = Color(0xFFFAF7FF);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF1E1B2E);
  static const textSecondary = Color(0xFF6B6883);
  static const divider = Color(0xFFEEEAF6);

  /// Primary CTA / mine-bubble gradient.
  static const primaryGradient = LinearGradient(
    colors: [indigo, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Login background gradient (richer, multi-stop).
  static const backdropGradient = LinearGradient(
    colors: [Color(0xFF5B5BF6), Color(0xFF8B5CF6), Color(0xFFF472B6)],
    stops: [0.0, 0.55, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Avatar ring gradient (for online users).
  static const avatarRing = LinearGradient(
    colors: [coral, violet, indigo],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppPalette.indigo,
    brightness: Brightness.light,
    primary: AppPalette.indigo,
    secondary: AppPalette.coral,
    surface: AppPalette.surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppPalette.bgLight,
    textTheme: const TextTheme(
      displayLarge:
          TextStyle(fontWeight: FontWeight.w700, color: AppPalette.textPrimary),
      headlineSmall:
          TextStyle(fontWeight: FontWeight.w700, color: AppPalette.textPrimary),
      titleLarge:
          TextStyle(fontWeight: FontWeight.w600, color: AppPalette.textPrimary),
      titleMedium:
          TextStyle(fontWeight: FontWeight.w600, color: AppPalette.textPrimary),
      bodyMedium: TextStyle(color: AppPalette.textPrimary, height: 1.35),
      bodySmall: TextStyle(color: AppPalette.textSecondary),
      labelMedium: TextStyle(color: AppPalette.textSecondary),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: AppPalette.textPrimary,
      titleTextStyle: TextStyle(
        color: AppPalette.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: AppPalette.textSecondary),
      hintStyle: const TextStyle(color: AppPalette.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppPalette.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppPalette.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppPalette.indigo, width: 1.6),
      ),
    ),
    dividerTheme:
        const DividerThemeData(color: AppPalette.divider, thickness: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppPalette.indigo,
      unselectedItemColor: AppPalette.textSecondary,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppPalette.coral,
      foregroundColor: Colors.white,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppPalette.textPrimary,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
