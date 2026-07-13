import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/segments.dart';

/// Synthesises a straight-line track at constant pace. Each step adds
/// roughly `stepM` of distance and `stepS` seconds. Lat advances along
/// a meridian (~111_320 m per degree) so haversine-cumulated distance
/// matches `(i * stepM)` to about half a metre. Mirrors the
/// `straightTrack` helper in `apps/web/src/lib/segments.test.ts`.
List<Waypoint> _straightTrack({
  required int points,
  required double stepM,
  required double stepS,
}) {
  const startLat = 37.0;
  const lng = -122.0;
  final out = <Waypoint>[];
  final t0 = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
  const degPerM = 1 / 111320;
  for (var i = 0; i < points; i++) {
    out.add(Waypoint(
      lat: startLat + i * stepM * degPerM,
      lng: lng,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          t0 + (i * stepS * 1000).round(),
          isUtc: true),
    ));
  }
  return out;
}

void main() {
  test('computes elapsed time over a clean segment', () {
    // 5 m/s = 200 s/km
    final track = _straightTrack(points: 200, stepM: 5, stepS: 1);
    final eff = computeEffortFromTrack(
      track,
      const SegmentSlice(startDistanceM: 100, endDistanceM: 600),
    );
    expect(eff, isNotNull);
    // 500 m at 5 m/s = 100 s, with sub-second interpolation slop.
    expect((eff!.timeSeconds - 100).abs() < 1, isTrue);
  });

  test('returns null when the run is shorter than the segment end', () {
    final track = _straightTrack(points: 50, stepM: 5, stepS: 1); // ~245 m
    final eff = computeEffortFromTrack(
      track,
      const SegmentSlice(startDistanceM: 0, endDistanceM: 1000),
    );
    expect(eff, isNull);
  });

  test('returns null on tracks shorter than two points', () {
    expect(
      computeEffortFromTrack(
        const [],
        const SegmentSlice(startDistanceM: 0, endDistanceM: 100),
      ),
      isNull,
    );
    expect(
      computeEffortFromTrack(
        [Waypoint(lat: 0, lng: 0, timestamp: DateTime.utc(2026, 1, 1))],
        const SegmentSlice(startDistanceM: 0, endDistanceM: 100),
      ),
      isNull,
    );
  });

  test('returns null when the segment window has zero or negative length', () {
    final track = _straightTrack(points: 50, stepM: 5, stepS: 1);
    expect(
      computeEffortFromTrack(
        track,
        const SegmentSlice(startDistanceM: 100, endDistanceM: 100),
      ),
      isNull,
    );
    expect(
      computeEffortFromTrack(
        track,
        const SegmentSlice(startDistanceM: 200, endDistanceM: 100),
      ),
      isNull,
    );
  });

  test('rejects sparse sampling (median step > segment / 5)', () {
    // 10 s sampling at 5 m/s = 50 m steps; segment of 100 m → ratio
    // 50 / 100 = 0.5, well above 0.2, so this should be rejected.
    final track = _straightTrack(points: 30, stepM: 50, stepS: 10);
    final eff = computeEffortFromTrack(
      track,
      const SegmentSlice(startDistanceM: 100, endDistanceM: 200),
    );
    expect(eff, isNull);
  });

  test('returns null when adjacent track points lack timestamps', () {
    // Window 50–55m falls in the bracket [10, 11]. Stripping ts on
    // either end of that bracket should kill the interpolation.
    final track = _straightTrack(points: 50, stepM: 5, stepS: 1);
    track[10] = Waypoint(lat: track[10].lat, lng: track[10].lng);
    track[11] = Waypoint(lat: track[11].lat, lng: track[11].lng);
    final eff = computeEffortFromTrack(
      track,
      const SegmentSlice(startDistanceM: 50, endDistanceM: 55),
    );
    expect(eff, isNull);
  });

  test('interpolates start and end timestamps mid-segment', () {
    // Segment endpoints fall between samples — interpolation should
    // land within the same fractional bracket. 5 m/s.
    final track = _straightTrack(points: 200, stepM: 10, stepS: 2);
    final eff = computeEffortFromTrack(
      track,
      const SegmentSlice(startDistanceM: 105, endDistanceM: 605),
    );
    expect(eff, isNotNull);
    expect((eff!.timeSeconds - 100).abs() < 1, isTrue);
  });

  test('handles segment endpoints aligned with sample crossings', () {
    final track = _straightTrack(points: 100, stepM: 10, stepS: 2);
    final eff = computeEffortFromTrack(
      track,
      const SegmentSlice(startDistanceM: 100, endDistanceM: 500),
    );
    expect(eff, isNotNull);
    expect((eff!.timeSeconds - 80).abs() < 1, isTrue);
  });

  // ─── computeGlobalSegmentEffort (free-standing catalogue geometry) ───

  Waypoint coordAt(double distanceM) =>
      Waypoint(lat: 37.0 + distanceM / 111320, lng: -122.0);

  test('global: matches an end-to-end run and times the effort', () {
    final track = _straightTrack(points: 200, stepM: 5, stepS: 1); // 5 m/s
    final eff = computeGlobalSegmentEffort(
      track,
      GlobalSegmentGeometry(
        points: [coordAt(100), coordAt(600)],
        distanceM: 500,
      ),
    );
    expect(eff, isNotNull);
    expect((eff!.timeSeconds - 100).abs() < 1, isTrue);
  });

  test('global: null when the run never approaches the segment start', () {
    final track = _straightTrack(points: 200, stepM: 5, stepS: 1);
    Waypoint far(double d) => Waypoint(lat: 37.0 + d / 111320, lng: -121.988);
    final eff = computeGlobalSegmentEffort(
      track,
      GlobalSegmentGeometry(points: [far(100), far(600)], distanceM: 500),
    );
    expect(eff, isNull);
  });

  test('global: null when the run reaches the start but not the end', () {
    final track = _straightTrack(points: 80, stepM: 5, stepS: 1); // ~395 m
    final eff = computeGlobalSegmentEffort(
      track,
      GlobalSegmentGeometry(
        points: [coordAt(100), coordAt(600)],
        distanceM: 500,
      ),
    );
    expect(eff, isNull);
  });

  test('global: null when covered distance fails the end-to-end guard', () {
    final track = _straightTrack(points: 200, stepM: 5, stepS: 1);
    // Run covers 500 m but the catalogue claims 200 m → rejected.
    final eff = computeGlobalSegmentEffort(
      track,
      GlobalSegmentGeometry(
        points: [coordAt(100), coordAt(600)],
        distanceM: 200,
      ),
    );
    expect(eff, isNull);
  });

  test('global: directional — a run going the wrong way does not match', () {
    final track = _straightTrack(points: 200, stepM: 5, stepS: 1);
    final eff = computeGlobalSegmentEffort(
      track,
      GlobalSegmentGeometry(
        points: [coordAt(600), coordAt(100)],
        distanceM: 500,
      ),
    );
    expect(eff, isNull);
  });

  test('global: null on degenerate track or geometry', () {
    expect(
      computeGlobalSegmentEffort(
        const [],
        GlobalSegmentGeometry(points: [coordAt(0), coordAt(100)], distanceM: 100),
      ),
      isNull,
    );
    final track = _straightTrack(points: 50, stepM: 5, stepS: 1);
    expect(
      computeGlobalSegmentEffort(
        track,
        GlobalSegmentGeometry(points: [coordAt(0)], distanceM: 100),
      ),
      isNull,
    );
    expect(
      computeGlobalSegmentEffort(
        track,
        GlobalSegmentGeometry(points: [coordAt(0), coordAt(100)], distanceM: 0),
      ),
      isNull,
    );
  });

  test('global: tolerates start/end falling between run samples', () {
    final track = _straightTrack(points: 200, stepM: 10, stepS: 2); // 5 m/s
    final eff = computeGlobalSegmentEffort(
      track,
      GlobalSegmentGeometry(
        points: [coordAt(105), coordAt(605)],
        distanceM: 500,
      ),
    );
    expect(eff, isNotNull);
    expect((eff!.timeSeconds - 100).abs() < 2, isTrue);
  });
}
