import 'dart:io';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_run_store.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

/// P2 adaptive-replan fitness gate wiring on plan_detail_screen.
///
/// The gate is OFF unless `ADAPTIVE_FITNESS_GATE` is set in dotenv. When ON and
/// the runner is DEEPLY fatigued (TSB past the floor with acute load high
/// against the chronic base), the under-fitness add-volume trend is overridden
/// to a DELOAD — `_proposeAdaptiveReplan` surfaces the held banner and previews
/// ease-off changes instead of the make-up. When OFF (default), no fitness is
/// consulted and the P1 behaviour is unchanged (an under-trend proposes a
/// make-up). The engine's branches themselves are covered by
/// `plan_adaptive_replan_test.dart`; this pins the screen wiring (dotenv flag +
/// LocalRunStore-threaded full-Run fitness input).

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
      isPublicTemplate: false,
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
      // A future NON-long workout, so a deload has something to ease. Long runs
      // are never eased, so which of the two moves tells the two directions
      // apart in the assertions below.
      _wo('easy', 'w3', _mondayThisWeek().add(const Duration(days: 10)), 'easy',
          8000),
    ];
    return (training: _FakeTraining(_plan(start), weeks, workouts), start: start);
  }

  /// Seed a store with `days` consecutive daily runs of `metres`, newest today.
  Future<LocalRunStore> seededStore(
    WidgetTester tester,
    String prefix, {
    required int days,
    required double metres,
  }) async {
    final store = LocalRunStore();
    await store.init(overrideDirectory: tmp(prefix));
    final now = DateTime.now();
    final runs = [
      for (var i = 0; i < days; i++)
        Run(
          id: 'seed-$i',
          startedAt: now.subtract(Duration(days: i)),
          duration: Duration(minutes: (metres / 200).round()),
          distanceMetres: metres,
          track: const [],
          source: RunSource.app,
        ),
    ];
    await tester.runAsync(() => store.saveManyFromRemote(runs));
    return store;
  }

  /// A short, heavy recent block with no chronic base: ATL runs away from CTL,
  /// so the latest load point is TSB ≈ -66 with ACWR ≈ 4.3 — past both
  /// `adaptiveDeepFatigueTsb` and `adaptiveHighAcwr`, i.e. DEEPLY fatigued.
  Future<LocalRunStore> deeplyFatiguedStore(WidgetTester tester) =>
      seededStore(tester, 'fitness_gate_deep_', days: 6, metres: 15000);

  /// Three months of steady daily running: CTL has caught up, so the latest
  /// load point is TSB ≈ -9 with ACWR ≈ 1.13 — negative form, but nowhere near
  /// the deload thresholds. The arm-1 hold, not the arm-2 override.
  Future<LocalRunStore> mildlyFatiguedStore(WidgetTester tester) =>
      seededStore(tester, 'fitness_gate_mild_', days: 90, metres: 8000);

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
    await pumpUntil(tester, () => !tester.any(find.byType(FullBodyLoader)),
        describe: 'the plan fetch to replace the full-body loader');
    await tester.pump();
  }

  testWidgets('gate ON + deeply fatigued runner deloads instead of adding volume',
      (tester) async {
    dotenv.loadFromString(envString: 'ADAPTIVE_FITNESS_GATE=true');
    final p = underTrendPlan();
    final store = await deeplyFatiguedStore(tester);
    await pump(
      tester,
      training: p.training,
      social: _FakeSocial(const []),
      runStore: store,
    );

    await tester.tap(find.text('Adaptive re-plan'));
    await tester.pump();

    // Held banner shown, and the preview is the ease-off — never the make-up.
    expect(
      find.textContaining('carrying fatigue', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Proposed changes'), findsOneWidget);
    expect(find.textContaining('ease off', findRichText: true), findsOneWidget);
    expect(find.textContaining('make up a missed long run', findRichText: true),
        findsNothing);
  });

  testWidgets('gate ON + mildly fatigued runner holds, proposing nothing',
      (tester) async {
    dotenv.loadFromString(envString: 'ADAPTIVE_FITNESS_GATE=true');
    final p = underTrendPlan();
    final store = await mildlyFatiguedStore(tester);
    await pump(
      tester,
      training: p.training,
      social: _FakeSocial(const []),
      runStore: store,
    );

    await tester.tap(find.text('Adaptive re-plan'));
    await tester.pump();

    expect(
      find.textContaining('carrying fatigue', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Proposed changes'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('gate OFF (default) ignores fitness — under-trend still proposes',
      (tester) async {
    // No dotenv flag → _adaptiveFitnessInput returns null → P1 behaviour.
    final p = underTrendPlan();
    final store = await deeplyFatiguedStore(tester);
    await pump(
      tester,
      training: p.training,
      social: _FakeSocial(const []),
      runStore: store,
    );

    await tester.tap(find.text('Adaptive re-plan'));
    await tester.pump();

    // No held banner; the under-trend proposes the make-up, not a deload.
    expect(find.textContaining('carrying fatigue', findRichText: true),
        findsNothing);
    expect(find.text('Proposed changes'), findsOneWidget);
    expect(find.textContaining('make up a missed long run', findRichText: true),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
