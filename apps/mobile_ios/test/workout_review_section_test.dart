import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/training.dart' show fmtPace;
import '../lib/widgets/workout_review_section.dart';

Map<String, dynamic> _step({
  required String kind,
  int? repIndex,
  int? repTotal,
  double targetDistanceM = 400,
  double actualDistanceM = 400,
  int targetPaceSecPerKm = 240,
  int? actualPaceSecPerKm = 240,
  String status = 'completed',
}) =>
    {
      'kind': kind,
      if (repIndex != null) 'rep_index': repIndex,
      if (repTotal != null) 'rep_total': repTotal,
      'target_distance_m': targetDistanceM,
      'actual_distance_m': actualDistanceM,
      'target_pace_sec_per_km': targetPaceSecPerKm,
      if (actualPaceSecPerKm != null)
        'actual_pace_sec_per_km': actualPaceSecPerKm,
      'status': status,
    };

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, dynamic>? metadata,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WorkoutReviewSection(metadata: metadata),
        ),
      ),
    ),
  );
}

void main() {
  group('WorkoutReviewSection', () {
    testWidgets('renders nothing when metadata is null', (tester) async {
      await _pump(tester, metadata: null);
      expect(find.text('Workout'), findsNothing);
    });

    testWidgets('renders nothing when workout_step_results is absent',
        (tester) async {
      await _pump(tester, metadata: const {'workout_adherence': 'completed'});
      expect(find.text('Workout'), findsNothing);
    });

    testWidgets('renders nothing when workout_step_results is empty',
        (tester) async {
      await _pump(tester, metadata: const {'workout_step_results': []});
      expect(find.text('Workout'), findsNothing);
    });

    testWidgets('renders header, adherence pill, and a row per step',
        (tester) async {
      await _pump(tester, metadata: {
        'workout_adherence': 'completed',
        'workout_step_results': [
          _step(kind: 'warmup', targetDistanceM: 1000, actualDistanceM: 1000),
          _step(kind: 'rep', repIndex: 1, repTotal: 6),
          _step(kind: 'recovery', repIndex: 1, repTotal: 6),
          _step(
              kind: 'cooldown', targetDistanceM: 1000, actualDistanceM: 1000),
        ],
      });

      expect(find.text('Workout'), findsOneWidget);
      expect(find.text('completed'), findsOneWidget);
      expect(find.text('Warmup'), findsOneWidget);
      expect(find.text('Rep 1/6'), findsOneWidget);
      expect(find.text('Recovery 1/6'), findsOneWidget);
      expect(find.text('Cooldown'), findsOneWidget);
      expect(find.text('STEP'), findsOneWidget);
      expect(find.text('PLAN'), findsOneWidget);
      expect(find.text('ACTUAL'), findsOneWidget);
    });

    testWidgets('shows skip label and strikethrough for skipped step',
        (tester) async {
      await _pump(tester, metadata: {
        'workout_adherence': 'partial',
        'workout_step_results': [
          _step(
            kind: 'rep',
            repIndex: 2,
            repTotal: 6,
            actualPaceSecPerKm: null,
            actualDistanceM: 0,
            status: 'skipped',
          ),
        ],
      });
      expect(find.text('skip'), findsOneWidget);

      final label = tester.widget<Text>(find.text('Rep 2/6'));
      expect(label.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('em-dash and neutral colour when actual pace is null',
        (tester) async {
      await _pump(tester, metadata: {
        'workout_step_results': [
          _step(
            kind: 'steady',
            actualPaceSecPerKm: null,
            actualDistanceM: 0,
          ),
        ],
      });
      // The pace column renders an em-dash via formatPace when null;
      // the delta column also renders an em-dash via paceDeltaOf.
      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('signed delta label matches +/− and seconds magnitude',
        (tester) async {
      await _pump(tester, metadata: {
        'workout_step_results': [
          _step(
            kind: 'rep',
            repIndex: 1,
            repTotal: 3,
            targetPaceSecPerKm: 240,
            actualPaceSecPerKm: 235,
          ),
          _step(
            kind: 'rep',
            repIndex: 2,
            repTotal: 3,
            targetPaceSecPerKm: 240,
            actualPaceSecPerKm: 252,
          ),
        ],
      });
      expect(find.text('−5s'), findsOneWidget);
      expect(find.text('+12s'), findsOneWidget);
    });

    test('paceDeltaOf returns "on" when within tolerance', () {
      final s = WorkoutStepReview.fromMap({
        'kind': 'rep',
        'target_pace_sec_per_km': 240,
        'actual_pace_sec_per_km': 244,
        'target_distance_m': 400,
        'actual_distance_m': 400,
      });
      expect(paceDeltaOf(s).tone, PaceDeltaTone.on);
    });

    test('paceDeltaOf returns "amber" between 1× and 2× tolerance', () {
      final s = WorkoutStepReview.fromMap({
        'kind': 'rep',
        'target_pace_sec_per_km': 240,
        'actual_pace_sec_per_km': 255,
        'target_distance_m': 400,
        'actual_distance_m': 400,
      });
      expect(paceDeltaOf(s).tone, PaceDeltaTone.amber);
    });

    test('paceDeltaOf returns "off" beyond 2× tolerance', () {
      final s = WorkoutStepReview.fromMap({
        'kind': 'rep',
        'target_pace_sec_per_km': 240,
        'actual_pace_sec_per_km': 270,
        'target_distance_m': 400,
        'actual_distance_m': 400,
      });
      expect(paceDeltaOf(s).tone, PaceDeltaTone.off);
    });

    test('fmtPace produces m:ss/km, em-dash for invalid', () {
      expect(fmtPace(0), '—');
      expect(fmtPace(null), '—');
      expect(fmtPace(245), '4:05/km');
    });

    testWidgets('duration-based step renders time plan + time actual cells',
        (tester) async {
      await _pump(tester, metadata: {
        'workout_adherence': 'completed',
        'workout_step_results': [
          {
            'kind': 'rep',
            'rep_index': 1,
            'rep_total': 4,
            'target_distance_m': 0,
            'actual_distance_m': 120,
            'target_duration_s': 30,
            'duration_s': 30,
            'target_pace_sec_per_km': 240,
            'actual_pace_sec_per_km': 240,
            'status': 'completed',
          },
          {
            'kind': 'recovery',
            'rep_index': 1,
            'rep_total': 3,
            'target_distance_m': 0,
            'actual_distance_m': 180,
            'target_duration_s': 90,
            'duration_s': 90,
            'target_pace_sec_per_km': 420,
            'actual_pace_sec_per_km': 420,
            'status': 'completed',
          },
        ],
      });
      // First row: 30s / 30s plan vs actual.
      expect(find.text('30s'), findsNWidgets(2));
      // Second row: 1m 30s / 1m 30s.
      expect(find.text('1m 30s'), findsNWidgets(2));
      // Distance formatting MUST NOT appear for time-based steps.
      expect(find.text('0.12 km'), findsNothing);
    });

    test('WorkoutStepReview.fromMap reads target_duration_s', () {
      final s = WorkoutStepReview.fromMap({
        'kind': 'rep',
        'target_distance_m': 0,
        'target_duration_s': 30,
        'duration_s': 30,
        'target_pace_sec_per_km': 240,
      });
      expect(s.isDurationBased, isTrue);
      expect(s.targetDurationSec, 30);
      expect(s.durationSeconds, 30);
    });

    test('WorkoutStepReview without target_duration_s stays distance-based',
        () {
      final s = WorkoutStepReview.fromMap({
        'kind': 'rep',
        'target_distance_m': 400,
        'actual_distance_m': 400,
        'target_pace_sec_per_km': 240,
      });
      expect(s.isDurationBased, isFalse);
      expect(s.targetDurationSec, isNull);
    });

    test('formatStepDuration formats <60 / =60 / minutes-plus-seconds', () {
      expect(formatStepDuration(30), '30s');
      expect(formatStepDuration(60), '1m');
      expect(formatStepDuration(90), '1m 30s');
      expect(formatStepDuration(240), '4m');
      expect(formatStepDuration(245), '4m 5s');
    });
  });
}
