import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter_test/flutter_test.dart';

import '../lib/sim_watch_sync.dart' show crc32;
import '../lib/watch_course.dart';

/// The frozen golden vectors — kept byte-identical to the firmware's
/// `watch_core::course_store` golden tests (the canned sim course's three
/// points, with and without its elevation series, each sealed with the v3
/// CRC32 trailer), so a wire-format drift on either side is caught here.
const _goldenHex =
    '435253310303000083edd91718ff40c1f0cdd91718ff40c1f0cdd9174e2841c1'
    '14996437';
const _goldenElevHex =
    '435253310303000183edd91718ff40c1f0cdd91718ff40c1f0cdd9174e2841c1'
    '720677066806'
    'b8269c11';

/// Width of the v3 CRC32 trailer.
const _crcLen = 4;

const _simPoints = [
  CoursePoint(40.0158083, -105.2705),
  CoursePoint(40.015, -105.2705),
  CoursePoint(40.015, -105.269445),
];

/// Bench-plausible altitudes for the sim course (Boulder, ~1650 m) — the same
/// series the Rust golden test pins.
const _simElevM = [1650, 1655, 1640];

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('encodeCourse', () {
    test('the sim course matches the golden vector byte-for-byte', () {
      final frame = encodeCourse(_simPoints);
      expect(frame, _hex(_goldenHex));
      expect(frame, hasLength(8 + 3 * 8 + _crcLen));
    });

    test('the sim course with elevation matches its golden vector', () {
      final frame = encodeCourse(_simPoints, elevationM: _simElevM);
      expect(frame, _hex(_goldenElevHex));
      expect(frame, hasLength(8 + 3 * 8 + 3 * 2 + _crcLen));
      expect(frame[7], kCourseFlagElev);
    });

    test(
      'header carries magic, version, and the little-endian point count',
      () {
        final frame = encodeCourse([
          const CoursePoint(1.0, 2.0),
          const CoursePoint(3.0, 4.0),
        ]);
        expect(frame.sublist(0, 4), _hex('43525331')); // "CRS1"
        expect(frame[4], 0x03); // version
        final view = ByteData.sublistView(frame);
        expect(view.getUint16(5, Endian.little), 2);
        expect(frame[7], 0); // no elevation
        // Point 0: lat_e7 = 10_000_000, lon_e7 = 20_000_000.
        expect(view.getInt32(8, Endian.little), 10000000);
        expect(view.getInt32(12, Endian.little), 20000000);
      },
    );

    test('the v3 trailer is the crc32 of every byte before it', () {
      // The goldens above pin the trailer as literal bytes; this pins that it is
      // actually derived, so a course the goldens do not cover still carries the
      // checksum the firmware verifies before it will load the breadcrumb.
      for (final frame in [
        encodeCourse(_simPoints),
        encodeCourse(_simPoints, elevationM: _simElevM),
      ]) {
        final body = frame.sublist(0, frame.length - _crcLen);
        final trailer = ByteData.sublistView(
          frame,
          frame.length - _crcLen,
        ).getUint32(0, Endian.little);
        expect(trailer, crc32(body));
      }
    });

    test('a course that differs by one point seals to a different crc', () {
      // The firmware refuses a frame whose trailer doesn't match, so the seal
      // has to actually depend on the polyline — a constant would pass the
      // golden tests and still let a displaced course through.
      final honest = encodeCourse(_simPoints);
      final moved = encodeCourse([
        const CoursePoint(40.0158084, -105.2705),
        _simPoints[1],
        _simPoints[2],
      ]);
      expect(
        moved.sublist(moved.length - _crcLen),
        isNot(honest.sublist(honest.length - _crcLen)),
      );
    });

    test('a negative longitude encodes as a signed i32', () {
      final frame = encodeCourse([
        const CoursePoint(0.0, -105.2705),
        const CoursePoint(0.0, 0.0),
      ]);
      final view = ByteData.sublistView(frame);
      expect(view.getInt32(12, Endian.little), -1052705000);
    });

    test('a below-sea-level elevation encodes as a signed i16', () {
      final frame = encodeCourse(
        [const CoursePoint(31.5, 35.5), const CoursePoint(31.6, 35.6)],
        elevationM: [-430, -415],
      );
      final view = ByteData.sublistView(frame);
      expect(view.getInt16(8 + 2 * 8, Endian.little), -430);
      expect(view.getInt16(8 + 2 * 8 + 2, Endian.little), -415);
    });

    test('an out-of-range elevation clamps to the i16 the wire carries', () {
      final frame = encodeCourse(
        [const CoursePoint(0.0, 0.0), const CoursePoint(0.1, 0.1)],
        elevationM: [99999, -99999],
      );
      final view = ByteData.sublistView(frame);
      expect(view.getInt16(8 + 2 * 8, Endian.little), 32767);
      expect(view.getInt16(8 + 2 * 8 + 2, Endian.little), -32768);
    });

    test('rejects an elevation series that is not one sample per point', () {
      expect(
        () => encodeCourse(_simPoints, elevationM: const [1650, 1655]),
        throwsArgumentError,
      );
      expect(
        () => encodeCourse(_simPoints, elevationM: const []),
        throwsArgumentError,
      );
      expect(
        () => encodeCourse(_simPoints, elevationM: const [1, 2, 3, 4]),
        throwsArgumentError,
      );
    });

    test('rejects a course with fewer than two points', () {
      expect(() => encodeCourse([]), throwsArgumentError);
      expect(
        () => encodeCourse([const CoursePoint(1.0, 2.0)]),
        throwsArgumentError,
      );
    });

    test('rejects a course over the tier-1 capacity', () {
      final over = List.generate(
        kMaxCoursePoints + 1,
        (i) => CoursePoint(0.0, i * 1e-4),
      );
      expect(() => encodeCourse(over), throwsArgumentError);
      // Exactly at the cap encodes.
      final atCap = List.generate(
        kMaxCoursePoints,
        (i) => CoursePoint(0.0, i * 1e-4),
      );
      expect(
        encodeCourse(atCap),
        hasLength(8 + kMaxCoursePoints * 8 + _crcLen),
      );
    });
  });

  group('chunkCourse', () {
    test('splits a frame into offset-tagged chunks that reassemble it', () {
      final frame = encodeCourse(_simPoints);
      final chunks = chunkCourse(frame, payloadMax: 8);
      final reassembled = Uint8List(frame.length);
      for (final chunk in chunks) {
        final off = ByteData.sublistView(chunk).getUint16(0, Endian.little);
        reassembled.setRange(off, off + (chunk.length - 2), chunk, 2);
      }
      expect(reassembled, frame);
      // Every payload but the last is full; offsets are in order and contiguous.
      var expectedOffset = 0;
      for (final chunk in chunks) {
        expect(
          ByteData.sublistView(chunk).getUint16(0, Endian.little),
          expectedOffset,
        );
        expectedOffset += chunk.length - 2;
      }
      expect(expectedOffset, frame.length);
    });

    test('a full-capacity elevation frame reassembles across many chunks', () {
      final points = List.generate(
        kMaxCoursePoints,
        (i) => CoursePoint(40.0 + i * 1e-4, -105.0),
      );
      final frame = encodeCourse(
        points,
        elevationM: List.generate(kMaxCoursePoints, (i) => 1600 + i),
      );
      final chunks = chunkCourse(frame);
      expect(chunks.length, greaterThan(1));
      final reassembled = Uint8List(frame.length);
      for (final chunk in chunks) {
        final off = ByteData.sublistView(chunk).getUint16(0, Endian.little);
        reassembled.setRange(off, off + (chunk.length - 2), chunk, 2);
      }
      expect(reassembled, frame);
    });

    test('a short frame fits one chunk under the default payload cap', () {
      final frame = encodeCourse(_simPoints);
      expect(frame.length, lessThan(kCourseChunkPayloadMax));
      final chunks = chunkCourse(frame);
      expect(chunks, hasLength(1));
      expect(chunks.first.length, frame.length + 2);
    });
  });

  group('courseFromWaypoints', () {
    Waypoint wp(double lat, double lng, {double? ele}) =>
        Waypoint(lat: lat, lng: lng, elevationMetres: ele);

    test('a short route passes through untouched and unsimplified', () {
      final result = courseFromWaypoints([
        wp(40.0158083, -105.2705),
        wp(40.015, -105.2705),
        wp(40.015, -105.269445),
      ]);
      expect(result.refusal, isNull);
      expect(result.points, hasLength(3));
      expect(result.points!.first.lat, 40.0158083);
      expect(result.points!.last.lng, -105.269445);
      expect(result.sourcePointCount, 3);
      expect(result.simplified, isFalse);
      expect(result.elevationM, isNull);
    });

    test('a dense route is thinned to the cap, not cut at it', () {
      final dense = [
        for (var i = 0; i < 4000; i++)
          wp(40.0 + math.sin(i / 9) * 0.002, -105.0 + i * 1e-5),
      ];
      final result = courseFromWaypoints(dense);
      expect(result.points, hasLength(kMaxCoursePoints));
      expect(result.sourcePointCount, 4000);
      expect(result.simplified, isTrue);
      // The tail is the route's real end, not point 256 of 4000 — a truncated
      // course would strand the breadcrumb mid-route.
      expect(result.points!.last.lng, closeTo(dense.last.lng, 1e-12));
      expect(result.points!.first.lat, closeTo(dense.first.lat, 1e-12));
      // And what came back actually encodes.
      expect(encodeCourse(result.points!), isNotEmpty);
    });

    test('elevation rides along when every carried point has one', () {
      final result = courseFromWaypoints([
        wp(40.0158083, -105.2705, ele: 1650.4),
        wp(40.015, -105.2705, ele: 1655.5),
        wp(40.015, -105.269445, ele: 1639.6),
      ]);
      expect(result.elevationM, [1650, 1656, 1640]);
      expect(
        encodeCourse(result.points!, elevationM: result.elevationM)[7],
        kCourseFlagElev,
      );
    });

    test('one missing elevation drops the whole profile, not just the gap', () {
      // The firmware wants one sample per point; carrying a partial series by
      // inventing the gap would draw a climb the route does not have.
      final result = courseFromWaypoints([
        wp(40.0158083, -105.2705, ele: 1650),
        wp(40.015, -105.2705),
        wp(40.015, -105.269445, ele: 1640),
      ]);
      expect(result.points, hasLength(3));
      expect(result.elevationM, isNull);
    });

    test('a non-finite elevation drops the profile too', () {
      final result = courseFromWaypoints([
        wp(40.0158083, -105.2705, ele: 1650),
        wp(40.015, -105.2705, ele: double.nan),
        wp(40.015, -105.269445, ele: 1640),
      ]);
      expect(result.elevationM, isNull);
    });

    test('a thinned route carries the elevation of the points it kept', () {
      final dense = [
        for (var i = 0; i < 1000; i++)
          wp(40.0 + math.sin(i / 6) * 0.002, -105.0 + i * 1e-5,
              ele: 1600 + i.toDouble()),
      ];
      final result = courseFromWaypoints(dense);
      expect(result.points, hasLength(kMaxCoursePoints));
      expect(result.elevationM, hasLength(kMaxCoursePoints));
      expect(result.elevationM!.first, 1600);
      expect(result.elevationM!.last, 2599);
      expect(
        () => encodeCourse(result.points!, elevationM: result.elevationM),
        returnsNormally,
      );
    });

    test('refuses a route with fewer than two positions', () {
      for (final waypoints in [
        <Waypoint>[],
        [wp(40.0, -105.0)],
      ]) {
        final result = courseFromWaypoints(waypoints);
        expect(result.refusal, WatchCourseRefusal.tooFewPoints);
        expect(result.points, isNull);
        expect(result.simplified, isFalse);
      }
    });
  });

  group('capCoursePoints', () {
    test('returns the input unchanged when already within the cap', () {
      final pts = [const CoursePoint(1, 2), const CoursePoint(3, 4)];
      expect(identical(capCoursePoints(pts), pts), isTrue);
    });

    test('caps a dense route to the max, keeping first and last exact', () {
      final dense = List.generate(1000, (i) => CoursePoint(0.0, i.toDouble()));
      final capped = capCoursePoints(dense);
      expect(capped, hasLength(kMaxCoursePoints));
      expect(capped.first.lng, dense.first.lng);
      expect(capped.last.lng, dense.last.lng);
      // The capped course still encodes within the tier-1 cap.
      expect(
        encodeCourse(capped),
        hasLength(8 + kMaxCoursePoints * 8 + _crcLen),
      );
    });
  });
}
