import 'package:flutter_test/flutter_test.dart';
import '../lib/session_steps.dart';

SessionPlanItemInput _item({
  String id = 'i',
  String? blockId,
  int position = 0,
  String movementName = 'Pose',
  SessionItemKind kind = SessionItemKind.hold,
  int? durationS = 30,
  int? reps,
  bool perSide = false,
  String? tempo,
  String? cue,
}) {
  return SessionPlanItemInput(
    id: id,
    blockId: blockId,
    position: position,
    movementName: movementName,
    kind: kind,
    durationS: durationS,
    reps: reps,
    perSide: perSide,
    tempo: tempo,
    cue: cue,
  );
}

void main() {
  test('block flatten: blocks in position order, items in position order within',
      () {
    final plan = SessionPlanInput(
      blocks: const [
        SessionPlanBlockInput(id: 'b2', position: 2, name: 'Standing'),
        SessionPlanBlockInput(id: 'b1', position: 1, name: 'Warm-up'),
      ],
      items: [
        _item(
            id: 'b2i1',
            blockId: 'b2',
            position: 1,
            movementName: 'Warrior II',
            durationS: 60),
        _item(
            id: 'b1i2',
            blockId: 'b1',
            position: 2,
            movementName: 'Cat-Cow',
            durationS: 20),
        _item(
            id: 'b1i1',
            blockId: 'b1',
            position: 1,
            movementName: 'Child',
            durationS: 30),
      ],
    );
    final out = expandSessionSteps(plan);
    expect(out.steps.map((s) => s.movementName).toList(),
        ['Child', 'Cat-Cow', 'Warrior II']);
    expect(out.steps.map((s) => s.cumulativeS).toList(), [30, 50, 110]);
    expect(out.totalS, 110);
  });

  test('per-side split: a perSide item becomes consecutive Left then Right steps',
      () {
    final plan = SessionPlanInput(
      blocks: const [],
      items: [
        _item(
            id: 'lunge',
            movementName: 'Low Lunge',
            durationS: 45,
            perSide: true),
      ],
    );
    final out = expandSessionSteps(plan);
    expect(out.steps.length, 2);
    expect(out.steps.map((s) => s.movementName).toList(),
        ['Low Lunge (Left)', 'Low Lunge (Right)']);
    expect(out.steps.map((s) => s.side).toList(),
        [SessionSide.left, SessionSide.right]);
    expect(out.steps.map((s) => s.cumulativeS).toList(), [45, 90]);
    expect(out.totalS, 90);
  });

  test('reps step with no duration contributes 0 to the time estimate', () {
    final plan = SessionPlanInput(
      blocks: const [],
      items: [
        _item(
            id: 'hold',
            movementName: 'Plank',
            kind: SessionItemKind.hold,
            durationS: 60),
        _item(
            id: 'roll',
            position: 1,
            movementName: 'Roll-Up',
            kind: SessionItemKind.reps,
            durationS: null,
            reps: 10),
        _item(
            id: 'flow',
            position: 2,
            movementName: 'Vinyasa',
            kind: SessionItemKind.flow,
            durationS: 15),
      ],
    );
    final out = expandSessionSteps(plan);
    expect(out.steps.map((s) => s.cumulativeS).toList(), [60, 60, 75]);
    expect(out.steps[1].reps, 10);
    expect(out.steps[1].durationS, null);
    expect(out.totalS, 75);
  });

  test('empty plan: no blocks, no items -> no steps, zero total', () {
    final out = expandSessionSteps(
        const SessionPlanInput(blocks: [], items: []));
    expect(out.steps, isEmpty);
    expect(out.totalS, 0);
  });

  test('single item: one non-per-side hold -> one step', () {
    final out = expandSessionSteps(
      SessionPlanInput(
        blocks: const [],
        items: [
          _item(
              id: 'savasana',
              movementName: 'Savasana',
              durationS: 300,
              cue: 'Soften'),
        ],
      ),
    );
    expect(out.steps.length, 1);
    expect(out.steps[0].movementName, 'Savasana');
    expect(out.steps[0].side, null);
    expect(out.steps[0].cue, 'Soften');
    expect(out.steps[0].cumulativeS, 300);
    expect(out.totalS, 300);
  });
}
