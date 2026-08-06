import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/route_detail_screen.dart';

/// The roadbook's discoverability contract on mobile (issue #666 M4, mirror of
/// web's `roadbook_entry_guard.test.ts`).
///
/// `RoadbookScreen` has exactly one entry point in the whole app — this button
/// — and it used to render only `if (_markerPins.isNotEmpty)`. A runner who
/// had never placed a course marker therefore had no way to discover that a
/// crew sheet exists: unlike web there is not even a URL to type. The roadbook
/// does not need markers (it projects start → finish off the line and the goal
/// time), so the affordance is always shown and disabled — with a stated
/// reason — only for a route with no line to walk.

/// A locally-built route (empty `userId`) so the screen's privacy clip takes
/// the signed-out own-route branch and `_displayWaypoints` is the row's own
/// line — the clip path itself is covered by the privacy suite.
cm.Route _route({required List<cm.Waypoint> waypoints}) => cm.Route(
      id: 'r1',
      userId: '',
      name: 'River Loop',
      waypoints: waypoints,
      distanceMetres: 8500,
      elevationGainMetres: 45,
      isPublic: true,
    );

List<cm.Waypoint> _line(int n) => [
      for (var i = 0; i < n; i++)
        cm.Waypoint(lat: 51.5 + i * 0.001, lng: -0.1 + i * 0.001),
    ];

Future<void> _pump(WidgetTester tester, cm.Route route) async {
  // Tall surface so the whole body builds without a drag — the roadbook button
  // sits below the hero map + the markers panel, and a fixed drag offset is an
  // absolute fit in disguise (decisions § 533).
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: RouteDetailScreen(
      route: route,
      routeStore: LocalRouteStore(),
      preferences: prefs,
      isOwner: false,
    ),
  ));
  // One pump to build; pumpAndSettle would spin LiveRunMap's pulse animation.
  await tester.pump();
  await tester.pump(Duration.zero);
}

OutlinedButton _crewSheetButton(WidgetTester tester) {
  final finder = find.ancestor(
    of: find.text('Roadbook (crew sheet)'),
    matching: find.byType(OutlinedButton),
  );
  expect(finder, findsOneWidget,
      reason: 'the crew-sheet affordance must always be rendered');
  return tester.widget<OutlinedButton>(finder);
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  group('route detail — roadbook entry point', () {
    testWidgets(
        'a route with a line and NO course markers still offers the crew sheet',
        (tester) async {
      await _pump(tester, _route(waypoints: _line(6)));

      // Assert the population, not only the property (§534): prove there are
      // genuinely no marker pins on this route before reading the button.
      expect(find.text('Add at least two points to this route to build a roadbook.'),
          findsNothing);
      expect(_crewSheetButton(tester).onPressed, isNotNull,
          reason: 'no markers is not a reason to withhold the roadbook — it '
              'projects start → finish off the line and the goal time');
    });

    testWidgets('a route with no walkable line disables it and says why',
        (tester) async {
      await _pump(tester, _route(waypoints: const []));

      expect(_crewSheetButton(tester).onPressed, isNull,
          reason: 'buildRoadbook cannot walk a line with fewer than two points');
      expect(
        find.text('Add at least two points to this route to build a roadbook.'),
        findsOneWidget,
        reason: 'a disabled affordance must state its reason, never no-op',
      );
    });

    testWidgets('a single-point line is still not walkable', (tester) async {
      await _pump(tester, _route(waypoints: _line(1)));
      expect(_crewSheetButton(tester).onPressed, isNull);
    });
  });
}
