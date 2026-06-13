import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training.dart' show toIsoDate;
import '../lib/training_service.dart';

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
  final List<String> duplicated = [];
  final Map<String, double> updated = {};

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

  @override
  Future<String> duplicatePlanWeek(String planId, int weekIndex) async {
    duplicated.add('$planId:$weekIndex');
    return 'new-week-id';
  }

  @override
  Future<void> updateWorkout(
    String workoutId, {
    String? kind,
    double? targetDistanceM,
    int? targetPaceSecPerKm,
    String? notes,
  }) async {
    if (targetDistanceM != null) updated[workoutId] = targetDistanceM;
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

PlanWeekRow _week(String id, int idx, String phase, double vol) =>
    PlanWeekRow(
        id: id, planId: 'plan-1', weekIndex: idx, phase: phase, targetVolumeM: vol);

PlanWorkoutRow _wo(String id, String weekId, DateTime date, String kind,
        double? dist,
        {bool manuallyCompleted = false}) =>
    PlanWorkoutRow(
      id: id,
      weekId: weekId,
      scheduledDate: date,
      kind: kind,
      targetDistanceM: dist,
      manuallyCompleted: manuallyCompleted,
    );

Future<void> _pump(
  WidgetTester tester, {
  required _FakeTraining training,
  required _FakeSocial social,
  String? viewerId = _uid,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanDetailScreen(
        training: training,
        planId: 'plan-1',
        social: social,
        viewerIdOverride: viewerId,
      ),
    ),
  );
  // _load (plan fetch) + _loadRecentRuns are async.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
  await tester.pump();
  await tester.pump();
}

void main() {
  group('PlanDetailScreen — adherence banner', () {
    testWidgets('flags under-running when actual mileage is well below plan',
        (tester) async {
      final start = _mondayThisWeek();
      final training = _FakeTraining(
        _plan(start),
        [_week('w0', 0, 'build', 40000)],
        [_wo('wo0', 'w0', start.add(const Duration(days: 1)), 'easy', 8000)],
      );
      // One 10 km run this week vs a 40 km plan → ~75% under.
      final social = _FakeSocial([
        RecentRunRow(
          id: 'r1',
          startedAt: start.add(const Duration(days: 1)),
          durationS: 3000,
          distanceM: 10000,
          activityType: 'run',
        ),
      ]);
      await _pump(tester, training: training, social: social);
      expect(find.textContaining('under plan this week'), findsOneWidget);
    });

    testWidgets('surfaces make-up advice for a missed long run', (tester) async {
      final start = _mondayThisWeek();
      // A long run earlier today/this week, uncompleted + in the past.
      final pastLong = start; // Monday — at or before today this week.
      final training = _FakeTraining(
        _plan(start),
        [_week('w0', 0, 'build', 40000)],
        [_wo('lr', 'w0', pastLong, 'long', 20000)],
      );
      final social = _FakeSocial([
        // Keep mileage on-plan so only the missed-long flag shows.
        RecentRunRow(
          id: 'r1',
          startedAt: start.add(const Duration(hours: 1)),
          durationS: 3000,
          distanceM: 38000,
          activityType: 'run',
        ),
      ]);
      await _pump(tester, training: training, social: social);
      // Only assert the missed-long flag when the long run actually sits in
      // the past (Monday < today). On a Monday run the day, it won't — skip.
      if (toIsoDate(pastLong).compareTo(toIsoDate(DateTime.now())) < 0) {
        expect(find.textContaining('missed'), findsWidgets);
      }
    });

    testWidgets('hidden for a non-owner viewer', (tester) async {
      final start = _mondayThisWeek();
      final training = _FakeTraining(
        _plan(start),
        [_week('w0', 0, 'build', 40000)],
        [_wo('wo0', 'w0', start.add(const Duration(days: 1)), 'easy', 8000)],
      );
      final social = _FakeSocial([
        RecentRunRow(
          id: 'r1',
          startedAt: start.add(const Duration(days: 1)),
          durationS: 3000,
          distanceM: 10000,
          activityType: 'run',
        ),
      ]);
      await _pump(tester,
          training: training, social: social, viewerId: 'someone-else');
      expect(find.textContaining('under plan this week'), findsNothing);
      expect(find.text('Re-plan remaining weeks'), findsNothing);
    });
  });

  group('PlanDetailScreen — re-plan flow', () {
    testWidgets('proposes a make-up and applies it', (tester) async {
      // Week 0 is complete + in the past (start two weeks ago), missed long;
      // week 1 is the current week with a shorter long run to bump.
      final start = _mondayThisWeek().subtract(const Duration(days: 14));
      final training = _FakeTraining(
        _plan(start),
        [
          _week('w0', 0, 'build', 40000),
          _week('w1', 1, 'build', 42000),
          _week('w2', 2, 'build', 44000),
        ],
        [
          _wo('missed', 'w0', start.add(const Duration(days: 1)), 'long', 28000),
          _wo('next', 'w2',
              _mondayThisWeek().add(const Duration(days: 9)), 'long', 22000),
        ],
      );
      final social = _FakeSocial(const []);
      await _pump(tester, training: training, social: social);

      await tester.tap(find.text('Re-plan remaining weeks'));
      await tester.pump();
      expect(find.text('Proposed changes'), findsOneWidget);

      await tester.tap(find.text('Apply changes'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
      // 28 km capped to 22 km * 1.15 = 25300.
      expect(training.updated['next'], (22000 * 1.15).round());
      // Drain the showTopBanner auto-dismiss timer before teardown.
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('PlanDetailScreen — duplicate week', () {
    testWidgets('owner duplicate action calls the RPC', (tester) async {
      final start = _mondayThisWeek();
      final training = _FakeTraining(
        _plan(start),
        [_week('w0', 0, 'build', 40000)],
        [_wo('wo0', 'w0', start.add(const Duration(days: 1)), 'easy', 8000)],
      );
      final social = _FakeSocial(const []);
      await _pump(tester, training: training, social: social);

      final dup = find.byTooltip('Duplicate week');
      await tester.scrollUntilVisible(dup, 200,
          scrollable: find.byType(Scrollable).first);
      expect(dup, findsOneWidget);
      await tester.tap(dup);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
      expect(training.duplicated, contains('plan-1:0'));
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('non-owner sees no duplicate action', (tester) async {
      final start = _mondayThisWeek();
      final training = _FakeTraining(
        _plan(start),
        [_week('w0', 0, 'build', 40000)],
        [_wo('wo0', 'w0', start.add(const Duration(days: 1)), 'easy', 8000)],
      );
      final social = _FakeSocial(const []);
      await _pump(tester,
          training: training, social: social, viewerId: 'someone-else');
      expect(find.byTooltip('Duplicate week'), findsNothing);
    });
  });

  group('PlanDetailScreen — plan progress', () {
    testWidgets('shows the longest completed long run', (tester) async {
      final start = _mondayThisWeek();
      final training = _FakeTraining(
        _plan(start),
        [_week('w0', 0, 'build', 40000)],
        [
          _wo('lr', 'w0', start.add(const Duration(days: 2)), 'long', 28000,
              manuallyCompleted: true),
          // An incomplete longer long run must NOT win.
          _wo('lr2', 'w0', start.add(const Duration(days: 5)), 'long', 32000),
        ],
      );
      final social = _FakeSocial(const []);
      await _pump(tester, training: training, social: social);
      expect(find.textContaining('Longest long run'), findsOneWidget);
    });

    testWidgets('hides the progress section with no completed long run',
        (tester) async {
      final start = _mondayThisWeek();
      final training = _FakeTraining(
        _plan(start),
        [_week('w0', 0, 'build', 40000)],
        [_wo('e', 'w0', start.add(const Duration(days: 1)), 'easy', 8000)],
      );
      final social = _FakeSocial(const []);
      await _pump(tester, training: training, social: social);
      expect(find.textContaining('Longest long run'), findsNothing);
    });
  });
}
