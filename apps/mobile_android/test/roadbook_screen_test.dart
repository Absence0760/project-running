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
  testWidgets('renders the schedule with checkpoints, services and a cutoff',
      (tester) async {
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 445, {'services': ['water', 'food']}),
      _marker('cutoff', 'Gate', 1000, {'cutoff_elapsed_s': 1800}),
    ]));
    await tester.pump();

    expect(find.text('Roadbook'), findsWidgets);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);
    expect(find.text('Aid 1'), findsOneWidget);
    expect(find.text('Gate'), findsOneWidget);
    // Aid services render their localised labels.
    expect(find.textContaining('Water'), findsOneWidget);
    // The cutoff row shows the localised cutoff label.
    expect(find.textContaining('Cut-off'), findsWidgets);
  });

  testWidgets('empty markers show the onboarding hint', (tester) async {
    await tester.pumpWidget(_host(const []));
    await tester.pump();
    expect(find.textContaining('Add course markers'), findsOneWidget);
  });

  testWidgets('switching to even pacing keeps the schedule rendered',
      (tester) async {
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 445, const {}),
    ]));
    await tester.pump();
    await tester.tap(find.text('Even'));
    await tester.pump();
    expect(find.text('Aid 1'), findsOneWidget);
  });
}
