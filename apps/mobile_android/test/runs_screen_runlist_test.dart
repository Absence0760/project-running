// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/runs_screen.dart';
import '../lib/widgets/run_list_tile.dart';
import '../lib/widgets/surface_peer_strip.dart';

/// Signed-in fake with no remote runs — keeps `_fetchRemote` off the network
/// so the run-list mode renders purely from the seeded local store.
class _FakeApi extends ApiClient {
  @override
  String? get userId => 'u1';

  @override
  Future<List<Run>> getRuns({
    int limit = 50,
    DateTime? before,
    DateTime? updatedSince,
  }) async =>
      const [];
}


/// Holds `deleteRun` open so the in-flight window of the bulk delete can be
/// inspected. Each call parks on [gate]; completing it releases every one.
class _SlowDeleteApi extends _FakeApi {
  final Completer<void> gate = Completer<void>();
  int deleteCalls = 0;

  @override
  Future<void> deleteRun(Run run) async {
    deleteCalls++;
    await gate.future;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting());

  final tmpDirs = <Directory>[];
  tearDown(() {
    for (final d in tmpDirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    tmpDirs.clear();
  });

  Directory tmp(String prefix) {
    final d = Directory.systemTemp.createTempSync(prefix);
    tmpDirs.add(d);
    return d;
  }

  /// Mount the run-list surface (no gymStore) the way the Fitness hub's Runs
  /// sub-tab does, with the labelled peer strip wired so the screen is as
  /// crowded as it gets in production.
  Future<void> pumpRunList(
    WidgetTester tester, {
    List<Run> runs = const [],
    Map<String, Object?>? filtersBlob,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (filtersBlob != null) 'runs_filters_v1': jsonEncode(filtersBlob),
    });
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('runs_rl_'));
    if (runs.isNotEmpty) {
      await tester.runAsync(() async => runStore.saveManyFromRemote(runs));
    }

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunsScreen(
        apiClient: _FakeApi(),
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
        surfacePeers: [
          const SurfacePeer(label: 'Runs'),
          SurfacePeer(label: 'Routes', onTap: () {}),
          SurfacePeer(label: 'Plans', onTap: () {}),
          SurfacePeer(label: 'Races', onTap: () {}),
        ],
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'a long custom date-range title does not overflow the crowded AppBar',
      (tester) async {
    // A realistic phone width where the AppBar actions (range, sort, refresh)
    // leave the title only a narrow slot —
    // enough room for the ellipsised label + count, but not for the full
    // two-date span, so the ellipsis is what keeps it from overflowing.
    await tester.binding.setSurfaceSize(const Size(420, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // A two-year custom range renders the longest possible title ("Dec 15,
    // 2023 – Jan 20, 2024"); seed it through the persisted-filters blob so the
    // screen restores it on mount without driving the picker UI. No runs are
    // seeded so this isolates the AppBar title (the empty-state body carries no
    // competing rows). This layout previously tripped a RenderFlex overflow.
    await pumpRunList(
      tester,
      filtersBlob: {
        'range': 'custom',
        'customFromMs': DateTime(2023, 12, 15).millisecondsSinceEpoch,
        'customToMs': DateTime(2024, 1, 20).millisecondsSinceEpoch,
      },
    );

    // The range label ellipsises rather than overflowing the title slot.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a standalone run-list mount keeps the cloud slot by default',
      (tester) async {
    // showSyncActions defaults to true: a signed-in, fully-synced store shows
    // the refresh state of the cloud slot. Only the Fitness hub's Runs
    // sub-tab opts out (pinned in fitness_hub_screen_test.dart).
    await pumpRunList(tester);
    expect(find.byIcon(Icons.cloud_download), findsOneWidget);
  });

  testWidgets('bulk delete disables its own controls while in flight',
      (tester) async {
    // The trash action stayed live through the whole per-run loop with
    // `_selected` still populated, so a second tap re-opened the confirm on
    // the SAME set and a second confirm launched a concurrent delete pass.
    final api = _SlowDeleteApi();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('runs_del_'));
    Run mk(String id, DateTime at) => Run(
          id: id,
          startedAt: at,
          duration: const Duration(seconds: 1500),
          distanceMetres: 5000,
          source: RunSource.app,
        );
    // Recent dates: the run list's default range filter windows out older
    // runs, and a filtered-out row cannot be long-pressed into selection.
    final now = DateTime.now().toUtc();
    final runs = [
      mk('r1', now.subtract(const Duration(days: 1))),
      mk('r2', now.subtract(const Duration(days: 2))),
    ];
    await tester.runAsync(() async => runStore.saveManyFromRemote(runs));
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunsScreen(
        apiClient: api,
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
      ),
    ));
    await tester.pumpAndSettle();

    // Long-press enters selection mode with that row selected.
    await tester.longPress(find.byType(RunListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget,
        reason: 'long-press enters selection mode with that row selected');
    final deleteBtn = find.widgetWithIcon(IconButton, Icons.delete_outline);
    expect(deleteBtn, findsOneWidget);
    expect(tester.widget<IconButton>(deleteBtn).onPressed, isNotNull);

    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();
    // Confirm — scoped to the dialog, the row action shares its label.
    await tester.runAsync(() async {
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Delete')));
    });
    await tester.pump();

    // In flight: both the delete AND the close action are inert, so neither a
    // second delete nor a mid-flight cancel can race the loop.
    expect(api.deleteCalls, 1);
    expect(tester.widget<IconButton>(deleteBtn).onPressed, isNull,
        reason: 'a second tap must not be able to reach _deleteSelected');
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.close))
            .onPressed,
        isNull);

    // Releasing the delete finishes the pass and leaves selection mode. The
    // tail does real store file I/O, so alternate real-clock delays (which let
    // that I/O complete) with pumps (which flush the fake-zone microtasks that
    // resume the awaiting UI code) until it lands — a fixed delay never drains
    // it. Same shape as gym_screen_test's `_pumpUntil`.
    await tester.runAsync(() async => api.gate.complete());
    for (var i = 0; i < 40 && tester.any(find.text('1 selected')); i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(api.deleteCalls, 1, reason: 'exactly one pass over the selection');
    // Selection mode ended, so its AppBar (and with it the guarded controls)
    // is gone. Asserted on the selection title rather than the trash glyph,
    // which also appears outside selection mode.
    expect(find.text('1 selected'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });
}
