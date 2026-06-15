import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/roadbook_screen.dart';

Route _route() {
  final wps = <Waypoint>[];
  for (var i = 0; i <= 18; i++) {
    wps.add(Waypoint(
      lat: 51.5 + i * 0.001,
      lng: -0.12,
      elevationMetres: i > 9 ? (i - 9) * 30.0 : 0.0,
    ));
  }
  return Route(
    id: 'route-1',
    name: 'Test Course',
    waypoints: wps,
    distanceMetres: 2000,
  );
}

RouteMarkerRow _marker(String kind, String label, double pos,
    Map<String, dynamic> meta) {
  return RouteMarkerRow(
    id: '$kind-$label',
    routeId: 'route-1',
    userId: 'owner',
    kind: kind,
    label: label,
    lat: 51.5,
    lng: -0.12,
    positionM: pos,
    meta: meta,
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
    updatedAt: DateTime.parse('2026-01-01T00:00:00Z'),
  );
}

Widget _host(List<RouteMarkerRow> markers) {
  final r = _route();
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: RoadbookScreen(
      route: r,
      waypoints: r.waypoints,
      api: null,
      initialMarkers: markers,
    ),
  );
}

void main() {
  testWidgets('fueling toggle reveals per-leg carbs and a carry hint',
      (tester) async {
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 1000, const {'services': ['water', 'food']}),
    ]));
    await tester.pump();

    // Fuel figures hidden until the toggle is on.
    expect(find.textContaining('Carbs:'), findsNothing);

    await tester.tap(find.text('Fuel'));
    await tester.pump();

    // Heat toggle only appears once fueling is on.
    expect(find.text('Heat'), findsOneWidget);

    // Per-leg carbs render.
    expect(find.textContaining('Carbs:'), findsWidgets);
    // The start leg carries fuel out to the first refill (Aid 1).
    expect(find.textContaining('carry'), findsWidgets);
  });
}
