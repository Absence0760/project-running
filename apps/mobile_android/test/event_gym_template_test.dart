import 'package:flutter_test/flutter_test.dart';
import '../lib/event_gym_template.dart';
import '../lib/session_steps.dart';

SessionStep _step({
  String itemId = 'i',
  String movementName = 'Move',
  SessionItemKind kind = SessionItemKind.hold,
  int? durationS = 30,
  int? reps,
  SessionSide? side,
  int cumulativeS = 30,
}) {
  return SessionStep(
    itemId: itemId,
    movementName: movementName,
    kind: kind,
    durationS: durationS,
    reps: reps,
    tempo: null,
    cue: null,
    side: side,
    cumulativeS: cumulativeS,
  );
}

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

  group('workoutDraftFromSession', () {
    test('title from discipline when present', () {
      final d = workoutDraftFromSession(
        const ExpandedSession(steps: [], totalS: 0),
        'Morning Flow',
        'Vinyasa yoga',
      );
      expect(d.title, 'Vinyasa yoga');
    });

    test('title from planTitle when discipline null', () {
      final d = workoutDraftFromSession(
        const ExpandedSession(steps: [], totalS: 0),
        'Morning Flow',
        null,
      );
      expect(d.title, 'Morning Flow');
    });

    test('whitespace-only discipline falls back to planTitle', () {
      final d = workoutDraftFromSession(
        const ExpandedSession(steps: [], totalS: 0),
        'Morning Flow',
        '   ',
      );
      expect(d.title, 'Morning Flow');
    });

    test('duration_s = totalS when > 0', () {
      final d = workoutDraftFromSession(
        const ExpandedSession(steps: [], totalS: 600),
        'Flow',
        'Yoga',
      );
      expect(d.durationS, 600);
    });

    test('duration_s null when totalS 0', () {
      final d = workoutDraftFromSession(
        const ExpandedSession(steps: [], totalS: 0),
        'Flow',
        'Yoga',
      );
      expect(d.durationS, isNull);
    });

    test('one set per step', () {
      final expanded = ExpandedSession(
        steps: [
          _step(itemId: 'a', movementName: 'Plank', durationS: 30),
          _step(itemId: 'b', movementName: 'Bridge', durationS: 45),
        ],
        totalS: 75,
      );
      final d = workoutDraftFromSession(expanded, 'Flow', 'Yoga');
      expect(d.sets.length, 2);
      expect(d.sets[0].exerciseName, 'Plank');
      expect(d.sets[0].durationS, 30);
      expect(d.sets[0].reps, isNull);
      expect(d.sets[1].exerciseName, 'Bridge');
      expect(d.sets[1].durationS, 45);
    });

    test('per-side step -> two sets', () {
      final expanded = ExpandedSession(
        steps: [
          _step(
              itemId: 'a',
              movementName: 'Lunge',
              durationS: 30,
              side: SessionSide.left),
          _step(
              itemId: 'a',
              movementName: 'Lunge',
              durationS: 30,
              side: SessionSide.right),
        ],
        totalS: 60,
      );
      final d = workoutDraftFromSession(expanded, 'Flow', 'Yoga');
      expect(d.sets.length, 2);
      expect(d.sets[0].exerciseName, 'Lunge');
      expect(d.sets[1].exerciseName, 'Lunge');
      expect(d.sets[0].durationS, 30);
      expect(d.sets[1].durationS, 30);
    });

    test('reps step carries reps, null duration', () {
      final expanded = ExpandedSession(
        steps: [
          _step(
            movementName: 'Push-up',
            kind: SessionItemKind.reps,
            durationS: null,
            reps: 12,
          ),
        ],
        totalS: 0,
      );
      final d = workoutDraftFromSession(expanded, 'Flow', 'Yoga');
      expect(d.sets.length, 1);
      expect(d.sets[0].exerciseName, 'Push-up');
      expect(d.sets[0].durationS, isNull);
      expect(d.sets[0].reps, 12);
    });
  });
}
