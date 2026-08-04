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
  static const Color duskDivider = Color(0xFF2E2545);
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
      splashFactory: InkRipple.splashFactory,
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
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
      // Light surfaceContainerLow computes to 1.005:1 against parchment (and
      // carries the seed's cool lavender cast on a warm page), so card
      // separation comes from the hairline outline, not a tonal fill.
      cardTheme: const CardThemeData(
        color: parchment,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: parchmentDim),
        ),
      ),
      textTheme: const TextTheme(
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
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
        // RawChip resolves only labelStyle.color as a WidgetStateProperty
        // (never the whole TextStyle, never secondaryLabelStyle), so the
        // selected/unselected fork must live on the color itself.
        labelStyle: TextStyle(
          color: WidgetStateColor.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? scheme.onPrimary : ink,
          ),
        ),
        checkmarkColor: scheme.onPrimary,
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
      extensions: const [AppSemanticColors.light],
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
      splashFactory: InkRipple.splashFactory,
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
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
      cardTheme: const CardThemeData(
        color: duskDeep,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: duskDivider),
        ),
      ),
      textTheme: const TextTheme(
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
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
        labelStyle: TextStyle(
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : parchment,
          ),
        ),
        checkmarkColor: scheme.onPrimary,
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
      dividerColor: duskDivider,
      extensions: const [AppSemanticColors.dark],
    );
  }
}

/// Semantic status colours outside the Material scheme: success, warning,
/// danger, and the segment-crown gold. Every on*/base pair is tuned to
/// >= 4.5:1 WCAG AA contrast and every base to >= 3:1 against its
/// brightness's scaffold background — the scheme's own error/onError pair
/// computes below AA (3.85:1 in light), which is why danger exists.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.danger,
    required this.onDanger,
    required this.crown,
    required this.onCrown,
  });

  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color danger;
  final Color onDanger;
  final Color crown;
  final Color onCrown;

  static const AppSemanticColors light = AppSemanticColors(
    success: Color(0xFF2E6B3C),
    onSuccess: AppTheme.parchment,
    warning: Color(0xFF8A5712),
    onWarning: AppTheme.parchment,
    danger: Color(0xFFA93B2E),
    onDanger: AppTheme.parchment,
    crown: Color(0xFF7A5C10),
    onCrown: AppTheme.parchment,
  );

  static const AppSemanticColors dark = AppSemanticColors(
    success: Color(0xFF8CC49B),
    onSuccess: AppTheme.midnight,
    warning: Color(0xFFE6A23C),
    onWarning: AppTheme.midnight,
    danger: Color(0xFFEC8B7A),
    onDanger: AppTheme.midnight,
    crown: Color(0xFFE0BE4E),
    onCrown: AppTheme.midnight,
  );

  // Brightness-matched fallback so a harness that pumps a bare MaterialApp
  // (no AppTheme) renders sane status colours instead of throwing.
  static AppSemanticColors of(BuildContext context) =>
      ofTheme(Theme.of(context));

  static AppSemanticColors ofTheme(ThemeData theme) =>
      theme.extension<AppSemanticColors>() ??
      (theme.brightness == Brightness.dark ? dark : light);

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? danger,
    Color? onDanger,
    Color? crown,
    Color? onCrown,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      crown: crown ?? this.crown,
      onCrown: onCrown ?? this.onCrown,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      crown: Color.lerp(crown, other.crown, t)!,
      onCrown: Color.lerp(onCrown, other.onCrown, t)!,
    );
  }
}
