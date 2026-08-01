import 'dart:math' as math;
import 'dart:typed_data';

import 'roadbook.dart'
    show CutoffStatus, Roadbook, RoadbookLeg;
import 'sim_watch_sync.dart' show crc32;

/// Pure Dart mirror of the custom watch's `watch_core::roadbook_store` RBK1
/// wire format — the phone → watch roadbook + cut-off-schedule push.
///
/// The phone builds the roadbook (`roadbook.dart` needs the route polyline the
/// watch doesn't hold) and pushes the numeric schedule as a fixed
/// little-endian frame:
///
///   magic("RBK1", 4) | version(1) | checkpoint_count(1, u8) |
///   cutoff_count(1, u8) | flags(1) | checkpoint[N] | cutoff[M] |
///   crc32(4, u32 LE)
///
/// where each checkpoint is `cum_dist_m(4, u32 LE) | leg_dist_m(4, u32 LE) |
/// projected_elapsed_s(4, u32 LE) | cutoff(1, u8) | flags(1, u8)` — the cutoff
/// byte naming [WatchCutoffStatus] (0 none / 1 safe / 2 tight / 3 miss) and the
/// flags byte carrying [kCheckpointFlagRefill] — and each cut-off leg is
/// `cum_dist_m(4, u32 LE) | limit_elapsed_s(4, u32 LE)`.
///
/// Distances travel as whole metres: a metre is four orders below the GPS noise
/// the watch's along-course projection carries, and a `u32` covers 4,294 km of
/// course. Checkpoints carry no name — the firmware's checkpoint is a `Copy`
/// struct because the phone holds the names and the 168x96 panel has no room
/// for them.
///
/// Both series ride one frame and neither is derivable from the other: a
/// checkpoint's `cutoff` is this side's *verdict* against its own goal-time
/// projection, while a [WatchCutoffLeg] is the *limit itself*, which is what the
/// watch needs to project a live arrival off the runner's own recent pace. One
/// frame being the whole schedule also means a re-push replaces it, so the
/// watch can never describe one race on its Roadbook page while projecting
/// another on its CutoffEta page.
///
/// The CRC32 trailer is mandatory from v1 (the CRS1 v3 reasoning): any
/// monotonic distance/time pair is a legal schedule, so a flipped byte decodes
/// as a plausible *different* one and would be shown to the runner as their
/// cut-off margin and their nap budget. There is no pre-checksum version to
/// fall back to, and the firmware refuses anything but the current version.
///
/// A schedule past either cap is **refused, not trimmed** — the watch's setters
/// cap rather than grow, and dropping the tail would hide the cut-offs nearest
/// the finish, which are the ones that end races. Trimming is this side's job,
/// where there is a runner to tell. An empty schedule is a legal frame and
/// means *clear*.
///
/// A whole schedule can exceed one BLE write, so [chunkRoadbook] splits the
/// frame into ordered `offset(2, u16 LE) | payload` chunks the watch's
/// `RoadbookAssembler` reassembles.
///
/// Deliberately pure — no BLE, no platform channels — so [encodeRoadbook] is
/// unit-testable against the frozen golden vector shared with the Rust tests,
/// reusing the run-sync module's [crc32] like `watch_course.dart` /
/// `watch_workout.dart` / `watch_settings.dart`.
const int _roadbookVersion = 0x01;

/// Per-checkpoint flag: this checkpoint offers water/food, so the watch's Fuel
/// page treats it as a refill point. Mirrors the firmware's
/// `roadbook_store::CHECKPOINT_FLAG_REFILL`.
const int kCheckpointFlagRefill = 1 << 0;

/// Tier-1 capacities — mirror `watch_core::record::MAX_PUSHED_LEGS` and
/// `MAX_CUTOFF_LEGS`.
const int kMaxRoadbookCheckpoints = 16;
const int kMaxRoadbookCutoffs = 16;

const int _roadbookHeaderLen = 8;
const int _roadbookCheckpointLen = 14;
const int _roadbookCutoffLen = 8;
const int _roadbookCrcLen = 4;

/// Max payload per chunk = the watch's `ROADBOOK_CHUNK_CAP` (244) minus the
/// 2-byte offset header each chunk carries.
const int kRoadbookChunkPayloadMax = 242;

/// The largest metre distance the wire's `u32` carries.
const int _maxWireMetres = 0xFFFFFFFF;

/// A checkpoint's cut-off verdict, as the phone computed it against its own
/// goal-time projection. **Declaration order is the wire contract** — the byte
/// is `index + 1`, and 0 means the checkpoint carries no cut-off at all.
enum WatchCutoffStatus { safe, tight, miss }

/// One roadbook checkpoint: where it is along the course, the leg that arrives
/// there, when the phone's schedule projects the runner reaching it, its cut-off
/// verdict if it has one, and whether it is a refill point.
class WatchRoadbookCheckpoint {
  final double cumDistanceM;
  final double legDistanceM;
  final int projectedElapsedSec;
  final WatchCutoffStatus? cutoff;
  final bool isRefill;

  const WatchRoadbookCheckpoint({
    required this.cumDistanceM,
    required this.legDistanceM,
    required this.projectedElapsedSec,
    this.cutoff,
    this.isRefill = false,
  });
}

/// One cut-off: the distance along the course and the elapsed-seconds limit to
/// reach it. The raw limit, not a verdict — the watch projects a live arrival
/// against it from the runner's own recent pace.
class WatchCutoffLeg {
  final double cumDistanceM;
  final int limitElapsedSec;

  const WatchCutoffLeg({
    required this.cumDistanceM,
    required this.limitElapsedSec,
  });
}

int _statusCode(WatchCutoffStatus? status) =>
    status == null ? 0 : status.index + 1;

/// A metre distance as the wire's `u32`. Throws when it cannot be represented —
/// non-finite, negative, or past [_maxWireMetres] — rather than clamping, which
/// would push a plausible wrong distance.
int _metres(double m, String what) {
  if (!m.isFinite || m < 0) {
    throw ArgumentError('$what must be a non-negative finite distance, got $m');
  }
  final rounded = m.round();
  if (rounded > _maxWireMetres) {
    throw ArgumentError('$what $rounded m exceeds the wire');
  }
  return rounded;
}

int _seconds(int s, String what) {
  if (s < 0 || s > _maxWireMetres) {
    throw ArgumentError('$what $s s exceeds the wire');
  }
  return s;
}

/// Encode a roadbook + cut-off schedule into an RBK1 v1 frame, sealed with the
/// CRC32 trailer the watch checks before it will load the schedule. Throws when
/// either series is over its cap ([kMaxRoadbookCheckpoints] /
/// [kMaxRoadbookCutoffs] — refused, not trimmed, matching the firmware's own
/// `encode`) or when a distance or elapsed time can't be carried by the wire.
/// Both series empty is legal and clears the watch's schedule.
Uint8List encodeRoadbook(
  List<WatchRoadbookCheckpoint> checkpoints,
  List<WatchCutoffLeg> cutoffs,
) {
  if (checkpoints.length > kMaxRoadbookCheckpoints) {
    throw ArgumentError(
      'roadbook takes at most $kMaxRoadbookCheckpoints checkpoints, '
      'got ${checkpoints.length}',
    );
  }
  if (cutoffs.length > kMaxRoadbookCutoffs) {
    throw ArgumentError(
      'roadbook takes at most $kMaxRoadbookCutoffs cut-offs, '
      'got ${cutoffs.length}',
    );
  }
  final len =
      _roadbookHeaderLen +
      checkpoints.length * _roadbookCheckpointLen +
      cutoffs.length * _roadbookCutoffLen +
      _roadbookCrcLen;
  final out = ByteData(len);
  out.setUint8(0, 0x52); // R
  out.setUint8(1, 0x42); // B
  out.setUint8(2, 0x4b); // K
  out.setUint8(3, 0x31); // 1
  out.setUint8(4, _roadbookVersion);
  out.setUint8(5, checkpoints.length);
  out.setUint8(6, cutoffs.length);
  out.setUint8(7, 0);

  var off = _roadbookHeaderLen;
  for (final cp in checkpoints) {
    out.setUint32(
      off,
      _metres(cp.cumDistanceM, 'checkpoint distance'),
      Endian.little,
    );
    out.setUint32(
      off + 4,
      _metres(cp.legDistanceM, 'checkpoint leg distance'),
      Endian.little,
    );
    out.setUint32(
      off + 8,
      _seconds(cp.projectedElapsedSec, 'projected arrival'),
      Endian.little,
    );
    out.setUint8(off + 12, _statusCode(cp.cutoff));
    out.setUint8(off + 13, cp.isRefill ? kCheckpointFlagRefill : 0);
    off += _roadbookCheckpointLen;
  }
  for (final leg in cutoffs) {
    out.setUint32(
      off,
      _metres(leg.cumDistanceM, 'cut-off distance'),
      Endian.little,
    );
    out.setUint32(
      off + 4,
      _seconds(leg.limitElapsedSec, 'cut-off limit'),
      Endian.little,
    );
    off += _roadbookCutoffLen;
  }

  final frame = out.buffer.asUint8List();
  out.setUint32(off, crc32(frame.sublist(0, off)), Endian.little);
  return frame;
}

/// Split an RBK1 [frame] into ordered BLE chunks — each is
/// `offset(2, u16 LE) | payload` — so the watch's `RoadbookAssembler` can
/// rebuild it. The phone writes these in order to the `roadbook`
/// characteristic.
List<Uint8List> chunkRoadbook(
  Uint8List frame, {
  int payloadMax = kRoadbookChunkPayloadMax,
}) {
  final chunks = <Uint8List>[];
  var offset = 0;
  while (offset < frame.length) {
    final end = math.min(offset + payloadMax, frame.length);
    final chunk = Uint8List(2 + (end - offset));
    final view = ByteData.sublistView(chunk);
    view.setUint16(0, offset, Endian.little);
    chunk.setRange(2, chunk.length, frame, offset);
    chunks.add(chunk);
    offset = end;
  }
  return chunks;
}

/// Why a route's roadbook cannot be sent to the watch.
enum WatchRoadbookRefusal {
  /// The route has no course distance, so there is nothing to schedule against.
  noSchedule,

  /// More cut-offs than the wire carries, once the schedule's end is counted.
  /// Cut-offs are the one series that is never reduced — see
  /// [watchRoadbookFromRoadbook].
  tooManyCutoffs,
}

/// A roadbook shaped for the watch: the checkpoints and cut-off legs an `RBK1`
/// push will carry, how many the route started with, how many cut-off markers
/// could not be resolved into a limit at all — or the reason it cannot be sent.
///
/// [checkpoints] and [refusal] are exclusive, mirroring `WatchCourseResult`. A
/// caller that gets checkpoints has a schedule it can push; a caller that gets
/// a refusal has something to say to the runner, never a silently short one.
class WatchRoadbookResult {
  final List<WatchRoadbookCheckpoint>? checkpoints;
  final List<WatchCutoffLeg>? cutoffs;

  /// Schedulable stops on the route before any reduction — the denominator
  /// behind "sent N of M checkpoints".
  final int sourceCheckpointCount;
  final int sourceCutoffCount;

  /// Markers of kind `cutoff` that carry no usable limit — a clock-only cut-off
  /// with no start time to resolve it against. Surfaced rather than swallowed:
  /// a cut-off that quietly fails to reach the watch is the one failure mode
  /// this whole schedule exists to prevent.
  final int unresolvedCutoffCount;

  final WatchRoadbookRefusal? refusal;

  const WatchRoadbookResult({
    required this.checkpoints,
    required this.cutoffs,
    required this.sourceCheckpointCount,
    required this.sourceCutoffCount,
    required this.unresolvedCutoffCount,
  }) : refusal = null;

  const WatchRoadbookResult.refused(
    this.refusal, {
    required this.sourceCheckpointCount,
    required this.sourceCutoffCount,
    required this.unresolvedCutoffCount,
  })  : checkpoints = null,
        cutoffs = null;

  /// Whether the checkpoint series had to be thinned to fit the watch's cap.
  bool get reduced =>
      checkpoints != null && checkpoints!.length < sourceCheckpointCount;
}

/// One schedulable stop, pre-rounded to the keys the wire actually carries so
/// collisions are judged on the bytes the watch will see, not on the doubles.
class _Stop {
  final RoadbookLeg leg;
  final int distM;
  final int elapsedS;
  final bool hasCutoff;
  _Stop(this.leg)
      : distM = leg.cumDistM.round(),
        elapsedS = leg.projectedElapsedS.round(),
        hasCutoff = leg.cutoff != null;

  bool get isRefill => leg.services.isNotEmpty || leg.kind == 'aid_station';

  /// Collision priority — which of two stops at the same wire position or the
  /// same wire second survives. A cut-off outranks everything (losing one is
  /// the unacceptable outcome), then the finish (the schedule must reach the
  /// end), then a refill point (the Fuel page reads it), then anything else.
  int get rank => hasCutoff
      ? 3
      : leg.isFinish
          ? 2
          : isRefill
              ? 1
              : 0;
}

/// Shape a built [Roadbook] into the checkpoints and cut-off legs an `RBK1`
/// push carries, reducing it to the watch's caps when it doesn't fit.
///
/// **The synthetic start is always dropped.** It sits at 0 m / 0 s, which the
/// watch already knows the instant a run begins, so it is the one row that
/// costs a slot and carries nothing. The firmware agrees by construction:
/// `Pacer::set_schedule` explicitly skips a leading `(0, 0)` point.
///
/// **Cut-off legs are never reduced.** Every cut-off is a hard elimination
/// point, and the watch's CutoffEta page projects against *the next one* — so a
/// dropped cut-off does not merely lose a row, it makes the page confidently
/// wrong about which limit is coming. A route carrying more cut-offs than the
/// frame holds (once the schedule's end is counted) is therefore **refused**,
/// not trimmed. In practice the cap is generous: a 240-mile race has ~16 aid
/// stations and far fewer timed barriers.
///
/// **Checkpoints are reduced cut-off-first, then by even spacing.** The kept set
/// is, in priority order: the schedule's end (a schedule that stops mid-race is
/// the worst possible answer — the runner would read a plan that just ends);
/// every checkpoint carrying a cut-off; then, filling whatever budget is left,
/// the remaining stops chosen by farthest-point sampling on distance-along-route
/// — repeatedly taking the stop furthest from anything already kept, seeded from
/// the start line. That minimises the longest unscheduled stretch of the race,
/// which is the thing a crew sheet is *for*; even index-sampling would instead
/// clump wherever the aid stations clump.
///
/// **Wire collisions are collapsed before any of that**, because two markers can
/// share a position — an aid station that *is* the barrier is normal on a
/// mountain ultra. The emitted series is strictly increasing in both rounded
/// metres and rounded seconds, which the firmware needs and does not police
/// loudly: `Pacer::set_schedule` silently rejects a non-monotonic schedule
/// whole, degrading the virtual partner back to even pace with no indication.
/// Collapsing here also stops a duplicate from eating a slot.
///
/// Per-checkpoint `legDistanceM` is recomputed against the previous *surviving*
/// checkpoint, so the pushed legs still sum to the course rather than to the
/// unreduced original.
WatchRoadbookResult watchRoadbookFromRoadbook(Roadbook rb) {
  final unresolved =
      rb.legs.where((l) => l.kind == 'cutoff' && l.cutoff == null).length;

  WatchRoadbookResult refuse(
          WatchRoadbookRefusal why, int stops, int cutoffs) =>
      WatchRoadbookResult.refused(
        why,
        sourceCheckpointCount: stops,
        sourceCutoffCount: cutoffs,
        unresolvedCutoffCount: unresolved,
      );

  final candidates = <_Stop>[];
  for (final leg in rb.legs) {
    if (leg.isStart) continue;
    if (!leg.cumDistM.isFinite || leg.cumDistM < 0) continue;
    if (!leg.projectedElapsedS.isFinite || leg.projectedElapsedS < 0) continue;
    candidates.add(_Stop(leg));
  }
  if (candidates.isEmpty || !(rb.totalDistM > 0)) {
    return refuse(WatchRoadbookRefusal.noSchedule, 0, 0);
  }

  // Collapse to a strictly-increasing series in the wire's own units, letting a
  // higher-ranked stop displace the one already kept when they land together.
  final kept = <_Stop>[];
  var prevDist = 0;
  var prevElapsed = 0;
  for (final c in candidates) {
    if (c.distM > prevDist && c.elapsedS > prevElapsed) {
      kept.add(c);
      prevDist = c.distM;
      prevElapsed = c.elapsedS;
      continue;
    }
    if (kept.isEmpty) continue;
    if (c.rank > kept.last.rank) {
      kept[kept.length - 1] = c;
      // The displaced stop shared this one's wire position, so the running
      // maxima only move if this stop is marginally further along.
      prevDist = math.max(prevDist, c.distM);
      prevElapsed = math.max(prevElapsed, c.elapsedS);
    }
  }
  if (kept.isEmpty) {
    return refuse(WatchRoadbookRefusal.noSchedule, 0, 0);
  }

  final sourceCheckpoints = kept.length;
  final cutoffStops = kept.where((s) => s.hasCutoff).toList();
  final sourceCutoffs = cutoffStops.length;

  if (sourceCutoffs > kMaxRoadbookCutoffs) {
    return refuse(
        WatchRoadbookRefusal.tooManyCutoffs, sourceCheckpoints, sourceCutoffs);
  }

  // The schedule's end plus every cut-off is the floor; nothing below it is a
  // schedule worth pushing.
  final mustKeep = <_Stop>{kept.last, ...cutoffStops};
  if (mustKeep.length > kMaxRoadbookCheckpoints) {
    return refuse(
        WatchRoadbookRefusal.tooManyCutoffs, sourceCheckpoints, sourceCutoffs);
  }

  final selected = <_Stop>{...mustKeep};
  if (kept.length > kMaxRoadbookCheckpoints) {
    // Farthest-point sampling: the start line anchors the spacing even though
    // it is never emitted, because the runner really is standing on it.
    final anchors = <int>[0, for (final s in selected) s.distM];
    final pool = kept.where((s) => !selected.contains(s)).toList();
    while (selected.length < kMaxRoadbookCheckpoints && pool.isNotEmpty) {
      var bestIndex = 0;
      var bestGap = -1;
      for (var i = 0; i < pool.length; i++) {
        var gap = 1 << 62;
        for (final a in anchors) {
          gap = math.min(gap, (pool[i].distM - a).abs());
        }
        if (gap > bestGap) {
          bestGap = gap;
          bestIndex = i;
        }
      }
      final chosen = pool.removeAt(bestIndex);
      selected.add(chosen);
      anchors.add(chosen.distM);
    }
  } else {
    selected.addAll(kept);
  }

  final ordered = kept.where(selected.contains).toList();

  final checkpoints = <WatchRoadbookCheckpoint>[];
  var prevKeptDist = 0;
  for (final s in ordered) {
    checkpoints.add(WatchRoadbookCheckpoint(
      cumDistanceM: s.distM.toDouble(),
      legDistanceM: (s.distM - prevKeptDist).toDouble(),
      projectedElapsedSec: s.elapsedS,
      cutoff: _watchStatus(s.leg.cutoff?.status),
      isRefill: s.isRefill,
    ));
    prevKeptDist = s.distM;
  }

  return WatchRoadbookResult(
    checkpoints: checkpoints,
    cutoffs: [
      for (final s in cutoffStops)
        WatchCutoffLeg(
          cumDistanceM: s.distM.toDouble(),
          limitElapsedSec: s.leg.cutoff!.limitElapsedS,
        ),
    ],
    sourceCheckpointCount: sourceCheckpoints,
    sourceCutoffCount: sourceCutoffs,
    unresolvedCutoffCount: unresolved,
  );
}

/// Map the phone roadbook's verdict onto the wire's. Written out rather than
/// taken off `.index`, so a reordering of either enum is a compile error here
/// instead of a silently shifted cut-off status on the watch.
WatchCutoffStatus? _watchStatus(CutoffStatus? status) {
  switch (status) {
    case null:
      return null;
    case CutoffStatus.safe:
      return WatchCutoffStatus.safe;
    case CutoffStatus.tight:
      return WatchCutoffStatus.tight;
    case CutoffStatus.miss:
      return WatchCutoffStatus.miss;
  }
}
