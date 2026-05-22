import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/verified_badge.dart';

/// Widget tests for the verified-club badge.
///
/// Real-world need this addresses: `clubs.name` is NOT unique
/// (only `clubs.slug` is), so a fan can register "Richmond Marathon"
/// before the official organisation does. The badge differentiates
/// the authentic operator. Pin the icon shape + colour + a11y label
/// so a refactor can't silently swap the mark for something less
/// recognisable.
void main() {
  group('VerifiedBadge', () {
    testWidgets('renders the canonical Material verified icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VerifiedBadge())),
      );
      expect(
        find.byIcon(Icons.verified),
        findsOneWidget,
        reason: 'Verified badge must render `Icons.verified` — pinned '
            'so a refactor that swaps it for `check_circle` or '
            '`star` fails this test loud (those marks have other '
            'meanings on the platform).',
      );
    });

    testWidgets('default tooltip is "Official verified club"', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VerifiedBadge())),
      );
      // Tooltip widget is mounted with the default copy.
      expect(
        find.byTooltip('Official verified club'),
        findsOneWidget,
      );
    });

    testWidgets('honours a custom tooltip', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerifiedBadge(tooltip: 'Verified event organiser'),
          ),
        ),
      );
      expect(find.byTooltip('Verified event organiser'), findsOneWidget);
    });

    testWidgets('paints in the same blue as the Svelte twin (#2563EB)',
        (tester) async {
      // The Svelte component uses `#2563eb`; the Flutter twin must
      // match so cross-platform users see the same mark.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VerifiedBadge())),
      );
      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.verified));
      expect(iconWidget.color, const Color(0xFF2563EB));
    });

    testWidgets('default size is 16 dp; honours a custom size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VerifiedBadge())),
      );
      var iconWidget = tester.widget<Icon>(find.byIcon(Icons.verified));
      expect(iconWidget.size, 16);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VerifiedBadge(size: 24))),
      );
      iconWidget = tester.widget<Icon>(find.byIcon(Icons.verified));
      expect(iconWidget.size, 24);
    });

    testWidgets('semantic label matches tooltip for screen-reader users',
        (tester) async {
      // The badge is a meaning-bearing icon; without a semantic
      // label TalkBack reads "image" which gives no clue. Pin the
      // a11y string so a refactor doesn't drop it.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VerifiedBadge())),
      );
      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.verified));
      expect(iconWidget.semanticLabel, 'Official verified club');
    });
  });
}
