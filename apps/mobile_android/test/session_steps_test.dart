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
        ['Low Lunge', 'Low Lunge']);
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

  SessionStep _step({
    String itemId = 'i',
    String movementName = 'Pose',
    SessionItemKind kind = SessionItemKind.hold,
    int? durationS = 30,
    int? reps,
    String? tempo,
    String? cue,
    SessionSide? side,
    int cumulativeS = 30,
  }) {
    return SessionStep(
      itemId: itemId,
      movementName: movementName,
      kind: kind,
      durationS: durationS,
      reps: reps,
      tempo: tempo,
      cue: cue,
      side: side,
      cumulativeS: cumulativeS,
    );
  }

  SessionStepResult _result({
    String itemId = 'i',
    String movementName = 'Pose',
    SessionItemKind kind = SessionItemKind.hold,
    SessionSide? side,
    int? targetDurationS = 30,
    int? actualDurationS = 30,
    SessionStepStatus status = SessionStepStatus.completed,
  }) {
    return SessionStepResult(
      itemId: itemId,
      movementName: movementName,
      kind: kind,
      side: side,
      targetDurationS: targetDurationS,
      actualDurationS: actualDurationS,
      status: status,
    );
  }

  test('adherence: all steps completed -> completed verdict, pct 1.0', () {
    final steps = [
      _step(itemId: 'a'),
      _step(itemId: 'b'),
      _step(itemId: 'c'),
    ];
    final results = [
      _result(itemId: 'a'),
      _result(itemId: 'b'),
      _result(itemId: 'c'),
    ];
    final out = computeSessionAdherence(steps, results);
    expect(out.completedSteps, 3);
    expect(out.totalSteps, 3);
    expect(out.adherencePct, 1.0);
    expect(out.verdict, SessionVerdict.completed);
  });

  test('adherence: zero completed -> abandoned verdict', () {
    final steps = [_step(itemId: 'a'), _step(itemId: 'b')];
    final results = [
      _result(
          itemId: 'a',
          status: SessionStepStatus.skipped,
          actualDurationS: null),
      _result(
          itemId: 'b',
          status: SessionStepStatus.skipped,
          actualDurationS: null),
    ];
    final out = computeSessionAdherence(steps, results);
    expect(out.completedSteps, 0);
    expect(out.adherencePct, 0.0);
    expect(out.verdict, SessionVerdict.abandoned);
  });

  test('adherence: 80% boundary -> completed verdict', () {
    final steps = ['a', 'b', 'c', 'd', 'e']
        .map((id) => _step(itemId: id))
        .toList();
    final results = [
      _result(itemId: 'a'),
      _result(itemId: 'b'),
      _result(itemId: 'c'),
      _result(itemId: 'd'),
      _result(
          itemId: 'e',
          status: SessionStepStatus.skipped,
          actualDurationS: null),
    ];
    final out = computeSessionAdherence(steps, results);
    expect(out.completedSteps, 4);
    expect(out.adherencePct, 0.8);
    expect(out.verdict, SessionVerdict.completed);
  });

  test('adherence: below 80% -> partial verdict', () {
    final steps =
        ['a', 'b', 'c', 'd'].map((id) => _step(itemId: id)).toList();
    final results = [
      _result(itemId: 'a'),
      _result(itemId: 'b'),
      _result(
          itemId: 'c',
          status: SessionStepStatus.skipped,
          actualDurationS: null),
      _result(
          itemId: 'd',
          status: SessionStepStatus.skipped,
          actualDurationS: null),
    ];
    final out = computeSessionAdherence(steps, results);
    expect(out.completedSteps, 2);
    expect(out.adherencePct, 0.5);
    expect(out.verdict, SessionVerdict.partial);
  });

  test('adherence: a skipped step counts toward total but not completed', () {
    final steps = [_step(itemId: 'a'), _step(itemId: 'b')];
    final results = [
      _result(itemId: 'a'),
      _result(
          itemId: 'b',
          status: SessionStepStatus.skipped,
          actualDurationS: null),
    ];
    final out = computeSessionAdherence(steps, results);
    expect(out.totalSteps, 2);
    expect(out.completedSteps, 1);
    expect(out.adherencePct, 0.5);
    expect(out.verdict, SessionVerdict.partial);
  });
}
