import 'dart:convert';

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

/// The leg-pace line of every schedule row, in course order.
List<String> _paceTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byKey(const Key('roadbook-leg-pace')),
      matching: find.byType(Text),
    ))
    .map((t) => t.data ?? '')
    .toList();

/// The same lines parsed back to seconds per unit, so an assertion can
/// compare two legs without pinning a formatted string. An unpriceable leg
/// reads as null.
List<double?> _paceSeconds(WidgetTester tester) => _paceTexts(tester).map((s) {
      final value = s.split(' ').where((p) => p.contains(':')).firstOrNull;
      if (value == null) return null;
      final parts = value.split(':').map(double.parse).toList();
      return parts[0] * 60 + parts[1];
    }).toList();

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

  testWidgets('every leg states the pace it has to be run at', (tester) async {
    // A crew chief reading cumulative arrivals alone cannot tell whether the
    // next leg asks for a jog or a march — the leg pace is the only place the
    // pacing model's output is visible as a pace.
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 1000, const {}),
    ]));
    await _settleStore(tester);

    // start / Aid 1 / finish.
    expect(_paceTexts(tester).length, 3);
    expect(_paceTexts(tester).skip(1), everyElement(contains('/km')));
  });

  testWidgets('the start row is priced as unknown, not as a confident number',
      (tester) async {
    // There is no leg arriving at the start, so there is no pace to state.
    // Rendering the goal pace there would read as a real instruction.
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 1000, const {}),
    ]));
    await _settleStore(tester);

    expect(_paceTexts(tester).first, 'Leg pace —');
  });

  testWidgets('a zero-length leg is priced as unknown', (tester) async {
    // Two markers on the same spot leave the second leg no distance to
    // divide by; web renders the same em-dash rather than an infinite pace.
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 1000, const {}),
      _marker('aid_station', 'Aid 2', 1000, const {}),
    ]));
    await _settleStore(tester);

    expect(_paceTexts(tester)[2], 'Leg pace —');
  });

  testWidgets('even pacing prices the climb and the flat the same',
      (tester) async {
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 1000, const {}),
    ]));
    await _settleStore(tester);
    await tester.tap(find.text('Even'));
    await _settleStore(tester);

    final paces = _paceSeconds(tester);
    expect((paces[1]! - paces[2]!).abs(), lessThanOrEqualTo(2));
  });

  testWidgets('the effort model prices the climb slower than the flat',
      (tester) async {
    // The seeded course climbs 270 m over its back half, so the effort model
    // must give that leg materially more time per kilometre than the flat
    // one. Mirrors web's roadbook.spec.ts leg-pace assertions — and it is the
    // whole reason the column is worth a row on a phone.
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 1000, const {}),
    ]));
    await _settleStore(tester);

    final paces = _paceSeconds(tester);
    expect(paces[2]!, greaterThan(paces[1]! * 2));
  });

  testWidgets('the leg pace is stated in the runner\'s own unit',
      (tester) async {
    SharedPreferences.setMockInitialValues({'use_miles': true});
    final prefs = Preferences();
    await prefs.init();
    registerActivePreferences(prefs);
    addTearDown(resetActivePreferencesForTest);

    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 1000, const {}),
    ]));
    await _settleStore(tester);

    expect(_paceTexts(tester).skip(1), everyElement(contains('/mi')));
    expect(_paceTexts(tester), everyElement(isNot(contains('/km'))));
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
