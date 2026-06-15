/// Checkpoint cutoff projection — from a runner's actual aid-station crossings,
/// project arrival at every remaining checkpoint and grade each cutoff
/// safe / tight / miss.
///
/// Live-results companion to `roadbook.dart`: the roadbook projects a crew
/// schedule from a goal time BEFORE the race; this projects from the crossings
/// logged DURING it. Both grade cutoffs on the same scale, so [CutoffStatus] +
/// [cutoffTightS] come from `roadbook.dart` rather than being redefined.
///
/// Pace model: average pace from the start to the last checkpoint actually
/// reached, extrapolated linearly to the remaining distance (no grade
/// adjustment yet — a future refinement can fold in `gradeFactor`).
///
/// Shared by the offline volunteer surface + organiser dashboards
/// (race_director_ops.md) and the predictive live tracker. Pure Dart. Twin of
/// `apps/web/src/lib/runs/checkpoint_projection.ts` — keep the projection,
/// cutoff rules, edge cases, and test count in lockstep.
import 'roadbook.dart' show CutoffStatus, cutoffTightS;

export 'roadbook.dart' show CutoffStatus, cutoffTightS;

class ProjectionCheckpoint {
  /// Distance along the course from the start, metres.
  final String id;
  final double positionM;

  /// Cutoff as elapsed seconds from the race start. Null = no cutoff here.
  final int? cutoffElapsedS;

  const ProjectionCheckpoint({
    required this.id,
    required this.positionM,
    this.cutoffElapsedS,
  });
}

class ProjectionCrossing {
  final String checkpointId;

  /// Arrival (in_time) as elapsed seconds from the race start.
  final double elapsedS;

  const ProjectionCrossing({
    required this.checkpointId,
    required this.elapsedS,
  });
}

enum RunnerStatus { racing, finished, dnf }

class CutoffVerdict {
  final double marginS;
  final CutoffStatus status;
  const CutoffVerdict({required this.marginS, required this.status});
}

class ProjectionLeg {
  final String checkpointId;
  final double positionM;
  final bool reached;

  /// Elapsed seconds at the actual crossing, when reached.
  final double? actualElapsedS;

  /// Linearly-projected elapsed seconds, when not yet reached + pace known.
  final double? projectedElapsedS;
  final int? cutoffElapsedS;

  /// Cutoff grade against the actual (reached) or projected (future) arrival.
  final CutoffVerdict? cutoff;

  const ProjectionLeg({
    required this.checkpointId,
    required this.positionM,
    required this.reached,
    required this.actualElapsedS,
    required this.projectedElapsedS,
    required this.cutoffElapsedS,
    required this.cutoff,
  });
}

class RunnerProjection {
  final List<ProjectionLeg> legs;
  final String? lastCheckpointId;
  final double? lastElapsedS;

  /// Distance covered to the last reached checkpoint, metres.
  final double coveredM;

  /// Average seconds per metre to the last reached checkpoint. Null until 1+.
  final double? paceSPerM;
  final RunnerStatus status;

  const RunnerProjection({
    required this.legs,
    required this.lastCheckpointId,
    required this.lastElapsedS,
    required this.coveredM,
    required this.paceSPerM,
    required this.status,
  });
}

CutoffVerdict _gradeCutoff(int cutoffS, double arrivalS) {
  final marginS = cutoffS - arrivalS;
  return CutoffVerdict(
    marginS: marginS,
    status: marginS < 0
        ? CutoffStatus.miss
        : marginS < cutoffTightS
            ? CutoffStatus.tight
            : CutoffStatus.safe,
  );
}

/// Project a single runner from their crossings. [checkpoints] need not be
/// pre-sorted; a NaN/negative position is treated as 0.
RunnerProjection projectRunner(
  List<ProjectionCheckpoint> checkpoints,
  List<ProjectionCrossing> crossings,
) {
  final ordered = checkpoints
      .map((c) => ProjectionCheckpoint(
            id: c.id,
            positionM:
                c.positionM.isFinite ? (c.positionM < 0 ? 0 : c.positionM) : 0,
            cutoffElapsedS: c.cutoffElapsedS,
          ))
      .toList()
    ..sort((a, b) => a.positionM.compareTo(b.positionM));

  final byId = <String, double>{};
  for (final x in crossings) {
    final prev = byId[x.checkpointId];
    if (prev == null || x.elapsedS < prev) byId[x.checkpointId] = x.elapsedS;
  }

  String? lastCheckpointId;
  double? lastElapsedS;
  var coveredM = 0.0;
  for (final c in ordered) {
    final e = byId[c.id];
    if (e == null) continue;
    if (lastElapsedS == null || c.positionM >= coveredM) {
      lastCheckpointId = c.id;
      lastElapsedS = e;
      coveredM = c.positionM;
    }
  }

  final paceSPerM =
      lastElapsedS != null && coveredM > 0 ? lastElapsedS / coveredM : null;

  var blownCutoff = false;
  final legs = ordered.map((c) {
    final actual = byId[c.id];
    final reached = actual != null;
    double? projected;
    if (!reached && paceSPerM != null && c.positionM > coveredM) {
      projected = paceSPerM * c.positionM;
    }

    CutoffVerdict? cutoff;
    if (c.cutoffElapsedS != null) {
      final arrival = reached ? actual : projected;
      if (arrival != null) {
        cutoff = _gradeCutoff(c.cutoffElapsedS!, arrival);
        if (reached && cutoff.status == CutoffStatus.miss) blownCutoff = true;
      }
    }

    return ProjectionLeg(
      checkpointId: c.id,
      positionM: c.positionM,
      reached: reached,
      actualElapsedS: reached ? actual : null,
      projectedElapsedS: projected,
      cutoffElapsedS: c.cutoffElapsedS,
      cutoff: cutoff,
    );
  }).toList();

  final reachedLast =
      ordered.isNotEmpty && lastCheckpointId == ordered.last.id;
  final status = blownCutoff
      ? RunnerStatus.dnf
      : reachedLast
          ? RunnerStatus.finished
          : RunnerStatus.racing;

  return RunnerProjection(
    legs: legs,
    lastCheckpointId: lastCheckpointId,
    lastElapsedS: lastElapsedS,
    coveredM: coveredM,
    paceSPerM: paceSPerM,
    status: status,
  );
}
