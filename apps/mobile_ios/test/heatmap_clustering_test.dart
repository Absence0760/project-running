import 'package:flutter_test/flutter_test.dart';

import '../lib/heatmap_clustering.dart';

// Test pin: lat/lng + an id to track membership.
class _P {
  final String id;
  final double lat;
  final double lng;
  const _P(this.id, this.lat, this.lng);
}

// Simple projector: 1 degree = 1000 px (so distances are easy to reason
// about). Mimics flutter_map's MapCamera.project for the test.
ScreenPoint _project(double lat, double lng) => (x: lng * 1000, y: lat * 1000);

List<PinCluster<_P>> _cluster(List<_P> pins, {double radiusPx = 60}) =>
    clusterPins<_P>(
      items: pins,
      latOf: (p) => p.lat,
      lngOf: (p) => p.lng,
      project: _project,
      radiusPx: radiusPx,
    );

void main() {
  test('empty input yields no clusters', () {
    expect(_cluster(const []), isEmpty);
  });

  test('pins at the identical coordinate merge into one cluster', () {
    final out = _cluster(const [
      _P('a', 39.74, -105.0),
      _P('b', 39.74, -105.0),
      _P('c', 39.74, -105.0),
    ]);
    expect(out.length, 1);
    expect(out.first.isCluster, isTrue);
    expect(out.first.count, 3);
  });

  test('pins far apart stay separate singles', () {
    // 0.1 deg apart = 100 px apart, well beyond the 60 px radius.
    final out = _cluster(const [
      _P('a', 39.70, -105.00),
      _P('b', 39.80, -105.00),
    ]);
    expect(out.length, 2);
    expect(out.every((c) => !c.isCluster), isTrue);
  });

  test('close pins merge, a distant one stays single', () {
    // a + b are 0.02 deg (20 px) apart → merge; c is 0.2 deg away → single.
    final out = _cluster(const [
      _P('a', 39.700, -105.000),
      _P('b', 39.700, -104.980),
      _P('c', 39.900, -105.000),
    ]);
    expect(out.length, 2);
    final cluster = out.firstWhere((c) => c.isCluster);
    final single = out.firstWhere((c) => !c.isCluster);
    expect(cluster.count, 2);
    expect(single.first.id, 'c');
  });

  test('a cluster sits at the centroid of its members', () {
    final out = _cluster(const [
      _P('a', 39.700, -105.000),
      _P('b', 39.710, -105.010),
    ]);
    expect(out.length, 1);
    expect(out.first.lat, closeTo(39.705, 1e-9));
    expect(out.first.lng, closeTo(-105.005, 1e-9));
  });

  test('a tighter radius un-merges pins that a looser radius merged', () {
    const pins = [
      _P('a', 39.700, -105.000),
      _P('b', 39.700, -104.950), // 50 px away
    ];
    expect(_cluster(pins, radiusPx: 60).length, 1); // 50 < 60 → merge
    expect(_cluster(pins, radiusPx: 40).length, 2); // 50 > 40 → split
  });
}
