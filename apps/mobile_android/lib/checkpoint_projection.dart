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

/// Grade one arrival against one cutoff, or null when the margin is not a
/// number.
///
/// The ladder is `marginS < 0 ? miss : marginS < tight ? tight : safe`, and a
/// NaN margin fails BOTH comparisons and lands on the optimistic terminal
/// branch -- so a crossing nothing could time was reported to a race director
/// as `safe`, with a NaN margin beside it (decisions § 1225). On a cutoff
/// board the only honest answer about an ungradeable crossing is no answer:
/// [ProjectionLeg.cutoff] is already nullable.
CutoffVerdict? _gradeCutoff(int cutoffS, double arrivalS) {
  final marginS = cutoffS - arrivalS;
  if (!marginS.isFinite) return null;
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
  // Tie-break on the ORIGINAL index, which makes this sort stable and so
  // reproduces web's Array.prototype.sort (stable since ES2019) exactly.
  // Dart's List.sort is insertion sort at <= 32 elements but unstable
  // dual-pivot quicksort above, so two co-located checkpoints came out in a
  // different order on the two platforms once the field passed 33 — and
  // `ordered.last` is what decides whether a runner reads as `racing` or
  // `finished`. Sorting by id instead would be deterministic but would NOT
  // match web, which preserves input order among equals.
  final indexed = <({int index, ProjectionCheckpoint cp})>[
    for (var i = 0; i < checkpoints.length; i++)
      (
        index: i,
        cp: ProjectionCheckpoint(
          id: checkpoints[i].id,
          positionM: checkpoints[i].positionM.isFinite
              ? (checkpoints[i].positionM < 0 ? 0 : checkpoints[i].positionM)
              : 0,
          cutoffElapsedS: checkpoints[i].cutoffElapsedS,
        ),
      ),
  ]..sort((a, b) {
      final byPosition = a.cp.positionM.compareTo(b.cp.positionM);
      return byPosition != 0 ? byPosition : a.index.compareTo(b.index);
    });
  final ordered = [for (final e in indexed) e.cp];

  final byId = <String, double>{};
  for (final x in crossings) {
    // A crossing whose elapsed time is not a number is not a crossing this
    // module can say anything about -- the same sanitisation [positionM] gets
    // one block up. Admitting it made the runner `reached` at that checkpoint
    // and every comparison downstream answered false, which the cutoff ladder
    // reads as `safe`.
    if (!x.elapsedS.isFinite) continue;
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

  // `lastElapsedS > 0` matters as much as `coveredM > 0`. A stamp at or before
  // the race start (a volunteer's tablet running fast, or the RD firing Go
  // after a start-area checkpoint already scanned) clamps to elapsed 0, and a
  // pace of exactly 0 is finite — so every remaining checkpoint projected an
  // arrival of 0 and graded "safe" with the full cutoff as its margin. An
  // unusable sample must leave future cutoffs ungraded, as a runner with no
  // crossings at all already does.
  final paceSPerM = lastElapsedS != null && lastElapsedS > 0 && coveredM > 0
      ? lastElapsedS / coveredM
      : null;

  var blownCutoff = false;
  final legs = ordered.map((c) {
    final actual = byId[c.id];
    final reached = actual != null;
    double? projected;
    if (!reached && paceSPerM != null && c.positionM >= coveredM) {
      projected = paceSPerM * c.positionM;
    }

    CutoffVerdict? cutoff;
    if (c.cutoffElapsedS != null) {
      final arrival = reached ? actual : projected;
      if (arrival != null) {
        cutoff = _gradeCutoff(c.cutoffElapsedS!, arrival);
        if (reached && cutoff?.status == CutoffStatus.miss) blownCutoff = true;
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
