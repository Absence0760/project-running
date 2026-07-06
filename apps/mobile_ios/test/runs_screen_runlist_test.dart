// ignore_for_file: avoid_relative_lib_imports
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
  /// sub-tab does, with the Routes + Plans AppBar actions wired so the bar is
  /// as crowded as it gets in production.
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
        onOpenRoutes: () {},
        onOpenPlans: () {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'a long custom date-range title does not overflow the crowded AppBar',
      (tester) async {
    // A realistic phone width where the six AppBar actions (Routes, Plans,
    // heatmap, range, sort, refresh) leave the title only a narrow slot —
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
}
