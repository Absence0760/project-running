import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Let real store I/O land — the screen adopts this route's stored race plan
/// asynchronously, and a fake-async pump never delivers it.
Future<void> _settleStore(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  testWidgets('a stored plan opens the sheet on the runner\'s own numbers',
      (tester) async {
    // The same record the custom-watch push builds its schedule from, so a
    // clock cut-off resolves identically on both surfaces.
    SharedPreferences.setMockInitialValues({
      roadbookPlanPrefsKey('route-1'):
          '{"goal_s":7200,"start_min":480,"model":"even"}',
    });
    await tester.pumpWidget(_host([
      _marker('cutoff', 'Gate', 1000, {'cutoff_clock': '09:00'}),
    ]));
    await _settleStore(tester);

    expect(find.text('2:00:00'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.textContaining('Cut-off +'), findsOneWidget);
  });

  testWidgets('without a start clock the same barrier resolves to nothing',
      (tester) async {
    // The reason the start clock is collected at all: a wall-clock barrier has
    // no elapsed limit to compare against until the gun time is known, so it
    // silently stops being a cut-off on every surface that reads the schedule.
    await tester.pumpWidget(_host([
      _marker('cutoff', 'Gate', 1000, {'cutoff_clock': '09:00'}),
    ]));
    await _settleStore(tester);

    expect(find.text('Gate'), findsOneWidget);
    expect(find.textContaining('Cut-off'), findsNothing);
  });

  testWidgets('a checkpoint target renders its time, margin and verdict',
      (tester) async {
    // The 2 km course at the seeded 6:30/km goal projects the halfway
    // checkpoint around 6:30, so a 20 min target is comfortably ahead and a
    // 60 s one comfortably behind. Both verdicts must reach the row — the
    // engine has computed them since the target twin landed, and the screen
    // rendered only the cutoff column.
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 1000, {'target_elapsed_s': 1200}),
    ]));
    await _settleStore(tester);

    expect(find.byKey(const Key('roadbook-target')), findsOneWidget);
    expect(find.textContaining('Target 20:00'), findsOneWidget);
    expect(find.textContaining('ahead'), findsOneWidget);
  });

  testWidgets('a target the projection misses reads behind, not on plan',
      (tester) async {
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 1000, {'target_elapsed_s': 60}),
    ]));
    await _settleStore(tester);

    expect(find.textContaining('behind'), findsOneWidget);
    expect(find.textContaining('ahead'), findsNothing);
  });

  testWidgets('a checkpoint with no target time grows no target chip',
      (tester) async {
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 1000, const {}),
    ]));
    await _settleStore(tester);

    expect(find.byKey(const Key('roadbook-target')), findsNothing);
  });

  testWidgets('editing the goal is persisted for the watch push',
      (tester) async {
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 445, const {}),
    ]));
    await _settleStore(tester);

    await tester.enterText(find.byType(TextField), '1:30:00');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settleStore(tester);

    final stored = await tester.runAsync(() async =>
        (await SharedPreferences.getInstance())
            .getString(roadbookPlanPrefsKey('route-1')));
    expect(jsonDecode(stored!), {'goal_s': 5400, 'model': 'effort'});
  });
}
