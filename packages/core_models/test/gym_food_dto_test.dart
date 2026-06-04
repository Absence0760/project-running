import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  group('GymWorkout.fromRow', () {
    test('parses scalars + inline sets', () {
      final w = GymWorkout.fromRow(
        {
          'id': 'w1',
          'title': 'Push day',
          'started_at': '2026-06-02T08:00:00.000Z',
          'duration_s': 3600,
          'notes': 'felt strong',
          'is_public': true,
          'external_id': null,
          'last_modified_at': '2026-06-02T09:00:00.000Z',
          'created_at': '2026-06-02T08:00:00.000Z',
        },
        sets: [
          {'exercise_name': 'Bench', 'reps': 8, 'weight_kg': 60.0, 'rpe': 8.0},
          {'exercise_name': 'Bench', 'reps': 6, 'weight_kg': 65, 'rpe': null},
        ],
      );
      expect(w.id, 'w1');
      expect(w.title, 'Push day');
      expect(w.startedAt, DateTime.utc(2026, 6, 2, 8));
      expect(w.durationS, 3600);
      expect(w.notes, 'felt strong');
      expect(w.isPublic, isTrue);
      expect(w.lastModifiedAt, DateTime.utc(2026, 6, 2, 9));
      expect(w.sets, hasLength(2));
      expect(w.sets.first.exerciseName, 'Bench');
      expect(w.sets.first.reps, 8);
      expect(w.sets.first.weightKg, 60.0);
      expect(w.sets.last.weightKg, 65.0);
      expect(w.sets.last.rpe, isNull);
    });

    test('tolerates a missing title / public / sets', () {
      final w = GymWorkout.fromRow({'id': 'w2'});
      expect(w.title, isNull);
      expect(w.isPublic, isFalse);
      expect(w.startedAt, isNull);
      expect(w.sets, isEmpty);
    });
  });

  group('GymSet.fromRow', () {
    test('parses set_index + coerces numerics', () {
      final s = GymSet.fromRow({
        'exercise_name': 'Squat',
        'reps': 5,
        'weight_kg': 100,
        'rpe': 9,
        'set_index': 2,
      });
      expect(s.exerciseName, 'Squat');
      expect(s.reps, 5);
      expect(s.weightKg, 100.0);
      expect(s.rpe, 9.0);
      expect(s.setIndex, 2);
    });
  });

  group('FoodEntry.fromRow', () {
    test('parses scalars', () {
      final f = FoodEntry.fromRow({
        'id': 'f1',
        'logged_at': '2026-06-02T12:00:00.000Z',
        'item_name': 'Oatmeal',
        'meal_slot': 'breakfast',
        'calories': 350.0,
        'protein_g': 12,
        'carbs_g': 60.0,
        'fat_g': 6,
        'is_public': false,
        'external_id': null,
        'last_modified_at': '2026-06-02T12:05:00.000Z',
        'created_at': '2026-06-02T12:00:00.000Z',
      });
      expect(f.id, 'f1');
      expect(f.loggedAt, DateTime.utc(2026, 6, 2, 12));
      expect(f.itemName, 'Oatmeal');
      expect(f.mealSlot, 'breakfast');
      expect(f.calories, 350.0);
      expect(f.proteinG, 12.0);
      expect(f.carbsG, 60.0);
      expect(f.fatG, 6.0);
      expect(f.isPublic, isFalse);
    });

    test('tolerates missing optionals', () {
      final f = FoodEntry.fromRow({'id': 'f2', 'item_name': 'Banana'});
      expect(f.mealSlot, isNull);
      expect(f.calories, isNull);
      expect(f.loggedAt, isNull);
      expect(f.isPublic, isFalse);
    });
  });
}
