import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

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

void main() {
  group('identityHue', () {
    test('is stable and matches the historical per-screen hash', () {
      expect(identityHue('alice'), 0);
      expect(identityHue('bob'), 157);
      expect(identityHue('club-42'), 173);
      expect(identityHue('e9b1c2d3-4f56-7890-abcd-ef1234567890'), 232);
    });

    test('same seed hashes to the same hue, in range', () {
      for (final id in ['alice', 'bob', 'club-42', '', 'x']) {
        final h = identityHue(id);
        expect(h, inInclusiveRange(0, 359));
        expect(identityHue(id), h);
      }
    });
  });

  group('identityInitial', () {
    test('uppercases the first letter', () {
      expect(identityInitial('alice'), 'A');
      expect(identityInitial('Bob'), 'B');
      expect(identityInitial('  zed'), 'Z');
    });

    test('falls back to ? for missing names', () {
      expect(identityInitial(null), '?');
      expect(identityInitial(''), '?');
      expect(identityInitial('   '), '?');
    });
  });

  group('identityBackground + identityForeground', () {
    test('foreground meets WCAG AA over the background for every hue', () {
      for (var hue = 0; hue < 360; hue++) {
        final bg = identityBackground(hue);
        final fg = identityForeground(bg);
        expect(
          _contrast(fg, bg),
          greaterThanOrEqualTo(4.5),
          reason: 'hue $hue must be legible',
        );
      }
    });

    test('hues legible against white keep the historical colour exactly', () {
      for (final hue in [0, 220, 260, 300, 350]) {
        final historical =
            HSLColor.fromAHSL(1, hue.toDouble(), 0.5, 0.55).toColor();
        if (_contrast(Colors.white, historical) >= 4.5) {
          expect(identityBackground(hue), historical,
              reason: 'hue $hue should not shift');
        }
      }
    });

    test('foreground contrast holds for a sweep of real-world seeds', () {
      final seeds = [
        for (var i = 0; i < 200; i++) 'user-$i',
        'alice',
        'bob',
        'runner@test.com',
      ];
      for (final seed in seeds) {
        final bg = identityBackground(identityHue(seed));
        expect(_contrast(identityForeground(bg), bg),
            greaterThanOrEqualTo(4.5), reason: 'seed $seed must be legible');
      }
    });
  });

  group('IdentityAvatar', () {
    testWidgets('renders the initial in the computed colours', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IdentityAvatar(seed: 'user-1', name: 'alice', size: 44),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('A'));
      final bg = identityBackground(identityHue('user-1'));
      expect(text.style?.color, identityForeground(bg));
      final container = tester.widget<Container>(
        find.ancestor(of: find.text('A'), matching: find.byType(Container)),
      );
      expect((container.decoration as BoxDecoration).color, bg);
    });

    testWidgets('falls back to ? without a name', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: IdentityAvatar(seed: 'user-2')),
        ),
      );
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('keeps the initial visible while an image is in flight',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IdentityAvatar(
              seed: 'user-3',
              name: 'alice',
              imageUrl: 'https://example.test/a.jpg',
            ),
          ),
        ),
      );
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('shows the initial, not an empty disc, when the image fails',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IdentityAvatar(
              seed: 'user-4',
              name: 'bob',
              imageUrl: 'https://example.test/gone.jpg',
            ),
          ),
        ),
      );
      // The test binding's mock HTTP client answers every request with a
      // 400, so the network image resolves to an error.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('B'), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
    });
  });
}
