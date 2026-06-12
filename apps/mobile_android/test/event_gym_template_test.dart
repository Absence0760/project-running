import 'package:flutter_test/flutter_test.dart';
import '../lib/event_gym_template.dart';

void main() {
  group('parseGymTemplate', () {
    test('valid full template', () {
      final t = parseGymTemplate({'discipline': 'Vinyasa yoga', 'duration_min': 60});
      expect(t!.discipline, 'Vinyasa yoga');
      expect(t.durationMin, 60);
    });

    test('null / non-map -> null', () {
      expect(parseGymTemplate(null), isNull);
      expect(parseGymTemplate('yoga'), isNull);
      expect(parseGymTemplate(42), isNull);
      expect(parseGymTemplate(['a', 'b']), isNull);
    });

    test('empty map -> null (treated as no template)', () {
      expect(parseGymTemplate(<String, dynamic>{}), isNull);
    });

    test('discipline only', () {
      final t = parseGymTemplate({'discipline': 'Spin'});
      expect(t!.discipline, 'Spin');
      expect(t.durationMin, isNull);
    });

    test('duration only', () {
      final t = parseGymTemplate({'duration_min': 45});
      expect(t!.discipline, isNull);
      expect(t.durationMin, 45);
    });

    test('wrong-typed values are dropped', () {
      expect(parseGymTemplate({'discipline': 123, 'duration_min': 'long'}), isNull);
      expect(parseGymTemplate({'discipline': '   ', 'duration_min': 0}), isNull);
      expect(parseGymTemplate({'discipline': '  ', 'duration_min': -10}), isNull);
      final t = parseGymTemplate({'discipline': '  Pilates ', 'duration_min': 30.9});
      expect(t!.discipline, 'Pilates');
      expect(t.durationMin, 30);
    });
  });

  group('gymTemplateFromInputs', () {
    test('both empty -> null', () {
      expect(gymTemplateFromInputs('', null), isNull);
      expect(gymTemplateFromInputs('   ', null), isNull);
      expect(gymTemplateFromInputs(null, null), isNull);
      expect(gymTemplateFromInputs('', 0), isNull);
    });

    test('discipline only', () {
      final t = gymTemplateFromInputs('Strength', null);
      expect(t!.discipline, 'Strength');
      expect(t.durationMin, isNull);
    });

    test('duration only', () {
      final t = gymTemplateFromInputs('', 50);
      expect(t!.discipline, isNull);
      expect(t.durationMin, 50);
    });

    test('both, trims', () {
      final t = gymTemplateFromInputs('  Yoga  ', 60);
      expect(t!.discipline, 'Yoga');
      expect(t.durationMin, 60);
    });
  });

  group('workoutDraftFromTemplate', () {
    test('duration -> seconds, title from discipline', () {
      final d = workoutDraftFromTemplate(
        const EventGymTemplate(discipline: 'Spin', durationMin: 45),
        'Sat ride',
      );
      expect(d.title, 'Spin');
      expect(d.durationS, 45 * 60);
    });

    test('title falls back to event title when no discipline', () {
      final d = workoutDraftFromTemplate(
        const EventGymTemplate(discipline: null, durationMin: 30),
        'Morning Strength',
      );
      expect(d.title, 'Morning Strength');
      expect(d.durationS, 30 * 60);
    });

    test('null template + null title -> empty draft', () {
      final d = workoutDraftFromTemplate(null, null);
      expect(d.title, isNull);
      expect(d.durationS, isNull);
      final d2 = workoutDraftFromTemplate(null, '  ');
      expect(d2.title, isNull);
    });
  });
}
