/// Live cutoff ETA — the SPECTATOR-side projection. From a runner's current
/// distance-along-route + recent pace, find the next cutoff ahead and project
/// whether they'll make it (`on` / `tight` / `behind`).
///
/// Sibling of `checkpoint_projection.dart`: that one grades a race-director's
/// runner from logged aid-station CROSSINGS; this one is the family-at-home view
/// driven by a single live position fix + recent pace. They share the tight
/// threshold ([cutoffTightS], re-exported here) so "tight" means the same span
/// on both surfaces.
///
/// The honesty rule that justifies the extra status: when the live fix is
/// **stale**, return [LiveCutoffStatus.unknown] with a null ETA rather than
/// fabricate an arrival off an 18h-old position — a lost-signal runner must not
/// read as "on pace". An unknown/zero recent pace is treated the same way.
///
/// The projection is deliberately FLAT pace (no grade adjustment) — the same
/// honest simplification `checkpoint_projection.dart` makes; a future refinement
/// can fold in `gradeFactor`. Twin of
/// `apps/web/src/lib/runs/live_cutoff_eta.ts` — keep logic, edge cases, and
/// test count in lockstep.
import 'roadbook.dart' show RoadbookLeg, cutoffTightS;

export 'roadbook.dart' show cutoffTightS;

enum LiveCutoffStatus { on, tight, behind, unknown }

class LiveCutoffCheckpoint {
  final String kind;
  final String label;
  const LiveCutoffCheckpoint({required this.kind, required this.label});
}

class LiveCutoffEta {
  /// The next cutoff checkpoint ahead, or null when none remain (hide the card).
  final LiveCutoffCheckpoint? checkpoint;

  /// Distance from the runner to that cutoff, metres (0 when no checkpoint).
  final double distanceToM;

  /// Projected arrival as elapsed seconds from start; null when unknown.
  final double? projectedArrivalElapsedS;

  /// limitElapsedS - projectedArrival; null when unknown.
  final double? marginS;
  final LiveCutoffStatus status;

  const LiveCutoffEta({
    required this.checkpoint,
    required this.distanceToM,
    required this.projectedArrivalElapsedS,
    required this.marginS,
    required this.status,
  });
}

LiveCutoffEta nextCutoffEta({
  required double distAlongRouteM,
  required double elapsedS,
  required double? recentPaceSecPerKm,
  required List<RoadbookLeg> legs,
  required bool stale,
}) {
  final ahead = legs
      .where((l) => l.cutoff != null && l.cumDistM > distAlongRouteM)
      .toList()
    ..sort((a, b) => a.cumDistM.compareTo(b.cumDistM));

  if (ahead.isEmpty) {
    return const LiveCutoffEta(
      checkpoint: null,
      distanceToM: 0,
      projectedArrivalElapsedS: null,
      marginS: null,
      status: LiveCutoffStatus.unknown,
    );
  }

  final leg = ahead.first;
  final checkpoint = leg.kind != null
      ? LiveCutoffCheckpoint(kind: leg.kind!, label: leg.label)
      : const LiveCutoffCheckpoint(kind: 'cutoff', label: '');
  final distanceToM = leg.cumDistM - distAlongRouteM;

  if (stale || recentPaceSecPerKm == null || recentPaceSecPerKm <= 0) {
    return LiveCutoffEta(
      checkpoint: checkpoint,
      distanceToM: distanceToM,
      projectedArrivalElapsedS: null,
      marginS: null,
      status: LiveCutoffStatus.unknown,
    );
  }

  final projectedArrivalElapsedS =
      elapsedS + (distanceToM / 1000) * recentPaceSecPerKm;
  final marginS = leg.cutoff!.limitElapsedS - projectedArrivalElapsedS;
  final status = marginS < 0
      ? LiveCutoffStatus.behind
      : marginS < cutoffTightS
          ? LiveCutoffStatus.tight
          : LiveCutoffStatus.on;

  return LiveCutoffEta(
    checkpoint: checkpoint,
    distanceToM: distanceToM,
    projectedArrivalElapsedS: projectedArrivalElapsedS,
    marginS: marginS,
    status: status,
  );
}
