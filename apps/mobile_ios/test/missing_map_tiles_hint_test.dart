import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/missing_map_tiles_hint.dart';

/// Widget tests for the missing-MAPTILER_KEY diagnostic banner.
/// The user reported "I'm still not seeing the map" multiple times
/// — without a visible hint, an unset env var presents as a silent
/// blank-grey LiveRunMap. Pin both branches of the visibility.
void main() {
  group('MissingMapTilesHint', () {
    testWidgets(
      'renders the hint banner when neither env key is set',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MissingMapTilesHint(envKeyPresentOverride: false),
            ),
          ),
        );
        // May 2026 copy update: tiles fall back to OSM instead of
        // going blank, so the heading reflects the active fallback
        // rather than the (no-longer-accurate) "disabled" wording.
        expect(
          find.text('Using OpenStreetMap fallback tiles'),
          findsOneWidget,
        );
        expect(
          find.textContaining('MAPTILER_KEY'),
          findsOneWidget,
          reason: 'Hint body must name the env var so users know '
              'what to set.',
        );
        // Map-outline icon shows so the banner reads as map-related.
        expect(find.byIcon(Icons.map_outlined), findsOneWidget);
      },
    );

    testWidgets(
      'renders NOTHING when at least one env key is configured '
      '(production builds + dev with a real key see no banner)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MissingMapTilesHint(envKeyPresentOverride: true),
            ),
          ),
        );
        expect(
          find.text('Using OpenStreetMap fallback tiles'),
          findsNothing,
        );
        expect(find.byIcon(Icons.map_outlined), findsNothing);
        // The widget collapses to SizedBox.shrink — no layout
        // footprint at all.
        final shrink = find.byType(SizedBox);
        expect(shrink, findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'hint copy mentions BOTH env var names, the file path, AND the '
      '10.0.2.2 vs LAN-IP footgun for physical devices',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MissingMapTilesHint(envKeyPresentOverride: false),
            ),
          ),
        );
        // The four pieces of info needed to act on the hint. Pin
        // each so a refactor to generic copy ("check your env
        // config") fails this test.
        expect(find.textContaining('MAPTILER_KEY'), findsOneWidget);
        expect(find.textContaining('TILE_URL_TEMPLATE'), findsOneWidget);
        expect(find.textContaining('.env.local'), findsOneWidget);
        expect(find.textContaining('10.0.2.2'), findsOneWidget);
      },
    );
  });
}
