import 'package:flutter_test/flutter_test.dart';
import '../lib/checkpoint_projection.dart';

void main() {
  final cps = <ProjectionCheckpoint>[
    const ProjectionCheckpoint(id: 'a', positionM: 10000, cutoffElapsedS: null),
    const ProjectionCheckpoint(id: 'b', positionM: 20000, cutoffElapsedS: 7200),
    const ProjectionCheckpoint(id: 'c', positionM: 40000, cutoffElapsedS: 18000),
  ];

  ProjectionLeg legFor(RunnerProjection p, String id) =>
      p.legs.firstWhere((l) => l.checkpointId == id);

  test('no crossings → racing, no pace, nothing reached', () {
    final p = projectRunner(cps, const []);
    expect(p.status, RunnerStatus.racing);
    expect(p.paceSPerM, isNull);
    expect(p.lastCheckpointId, isNull);
    expect(p.coveredM, 0);
    expect(p.legs.every((l) => !l.reached), isTrue);
    expect(p.legs.every((l) => l.projectedElapsedS == null), isTrue);
  });

  test('one crossing sets pace and last checkpoint', () {
    final p = projectRunner(
        cps, const [ProjectionCrossing(checkpointId: 'a', elapsedS: 3600)]);
    expect(p.lastCheckpointId, 'a');
    expect(p.lastElapsedS, 3600);
    expect(p.coveredM, 10000);
    expect(p.paceSPerM, 3600 / 10000);
    expect(p.status, RunnerStatus.racing);
  });

  test('future checkpoints are linearly projected from pace', () {
    final p = projectRunner(
        cps, const [ProjectionCrossing(checkpointId: 'a', elapsedS: 3600)]);
    expect(legFor(p, 'b').projectedElapsedS, 0.36 * 20000);
    expect(legFor(p, 'c').projectedElapsedS, 0.36 * 40000);
  });

  test('projected arrival exactly on the cutoff is tight, not miss', () {
    final p = projectRunner(
        cps, const [ProjectionCrossing(checkpointId: 'a', elapsedS: 3600)]);
    final b = legFor(p, 'b');
    expect(b.cutoff!.marginS, 0);
    expect(b.cutoff!.status, CutoffStatus.tight);
  });

  test('comfortable projection is safe', () {
    final p = projectRunner(
        cps, const [ProjectionCrossing(checkpointId: 'a', elapsedS: 1800)]);
    final b = legFor(p, 'b');
    expect(b.cutoff!.status, CutoffStatus.safe);
    expect(b.cutoff!.marginS > cutoffTightS, isTrue);
  });

  test('slow projection blows a future cutoff (miss), still racing', () {
    final p = projectRunner(
        cps, const [ProjectionCrossing(checkpointId: 'a', elapsedS: 5400)]);
    final b = legFor(p, 'b');
    expect(b.cutoff!.status, CutoffStatus.miss);
    expect(b.cutoff!.marginS < 0, isTrue);
    expect(p.status, RunnerStatus.racing);
  });

  test('a reached checkpoint past its cutoff is a DNF', () {
    final p = projectRunner(cps, const [
      ProjectionCrossing(checkpointId: 'a', elapsedS: 3600),
      ProjectionCrossing(checkpointId: 'b', elapsedS: 7500),
    ]);
    final b = legFor(p, 'b');
    expect(b.reached, isTrue);
    expect(b.cutoff!.status, CutoffStatus.miss);
    expect(p.status, RunnerStatus.dnf);
  });

  test('reaching the last checkpoint within cutoff is finished', () {
    final p = projectRunner(cps, const [
      ProjectionCrossing(checkpointId: 'a', elapsedS: 3600),
      ProjectionCrossing(checkpointId: 'b', elapsedS: 7000),
      ProjectionCrossing(checkpointId: 'c', elapsedS: 16000),
    ]);
    expect(p.status, RunnerStatus.finished);
    expect(p.lastCheckpointId, 'c');
  });

  test('checkpoints are sorted by position before projecting', () {
    final unsorted = <ProjectionCheckpoint>[cps[2], cps[0], cps[1]];
    final p = projectRunner(unsorted,
        const [ProjectionCrossing(checkpointId: 'a', elapsedS: 3600)]);
    expect(p.legs.map((l) => l.checkpointId).toList(), ['a', 'b', 'c']);
  });

  test('a reached checkpoint has no projection, only an actual', () {
    final p = projectRunner(
        cps, const [ProjectionCrossing(checkpointId: 'a', elapsedS: 3600)]);
    final a = legFor(p, 'a');
    expect(a.reached, isTrue);
    expect(a.actualElapsedS, 3600);
    expect(a.projectedElapsedS, isNull);
  });

  test('a cutoff co-located with the last-reached checkpoint is graded on the exact arrival',
      () {
    final coLocated = <ProjectionCheckpoint>[
      const ProjectionCheckpoint(id: 'aid', positionM: 20000, cutoffElapsedS: null),
      const ProjectionCheckpoint(id: 'gate', positionM: 20000, cutoffElapsedS: 7200),
    ];
    final p = projectRunner(coLocated,
        const [ProjectionCrossing(checkpointId: 'aid', elapsedS: 7000)]);
    final gate = legFor(p, 'gate');
    expect(gate.reached, isFalse);
    expect(gate.projectedElapsedS, 7000);
    expect(gate.cutoff, isNotNull);
    expect(gate.cutoff!.marginS, 200);
    expect(gate.cutoff!.status, CutoffStatus.tight);
  });

  test('a crossing stamped at elapsed 0 leaves future cutoffs ungraded, not "safe"', () {
    // A volunteer's tablet running a minute fast (or the RD firing Go after a
    // start-area checkpoint already scanned) clamps to elapsed 0 upstream. Pace
    // then computed as 0 s/m — finite, so every remaining checkpoint projected
    // an arrival of 0 and graded "safe" with the full cutoff as its margin: the
    // board told the race director a runner was clear of every gate ahead.
    final p = projectRunner(
        cps, const [ProjectionCrossing(checkpointId: 'a', elapsedS: 0)]);
    expect(p.paceSPerM, isNull, reason: 'a zero-elapsed sample yields no usable pace');
    for (final leg in p.legs.where((l) => !l.reached)) {
      expect(leg.projectedElapsedS, isNull, reason: leg.checkpointId);
      expect(leg.cutoff, isNull, reason: leg.checkpointId);
    }
  });

  test('a negative elapsed crossing is equally unusable', () {
    final p = projectRunner(
        cps, const [ProjectionCrossing(checkpointId: 'a', elapsedS: -120)]);
    expect(p.paceSPerM, isNull);
    expect(p.legs.where((l) => l.cutoff != null), isEmpty);
  });

  test('the smallest genuinely-positive elapsed still projects', () {
    // The guard must reject only the unusable sample, not clamp real early data:
    // a fast runner through a near-start checkpoint is legitimate.
    final p = projectRunner(
        cps, const [ProjectionCrossing(checkpointId: 'a', elapsedS: 1)]);
    expect(p.paceSPerM, isNotNull);
    final b = legFor(p, 'b');
    expect(b.projectedElapsedS, isNotNull);
    expect(b.cutoff, isNotNull);
  });

  test('a zero-elapsed crossing does not mask a later usable one', () {
    final p = projectRunner(cps, const [
      ProjectionCrossing(checkpointId: 'a', elapsedS: 0),
      ProjectionCrossing(checkpointId: 'b', elapsedS: 7200),
    ]);
    expect(p.paceSPerM, isNotNull);
    expect(p.lastElapsedS, 7200);
  });

  test('co-located checkpoints keep input order past the 32-element cutover', () {
    // Dart's List.sort is insertion sort at <= 32 elements and unstable
    // dual-pivot quicksort above, so a big field could order two co-located
    // checkpoints differently from web's (stable) Array.prototype.sort — and
    // `ordered.last` is what decides `racing` vs `finished`. 34 checkpoints
    // supplied DESCENDING, with `mat` and `gate` sharing 40000 m.
    final checkpoints = <ProjectionCheckpoint>[
      for (var i = 31; i >= 0; i--)
        ProjectionCheckpoint(id: 'cp\$i', positionM: i * 1000.0),
      const ProjectionCheckpoint(id: 'mat', positionM: 40000),
      const ProjectionCheckpoint(id: 'gate', positionM: 40000),
    ];
    final p = projectRunner(
      checkpoints,
      const [ProjectionCrossing(checkpointId: 'mat', elapsedS: 18000)],
    );
    // `mat` precedes `gate` in the input, so it must NOT be the last
    // checkpoint — the runner is still racing, not finished.
    expect(p.status, RunnerStatus.racing);
  });

  test('a crossing with a non-finite elapsed time is not a crossing', () {
    // The board derives elapsed from a parsed wall-clock stamp less the race
    // start, so an unparseable stamp arrives here as NaN. It used to be
    // admitted: the runner read as REACHED at that checkpoint, both cutoff
    // comparisons answered false, and the ladder's terminal branch told a race
    // director `safe` about a crossing nothing could time.
    final p = projectRunner(cps, [
      const ProjectionCrossing(checkpointId: 'b', elapsedS: double.nan),
    ]);
    final b = p.legs.firstWhere((l) => l.checkpointId == 'b');
    expect(b.reached, isFalse);
    expect(b.cutoff, isNull);
    expect(p.lastCheckpointId, isNull);
    expect(p.lastElapsedS, isNull);
    expect(p.paceSPerM, isNull);
    expect(p.status, RunnerStatus.racing);
  });

  test('an unusable stamp on the last checkpoint does not read as finished', () {
    final p = projectRunner(cps, [
      const ProjectionCrossing(checkpointId: 'c', elapsedS: double.infinity),
    ]);
    expect(p.status, RunnerStatus.racing);
    expect(p.legs.every((l) => !l.reached), isTrue);
    expect(p.legs.every((l) => l.cutoff == null), isTrue);
  });

  test('an unusable stamp does not mask a usable one at the same checkpoint', () {
    final p = projectRunner(cps, [
      const ProjectionCrossing(checkpointId: 'b', elapsedS: double.nan),
      const ProjectionCrossing(checkpointId: 'b', elapsedS: 6000),
    ]);
    expect(p.lastElapsedS, 6000);
    expect(
      p.legs.firstWhere((l) => l.checkpointId == 'b').cutoff!.status,
      CutoffStatus.tight,
    );
  });

  // The web twin carries one further case -- a `cutoffElapsedS` that is not a
  // number -- which has no analogue here: [ProjectionCheckpoint.cutoffElapsedS]
  // is a Dart `int?`, so an unusable cutoff cannot reach the grader at all.
}
