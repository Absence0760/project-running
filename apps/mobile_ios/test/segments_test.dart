import 'dart:math' as math;

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

  // ─── computeGlobalSegmentEfforts (catalogue sweep) ───

  /// `n` catalogue geometries spread around the world, none near `coordAt`.
  List<GlobalSegmentGeometry> distantCatalogue(int n) {
    final out = <GlobalSegmentGeometry>[];
    for (var i = 0; i < n; i++) {
      final lat = -60 + ((i * 13) % 120).toDouble();
      final lng = -180 + ((i * 29) % 360).toDouble();
      out.add(GlobalSegmentGeometry(
        points: [Waypoint(lat: lat, lng: lng), Waypoint(lat: lat + 0.004, lng: lng)],
        distanceM: 450,
      ));
    }
    return out;
  }

  test('global sweep: each entry equals the single-segment result', () {
    final track = _straightTrack(points: 200, stepM: 5, stepS: 1);
    final catalogue = <GlobalSegmentGeometry>[
      GlobalSegmentGeometry(points: [coordAt(100), coordAt(600)], distanceM: 500),
      GlobalSegmentGeometry(points: [coordAt(600), coordAt(100)], distanceM: 500),
      GlobalSegmentGeometry(points: [coordAt(100), coordAt(600)], distanceM: 200),
      ...distantCatalogue(3),
    ];

    final swept = computeGlobalSegmentEfforts(track, catalogue);
    final oneByOne =
        catalogue.map((s) => computeGlobalSegmentEffort(track, s)).toList();

    expect(swept.length, catalogue.length);
    for (var i = 0; i < catalogue.length; i++) {
      expect(swept[i]?.timeSeconds, oneByOne[i]?.timeSeconds);
      expect(swept[i]?.startedAt, oneByOne[i]?.startedAt);
    }
    expect(swept[0], isNotNull);
    expect(swept[1], isNull);
    expect(swept[2], isNull);
    expect(swept.sublist(3).every((e) => e == null), isTrue);
  });

  test('global sweep: a segment just inside the tolerance is still matched', () {
    // The extent test must be conservative — a segment offset laterally by
    // less than the tolerance is a real match and must survive the reject.
    final track = _straightTrack(points: 200, stepM: 5, stepS: 1);
    final offsetDeg = 30 / (111320 * math.cos(37 * math.pi / 180)); // ~30 m east
    Waypoint nudge(double d) =>
        Waypoint(lat: coordAt(d).lat, lng: coordAt(d).lng + offsetDeg);
    final eff = computeGlobalSegmentEfforts(track, [
      GlobalSegmentGeometry(points: [nudge(100), nudge(600)], distanceM: 500),
    ]).first;
    expect(eff, isNotNull);
    expect((eff!.timeSeconds - 100).abs() < 2, isTrue);
  });

  test('global sweep: a run straddling the antimeridian still matches', () {
    // The extent is a planar frame, so it goes through geo.dart's unwrapping —
    // a naive min/max would read this track as spanning the globe and admit
    // everything, or read the segment as 40,000 km away and reject it.
    const degPerM = 1 / 111320;
    final t0 = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    final track = <Waypoint>[];
    for (var i = 0; i < 200; i++) {
      track.add(Waypoint(
        lat: 0.5 + i * 5 * degPerM,
        lng: i < 100 ? 179.9999 : -179.9999,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(t0 + i * 1000, isUtc: true),
      ));
    }
    final eff = computeGlobalSegmentEfforts(track, [
      GlobalSegmentGeometry(points: [track[20], track[120]], distanceM: 500),
    ]).first;
    expect(eff, isNotNull);
  });

  // ─── computeEffortsFromTrack (route-slice sweep) ───

  test('slice sweep: each entry equals the single-slice result', () {
    final track = _straightTrack(points: 200, stepM: 5, stepS: 1);
    final slices = <SegmentSlice>[
      const SegmentSlice(startDistanceM: 100, endDistanceM: 600), // clean
      const SegmentSlice(startDistanceM: 100, endDistanceM: 100), // zero length
      const SegmentSlice(startDistanceM: 200, endDistanceM: 100), // reversed
      const SegmentSlice(startDistanceM: 0, endDistanceM: 100000), // past track
      const SegmentSlice(startDistanceM: 0, endDistanceM: 20), // too sparse
    ];

    final swept = computeEffortsFromTrack(track, slices);
    final oneByOne =
        slices.map((s) => computeEffortFromTrack(track, s)).toList();

    expect(swept.length, slices.length);
    for (var i = 0; i < slices.length; i++) {
      expect(swept[i]?.timeSeconds, oneByOne[i]?.timeSeconds);
      expect(swept[i]?.startedAt, oneByOne[i]?.startedAt);
    }
    expect(swept[0], isNotNull);
    expect(swept.sublist(1).every((e) => e == null), isTrue);
  });

  test('slice sweep: the binary-searched crossing matches a linear scan', () {
    // _msAtDistance takes the FIRST index whose cumulative distance reaches
    // the target; the search must land on exactly that bracket, including
    // when the target sits on a sample boundary.
    final track = _straightTrack(points: 300, stepM: 10, stepS: 2); // 5 m/s
    for (final start in [0.0, 5.0, 10.0, 15.0, 1000.0, 1005.0, 2480.0]) {
      final eff = computeEffortFromTrack(
        track,
        SegmentSlice(startDistanceM: start, endDistanceM: start + 500),
      );
      expect(eff, isNotNull, reason: 'no effort at start $start');
      expect((eff!.timeSeconds - 100).abs() < 1, isTrue,
          reason: '500 m at 5 m/s from $start should be ~100 s');
    }
  });

  // ─── extent-test soundness ───

  /// The pre-prefilter matcher, kept here as the oracle: nearest track point
  /// to the segment start, then the nearest AFTER it to the segment end, both
  /// within tolerance. The extent test is only allowed to skip work — never to
  /// change this answer.
  bool scanMatches(List<Waypoint> track, GlobalSegmentGeometry seg,
      {double toleranceM = 35}) {
    if (track.length < 2 || seg.points.length < 2 || seg.distanceM <= 0) {
      return false;
    }
    double haversine(double aLat, double aLng, double bLat, double bLng) {
      const r = 6371000.0;
      final dLat = (bLat - aLat) * math.pi / 180;
      final dLng = (bLng - aLng) * math.pi / 180;
      final sLat = math.sin(dLat / 2);
      final sLng = math.sin(dLng / 2);
      final h = sLat * sLat +
          math.cos(aLat * math.pi / 180) *
              math.cos(bLat * math.pi / 180) *
              sLng *
              sLng;
      return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
    }

    (int, double) nearest(Waypoint p, int from) {
      var idx = -1;
      var best = double.infinity;
      for (var i = from; i < track.length; i++) {
        final d = haversine(track[i].lat, track[i].lng, p.lat, p.lng);
        if (d < best) {
          best = d;
          idx = i;
        }
      }
      return (idx, best);
    }

    final (startIdx, startBest) = nearest(seg.points.first, 0);
    if (startIdx < 0 || startBest > toleranceM) return false;
    final (endIdx, endBest) = nearest(seg.points.last, startIdx + 1);
    return endIdx >= 0 && endBest <= toleranceM;
  }

  test('global sweep: the extent test never rejects a segment the full scan matches',
      () {
    // The prefilter is only sound if it is conservative. Sweep a range of
    // track latitudes (including polar, where a degree of longitude collapses)
    // and antimeridian crossings, against segments nudged out to and past the
    // tolerance in both axes.
    const degPerM = 1 / 111320;
    final t0 = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    List<Waypoint> makeTrack(double lat0, double lng0, double lngDrift) => [
          for (var i = 0; i < 120; i++)
            Waypoint(
              lat: lat0 + i * 5 * degPerM,
              lng: lng0 + i * lngDrift,
              timestamp:
                  DateTime.fromMillisecondsSinceEpoch(t0 + i * 1000, isUtc: true),
            ),
        ];

    var matched = 0;
    for (final (lat0, lng0, drift) in <(double, double, double)>[
      (37, -122, 0),
      (0.5, 179.99, 0.00002),
      (60, 11, 0.00001),
      (89.9, 10, 0.0001),
      (-33.9, 151.2, 0),
    ]) {
      final track = makeTrack(lat0, lng0, drift);
      double metresEast(double lat, double m) =>
          m * degPerM / math.cos(lat * math.pi / 180);
      for (final offsetM in <double>[0, 10, 34, 36, 200, 5000]) {
        for (final axis in <String>['lat', 'lng']) {
          Waypoint shift(int i) => Waypoint(
                lat: track[i].lat + (axis == 'lat' ? offsetM * degPerM : 0),
                lng: track[i].lng +
                    (axis == 'lng' ? metresEast(track[i].lat, offsetM) : 0),
              );
          final seg = GlobalSegmentGeometry(
            points: [shift(20), shift(100)],
            distanceM: 400,
          );
          final swept = computeGlobalSegmentEfforts(track, [seg]).first;
          if (!scanMatches(track, seg)) continue;
          matched++;
          expect(swept, isNotNull,
              reason: 'extent test rejected a real match: '
                  'lat0=$lat0 offset=${offsetM}m axis=$axis');
        }
      }
    }
    expect(matched >= 10, isTrue,
        reason: 'oracle produced too few matches to be meaningful ($matched)');
  });
}
