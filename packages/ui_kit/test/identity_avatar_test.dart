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

    test('takes a whole grapheme, not half a surrogate pair', () {
      // `substring(0, 1)` cut an astral character in half and the avatar
      // rendered the lone surrogate as the replacement glyph.
      expect(identityInitial('\u{1F600}bob'), '\u{1F600}');
      expect(identityInitial('\u{1F468}\u200D\u{1F469}\u200D\u{1F467}'),
          '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}');
      for (final s in <String>['\u{1F600}bob', '\u{1D400}X']) {
        expect(identityInitial(s).runes.first, s.runes.first);
        expect(identityInitial(s).codeUnits.first & 0xFC00 == 0xDC00, isFalse,
            reason: 'never a bare low surrogate');
      }
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

    testWidgets('the initial stays inside the circle at 2x OS text scale',
        (tester) async {
      Future<void> pump(double scale) => tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const Scaffold(
                body: Center(
                  child: IdentityAvatar(
                      seed: 'user-5', name: 'alice', size: 18, fontSize: 10),
                ),
              ),
            ),
          );

      // The caller picks the diameter for layout, so the initial is bounded
      // by the circle. Pre-fix a 10 px initial rendered 20.3 x 29 at 2x and
      // spilled outside an 18 px avatar.
      await pump(1.0);
      final at1x = tester.getSize(find.byType(FittedBox));
      expect(at1x.height, lessThanOrEqualTo(18));

      await pump(2.0);
      final at2x = tester.getSize(find.byType(FittedBox));
      expect(at2x.width, lessThanOrEqualTo(18));
      expect(at2x.height, lessThanOrEqualTo(18));
      // Still bigger than at 1.0x — scaleDown honours the larger setting up
      // to what the circle can hold, it does not pin the initial at 1.0x.
      expect(at2x.height, greaterThan(at1x.height));
    });
  });
}
