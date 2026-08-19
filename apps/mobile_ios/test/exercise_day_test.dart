import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/exercise_day.dart';

/// The day reduction behind the nutrition exercise add-on. Moved here with the
/// helper when it left `screens/nutrition_screen.dart` (decisions § 695) —
/// these cases never needed a screen mounted, which is why they were pulled
/// out of the widget path in the first place.
void main() {
  group('exerciseInputsForDay', () {
    ActivityRow row(String kind, DateTime at, Map<String, dynamic> summary) =>
        ActivityRow(id: kind, kind: kind, startedAt: at, summary: summary);

    final start = DateTime(2026, 7, 24);
    final end = DateTime(2026, 7, 25);

    test('a gym workout counts toward the day, under its real kind', () {
      final day = exerciseInputsForDay([
        row(ActivityRow.kindLift, DateTime(2026, 7, 24, 18),
            {'duration_s': 3600}),
      ], start, end);

      expect(day.gym.length, 1);
      expect(day.gym.single.durationS, 3600);
      expect(day.seconds, 3600);
      expect(day.runs, isEmpty);
    });

    test("'gym' is not a kind the view emits and must not be matched", () {
      final day = exerciseInputsForDay(
        [row('gym', DateTime(2026, 7, 24, 18), {'duration_s': 3600})],
        start,
        end,
      );
      expect(day.gym, isEmpty);
      expect(day.seconds, 0);
    });

    test('runs carry distance, meals are ignored entirely', () {
      final day = exerciseInputsForDay([
        row(ActivityRow.kindRun, DateTime(2026, 7, 24, 7),
            {'duration_s': 1800, 'distance_m': 5000}),
        row(ActivityRow.kindMeal, DateTime(2026, 7, 24, 12), {'duration_s': 60}),
      ], start, end);

      expect(day.runs.single.distanceM, 5000);
      expect(day.gym, isEmpty);
      expect(day.seconds, 1800, reason: 'the meal must not add to the total');
    });

    test('the window is half-open — yesterday and tomorrow are excluded', () {
      final day = exerciseInputsForDay([
        row(ActivityRow.kindRun, DateTime(2026, 7, 23, 23, 59),
            {'duration_s': 600}),
        row(ActivityRow.kindLift, end, {'duration_s': 600}),
        row(ActivityRow.kindRun, DateTime(2026, 7, 24, 23, 59),
            {'duration_s': 600}),
      ], start, end);

      expect(day.seconds, 600);
      expect(day.runs.length, 1);
      expect(day.gym, isEmpty);
    });

    test('a missing duration contributes zero rather than throwing', () {
      final day = exerciseInputsForDay([
        row(ActivityRow.kindLift, DateTime(2026, 7, 24, 18), const {}),
      ], start, end);

      expect(day.gym.single.durationS, isNull);
      expect(day.seconds, 0);
    });

    test('the kind constants are the literals the activities view emits', () {
      // Ties the Dart names to the SQL so a renamed UNION branch fails here
      // instead of silently matching nothing at a call site.
      final sql = File(
        '../backend/supabase/migrations/'
        '20270413_001_activities_view_project_is_dnf.sql',
      ).readAsStringSync();
      for (final kind in [
        ActivityRow.kindRun,
        ActivityRow.kindLift,
        ActivityRow.kindMeal,
      ]) {
        expect(sql, contains("'$kind'::text as kind"), reason: kind);
      }
    });
  });
}
