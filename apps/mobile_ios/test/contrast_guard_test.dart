import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gear_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/gear_screen.dart';
import '../lib/widgets/workout_review_section.dart';

/// Mobile contrast guard — the Dart counterpart to web's
/// `contrast_guard.test.ts`. It renders the small tinted status badges that
/// carry fixed (non-Material-token) colour pairs and asserts the foreground
/// text meets WCAG 2.2 AA (>= 4.5:1 for this sub-18sp `labelSmall` text) in
/// both the light and dark app themes. A regression here means a recent edit
/// reverted a status colour to a pair that goes illegible.
///
/// Material-token pairs (`onErrorContainer` on `errorContainer`, etc.) are not
/// asserted — Material 3 guarantees their tonal contrast by construction.

/// WCAG relative luminance of an sRGB colour.
double _luminance(Color c) {
  double chan(double v) {
    v /= 255.0;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  // ignore: deprecated_member_use
  return 0.2126 * chan(c.red.toDouble()) +
      // ignore: deprecated_member_use
      0.7152 * chan(c.green.toDouble()) +
      // ignore: deprecated_member_use
      0.0722 * chan(c.blue.toDouble());
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The badge's foreground text colour and its pill background, read from the
/// actually-rendered widgets so the guard tracks the real colours, not a copy.
({Color fg, Color bg}) _badgeColors(WidgetTester tester, String label) {
  final text = tester.widget<Text>(find.text(label));
  final fg = text.style?.color;
  expect(fg, isNotNull, reason: 'badge "$label" has no text colour');
  final container = tester.widget<Container>(
    find
        .ancestor(of: find.text(label), matching: find.byType(Container))
        .first,
  );
  final decoration = container.decoration as BoxDecoration?;
  final bg = decoration?.color;
  expect(bg, isNotNull, reason: 'badge "$label" has no pill background');
  return (fg: fg!, bg: bg!);
}

Future<({Preferences prefs, LocalGearStore store, Directory dir})>
    _gearFixtures() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  final dir = Directory.systemTemp.createTempSync('contrast_gear_');
  final store = LocalGearStore();
  await store.init(overrideDirectory: dir);
  return (prefs: prefs, store: store, dir: dir);
}

Map<String, dynamic> _gearRow(String id, String name, num total, num target) => {
      'id': id,
      'kind': 'shoe',
      'name': name,
      'brand': null,
      'model': null,
      'purchased_at': null,
      'retired_at': null,
      'notes': null,
      'target_distance_m': target,
      'total_distance_m': total,
      'run_count': 1,
    };

void main() {
  group('gear wear badge meets WCAG AA', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('due + worn badges in $mode', (tester) async {
        final f = await _gearFixtures();
        try {
          await tester.runAsync(() => f.store.replaceFromServer([
                _gearRow('a', 'Worn Shoe', 900000, 800000), // worn
                _gearRow('b', 'Due Shoe', 720000, 800000), // 90% -> due
              ]));
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GearScreen(api: null, preferences: f.prefs, store: f.store),
          ));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          for (final label in ['Replace soon', 'Past replacement distance']) {
            final c = _badgeColors(tester, label);
            final ratio = _contrast(c.fg, c.bg);
            expect(ratio, greaterThanOrEqualTo(4.5),
                reason: '"$label" badge contrast $ratio in $mode fails AA');
          }
        } finally {
          f.dir.deleteSync(recursive: true);
        }
      });
    }
  });

  group('hint text token meets WCAG AA', () {
    // Settings hint text (sign-in-to-edit, BLE scan hints) uses
    // colorScheme.onSurfaceVariant, not a hardcoded Colors.grey (~2.42:1 on
    // parchment, below the 4.5:1 floor). Pin that the token clears AA against
    // both the surface and scaffold background in each theme.
    for (final entry in {
      'light': AppTheme.light,
      'dark': AppTheme.dark,
    }.entries) {
      test('onSurfaceVariant in ${entry.key}', () {
        final theme = entry.value;
        final fg = theme.colorScheme.onSurfaceVariant;
        for (final bg in {theme.colorScheme.surface, theme.scaffoldBackgroundColor}) {
          final ratio = _contrast(fg, bg);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason:
                  'hint text onSurfaceVariant contrast $ratio in ${entry.key} fails AA');
        }
      });
    }
  });

  group('AdherencePill meets WCAG AA', () {
    for (final adherence in ['completed', 'partial']) {
      testWidgets('$adherence pill', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: Center(child: AdherencePill(adherence: adherence))),
        ));
        await tester.pump();
        final c = _badgeColors(tester, adherence);
        final ratio = _contrast(c.fg, c.bg);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '"$adherence" pill contrast $ratio fails AA');
      });
    }
  });
}
