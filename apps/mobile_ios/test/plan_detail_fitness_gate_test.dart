import 'dart:io';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_run_store.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';

/// P2 adaptive-replan fitness gate wiring on plan_detail_screen.
///
/// The gate is OFF unless `ADAPTIVE_FITNESS_GATE` is set in dotenv. When ON and
/// the runner is carrying fatigue (TSB < 0), an under-fitness add-volume trend
/// is HELD — `_proposeAdaptiveReplan` surfaces the held toast and proposes no
/// change. When OFF (default), no fitness is consulted and the P1 behaviour is
/// unchanged (an under-trend proposes a make-up). The engine's `fitnessGated`
/// branch itself is covered by `plan_adaptive_replan_test.dart`; this pins the
/// screen wiring (dotenv flag + LocalRunStore-threaded full-Run fitness input).

const _uid = 'owner-uuid';

DateTime _mondayThisWeek() {
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

class _FakeTraining extends TrainingService {
  final TrainingPlanRow plan;
  final List<PlanWeekRow> weeks;
  final List<PlanWorkoutRow> workouts;
  _FakeTraining(this.plan, this.weeks, this.workouts);

  @override
  Future<
      ({
        TrainingPlanRow? plan,
        List<PlanWeekRow> weeks,
        List<PlanWorkoutRow> workouts
      })> fetchPlan(String id) async {
    return (plan: plan, weeks: weeks, workouts: workouts);
  }
}

class _FakeSocial extends SocialService {
  final List<RecentRunRow> runs;
  _FakeSocial(this.runs);
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async => runs;
}

TrainingPlanRow _plan(DateTime start) => TrainingPlanRow(
      id: 'plan-1',
      userId: _uid,
      name: 'Test Plan',
      goalEvent: 'distance_half',
      goalDistanceM: 21097.5,
      startDate: start,
      endDate: start.add(const Duration(days: 56)),
      daysPerWeek: 4,
      status: 'active',
      source: 'generated',
      isTemplate: false,
    );

PlanWeekRow _week(String id, int idx, double vol) => PlanWeekRow(
    id: id, planId: 'plan-1', weekIndex: idx, phase: 'build', targetVolumeM: vol);

PlanWorkoutRow _wo(String id, String weekId, DateTime date, String kind,
        double? dist) =>
    PlanWorkoutRow(
      id: id,
      weekId: weekId,
      scheduledDate: date,
      kind: kind,
      targetDistanceM: dist,
      manuallyCompleted: false,
    );

void main() {
  final tmpDirs = <Directory>[];
  tearDown(() {
    for (final d in tmpDirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    tmpDirs.clear();
    dotenv.clean();
  });

  Directory tmp(String prefix) {
    final d = Directory.systemTemp.createTempSync(prefix);
    tmpDirs.add(d);
    return d;
  }

  // Three completed under-run weeks (planned 40k, actual ~10k each) + a future
  // long run that an under-trend re-plan would bump. Anchored two weeks back so
  // weeks 0-2 are complete + in the past and week 3 holds the future long.
  ({
    _FakeTraining training,
    DateTime start,
  }) underTrendPlan() {
    final start = _mondayThisWeek().subtract(const Duration(days: 21));
    final weeks = [
      _week('w0', 0, 40000),
      _week('w1', 1, 40000),
      _week('w2', 2, 40000),
      _week('w3', 3, 42000),
    ];
    final workouts = [
      _wo('missed', 'w0', start.add(const Duration(days: 1)), 'long', 28000),
      // Clearly in the future (next week) regardless of which weekday the test
      // runs, so it qualifies as a make-up target for the missed long.
      _wo('next', 'w3', _mondayThisWeek().add(const Duration(days: 9)), 'long',
          22000),
    ];
    return (training: _FakeTraining(_plan(start), weeks, workouts), start: start);
  }

  /// A LocalRunStore seeded with a recent high-volume block so the latest
  /// training-load point has TSB < 0 (ATL spikes above CTL with no prior
  /// history) — i.e. a fatigued runner.
  Future<LocalRunStore> fatiguedStore(WidgetTester tester) async {
    final store = LocalRunStore();
    await store.init(overrideDirectory: tmp('fitness_gate_runs_'));
    final now = DateTime.now();
    final runs = [
      for (var i = 0; i < 6; i++)
        Run(
          id: 'recent-$i',
          startedAt: now.subtract(Duration(days: i)),
          duration: const Duration(minutes: 75),
          distanceMetres: 15000,
          track: const [],
          source: RunSource.app,
        ),
    ];
    await tester.runAsync(() => store.saveManyFromRemote(runs));
    return store;
  }

  Future<void> pump(
    WidgetTester tester, {
    required _FakeTraining training,
    required _FakeSocial social,
    LocalRunStore? runStore,
  }) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanDetailScreen(
        training: training,
        planId: 'plan-1',
        social: social,
        viewerIdOverride: _uid,
        runStore: runStore,
      ),
    ));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    await tester.pump();
  }

  testWidgets('gate ON + fatigued runner holds the under-trend re-plan',
      (tester) async {
    dotenv.loadFromString(envString: 'ADAPTIVE_FITNESS_GATE=true');
    final p = underTrendPlan();
    final store = await fatiguedStore(tester);
    await pump(
      tester,
      training: p.training,
      social: _FakeSocial(const []),
      runStore: store,
    );

    await tester.tap(find.text('Adaptive re-plan'));
    await tester.pump();

    // Held toast shown; no preview proposed.
    expect(
      find.textContaining('carrying fatigue', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Proposed changes'), findsNothing);
    // Drain the showTopBanner auto-dismiss timer before teardown.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('gate OFF (default) ignores fitness — under-trend still proposes',
      (tester) async {
    // No dotenv flag → _adaptiveFitnessInput returns null → P1 behaviour.
    final p = underTrendPlan();
    final store = await fatiguedStore(tester);
    await pump(
      tester,
      training: p.training,
      social: _FakeSocial(const []),
      runStore: store,
    );

    await tester.tap(find.text('Adaptive re-plan'));
    await tester.pump();

    // No held toast; the under-trend proposes a make-up.
    expect(find.textContaining('carrying fatigue', findRichText: true),
        findsNothing);
    expect(find.text('Proposed changes'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
