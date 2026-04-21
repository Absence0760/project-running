import 'package:flutter/material.dart';

/// App-wide theme and design tokens. "Dusk".
class AppTheme {
  static const Color dusk = Color(0xFF3A2E5C);
  static const Color duskDeep = Color(0xFF241B3D);
  static const Color midnight = Color(0xFF120D22);
  static const Color coral = Color(0xFFF2A07B);
  static const Color coralDeep = Color(0xFFD97A54);
  static const Color lilac = Color(0xFFB9A7E8);
  static const Color parchment = Color(0xFFF7F3EC);
  static const Color parchmentDim = Color(0xFFEBE5D8);
  static const Color ink = Color(0xFF1B1628);
  static const Color haze = Color(0xFF6B6380);
  static const Color error = Color(0xFFD8594C);

  static const Color primary = dusk;
  static const Color secondary = coral;
  static const Color surface = parchment;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: dusk,
      brightness: Brightness.light,
    ).copyWith(
      primary: dusk,
      onPrimary: parchment,
      secondary: coralDeep,
      onSecondary: parchment,
      surface: parchment,
      onSurface: ink,
      error: error,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: parchment,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: parchment,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dusk,
          foregroundColor: parchment,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: coralDeep,
        foregroundColor: parchment,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: dusk,
        side: const BorderSide(color: haze),
        labelStyle: const TextStyle(color: ink),
        secondaryLabelStyle: const TextStyle(color: parchment),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: parchment,
        indicatorColor: coralDeep.withOpacity(0.18),
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? coralDeep : haze,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? ink : haze,
          ),
        ),
      ),
      dividerColor: parchmentDim,
    );
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: dusk,
      brightness: Brightness.dark,
    ).copyWith(
      primary: coral,
      onPrimary: midnight,
      secondary: lilac,
      onSecondary: midnight,
      surface: duskDeep,
      onSurface: parchment,
      error: error,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: midnight,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: midnight,
        foregroundColor: parchment,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: coral,
          foregroundColor: midnight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: coral,
        foregroundColor: midnight,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: coral,
        side: const BorderSide(color: haze),
        labelStyle: const TextStyle(color: parchment),
        secondaryLabelStyle: const TextStyle(color: midnight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: midnight,
        indicatorColor: coral.withOpacity(0.22),
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? coral
                : parchment.withOpacity(0.55),
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? parchment
                : parchment.withOpacity(0.55),
          ),
        ),
      ),
      dividerColor: const Color(0xFF2E2545),
    );
  }
}
