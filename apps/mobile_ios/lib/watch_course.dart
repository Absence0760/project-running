import 'dart:math' as math;
import 'dart:typed_data';

/// Pure Dart mirror of the custom watch's `watch_core::course_store` CRS1 wire
/// format — the phone → watch breadcrumb-course push.
///
/// The phone simplifies a route to at most [kMaxCoursePoints] points, then
/// encodes them as a fixed little-endian frame the firmware decodes into the
/// `Course` its nav task follows:
///
///   magic("CRS1", 4) | version(1) | point_count(2, u16 LE) | point[N]
///
/// where each point is `lat_e7(i32 LE) | lon_e7(i32 LE)` — lat/lon quantised to
/// 1e-7 degrees (`(deg * 1e7).round()`, the same integer scaling `run_store`
/// uses for track points), so the route survives the wire without float drift.
///
/// A whole course exceeds one BLE notification, so [chunkCourse] splits the
/// frame into ordered `offset(2, u16 LE) | payload` chunks the watch's
/// `CourseAssembler` reassembles.
///
/// Deliberately pure — no BLE, no platform channels — so [encodeCourse] is
/// unit-testable against a frozen golden vector shared with the Rust test. The
/// phone only ever encodes (the watch decodes), mirroring how `watch_settings`
/// is the phone's encode side of the settings push.
const int _courseVersion = 0x01;

/// Tier-1 course capacity — mirrors `watch_core::course::MAX_COURSE_POINTS`. A
/// longer route must be simplified below this before encoding.
const int kMaxCoursePoints = 256;

const int _courseHeaderLen = 7;
const int _coursePointLen = 8;

/// Max payload per chunk = the watch's `COURSE_CHUNK_CAP` (244) minus the 2-byte
/// offset header each chunk carries.
const int kCourseChunkPayloadMax = 242;

class CoursePoint {
  final double lat;
  final double lng;

  const CoursePoint(this.lat, this.lng);
}

/// Encode a simplified course polyline into a CRS1 frame. Throws when the course
/// has fewer than 2 or more than [kMaxCoursePoints] points (fail-closed, matching
/// the firmware's `course_store::encode` / `Course::from_points`) — call
/// [capCoursePoints] first to bring a dense route under the cap.
Uint8List encodeCourse(List<CoursePoint> points) {
  if (points.length < 2 || points.length > kMaxCoursePoints) {
    throw ArgumentError(
      'course must have 2..$kMaxCoursePoints points, got ${points.length}',
    );
  }
  final len = _courseHeaderLen + points.length * _coursePointLen;
  final out = ByteData(len);
  out.setUint8(0, 0x43); // C
  out.setUint8(1, 0x52); // R
  out.setUint8(2, 0x53); // S
  out.setUint8(3, 0x31); // 1
  out.setUint8(4, _courseVersion);
  out.setUint16(5, points.length, Endian.little);

  var off = _courseHeaderLen;
  for (final p in points) {
    out.setInt32(off, (p.lat * 1e7).round(), Endian.little);
    out.setInt32(off + 4, (p.lng * 1e7).round(), Endian.little);
    off += _coursePointLen;
  }
  return out.buffer.asUint8List();
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
