// The route share card — the one surface in this tree whose artifact leaves
// the app entirely. What it draws is a PNG posted to social media, and until
// now nothing rendered it: every test naming this file was a guard reading the
// source as a string, because the card itself was a private class.
//
// Two things are worth pinning about a picture nobody can correct after the
// fact. The units have to be the reader's own — the climb was hard-coded to
// metres beside a distance that already followed the preference, so a
// mile-unit runner shared "3.11 mi" next to "128 m". And
// `routeShareCardHasMap` has to agree with the card's own glyph fallback:
// the sheet waits for basemap tiles only when that predicate says there are
// tiles, so a disagreement is either an eight-second dead spinner on a card
// with no map, or a part-black basemap baked into the PNG.

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/widgets/route_share_card.dart';

cm.Route _route({
  String name = 'Richmond Park loop',
  double distanceMetres = 10000,
  double elevationGainMetres = 128,
  String? surface = 'trail',
  int waypoints = 4,
}) =>
    cm.Route(
      id: 'route-1',
      userId: 'owner',
      name: name,
      waypoints: [
        for (var i = 0; i < waypoints; i++)
          cm.Waypoint(lat: 51.44 + i / 1000, lng: -0.27 + i / 1000),
      ],
      distanceMetres: distanceMetres,
      elevationGainMetres: elevationGainMetres,
      isPublic: true,
      surface: surface,
    );

Future<Preferences> _prefs({bool miles = false}) async {
  SharedPreferences.setMockInitialValues({'use_miles': miles});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Future<void> _pump(
  WidgetTester tester,
  cm.Route route,
  Preferences prefs,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 640, // 9:16, the ratio the sheet rasterises at
          child: RouteShareCard(route: route, preferences: prefs),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));

  group('routeShareCardHasMap', () {
    // The sheet waits for tiles iff this says so. A route the card draws a
    // glyph for has no tiles to settle, and `MapTileReadiness` reports an
    // empty tile set as never settled — so a false positive is the full
    // ceiling spent staring at a spinner.
    test('a route with fewer than two points draws no map', () {
      expect(routeShareCardHasMap(_route(waypoints: 0)), isFalse);
      expect(routeShareCardHasMap(_route(waypoints: 1)), isFalse);
    });

    test('two points is a line, and a line is a map', () {
      expect(routeShareCardHasMap(_route(waypoints: 2)), isTrue);
    });

    testWidgets('and the card agrees with it at the boundary', (tester) async {
      // Two independent spellings of one threshold, in two places. This is
      // the assertion that keeps them one threshold.
      final prefs = await _prefs();
      for (final points in const [0, 1, 2, 3]) {
        final route = _route(waypoints: points);
        await _pump(tester, route, prefs);
        final drawsMap = tester.any(find.byType(FlutterMap));
        expect(drawsMap, routeShareCardHasMap(route),
            reason: 'routeShareCardHasMap disagrees with the card at '
                '$points waypoints');
        expect(find.byIcon(Icons.route), drawsMap ? findsNothing : findsOneWidget,
            reason: 'the glyph fallback is what a mapless card shows instead');
      }
    });
  });

  group('the stats block', () {
    testWidgets('reads in kilometres and metres under a km preference',
        (tester) async {
      await _pump(tester, _route(), await _prefs());

      expect(find.text('10.00 km'), findsOneWidget);
      expect(find.text('128 m'), findsOneWidget);
    });

    testWidgets('reads in miles AND feet under a miles preference',
        (tester) async {
      // The defect: the climb ignored the preference entirely, so this card
      // went out reading "6.21 mi" beside "128 m".
      await _pump(tester, _route(), await _prefs(miles: true));

      expect(find.text('6.21 mi'), findsOneWidget);
      expect(find.text('420 ft'), findsOneWidget);
      expect(find.text('128 m'), findsNothing,
          reason: 'a mile-unit runner must not be handed a metric climb');
    });

    testWidgets('a flat route omits the climb rather than printing a zero',
        (tester) async {
      await _pump(tester, _route(elevationGainMetres: 0), await _prefs());

      expect(find.text('CLIMB'), findsNothing);
      expect(find.text('DISTANCE'), findsOneWidget);
    });

    testWidgets('carries the route name and its surface', (tester) async {
      await _pump(tester, _route(), await _prefs());

      expect(find.text('Richmond Park loop'), findsOneWidget);
      expect(find.text('TRAIL'), findsOneWidget);
    });

    testWidgets('a route with no surface on record claims none',
        (tester) async {
      await _pump(tester, _route(surface: null), await _prefs());

      expect(find.text('TRAIL'), findsNothing);
      expect(find.text('Richmond Park loop'), findsOneWidget);
    });
  });

  testWidgets('the drawn line is exactly the waypoints it was handed',
      (tester) async {
    // The sheet is opened with the CLIPPED waypoints for a non-owner viewer,
    // so the card must draw what it is given and never reach past it — the
    // PNG is the one artifact a privacy zone cannot be re-applied to.
    final route = _route(waypoints: 5);
    await _pump(tester, route, await _prefs());

    final layers = tester.widgetList<PolylineLayer>(find.byType(PolylineLayer));
    expect(layers, isNotEmpty, reason: 'the card draws no line at all');
    for (final layer in layers) {
      expect(layer.polylines.single.points.length, route.waypoints.length);
      expect(layer.polylines.single.points.first.latitude,
          closeTo(route.waypoints.first.lat, 1e-9));
      expect(layer.polylines.single.points.last.latitude,
          closeTo(route.waypoints.last.lat, 1e-9));
    }
  });
}
