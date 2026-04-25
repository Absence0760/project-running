import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/training.dart' show fmtPace;
import 'package:mobile_android/widgets/workout_review_section.dart';

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
  });
}
