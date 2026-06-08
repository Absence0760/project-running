// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/runs_screen.dart';

/// Fake client: serves a canned activities feed, no runs, signed in. Every
/// network method RunsScreen touches on mount is overridden so nothing hits
/// Supabase.
class _FakeApi extends ApiClient {
  final List<ActivityRow> activities;
  _FakeApi(this.activities);

  @override
  String? get userId => 'u1';

  @override
  Future<List<ActivityRow>> fetchActivities({int limit = 100}) async =>
      activities;

  @override
  Future<List<Run>> getRuns({
    int limit = 50,
    DateTime? before,
    DateTime? updatedSince,
  }) async =>
      const [];
}

/// Fake whose activities feed resolves only when [feed] completes, so a test
/// can observe the History tab's pre-resolve paint (the loading gate).
class _DelayedApi extends ApiClient {
  final Future<List<ActivityRow>> feed;
  _DelayedApi(this.feed);

  @override
  String? get userId => 'u1';

  @override
  Future<List<ActivityRow>> fetchActivities({int limit = 100}) => feed;

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

  Directory? dir;
  tearDown(() {
    if (dir != null && dir!.existsSync()) dir!.deleteSync(recursive: true);
    dir = null;
  });

  Future<void> pump(WidgetTester tester, List<ActivityRow> activities) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    dir = Directory.systemTemp.createTempSync('runs_timeline_test_');
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: dir);
    final gymStore = LocalGymStore();
    await gymStore.init(
        overrideDirectory: Directory.systemTemp.createTempSync('gym_tl_'));

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunsScreen(
        apiClient: _FakeApi(activities),
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
        gymStore: gymStore,
      ),
    ));
    await tester.pumpAndSettle();
  }

  ActivityRow row(String id, String kind, Map<String, dynamic> summary) =>
      ActivityRow(id: id, kind: kind, startedAt: DateTime.now(), summary: summary);

  testWidgets('chips appear once a second modality has data + gym store wired',
      (tester) async {
    await pump(tester, [
      row('l1', 'lift', {'title': 'Push day', 'set_count': 5, 'volume_kg': 12000}),
      row('m1', 'meal', {'item_name': 'Oats', 'calories': 300}),
    ]);
    // All / Runs / Lifts / Meals chips render; the lift row shows in All view.
    expect(find.text('Lifts'), findsOneWidget);
    expect(find.text('Meals'), findsOneWidget);
    expect(find.text('Push day'), findsOneWidget);
  });

  testWidgets('tapping Runs leaves the timeline; tapping Lifts filters to lifts',
      (tester) async {
    await pump(tester, [
      row('l1', 'lift', {'title': 'Leg day', 'set_count': 4, 'volume_kg': 9000}),
      row('m1', 'meal', {'item_name': 'Rice bowl', 'calories': 500}),
    ]);
    // Default All view shows both a lift and a meal.
    expect(find.text('Leg day'), findsOneWidget);
    expect(find.text('Rice bowl'), findsOneWidget);

    // Tap Runs → the run list takes over, the timeline rows disappear.
    await tester.tap(find.text('Runs'));
    await tester.pumpAndSettle();
    expect(find.text('Leg day'), findsNothing);
    expect(find.text('Rice bowl'), findsNothing);

    // Tap Lifts → only the lift shows, the meal is filtered out.
    await tester.tap(find.text('Lifts'));
    await tester.pumpAndSettle();
    expect(find.text('Leg day'), findsOneWidget);
    expect(find.text('Rice bowl'), findsNothing);
  });

  testWidgets('no chips when gym store is absent (run-only history)',
      (tester) async {
    // gymStore omitted → even with a lift in the feed, the screen stays the
    // run-only history (graceful degradation for non-multi-modal mounts).
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    dir = Directory.systemTemp.createTempSync('runs_timeline_nochips_');
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: dir);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunsScreen(
        apiClient: _FakeApi([
          row('l1', 'lift', {'title': 'X', 'set_count': 1, 'volume_kg': 100}),
        ]),
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Lifts'), findsNothing);
  });

  testWidgets(
      'cached multi-modal account holds a loading gate until the feed resolves',
      (tester) async {
    // Regression guard for the run-list → timeline flip: a known multi-modal
    // account must NOT paint the run list (or its empty state) and then flip
    // to the timeline once the feed lands. With the modality cached, the body
    // holds a spinner until the feed resolves, then paints the timeline once.
    SharedPreferences.setMockInitialValues({'history_multi_modal_v1': true});
    final prefs = Preferences();
    await prefs.init();
    dir = Directory.systemTemp.createTempSync('runs_timeline_gate_');
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: dir);
    final gymStore = LocalGymStore();
    await gymStore.init(
        overrideDirectory: Directory.systemTemp.createTempSync('gym_gate_'));
    final completer = Completer<List<ActivityRow>>();

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunsScreen(
        apiClient: _DelayedApi(completer.future),
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
        gymStore: gymStore,
      ),
    ));
    // Feed still pending: the body is the loading gate, not run-list content
    // (the empty-runs state) or timeline rows.
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('No runs yet'), findsNothing);
    expect(find.text('Push day'), findsNothing);

    // Resolve the feed → the unified timeline paints with no run-list flash.
    completer.complete([
      row('l1', 'lift',
          {'title': 'Push day', 'set_count': 5, 'volume_kg': 12000}),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Push day'), findsOneWidget);
  });

  testWidgets('a non-cached account is not gated — run UI shows before the feed',
      (tester) async {
    // Pure runner (no cached modality): the run list / empty state renders
    // immediately even while the activities feed is still in flight — the gate
    // is only for accounts already known to be multi-modal.
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    dir = Directory.systemTemp.createTempSync('runs_timeline_nogate_');
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: dir);
    final gymStore = LocalGymStore();
    await gymStore.init(
        overrideDirectory: Directory.systemTemp.createTempSync('gym_nogate_'));
    final completer = Completer<List<ActivityRow>>();

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunsScreen(
        apiClient: _DelayedApi(completer.future),
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
        gymStore: gymStore,
      ),
    ));
    await tester.pump();
    // No gate — the run-only empty state is shown despite the pending feed.
    expect(find.text('No runs yet'), findsOneWidget);

    completer.complete(const []);
    await tester.pumpAndSettle();
  });
}
