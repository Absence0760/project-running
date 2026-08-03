import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';

/// Streak-card truth pins (decisions § 475): the all-time figures come
/// from the `run_streaks_for_user` aggregate, a missing answer suppresses
/// the all-time claim instead of presenting the store's resident sliver
/// as one, an unsynced local run is never walked back by the server row,
/// and signed-out never calls the RPC.
class _StreakApi extends ApiClient {
  _StreakApi({this.uid = 'u1', this.result, this.hang = false});

  final String? uid;
  final ({int current, int best})? result;
  final bool hang;
  final tzCalls = <String>[];

  @override
  String? get userId => uid;

  @override
  Future<({int current, int best})?> fetchRunStreaks({
    required String tz,
    String? source,
  }) async {
    tzCalls.add(tz);
    if (hang) return Completer<({int current, int best})?>().future;
    return result;
  }
}

Run _run(String id, DateTime startedAt) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 25),
      distanceMetres: 5000,
      source: RunSource.app,
    );

DateTime _todayRunStart() => DateTime.now();

DateTime _yesterdayNoon() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - 1, 12);
}

Future<Directory> _seedAndPump(
  WidgetTester tester, {
  required ApiClient api,
  required List<Run> runs,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  final dir = Directory.systemTemp.createTempSync('dash_streak_');
  final seedStore = LocalRunStore();
  await seedStore.init(overrideDirectory: dir);
  for (final r in runs) {
    await seedStore.save(r);
  }
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: dir);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DashboardScreen(
        apiClient: api,
        runStore: runStore,
        routeStore: LocalRouteStore(),
        gymStore: LocalGymStore(),
        foodStore: LocalFoodStore(),
        preferences: prefs,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  // The streak load chains two real awaits (platform-zone probe → RPC);
  // under runAsync those complete on the real event loop, so yield to it
  // before pumping the resulting setState into a frame.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await tester.pump();
  return dir;
}

Future<void> _scrollToStreakRow(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('dashboardStreakRow')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

Finder _inStreakRow(String text) => find.descendant(
      of: find.byKey(const Key('dashboardStreakRow')),
      matching: find.text(text),
    );

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('the server aggregate drives the best-streak sub-label',
      (tester) async {
    await tester.runAsync(() async {
      final api = _StreakApi(result: (current: 1, best: 10));
      final dir = await _seedAndPump(
        tester,
        api: api,
        runs: [_run('r1', _todayRunStart())],
      );
      try {
        await _scrollToStreakRow(tester);
        // Windowed compute sees (1, 1); pre-§ 475 the card claimed
        // "all-time best" from it. The RPC row (1, 10) must win.
        expect(_inStreakRow('best 10 days'), findsOneWidget);
        expect(_inStreakRow('all-time best'), findsNothing);
        // The device zone rides along; with no platform channel in the
        // test harness the helper degrades to the explicit UTC fallback.
        expect(api.tzCalls, ['UTC']);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  testWidgets('a failed fetch suppresses the all-time claim', (tester) async {
    await tester.runAsync(() async {
      final api = _StreakApi(result: null);
      final dir = await _seedAndPump(
        tester,
        api: api,
        runs: [
          _run('r1', _todayRunStart()),
          _run('r2', _yesterdayNoon()),
        ],
      );
      try {
        await _scrollToStreakRow(tester);
        // The local current streak still shows — it is provable from the
        // resident runs — but no best/all-time sub-label may render from
        // a windowed figure indistinguishable from the truth.
        expect(_inStreakRow('2'), findsOneWidget);
        expect(_inStreakRow('all-time best'), findsNothing);
        expect(_inStreakRow('best 2 days'), findsNothing);
        expect(_inStreakRow('History'), findsNothing);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  testWidgets('an in-flight fetch shows no all-time claim', (tester) async {
    await tester.runAsync(() async {
      final api = _StreakApi(hang: true);
      final dir = await _seedAndPump(
        tester,
        api: api,
        runs: [
          _run('r1', _todayRunStart()),
          _run('r2', _yesterdayNoon()),
        ],
      );
      try {
        await _scrollToStreakRow(tester);
        expect(_inStreakRow('2'), findsOneWidget);
        expect(_inStreakRow('all-time best'), findsNothing);
        expect(_inStreakRow('best 2 days'), findsNothing);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  testWidgets('an unsynced local run day is never walked back',
      (tester) async {
    await tester.runAsync(() async {
      // The server row lags the just-recorded local run (current 1), but
      // the local store proves two consecutive days — the fold keeps the
      // headline at 2 while the server's deep-history best still lands.
      final api = _StreakApi(result: (current: 1, best: 10));
      final dir = await _seedAndPump(
        tester,
        api: api,
        runs: [
          _run('r1', _todayRunStart()),
          _run('r2', _yesterdayNoon()),
        ],
      );
      try {
        await _scrollToStreakRow(tester);
        expect(_inStreakRow('2'), findsOneWidget);
        expect(_inStreakRow('best 10 days'), findsOneWidget);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  testWidgets('signed-out never calls the streak RPC', (tester) async {
    await tester.runAsync(() async {
      final api = _StreakApi(uid: null, result: (current: 9, best: 9));
      final dir = await _seedAndPump(
        tester,
        api: api,
        runs: [_run('r1', _todayRunStart())],
      );
      try {
        await _scrollToStreakRow(tester);
        expect(api.tzCalls, isEmpty);
        expect(_inStreakRow('all-time best'), findsNothing);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
