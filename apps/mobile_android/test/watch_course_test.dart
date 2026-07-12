import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/watch_course.dart';

/// The frozen golden vector — kept byte-identical to the firmware's
/// `watch_core::course_store` golden test (the canned sim course's three
/// points), so a wire-format drift on either side is caught here.
const _goldenHex =
    '4352533101030083edd91718ff40c1f0cdd91718ff40c1f0cdd9174e2841c1';

const _simPoints = [
  CoursePoint(40.0158083, -105.2705),
  CoursePoint(40.015, -105.2705),
  CoursePoint(40.015, -105.269445),
];

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
      expect(frame, hasLength(7 + 3 * 8));
    });

    test('header carries magic, version, and the little-endian point count', () {
      final frame = encodeCourse([
        const CoursePoint(1.0, 2.0),
        const CoursePoint(3.0, 4.0),
      ]);
      expect(frame.sublist(0, 4), _hex('43525331')); // "CRS1"
      expect(frame[4], 0x01); // version
      final view = ByteData.sublistView(frame);
      expect(view.getUint16(5, Endian.little), 2);
      // Point 0: lat_e7 = 10_000_000, lon_e7 = 20_000_000.
      expect(view.getInt32(7, Endian.little), 10000000);
      expect(view.getInt32(11, Endian.little), 20000000);
    });

    test('a negative longitude encodes as a signed i32', () {
      final frame = encodeCourse([
        const CoursePoint(0.0, -105.2705),
        const CoursePoint(0.0, 0.0),
      ]);
      final view = ByteData.sublistView(frame);
      expect(view.getInt32(11, Endian.little), -1052705000);
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
      expect(encodeCourse(atCap), hasLength(7 + kMaxCoursePoints * 8));
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

    test('a short frame fits one chunk under the default payload cap', () {
      final frame = encodeCourse(_simPoints);
      expect(frame.length, lessThan(kCourseChunkPayloadMax));
      final chunks = chunkCourse(frame);
      expect(chunks, hasLength(1));
      expect(chunks.first.length, frame.length + 2);
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
      expect(encodeCourse(capped), hasLength(7 + kMaxCoursePoints * 8));
    });
  });
}
