import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_models/core_models.dart' show Waypoint;

import 'route_simplify.dart' show simplifyToBudget;
import 'sim_watch_sync.dart' show crc32;

/// Pure Dart mirror of the custom watch's `watch_core::course_store` CRS1 wire
/// format — the phone → watch breadcrumb-course push.
///
/// The phone simplifies a route to at most [kMaxCoursePoints] points, then
/// encodes them as a fixed little-endian frame the firmware decodes into the
/// `Course` its nav task follows:
///
///   magic("CRS1", 4) | version(1) | point_count(2, u16 LE) | flags(1) |
///   point[N] | elev_m[N]? | crc32(4, u32 LE)
///
/// where each point is `lat_e7(i32 LE) | lon_e7(i32 LE)` — lat/lon quantised to
/// 1e-7 degrees (`(deg * 1e7).round()`, the same integer scaling `run_store`
/// uses for track points), so the route survives the wire without float drift —
/// and each elevation is `i16 LE` metres, present only when [kCourseFlagElev]
/// is set. Metres, not decimetres: a decimetre `i16` tops out at 3276.7 m,
/// below Mont Blanc.
///
/// Version 2 (2026-07-26) added the flags byte and the elevation series the
/// watch's RouteElev page draws as a climb profile. Version 3 (2026-07-26)
/// appends the CRC32 trailer over every byte before it: the length check alone
/// could not tell a flipped byte inside the point array from a real course, so
/// the watch would follow a *displaced* breadcrumb and calibrate its off-course
/// alert against it. Unlike the settings frame, the firmware does **not** still
/// decode the pre-CRC versions — a course has no plausibility guard downstream,
/// so a wrong one is worse than none — which makes emitting the current version
/// here mandatory rather than merely preferred.
///
/// A whole course exceeds one BLE notification, so [chunkCourse] splits the
/// frame into ordered `offset(2, u16 LE) | payload` chunks the watch's
/// `CourseAssembler` reassembles.
///
/// Deliberately pure — no BLE, no platform channels — so [encodeCourse] is
/// unit-testable against the frozen golden vectors shared with the Rust tests.
/// The phone only ever encodes (the watch decodes), mirroring how
/// `watch_settings` is the phone's encode side of the settings push — and, like
/// it, reusing the run-sync module's [crc32], the same checksum the firmware
/// shares between `run_store`, `flash_store` and `settings`.
const int _courseVersion = 0x03;

/// Presence bit: the frame ends with one `i16 LE` metre elevation per point.
/// Mirrors the firmware's `course_store::COURSE_FLAG_ELEV`.
const int kCourseFlagElev = 1 << 0;

/// Tier-1 course capacity — mirrors `watch_core::course::MAX_COURSE_POINTS`. A
/// longer route must be simplified below this before encoding.
const int kMaxCoursePoints = 256;

const int _courseHeaderLen = 8;
const int _coursePointLen = 8;
const int _courseElevLen = 2;

/// Width of the v3 CRC32 trailer.
const int _courseCrcLen = 4;

/// Max payload per chunk = the watch's `COURSE_CHUNK_CAP` (244) minus the 2-byte
/// offset header each chunk carries.
const int kCourseChunkPayloadMax = 242;

class CoursePoint {
  final double lat;
  final double lng;

  const CoursePoint(this.lat, this.lng);
}

/// Encode a simplified course polyline — and, when the route has one, its
/// per-point elevation in whole metres — into a CRS1 v3 frame, sealed with the
/// CRC32 trailer the watch checks before it will load the course. Throws when the
/// course has fewer than 2 or more than [kMaxCoursePoints] points (fail-closed,
/// matching the firmware's `course_store::encode` / `Course::from_points`) — call
/// [capCoursePoints] first to bring a dense route under the cap — or when
/// [elevationM] is given but doesn't carry exactly one sample per point, which
/// the firmware refuses rather than trims: a profile that doesn't line up
/// point-for-point would mark the wrong climb on the watch. Samples are clamped
/// to the `i16` metre range the wire carries.
Uint8List encodeCourse(List<CoursePoint> points, {List<int>? elevationM}) {
  if (points.length < 2 || points.length > kMaxCoursePoints) {
    throw ArgumentError(
      'course must have 2..$kMaxCoursePoints points, got ${points.length}',
    );
  }
  if (elevationM != null && elevationM.length != points.length) {
    throw ArgumentError(
      'elevation must carry one sample per point: '
      '${elevationM.length} for ${points.length} points',
    );
  }
  final len =
      _courseHeaderLen +
      points.length * _coursePointLen +
      (elevationM == null ? 0 : points.length * _courseElevLen) +
      _courseCrcLen;
  final out = ByteData(len);
  out.setUint8(0, 0x43); // C
  out.setUint8(1, 0x52); // R
  out.setUint8(2, 0x53); // S
  out.setUint8(3, 0x31); // 1
  out.setUint8(4, _courseVersion);
  out.setUint16(5, points.length, Endian.little);
  out.setUint8(7, elevationM == null ? 0 : kCourseFlagElev);

  var off = _courseHeaderLen;
  for (final p in points) {
    out.setInt32(off, (p.lat * 1e7).round(), Endian.little);
    out.setInt32(off + 4, (p.lng * 1e7).round(), Endian.little);
    off += _coursePointLen;
  }
  for (final e in elevationM ?? const <int>[]) {
    out.setInt16(off, e.clamp(-32768, 32767), Endian.little);
    off += _courseElevLen;
  }

  final frame = out.buffer.asUint8List();
  out.setUint32(off, crc32(frame.sublist(0, off)), Endian.little);
  return frame;
}

/// Split a CRS1 [frame] into ordered BLE chunks — each is
/// `offset(2, u16 LE) | payload` — so the watch's `CourseAssembler` can rebuild
/// it. The phone writes these in order to the `course` characteristic.
List<Uint8List> chunkCourse(
  Uint8List frame, {
  int payloadMax = kCourseChunkPayloadMax,
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

/// Why a saved route cannot be sent to the watch as a course.
enum WatchCourseRefusal {
  /// Fewer than two positions. There is no line to follow, [encodeCourse]
  /// refuses such a frame, and so does the firmware — so the push is refused
  /// here, where there is a runner to tell.
  tooFewPoints,
}

/// A route shaped for the watch: the positions a `CRS1` push will carry, their
/// per-point elevation when the route has one for *every* carried position, how
/// many positions the route started with — or the reason it cannot be sent.
///
/// [points] and [refusal] are exclusive. A caller that gets [points] has a
/// course; a caller that gets a [refusal] has something to say to the runner,
/// never a silently shortened route.
class WatchCourseResult {
  final List<CoursePoint>? points;
  final List<int>? elevationM;

  /// Positions on the route before any thinning — the denominator behind
  /// "simplified N of M points to fit".
  final int sourcePointCount;
  final WatchCourseRefusal? refusal;

  const WatchCourseResult({
    required this.points,
    required this.elevationM,
    required this.sourcePointCount,
  }) : refusal = null;

  const WatchCourseResult.refused(this.refusal, this.sourcePointCount)
      : points = null,
        elevationM = null;

  /// Whether the polyline had to be thinned to fit the watch's capacity.
  bool get simplified =>
      points != null && points!.length < sourcePointCount;
}

/// Shape a saved route's polyline into the positions a `CRS1` push carries.
///
/// A route longer than [kMaxCoursePoints] is thinned by priority
/// Douglas–Peucker (`simplifyToBudget`), never cut at the cap: a course that
/// stopped at position 256 would hand the watch a breadcrumb ending in the
/// middle of nowhere, and an off-course alert calibrated against it — worse
/// than the honest `NO COURSE LOADED` the watch shows without one.
///
/// The elevation series is all-or-nothing. The firmware refuses a profile that
/// isn't one sample per point, and filling the gaps would draw a climb the
/// route does not have — so a polyline with any elevation missing is pushed as
/// a line with no profile and the watch's climb pages stay honestly empty.
WatchCourseResult courseFromWaypoints(List<Waypoint> waypoints) {
  if (waypoints.length < 2) {
    return WatchCourseResult.refused(
      WatchCourseRefusal.tooFewPoints,
      waypoints.length,
    );
  }
  final kept = simplifyToBudget(waypoints, maxPoints: kMaxCoursePoints);
  final points = [for (final w in kept) CoursePoint(w.lat, w.lng)];
  final elevations = <int>[];
  for (final w in kept) {
    final e = w.elevationMetres;
    if (e == null || !e.isFinite) {
      elevations.clear();
      break;
    }
    elevations.add(e.round());
  }
  return WatchCourseResult(
    points: points,
    elevationM: elevations.length == points.length ? elevations : null,
    sourcePointCount: waypoints.length,
  );
}

/// Bring a dense route under [kMaxCoursePoints] by evenly sampling indices,
/// always keeping the first and last point so the course endpoints are exact.
/// Returns [points] unchanged when already within the cap. The watch expects a
/// pre-simplified polyline; this is the cheap even-decimation fallback (a route
/// with real geometry should prefer an RDP simplifier before this).
List<CoursePoint> capCoursePoints(List<CoursePoint> points) {
  if (points.length <= kMaxCoursePoints) {
    return points;
  }
  final out = <CoursePoint>[];
  final last = points.length - 1;
  for (var i = 0; i < kMaxCoursePoints - 1; i++) {
    out.add(points[(i * last) ~/ (kMaxCoursePoints - 1)]);
  }
  out.add(points[last]);
  return out;
}
