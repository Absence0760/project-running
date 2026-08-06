import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// [ProgressBar]'s two contrast axes, measured on the surfaces it is actually
/// mounted on, plus the geometry that has to stay derived rather than picked.
///
/// The arithmetic these numbers rest on is in the widget's own doc comment: no
/// track colour can carry both axes at 3:1, so the boundary is drawn and the
/// track is chosen for the fill axis alone. If a future edit tries to drop the
/// hairline and lean on the track again, the surface assertion below fails.
double _luminance(Color c) {
  double chan(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Every fill the app passes to a [ProgressBar], by name. `colorScheme.error`
/// is deliberately absent: it is 2.991:1 on the light track and is the reason
/// the gear "worn" bar takes `AppSemanticColors.danger` instead.
Map<String, Color> _fills(ThemeData t) {
  final semantic = AppSemanticColors.ofTheme(t);
  return {
    'primary': t.colorScheme.primary,
    'success': semantic.success,
    'warning': semantic.warning,
    'danger': semantic.danger,
  };
}

/// The surfaces a bar is mounted on: the card (10 of the 11 call sites) and
/// the scaffold (the session-runner bar, which is on the page itself).
Map<String, Color> _grounds(ThemeData t) => {
      'card': t.cardTheme.color!,
      'scaffold': t.scaffoldBackgroundColor,
    };

/// The colours the widget actually paints, read back off the rendered tree so
/// the assertions below track the implementation rather than a copy of it.
Future<({Color track, Color outline})> _painted(
    WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: const Scaffold(
      body: Center(child: SizedBox(width: 200, child: ProgressBar(value: 0.5))),
    ),
  ));
  final decorated = tester.widget<DecoratedBox>(
    find
        .descendant(of: find.byType(ProgressBar), matching: find.byType(DecoratedBox))
        .first,
  );
  final decoration = decorated.decoration as BoxDecoration;
  return (
    track: decoration.color!,
    outline: (decoration.border! as Border).top.color,
  );
}

void main() {
  group('ProgressBar contrast', () {
    for (final entry in {'light': AppTheme.light, 'dark': AppTheme.dark}
        .entries) {
      final name = entry.key;
      final theme = entry.value;

      testWidgets(
          '$name: the painted hairline clears 3:1 on every ground the bar '
          'sits on', (tester) async {
        final painted = await _painted(tester, theme);
        final grounds = _grounds(theme);
        expect(grounds, isNotEmpty);
        grounds.forEach((groundName, ground) {
          final ratio = _contrast(painted.outline, ground);
          expect(ratio, greaterThanOrEqualTo(3.0),
              reason: '$name hairline on $groundName is '
                  '${ratio.toStringAsFixed(3)}:1');
        });
      });

      testWidgets('$name: every fill clears 3:1 against the painted track',
          (tester) async {
        final painted = await _painted(tester, theme);
        final fills = _fills(theme);
        expect(fills, isNotEmpty);
        fills.forEach((fillName, fill) {
          final ratio = _contrast(fill, painted.track);
          expect(ratio, greaterThanOrEqualTo(3.0),
              reason: '$name $fillName on the painted track is '
                  '${ratio.toStringAsFixed(3)}:1');
        });
      });

      testWidgets('$name: colorScheme.error is why danger exists',
          (tester) async {
        // Pins the reason the gear bar was moved: the scheme error is the one
        // status colour that cannot be a bar fill.
        final painted = await _painted(tester, theme);
        final schemeError = _contrast(theme.colorScheme.error, painted.track);
        final danger =
            _contrast(AppSemanticColors.ofTheme(theme).danger, painted.track);
        expect(danger, greaterThan(schemeError));
        if (name == 'light') {
          expect(schemeError, lessThan(3.0));
        }
      });
    }
  });

  group('ProgressBar geometry', () {
    testWidgets('the bar is the fill lane plus one hairline each side',
        (tester) async {
      expect(ProgressBar.height, ProgressBar.fillHeight + 2);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(child: SizedBox(width: 200, child: ProgressBar(value: 0.5))),
        ),
      ));
      expect(tester.getSize(find.byType(ProgressBar)).height,
          ProgressBar.height);
      expect(
          tester.getSize(find.byType(LinearProgressIndicator)).height,
          ProgressBar.fillHeight);
    });

    testWidgets('a null value renders the indeterminate animation',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(child: SizedBox(width: 200, child: ProgressBar(value: null))),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      final indicator =
          tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(indicator.value, isNull);
      // Leave the repeating controller un-pumped-to-settle; it never settles.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the track and hairline come from the theme, not the call site',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(child: SizedBox(width: 200, child: ProgressBar(value: 0.25))),
        ),
      ));
      final decorated = tester.widget<DecoratedBox>(
        find.descendant(
            of: find.byType(ProgressBar), matching: find.byType(DecoratedBox)).first,
      );
      final decoration = decorated.decoration as BoxDecoration;
      expect(decoration.color, AppTheme.dark.colorScheme.surfaceContainerHighest);
      expect((decoration.border as Border).top.color,
          AppTheme.dark.colorScheme.outlineVariant);
      // The LinearProgressIndicator must not paint its own track over ours.
      final indicator = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(indicator.backgroundColor, Colors.transparent);
    });

    testWidgets('fill defaults to primary and is overridable', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(children: const [
            SizedBox(width: 200, child: ProgressBar(value: 0.5)),
            SizedBox(
                width: 200,
                child: ProgressBar(value: 0.5, fill: Color(0xFF2E6B3C))),
          ]),
        ),
      ));
      final bars = tester
          .widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .toList();
      expect(bars, hasLength(2));
      expect(bars[0].color, AppTheme.light.colorScheme.primary);
      expect(bars[1].color, const Color(0xFF2E6B3C));
    });
  });
}
