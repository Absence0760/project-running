// Issue #666 C8: one run row, whichever surface draws it. The two constructors
// read different sources — a local `Run` with an inline track, or a `RunRow`
// from someone else's profile — and must produce the same row from the same run.
//
// Per §500 these assert relations and shared structure, never an absolute pixel
// figure: flutter_test's font is fixed-advance, so a width assertion says
// nothing about the real device.

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/widgets/run_list_tile.dart';

final _startedAt = DateTime.utc(2026, 4, 15, 7, 30);

Run _run({Map<String, dynamic>? metadata, List<Waypoint>? track}) => Run(
      id: 'run-1',
      startedAt: _startedAt,
      duration: const Duration(minutes: 25),
      distanceMetres: 5000,
      source: RunSource.app,
      metadata: metadata,
      track: track ?? const [],
    );

RunRow _row({dynamic metadata, String activityType = 'run', double? elevationGainM}) =>
    RunRow(
      id: 'run-1',
      userId: 'owner-1',
      startedAt: _startedAt,
      durationS: 1500,
      distanceM: 5000,
      source: 'app',
      isDnf: false,
      metadata: metadata,
      activityType: activityType,
      elevationGainM: elevationGainM,
    );

Future<void> _pump(WidgetTester tester, Widget tile) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: ListView(children: [tile])),
  ));
  await tester.pump();
}

void main() {
  testWidgets('both constructors draw the same run the same way',
      (tester) async {
    await _pump(
      tester,
      RunListTile.owned(
        run: _run(metadata: const {'activity_type': 'run'}),
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
      ),
    );
    final owned = [
      for (final t in tester.widgetList<Text>(find.byType(Text))) t.data,
    ];

    await _pump(
      tester,
      RunListTile.public(
        row: _row(activityType: 'run'),
        ownerUserId: 'owner-1',
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
      ),
    );
    final public = [
      for (final t in tester.widgetList<Text>(find.byType(Text))) t.data,
    ];

    expect(public, owned,
        reason: 'the same run must read identically on the owner\'s list and '
            'on a profile — the two had disagreed on the distance weight, the '
            'subtitle grammar and whether the pace was in the trailing slot');
  });

  testWidgets('a run with no metadata builds', (tester) async {
    // The bug the extraction shipped with: reading the absent source as a
    // fallback for a null value dereferenced the other one.
    await _pump(
      tester,
      RunListTile.owned(
        run: _run(),
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('a row with no metadata bag builds', (tester) async {
    await _pump(
      tester,
      RunListTile.public(
        row: _row(),
        ownerUserId: 'owner-1',
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('the row does not widen on a flat run', (tester) async {
    await _pump(
      tester,
      RunListTile.owned(
        run: _run(metadata: const {'activity_type': 'run'}),
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
      ),
    );
    expect(find.textContaining('↑'), findsNothing);

    await _pump(
      tester,
      RunListTile.owned(
        run: _run(metadata: const {'activity_type': 'run', 'elevation_m': 420}),
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
      ),
    );
    expect(find.textContaining('↑'), findsOneWidget);
  });

  testWidgets('a promoted elevation column reads the same as the bag',
      (tester) async {
    await _pump(
      tester,
      RunListTile.public(
        row: _row(activityType: 'run', elevationGainM: 420),
        ownerUserId: 'owner-1',
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
      ),
    );
    final fromColumn = tester
        .widget<Text>(find.textContaining('↑'))
        .data;

    await _pump(
      tester,
      RunListTile.public(
        row: _row(activityType: 'run', metadata: const {'elevation_m': 420}),
        ownerUserId: 'owner-1',
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
      ),
    );
    expect(tester.widget<Text>(find.textContaining('↑')).data, fromColumn);
  });

  testWidgets('the leading slot is one width whichever leading it draws',
      (tester) async {
    final widths = <double>[];
    for (final tile in [
      RunListTile.owned(
        run: _run(metadata: const {'activity_type': 'run'}),
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
      ),
      RunListTile.owned(
        run: _run(metadata: const {'activity_type': 'run'}),
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
        selecting: true,
        selected: true,
      ),
      RunListTile.public(
        row: _row(activityType: 'run'),
        ownerUserId: 'owner-1',
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
      ),
    ]) {
      await _pump(tester, tile);
      widths.add(tester
          .getRect(find.descendant(
              of: find.byType(ListTile), matching: find.byType(SizedBox).first))
          .width);
    }
    expect(widths.toSet(), hasLength(1),
        reason: 'the title column must start at the same x on every surface '
            'and in every leading state: $widths');
    expect(widths.first, kRunTileLeadingWidth);
  });

  testWidgets('an unsynced run is marked, a synced one is not', (tester) async {
    await _pump(
      tester,
      RunListTile.owned(
        run: _run(metadata: const {'activity_type': 'run'}),
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
        isUnsynced: true,
      ),
    );
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);

    await _pump(
      tester,
      RunListTile.public(
        row: _row(activityType: 'run'),
        ownerUserId: 'owner-1',
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
      ),
    );
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing,
        reason: 'sync state is the owner\'s own concern; a profile row has no '
            'field for it, which is why the constructors are separate');
  });

  testWidgets('a parked run reads as stuck, not as queued', (tester) async {
    // "Waiting" and "stuck" are different promises and only one of them is
    // true. Before decisions § 1070 both rendered as the queued-to-sync cloud,
    // so a run that would never sync advertised that it was about to.
    await _pump(
      tester,
      RunListTile.owned(
        run: _run(),
        unit: DistanceUnit.km,
        api: null,
        onTap: () {},
        isUnsynced: true,
        isBlocked: true,
      ),
    );

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing,
        reason: 'the blocked mark outranks the queued one; showing both, or '
            'showing the queued one, promises a sync that cannot happen');

    final semantics = tester.widget<Semantics>(
      find.ancestor(
        of: find.byType(Card),
        matching: find.byType(Semantics),
      ).first,
    );
    final en = lookupAppLocalizations(const Locale('en'));
    expect(semantics.properties.label,
        contains(en.historyBlockedRowSemantics));
    expect(semantics.properties.label,
        isNot(contains(en.historyUnsyncedRowSemantics)));
  });
}
