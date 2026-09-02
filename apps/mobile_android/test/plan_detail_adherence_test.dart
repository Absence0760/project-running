import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader, TextLane;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training.dart' show toIsoDate;
import '../lib/training_service.dart';
import 'pump_until.dart';

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
      isPublicTemplate: false,
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
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: PlanDetailScreen(
        training: training,
        planId: 'plan-1',
        social: social,
        viewerIdOverride: viewerId,
      ),
    ),
  );
  // _load's plan fetch is async; the trailing pump lands the setState that
  // _loadRecentRuns — kicked off once the plan is in — resolves into.
  await pumpUntil(tester, () => !tester.any(find.byType(FullBodyLoader)),
      describe: 'the plan fetch to replace the full-body loader');
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
      await pumpUntil(tester, () => training.updated.isNotEmpty,
          describe: 'the re-plan to write its week updates');
      // 28 km capped to 22 km * 1.15 = 25300.
      expect(training.updated['next'], (22000 * 1.15).round());
      // Drain the showTopBanner auto-dismiss timer before teardown.
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('PlanDetailScreen — duplicate week', () {
    testWidgets('owner duplicate action confirms then calls the RPC',
        (tester) async {
      final start = _mondayThisWeek();
      final training = _FakeTraining(
        _plan(start),
        [_week('w0', 0, 'build', 40000)],
        [_wo('wo0', 'w0', start.add(const Duration(days: 1)), 'easy', 8000)],
      );
      final social = _FakeSocial(const []);
      await _pump(tester, training: training, social: social);

      final dup = find.byTooltip('Duplicate week');
      // Both primitives, because the two Flutter versions leave the button in
      // different states: scrollUntilVisible builds it where the list is lazy
      // (it is absent from the tree entirely on 3.44), and ensureVisible then
      // pulls it inside the 800x600 viewport where it is built but below the
      // fold (3.47 lands it at y=612.5, so the tap misses the render tree).
      // Either one alone passes on one version and fails on the other.
      await tester.scrollUntilVisible(dup, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(dup);
      await tester.pumpAndSettle();
      expect(dup, findsOneWidget);
      await tester.tap(dup);
      await tester.pumpAndSettle();
      // The dialog gates the destructive RPC — nothing fired yet.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(training.duplicated, isEmpty);

      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Duplicate')));
      await pumpUntil(tester, () => training.duplicated.isNotEmpty,
          describe: 'the confirmed duplicate to reach the RPC');
      expect(training.duplicated, contains('plan-1:0'));
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('cancelling the duplicate confirm is a no-op', (tester) async {
      final start = _mondayThisWeek();
      final training = _FakeTraining(
        _plan(start),
        [_week('w0', 0, 'build', 40000)],
        [_wo('wo0', 'w0', start.add(const Duration(days: 1)), 'easy', 8000)],
      );
      final social = _FakeSocial(const []);
      await _pump(tester, training: training, social: social);

      final dup = find.byTooltip('Duplicate week');
      // Both primitives, because the two Flutter versions leave the button in
      // different states: scrollUntilVisible builds it where the list is lazy
      // (it is absent from the tree entirely on 3.44), and ensureVisible then
      // pulls it inside the 800x600 viewport where it is built but below the
      // fold (3.47 lands it at y=612.5, so the tap misses the render tree).
      // Either one alone passes on one version and fails on the other.
      await tester.scrollUntilVisible(dup, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(dup);
      await tester.pumpAndSettle();
      await tester.tap(dup);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(training.duplicated, isEmpty);
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

  group('PlanDetailScreen — adaptive width', () {
    _FakeTraining training() {
      final start = _mondayThisWeek();
      return _FakeTraining(
        _plan(start),
        [_week('w0', 0, 'build', 40000)],
        [_wo('wo0', 'w0', start.add(const Duration(days: 1)), 'easy', 8000)],
      );
    }

    testWidgets('expanded surface caps the scrollable body at 900dp',
        (tester) async {
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await _pump(tester, training: training(), social: _FakeSocial(const []));
      // 1280dp surface → the body ListView is centered + capped at 900dp.
      expect(tester.getSize(find.byType(ListView).first).width, 900);
    });

    testWidgets('compact surface keeps the body full width', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _pump(tester, training: training(), social: _FakeSocial(const []));
      expect(tester.getSize(find.byType(ListView).first).width, 400);
    });
  });

  group('PlanDetailScreen — OS text scaling (issue #666 V12)', () {
    _FakeTraining allDone() {
      final start = _mondayThisWeek();
      return _FakeTraining(
        _plan(start),
        [_week('w0', 0, 'build', 8000)],
        [
          _wo('wo0', 'w0', start.add(const Duration(days: 1)), 'easy', 8000,
              manuallyCompleted: true),
        ],
      );
    }

    testWidgets('the progress ring caption stays inside the 64 px ring',
        (tester) async {
      final caption = find.byWidgetPredicate((w) =>
          w is FittedBox && w.child is Column && w.fit == BoxFit.scaleDown);

      await _pump(tester, training: allDone(), social: _FakeSocial(const []));
      final at1x = tester.getSize(caption.first);

      await _pump(
          tester, training: allDone(), social: _FakeSocial(const []),
          textScale: 2.0);
      // Pre-fix this Column measured 144 px inside a 64 px ring and painted a
      // 112 px RenderFlex overflow stripe over the plan header.
      final at2x = tester.getSize(caption.first);
      expect(at2x.height, lessThanOrEqualTo(64));
      expect(at2x.width, lessThanOrEqualTo(64));
      expect(at2x.height, greaterThanOrEqualTo(at1x.height));
      expect(tester.takeException(), isNull);
    });
  });

  group('PlanDetailScreen — the week-grid weekday lane', () {
    // The weekday sat in a 34px box. Portuguese "dom." needs 27.1px in real
    // Roboto at labelSmall, which clears the box from 1.5x (39.7) and reaches
    // 52.2 at 2x — and the abbreviation carries no break opportunity, so it
    // painted over the workout name beside it rather than reflowing.
    //
    // Pinned as a derivation, never as an absolute fit: flutter_test renders a
    // fixed-advance font 2-6x wider than Roboto, so a lane whose floor tracks
    // the scale here tracks it on a device too.
    Future<void> pumpGrid(WidgetTester tester, {double textScale = 1.0}) async {
      final start = _mondayThisWeek();
      final training = _FakeTraining(
        _plan(start),
        [_week('w0', 0, 'build', 40000)],
        [_wo('wo0', 'w0', start, 'easy', 8000)],
      );
      await _pump(tester,
          training: training,
          social: _FakeSocial(const []),
          textScale: textScale);
      // The week cards sit below the calendar in a lazy ListView.
      await tester.scrollUntilVisible(
        find.byType(TextLane),
        400,
        scrollable: find.byType(Scrollable).first,
      );
    }

    Finder dowLane() => find.byType(TextLane);

    testWidgets('the lane widens to the weekday instead of overpainting',
        (tester) async {
      await pumpGrid(tester);
      expect(dowLane(), findsWidgets);
      final lane = dowLane().first;
      final dow = find.descendant(of: lane, matching: find.byType(Text)).first;
      final para = tester.renderObject<RenderParagraph>(dow);
      expect(
        tester.getSize(lane).width,
        greaterThanOrEqualTo(para.getMaxIntrinsicWidth(double.infinity)),
      );
    });

    testWidgets('the lane floor grows with the OS text scale', (tester) async {
      await pumpGrid(tester, textScale: 2.0);
      expect(tester.getSize(dowLane().first).width, greaterThanOrEqualTo(68));
    });

  });
}
