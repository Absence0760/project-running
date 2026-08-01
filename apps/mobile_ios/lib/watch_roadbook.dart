import 'dart:math' as math;
import 'dart:typed_data';

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
