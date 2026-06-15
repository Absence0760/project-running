import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
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

Widget _host(List<RouteMarkerRow> markers, {Preferences? prefs}) {
  final r = _route();
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: RoadbookScreen(
      route: r,
      waypoints: r.waypoints,
      api: null,
      preferences: prefs,
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

  testWidgets('fueling uses the carbs/hr preference, not the flat default',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs60 = Preferences();
    await prefs60.init(); // defaults to 60 g/hr
    final prefs90 = Preferences();
    await prefs90.init();
    await prefs90.setCarbsPerHourG(90);

    final markers = [
      _marker('aid_station', 'Aid 1', 1000, const {'services': ['water', 'food']}),
    ];
    List<String> carbsTexts() => tester
        .widgetList<Text>(find.textContaining('Carbs:'))
        .map((t) => t.data ?? '')
        .toList();

    await tester.pumpWidget(_host(markers, prefs: prefs60));
    await tester.pump();
    await tester.tap(find.text('Fuel'));
    await tester.pump();
    final at60 = carbsTexts();

    await tester.pumpWidget(_host(markers, prefs: prefs90));
    await tester.pump();
    await tester.tap(find.text('Fuel'));
    await tester.pump();
    final at90 = carbsTexts();

    // Same course + goal; only the rate differs, so every leg's carbs scale
    // up — proving the screen reads the preference, not the flat constant.
    expect(at60, isNotEmpty);
    expect(at90, isNot(equals(at60)));
  });
}
