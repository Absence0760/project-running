import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/adaptive_width.dart';

/// Widths the clamp is exercised at, one per class.
const _compact = Size(390, 844);
const _expanded = Size(1280, 800);

Future<double> _childWidthAt(WidgetTester tester, Size size,
    {double? maxWidth}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => maxWidth == null
            ? contentColumn(context, const SizedBox.expand(key: Key('body')))
            : contentColumn(
                context,
                const SizedBox.expand(key: Key('body')),
                maxWidth: maxWidth,
              ),
      ),
    ),
  );
  return tester.getSize(find.byKey(const Key('body'))).width;
}

void main() {
  group('widthClassOfWidth', () {
    test('phone widths are compact', () {
      expect(widthClassOfWidth(320), WidthClass.compact);
      expect(widthClassOfWidth(411), WidthClass.compact);
      expect(widthClassOfWidth(599), WidthClass.compact);
    });

    test('600-839 is medium — includes the 800dp flutter_test surface', () {
      expect(widthClassOfWidth(600), WidthClass.medium);
      expect(widthClassOfWidth(800), WidthClass.medium);
      expect(widthClassOfWidth(839), WidthClass.medium);
    });

    test('840+ is expanded — the 10-inch tablet class', () {
      expect(widthClassOfWidth(840), WidthClass.expanded);
      expect(widthClassOfWidth(1280), WidthClass.expanded);
    });
  });

  group('contentColumn (issue #666 C15)', () {
    testWidgets('a phone keeps the full width — the child is untouched',
        (tester) async {
      expect(await _childWidthAt(tester, _compact), _compact.width);
    });

    testWidgets('a tablet caps the child at kContentMaxWidth', (tester) async {
      expect(await _childWidthAt(tester, _expanded), kContentMaxWidth);
    });

    testWidgets('a caller may widen the cap', (tester) async {
      expect(
        await _childWidthAt(tester, _expanded, maxWidth: 1100),
        1100.0,
      );
    });
  });

  group('contentColumn adoption (issue #666 C15)', () {
    // Every clamp used to be the same four lines written out by hand, which
    // is how the app ended up with four of them across 75 screens. Once the
    // helper exists a screen must reach for it rather than re-derive the
    // idiom, or the next reviewer has two shapes to keep in step.
    test('no screen hand-rolls the Center + ConstrainedBox clamp', () {
      final offenders = <String>[];
      for (final f in Directory('lib/screens').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains('kContentMaxWidth') &&
            !src.contains('contentColumn(')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'use contentColumn(context, body) from adaptive_width.dart');
    });

    // Assert the population, not only the property (decisions § 534): an
    // empty adoption set would satisfy the guard above while proving nothing.
    test('the screens that adopted it are still adopting it', () {
      final adopters = <String>[];
      for (final f in Directory('lib/screens').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.readAsStringSync().contains('contentColumn(')) {
          adopters.add(f.uri.pathSegments.last);
        }
      }
      expect(
        adopters,
        containsAll(<String>[
          'dashboard_screen.dart',
          'event_detail_screen.dart',
          'feed_screen.dart',
          'gym_screen.dart',
          'nutrition_screen.dart',
          'plan_detail_screen.dart',
          'runs_screen.dart',
          'settings_preferences_screen.dart',
        ]),
      );
    });
  });
}
