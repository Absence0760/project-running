import 'package:flutter_test/flutter_test.dart';

import '../lib/route_snap.dart';

/// Twin of web's `routes/route_snap.test.ts`. Keep in lockstep — same
/// cases, same tolerances.
///
/// A roughly 1 km west→east segment at latitude 51.5, plus a second leg
/// turning north. Distances use haversine so the exact metres are
/// approximate; assertions use tolerances.
void main() {
  const line = <List<double>>[
    [-0.12, 51.5],
    [-0.1, 51.5], // ~1.39 km east
    [-0.1, 51.51], // ~1.11 km north
  ];

  test('returns null when the polyline has fewer than two points', () {
    expect(snapToPolyline((lng: 0, lat: 0), const []), isNull);
    expect(
      snapToPolyline((lng: 0, lat: 0), const [
        [-0.12, 51.5],
      ]),
      isNull,
    );
  });

  test('returns null for a non-finite input point', () {
    expect(snapToPolyline((lng: double.nan, lat: 51.5), line), isNull);
    expect(
      snapToPolyline((lng: -0.11, lat: double.infinity), line),
      isNull,
    );
  });

  test('snaps a point above the first segment straight down onto the line',
      () {
    // A point north of the horizontal first leg snaps to the same lng, on
    // the line's latitude.
    final r = snapToPolyline((lng: -0.11, lat: 51.502), line);
    expect(r, isNotNull);
    expect(r!.segmentIndex, 0);
    expect((r.lng - -0.11).abs() < 1e-6, isTrue, reason: 'lng ${r.lng}');
    expect((r.lat - 51.5).abs() < 1e-6, isTrue, reason: 'lat ${r.lat}');
    // t is the fraction along the first leg: -0.11 is halfway between
    // -0.12 and -0.10.
    expect((r.t - 0.5).abs() < 0.01, isTrue, reason: 't ${r.t}');
    // Offset ≈ 0.002° latitude ≈ 222 m.
    expect(r.offsetM > 180 && r.offsetM < 260, isTrue,
        reason: 'offset ${r.offsetM}');
  });

  test('clamps to the start vertex for a point before the line begins', () {
    final r = snapToPolyline((lng: -0.13, lat: 51.5), line);
    expect(r, isNotNull);
    expect(r!.segmentIndex, 0);
    expect(r.t, 0);
    expect((r.lng - -0.12).abs() < 1e-9, isTrue);
    expect(r.alongM.abs() < 1e-6, isTrue, reason: 'alongM ${r.alongM}');
  });

  test('clamps to the end vertex for a point past the line end', () {
    final r = snapToPolyline((lng: -0.1, lat: 51.52), line);
    expect(r, isNotNull);
    expect(r!.segmentIndex, 1);
    expect(r.t, 1);
    expect((r.lat - 51.51).abs() < 1e-9, isTrue);
  });

  test('picks the nearer segment when two are in range', () {
    // A point near the corner but closer to the vertical second leg.
    final r = snapToPolyline((lng: -0.099, lat: 51.505), line);
    expect(r, isNotNull);
    expect(r!.segmentIndex, 1);
  });

  test('alongM accumulates across segments', () {
    // A point projecting onto the middle of the second (vertical) leg: its
    // along-distance is the whole first leg plus half the second.
    final r = snapToPolyline((lng: -0.1, lat: 51.505), line);
    expect(r, isNotNull);
    expect(r!.segmentIndex, 1);
    expect((r.t - 0.5).abs() < 0.02, isTrue, reason: 't ${r.t}');
    // First leg ~1.39 km + half of second leg ~0.55 km ≈ 1.9–2.0 km.
    expect(r.alongM > 1800 && r.alongM < 2050, isTrue,
        reason: 'alongM ${r.alongM}');
  });

  test('a point already on the line snaps to itself with ~zero offset', () {
    final r = snapToPolyline((lng: -0.11, lat: 51.5), line);
    expect(r, isNotNull);
    expect(r!.offsetM < 1, isTrue, reason: 'offset ${r.offsetM}');
    expect((r.lat - 51.5).abs() < 1e-6, isTrue);
  });

  test('tolerates duplicate consecutive vertices without dividing by zero',
      () {
    const dup = <List<double>>[
      [-0.12, 51.5],
      [-0.12, 51.5],
      [-0.1, 51.5],
    ];
    final r = snapToPolyline((lng: -0.11, lat: 51.501), dup);
    expect(r, isNotNull);
    expect(r!.alongM.isFinite, isTrue);
    expect(r.t.isFinite, isTrue);
  });

  test('snapped point is bit-stable for the same input (idempotent)', () {
    final a = snapToPolyline((lng: -0.105, lat: 51.503), line);
    final b = snapToPolyline((lng: -0.105, lat: 51.503), line);
    expect(a, b);
  });

  test('a point past the antimeridian snaps onto the line, not away from it',
      () {
    const across = <List<double>>[
      [179.98, 0],
      [-179.96, 0],
    ];
    // 1 km north of the line, a third of the way along it.
    final r = snapToPolyline((lng: -179.99, lat: 0.009), across)!;
    expect(r.lng, closeTo(-179.99, 1e-6));
    expect(r.offsetM, closeTo(1000, 20));
    expect(r.alongM, closeTo(3335.8, 5));
  });

  test('a snapped point on a leg across the line wraps back into range', () {
    const across = <List<double>>[
      [179.99, 0],
      [-179.97, 0],
    ];
    final r = snapToPolyline((lng: -179.99, lat: 0), across)!;
    expect(r.lng >= -180 && r.lng < 180, isTrue, reason: 'lng ${r.lng}');
    expect(r.lng, closeTo(-179.99, 1e-9));
  });
}
