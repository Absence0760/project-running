import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// StatTile guard (issue #666 V8). Twelve private stat-tile classes drifted to
/// six value type sizes, two label sizes and two muted colours between them.
/// These pin the ramp, the muted token, and the invariant that separates a
/// value from a label: a label may ellipsise, a value may only shrink.
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

Future<void> _pump(
  WidgetTester tester,
  Widget tile, {
  ThemeData? theme,
  double width = 120,
  double textScale = 1.0,
}) => tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Center(
              child: SizedBox(width: width, child: tile),
            ),
          ),
        ),
      ),
    );

Text _textOf(WidgetTester tester, String data) =>
    tester.widget<Text>(find.text(data));

void main() {
  group('StatTile — the type ramp', () {
    testWidgets('the three tiers step monotonically and none reuses another', (tester) async {
      final sizes = <String, double>{};
      for (final (name, tile) in <(String, Widget)>[
        (
          'small',
          const StatTile.small(
            icon: Icons.terrain,
            label: 'Elev Gain',
            value: '123',
          ),
        ),
        ('medium', const StatTile.medium(label: 'Time', value: '123')),
        ('large', const StatTile.large(label: 'Distance', value: '123')),
      ]) {
        await _pump(tester, tile);
        sizes[name] = _textOf(tester, '123').style!.fontSize!;
      }
      expect(sizes['small']!, lessThan(sizes['medium']!));
      expect(sizes['medium']!, lessThan(sizes['large']!));
    });

    testWidgets('only the live tier takes tabular figures', (tester) async {
      await _pump(tester, const StatTile.medium(label: 'Time', value: '1:02'));
      expect(
        _textOf(tester, '1:02').style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );

      await _pump(tester, const StatTile.large(label: 'Time', value: '1:02'));
      expect(_textOf(tester, '1:02').style!.fontFeatures, isNull);
    });

    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      testWidgets('the $name label clears 4.5:1 as text on its card', (tester) async {
        await _pump(
          tester,
          const StatTile.large(label: 'Distance', value: '5.00', unit: 'km'),
          theme: theme,
        );
        final scheme = theme.colorScheme;
        for (final text in ['Distance', 'km']) {
          final colour = _textOf(tester, text).style!.color!;
          // `colorScheme.outline`, which five of the twelve tiles used, is the
          // 3:1 boundary token and fails here on the light card.
          expect(colour, scheme.onSurfaceVariant);
          expect(
            _contrast(colour, theme.cardColor),
            greaterThanOrEqualTo(4.5),
            reason: '$text on the $name card',
          );
        }
      });
    }
  });

  group('StatTile — a value shrinks, only a label truncates', () {
    testWidgets(
      'the label is capped at one ellipsised line, the value is not',
      (tester) async {
        await _pump(
          tester,
          const StatTile.large(
            label: 'Durchschnittsgeschwindigkeit',
            value: '1234.56',
          ),
          width: 60,
        );
        expect(tester.takeException(), isNull);

        final label = _textOf(tester, 'Durchschnittsgeschwindigkeit');
        expect(label.maxLines, 1);
        expect(label.overflow, TextOverflow.ellipsis);

        final value = _textOf(tester, '1234.56');
        expect(value.maxLines, isNull);
        expect(value.overflow, isNull);
      },
    );

    testWidgets('four medium tiles in a cramped Row scale down rather than '
        'overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: Row(
                  children: [
                    Expanded(
                      child: StatTile.medium(
                        label: 'Distance',
                        value: '1234.56',
                      ),
                    ),
                    Expanded(
                      child: StatTile.medium(label: 'Time', value: '12:34:56'),
                    ),
                    Expanded(
                      child: StatTile.medium(
                        label: 'Moving',
                        value: '12:30:01',
                      ),
                    ),
                    Expanded(
                      child: StatTile.medium(
                        label: 'Avg pace',
                        value: '12:34',
                        unit: '/km',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('1234.56'), findsOneWidget);
      expect(find.text('12:34:56'), findsOneWidget);
      expect(find.text('/km'), findsOneWidget);
    });

    testWidgets('the small tier keeps its ellipsis — a 72 dp grid cell has no '
        'room to shrink into', (tester) async {
      await _pump(
        tester,
        const StatTile.small(
          icon: Icons.favorite,
          label: 'Avg HR',
          value: '142',
        ),
      );
      final value = _textOf(tester, '142');
      expect(value.maxLines, 1);
      expect(value.overflow, TextOverflow.ellipsis);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });
  });

  testWidgets('labelTrailing sits beside the label without displacing it', (tester) async {
    await _pump(
      tester,
      const StatTile.large(
        label: 'VDOT',
        value: '49.8',
        labelTrailing: Icon(Icons.info_outline, size: 13),
      ),
    );
    expect(find.text('VDOT'), findsOneWidget);
    final label = tester.getRect(find.text('VDOT'));
    final glyph = tester.getRect(find.byIcon(Icons.info_outline));
    expect(glyph.left, greaterThanOrEqualTo(label.right));
  });
}
