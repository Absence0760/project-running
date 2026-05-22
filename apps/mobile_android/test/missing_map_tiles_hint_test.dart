import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/missing_map_tiles_hint.dart';

/// Widget tests for the missing-MAPTILER_KEY diagnostic banner.
/// The user reported "I'm still not seeing the map" multiple times
/// — without a visible hint, an unset env var presents as a silent
/// blank-grey LiveRunMap. Pin both branches of the visibility.
void main() {
  group('MissingMapTilesHint', () {
    testWidgets(
      'renders the hint banner when the env key is absent',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MissingMapTilesHint(envKeyPresentOverride: false),
            ),
          ),
        );
        expect(find.text('Map tiles disabled'), findsOneWidget);
        expect(
          find.textContaining('Set MAPTILER_KEY'),
          findsOneWidget,
          reason: 'Hint must include the exact fix-instruction (env '
              'var name + file path) so the user knows what to '
              'set.',
        );
        // Map-outline icon shows so the banner reads as map-related.
        expect(find.byIcon(Icons.map_outlined), findsOneWidget);
      },
    );

    testWidgets(
      'renders NOTHING when the env key is present (production '
      'builds with a configured key see no banner)',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MissingMapTilesHint(envKeyPresentOverride: true),
            ),
          ),
        );
        expect(find.text('Map tiles disabled'), findsNothing);
        expect(find.byIcon(Icons.map_outlined), findsNothing);
        // The widget collapses to SizedBox.shrink — no layout
        // footprint at all.
        final shrink = find.byType(SizedBox);
        expect(shrink, findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'hint copy mentions BOTH the env var name AND the file path so '
      'the user can act without scrolling docs',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MissingMapTilesHint(envKeyPresentOverride: false),
            ),
          ),
        );
        // Env var name + file path are the two pieces of info
        // needed to fix the problem. Pin both so a refactor to
        // generic copy ("check your env config") fails this test.
        expect(find.textContaining('MAPTILER_KEY'), findsOneWidget);
        expect(find.textContaining('.env.local'), findsOneWidget);
      },
    );
  });
}
