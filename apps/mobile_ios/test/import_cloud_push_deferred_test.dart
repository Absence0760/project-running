import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/health_connect_importer.dart';
import '../lib/import_failures.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_run_store.dart';
import '../lib/screens/import_screen.dart';

/// Behavioural cover for the import screen's "on this device, not on the
/// server" disclosure, on both push paths that can produce it.
///
/// `saveRunsBatch` reports a partial failure by RETURNING the ids whose track
/// upload failed — it does not throw. Both push sites used to set the deferral
/// only from their catch, so a half-landed batch rendered as a clean import.
///
/// The screen's Health Connect platform calls are constructor seams, so the
/// import and the route backfill both run on the host with no Android device;
/// `ApiClient` is faked by subclassing, the same seam `sync_service_test.dart`
/// uses.
class _FakeApi extends ApiClient {
  String? fakeUserId = 'user-1';

  /// Ids to report as failed, per `saveRunsBatch` call. A call past the end of
  /// the list succeeds outright.
  List<Set<String>> failedByCall = const [];
  Object? throwOnBatch;
  final List<List<String>> batches = [];

  @override
  String? get userId => fakeUserId;

  @override
  Future<Set<String>> saveRunsBatch(
    List<Run> runs, {
    int uploadConcurrency = 8,
    int rowChunkSize = 100,
    void Function(int saved)? onProgress,
  }) async {
    final call = batches.length;
    batches.add(runs.map((r) => r.id).toList());
    if (throwOnBatch != null) throw throwOnBatch!;
    return call < failedByCall.length ? failedByCall[call] : const <String>{};
  }
}

late Directory _runsDir;

Future<LocalRunStore> _makeStore() async {
  _runsDir = Directory.systemTemp.createTempSync('import_deferred_test_');
  final store = LocalRunStore();
  await store.init(overrideDirectory: _runsDir);
  return store;
}

Run _hcRun(String sessionId, int minuteOffset) => Run(
      id: 'run-$sessionId',
      startedAt: DateTime.utc(2026, 3, 1, 7).add(Duration(hours: minuteOffset)),
      duration: const Duration(minutes: 30),
      distanceMetres: 5000 + minuteOffset * 100,
      source: RunSource.healthconnect,
      externalId: 'healthconnect:$sessionId',
    );

HealthConnectImport _import(List<Run> runs, {Set<String> withheld = const {}}) =>
    (
      runs: runs,
      withheldSessionIds: withheld,
      failures: newImportFailureLog(),
    );

const _emptyRoutes = (
  tracks: <String, List<Waypoint>>{},
  withheldSessionIds: <String>{},
  readFailure: null,
);

Future<void> _pump(
  WidgetTester tester,
  LocalRunStore store,
  _FakeApi api, {
  required HealthConnectImport workouts,
  HealthConnectRoutes routes = _emptyRoutes,
  bool routeGrant = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ImportScreen(
        apiClient: api,
        runStore: store,
        requestHealthPermissionFn: () async => true,
        fetchHealthWorkoutsFn: () async => workouts,
        requestHealthRoutePermissionFn: () async => routeGrant,
        fetchHealthRoutesFn: () async => routes,
      ),
    ),
  );
  await tester.pump();
}

/// Drives a tap through real disk I/O — `LocalRunStore.save` writes files the
/// fake clock cannot advance past.
Future<void> _tapAndDrain(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.runAsync(() async {
    await tester.tap(button);
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
}

Finder get _importButton =>
    find.widgetWithText(FilledButton, 'Import from Health Connect');

Finder get _allowRoutesButton =>
    find.widgetWithText(OutlinedButton, 'Allow map import');

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('import batch push', () {
    testWidgets('a partial push names how many runs did not reach the server',
        (tester) async {
      final store = await _makeStore();
      final api = _FakeApi()
        ..failedByCall = [
          {'run-b'}
        ];
      await _pump(
        tester,
        store,
        api,
        workouts: _import([_hcRun('a', 0), _hcRun('b', 1), _hcRun('c', 2)]),
      );

      await _tapAndDrain(tester, _importButton);

      expect(api.batches.single, hasLength(3));
      expect(find.text(l10n.importStatusCloudPushDeferred(1)), findsOneWidget);
      // The count is the point: without it a runner cannot tell 1-of-3 from
      // 3-of-3, and the whole-batch case renders a different sentence.
      expect(find.text(l10n.importStatusCloudPushDeferred(3)), findsNothing);
    });

    testWidgets('a fully landed push discloses nothing', (tester) async {
      final store = await _makeStore();
      final api = _FakeApi();
      await _pump(
        tester,
        store,
        api,
        workouts: _import([_hcRun('a', 0), _hcRun('b', 1)]),
      );

      await _tapAndDrain(tester, _importButton);

      expect(find.textContaining('saved on this device'), findsNothing);
    });

    testWidgets('a thrown push defers the whole batch', (tester) async {
      final store = await _makeStore();
      final api = _FakeApi()..throwOnBatch = Exception('offline');
      await _pump(
        tester,
        store,
        api,
        workouts: _import([_hcRun('a', 0), _hcRun('b', 1), _hcRun('c', 2)]),
      );

      await _tapAndDrain(tester, _importButton);

      expect(find.text(l10n.importStatusCloudPushDeferred(3)), findsOneWidget);
    });
  });

  group('Health Connect route backfill', () {
    const routes = (
      tracks: <String, List<Waypoint>>{
        's1': [
          Waypoint(lat: 51.5, lng: -0.1),
          Waypoint(lat: 51.51, lng: -0.11),
        ],
      },
      withheldSessionIds: <String>{},
      readFailure: null,
    );

    Future<void> importThenAllow(
      WidgetTester tester,
      LocalRunStore store,
      _FakeApi api, {
      bool routeGrant = true,
    }) async {
      await _pump(
        tester,
        store,
        api,
        workouts: _import([_hcRun('s1', 0)], withheld: {'s1'}),
        routes: routes,
        routeGrant: routeGrant,
      );
      await _tapAndDrain(tester, _importButton);
      await _tapAndDrain(tester, _allowRoutesButton);
    }

    testWidgets('fills the withheld map and reports it', (tester) async {
      final store = await _makeStore();
      final api = _FakeApi();
      await importThenAllow(tester, store, api);

      expect(find.text(l10n.importHealthRoutesAdded(1)), findsOneWidget);
      final stored = await store.runById('run-s1');
      expect(stored!.track, hasLength(2));
      expect(find.textContaining('saved on this device'), findsNothing);
      // Two pushes: the summary-only import, then the backfilled map.
      expect(api.batches, hasLength(2));
    });

    testWidgets('a partial backfill push says so in the import vocabulary',
        (tester) async {
      final store = await _makeStore();
      // Call 0 is the summary import and lands; call 1 is the backfill.
      final api = _FakeApi()
        ..failedByCall = [
          const <String>{},
          {'run-s1'},
        ];
      await importThenAllow(tester, store, api);

      expect(find.text(l10n.importHealthRoutesAdded(1)), findsOneWidget);
      expect(find.text(l10n.importStatusCloudPushDeferred(1)), findsOneWidget);
    });

    testWidgets('a refused route grant leaves the runs untouched',
        (tester) async {
      final store = await _makeStore();
      final api = _FakeApi();
      await importThenAllow(tester, store, api, routeGrant: false);

      expect(find.text(l10n.importHealthRoutesDenied), findsOneWidget);
      final stored = await store.runById('run-s1');
      expect(stored!.track, isEmpty);
      expect(find.textContaining('saved on this device'), findsNothing);
      expect(api.batches, hasLength(1));
    });
  });
}
