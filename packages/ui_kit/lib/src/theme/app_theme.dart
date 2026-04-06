import 'package:flutter/material.dart';

/// App-wide theme and design tokens.
class AppTheme {
  static const Color primary = Color(0xFF1E88E5);
  static const Color secondary = Color(0xFF43A047);
  static const Color surface = Color(0xFFFAFAFA);
  static const Color error = Color(0xFFE53935);

  static ThemeData get light => ThemeData(
        colorSchemeSeed: primary,
        brightness: Brightness.light,
        useMaterial3: true,
      );

  static ThemeData get dark => ThemeData(
        colorSchemeSeed: primary,
        brightness: Brightness.dark,
        useMaterial3: true,
      );
}
