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
}
