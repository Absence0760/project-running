import 'package:flutter_test/flutter_test.dart';

import '../lib/route_description.dart';

/// Mirror of `apps/web/src/lib/routes/route_description.test.ts`. Keep in
/// lockstep — the templated route description shown on web route detail
/// and mobile route detail both derive from this helper.

void main() {
  test('elevationProfile buckets gain-per-km into the four bands', () {
    expect(elevationProfile(10000, 0).profile, ElevationProfile.flat);
    expect(elevationProfile(10000, 50).profile, ElevationProfile.flat);
    expect(elevationProfile(10000, 150).profile, ElevationProfile.rolling);
    expect(elevationProfile(10000, 400).profile, ElevationProfile.hilly);
    expect(elevationProfile(10000, 1000).profile, ElevationProfile.mountainous);
  });

  test('elevationProfile thresholds are inclusive lower bounds', () {
    expect(elevationProfile(1000, 10).profile, ElevationProfile.rolling);
    expect(elevationProfile(1000, 30).profile, ElevationProfile.hilly);
    expect(elevationProfile(1000, 70).profile, ElevationProfile.mountainous);
  });

  test('elevationProfile guards zero / negative distance', () {
    expect(elevationProfile(0, 500).profile, ElevationProfile.flat);
    expect(elevationProfile(0, 500).gainPerKm, 0);
    expect(elevationProfile(-10, 500).profile, ElevationProfile.flat);
    expect(elevationProfile(-10, 500).gainPerKm, 0);
  });

  test('routeShape reports a loop when start ≈ end', () {
    const input = RouteDescriptionInput(
      name: 'Park loop',
      distanceM: 5000,
      elevationM: 20,
      surface: 'road',
      start: LatLng(51.5, -0.12),
      end: LatLng(51.5, -0.12),
    );
    expect(routeShape(input), RouteShape.loop);
  });

  test('routeShape reports pointToPoint when endpoints differ', () {
    const input = RouteDescriptionInput(
      name: 'Trail run',
      distanceM: 12000,
      elevationM: 300,
      surface: 'trail',
      start: LatLng(51.5, -0.12),
      end: LatLng(51.6, -0.05),
    );
    expect(routeShape(input), RouteShape.pointToPoint);
  });

  test('routeShape falls back to pointToPoint without endpoints', () {
    expect(
      routeShape(const RouteDescriptionInput(name: 'x', distanceM: 5000)),
      RouteShape.pointToPoint,
    );
  });

  test('loopCloseM boundary: a small gap still reads as a loop', () {
    const start = LatLng(51.5, -0.12);
    const end = LatLng(51.5, -0.12 + 0.0007); // ~48 m at this latitude
    expect(loopCloseM >= 75, isTrue);
    expect(
      routeShape(const RouteDescriptionInput(
        name: 'x',
        distanceM: 5000,
        elevationM: 0,
        start: start,
        end: end,
      )),
      RouteShape.loop,
    );
  });

  test('describeRoute assembles the structured parts', () {
    final parts = describeRoute(const RouteDescriptionInput(
      name: 'Riverside 10K',
      distanceM: 10000,
      elevationM: 150,
      surface: 'mixed',
      start: LatLng(51.5, -0.12),
      end: LatLng(51.5, -0.12),
    ));
    expect(parts.band, '10k');
    expect(parts.surface, 'mixed');
    expect(parts.elevation, ElevationProfile.rolling);
    expect(parts.gainPerKm, 15);
    expect(parts.shape, RouteShape.loop);
  });

  test('describeRoute returns a null band for between-band distances', () {
    final parts = describeRoute(const RouteDescriptionInput(
      name: 'x',
      distanceM: 15000,
      elevationM: 0,
      surface: 'road',
    ));
    expect(parts.band, isNull);
  });

  test('describeRoute clamps non-finite / negative inputs to zero', () {
    final parts = describeRoute(const RouteDescriptionInput(
      name: 'x',
      distanceM: double.nan,
      elevationM: -500,
    ));
    expect(parts.distanceM, 0);
    expect(parts.elevationM, 0);
    expect(parts.elevation, ElevationProfile.flat);
  });

  test('assembleEnglish produces a hilly point-to-point sentence', () {
    final parts = describeRoute(const RouteDescriptionInput(
      name: 'Summit Trail',
      distanceM: 12000,
      elevationM: 480,
      surface: 'trail',
      start: LatLng(51.5, -0.12),
      end: LatLng(51.7, 0.0),
    ));
    final text = assembleEnglish(parts, 'Summit Trail');
    expect(text, startsWith('Summit Trail is a 12.0 km trail point-to-point route'));
    expect(text, endsWith('480 m of climbing (hilly, about 40 m per km).'));
  });

  test('assembleEnglish handles a flat road loop with no climbing', () {
    final parts = describeRoute(const RouteDescriptionInput(
      name: 'Track',
      distanceM: 5000,
      elevationM: 0,
      surface: 'road',
      start: LatLng(0, 0),
      end: LatLng(0, 0),
    ));
    final text = assembleEnglish(parts, 'Track');
    expect(
      text,
      'Track is a 5.0 km road loop route with little to no elevation change.',
    );
  });
}
