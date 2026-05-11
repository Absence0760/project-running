import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter_test/flutter_test.dart';

import '../lib/elevation.dart';

class _StubFetcher {
  final List<String> bodies;
  int idx = 0;
  Uri? lastUrl;
  int callCount = 0;
  _StubFetcher(this.bodies);
  Future<String> call(Uri url) async {
    lastUrl = url;
    callCount++;
    return bodies[idx++ % bodies.length];
  }
}

void main() {
  group('fetchElevations', () {
    test('returns empty list for empty input', () async {
      final out = await fetchElevations(const [],
          fetcher: (_) async => fail('fetcher must not be called'));
      expect(out, isEmpty);
    });

    test('parses elevation array on success', () async {
      final stub = _StubFetcher([
        jsonEncode({
          'elevation': [410.0, 412.5, 415.0],
        }),
      ]);
      final out = await fetchElevations(
        const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
          Waypoint(lat: 47.39, lng: 8.56),
        ],
        fetcher: stub.call,
      );
      expect(out, [410.0, 412.5, 415.0]);
    });

    test('returns zeros when fetcher throws (offline / API down)', () async {
      Future<String> bomb(Uri _) async => throw const SocketException('down');
      final out = await fetchElevations(
        const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
        ],
        fetcher: bomb,
      );
      expect(out, [0, 0]);
    });

    test('returns zeros when response length disagrees with input', () async {
      final stub = _StubFetcher([
        jsonEncode({
          'elevation': [410.0],
        }),
      ]);
      final out = await fetchElevations(
        const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
        ],
        fetcher: stub.call,
      );
      expect(out, [0, 0]);
    });

    test('batches inputs larger than kElevationBatchSize', () async {
      final stub = _StubFetcher([
        jsonEncode({
          'elevation': List<double>.filled(kElevationBatchSize, 1.0),
        }),
        jsonEncode({
          'elevation': [2.0, 3.0],
        }),
      ]);
      final points = [
        for (var i = 0; i < kElevationBatchSize + 2; i++)
          Waypoint(lat: 47.0 + i * 0.0001, lng: 8.0),
      ];
      final out = await fetchElevations(points, fetcher: stub.call);
      expect(out, hasLength(kElevationBatchSize + 2));
      expect(stub.callCount, 2,
          reason: 'must split into 2 batches when > kElevationBatchSize');
      expect(out.first, 1.0);
      expect(out.last, 3.0);
    });

    test('builds URL with comma-joined latitudes + longitudes', () async {
      final stub = _StubFetcher([
        jsonEncode({
          'elevation': [10.0, 20.0],
        }),
      ]);
      await fetchElevations(
        const [
          Waypoint(lat: 47.0, lng: 8.0),
          Waypoint(lat: 47.5, lng: 8.5),
        ],
        fetcher: stub.call,
      );
      expect(stub.lastUrl!.queryParameters['latitude'], '47.0,47.5');
      expect(stub.lastUrl!.queryParameters['longitude'], '8.0,8.5');
    });
  });

  group('calculateElevationGain', () {
    test('sums positive deltas only', () {
      expect(
        calculateElevationGain([100, 110, 105, 120, 119, 130]),
        // 110-100=10, 120-105=15, 130-119=11 → 36
        36,
      );
    });

    test('returns 0 for flat or descending series', () {
      expect(calculateElevationGain([100, 100, 100]), 0);
      expect(calculateElevationGain([100, 95, 90]), 0);
    });

    test('returns 0 for <2 samples', () {
      expect(calculateElevationGain(const []), 0);
      expect(calculateElevationGain([100]), 0);
    });
  });

  group('sampleCoordinates', () {
    test('returns input unchanged when length <= maxPoints', () {
      final pts = List<Waypoint>.generate(
        50,
        (i) => Waypoint(lat: 47.0 + i * 1e-4, lng: 8.0),
      );
      final out = sampleCoordinates(pts, maxPoints: 100);
      expect(out, same(pts));
    });

    test('downsamples to exactly maxPoints', () {
      final pts = List<Waypoint>.generate(
        500,
        (i) => Waypoint(lat: 47.0 + i * 1e-4, lng: 8.0),
      );
      final out = sampleCoordinates(pts, maxPoints: 100);
      expect(out, hasLength(100));
      // First + last always preserved.
      expect(out.first.lat, closeTo(47.0, 1e-9));
      expect(out.last.lat, closeTo(pts.last.lat, 1e-9));
    });

    test('produces evenly-spaced samples', () {
      final pts = List<Waypoint>.generate(
        10,
        (i) => Waypoint(lat: i.toDouble(), lng: 0),
      );
      final out = sampleCoordinates(pts, maxPoints: 5);
      // 5 evenly-spaced samples over [0..9]: step=(10-1)/(5-1)=2.25
      // indices: 0, 2, 5, 7, 9
      expect(out.map((w) => w.lat).toList(), [0, 2, 5, 7, 9]);
    });
  });
}
