// Mirror of apps/web/src/lib/routes/run_heatmap.test.ts for the ported
// pure aggregation (buildHeatCells / heatBounds). The GeoJSON emitters
// on the web side are MapLibre-specific and have no Dart twin, so the
// two toGeoJSON cases are not mirrored here.

import 'package:flutter_test/flutter_test.dart';

import '../lib/run_heatmap.dart';

void main() {
  test('collapses many points within one grid cell into a single weighted cell',
      () {
    final track = [
      for (var i = 0; i < 10; i++)
        HeatLatLng(51.5 + i * 0.00001, -0.12 + i * 0.00001),
    ];
    final cells = buildHeatCells([track]);
    expect(cells.length, 1);
    expect(cells.first.weight, 10);
  });

  test('repeated routes accumulate weight in shared cells', () {
    final track = [
      const HeatLatLng(40.0, -75.0),
      const HeatLatLng(40.001, -75.0),
    ];
    final single = buildHeatCells([track]);
    final tripled = buildHeatCells([track, track, track]);
    expect(single.length, tripled.length);
    final sumSingle = single.fold<int>(0, (s, c) => s + c.weight);
    final sumTripled = tripled.fold<int>(0, (s, c) => s + c.weight);
    expect(sumTripled, sumSingle * 3);
  });

  test('distinct locations produce distinct cells', () {
    final cells = buildHeatCells([
      [const HeatLatLng(51.5, -0.12)],
      [const HeatLatLng(48.85, 2.35)],
    ]);
    expect(cells.length, 2);
  });

  test('clamps a single cell weight at kMaxCellWeight', () {
    final track = [
      for (var i = 0; i < kMaxCellWeight + 200; i++)
        const HeatLatLng(34.05, -118.24),
    ];
    final cells = buildHeatCells([track]);
    expect(cells.length, 1);
    expect(cells.first.weight, kMaxCellWeight);
  });

  test('drops invalid / out-of-range points', () {
    final cells = buildHeatCells([
      [
        const HeatLatLng(double.nan, 0),
        const HeatLatLng(0, double.infinity),
        const HeatLatLng(200, 0),
        const HeatLatLng(0, -400),
        const HeatLatLng(45, 9),
      ],
    ]);
    expect(cells.length, 1);
    expect(cells.first.weight, 1);
  });

  test(
      'quantises a negative coordinate on a grid half-boundary toward +Infinity (cross-platform parity)',
      () {
    // lng/lat = -0.5 * gridDeg sits exactly on a grid half-boundary. The
    // quantiser must round half toward +Infinity (gx = 0 → cell centre 0),
    // matching JS Math.round on the web twin — NOT Dart's raw .round() (which
    // rounds half away from zero to gx = -1). A drift here shifts the cell by
    // one grid step (~33 m) for any Americas / west-of-Greenwich track and the
    // web + mobile heatmaps disagree.
    const g = kDefaultGridDeg;
    final cells = buildHeatCells([
      [const HeatLatLng(-0.5 * g, -0.5 * g)],
    ]);
    expect(cells.length, 1);
    expect(cells.first.lat, 0);
    expect(cells.first.lng, 0);
  });

  test('empty / all-invalid input yields no cells and null bounds', () {
    expect(buildHeatCells([]), isEmpty);
    expect(buildHeatCells([[]]), isEmpty);
    expect(heatBounds([]), isNull);
  });

  test('heatBounds spans the cell extent as [[w,s],[e,n]]', () {
    final cells = buildHeatCells([
      [const HeatLatLng(10, 20), const HeatLatLng(30, 40)],
    ]);
    final b = heatBounds(cells)!;
    final w = b[0][0], s = b[0][1], e = b[1][0], n = b[1][1];
    const tol = kDefaultGridDeg;
    expect((w - 20).abs() <= tol && (s - 10).abs() <= tol, isTrue);
    expect((e - 40).abs() <= tol && (n - 30).abs() <= tol, isTrue);
    expect(w <= e && s <= n, isTrue);
  });

  test('invalid gridDeg falls back to the default', () {
    final track = [const HeatLatLng(1, 1)];
    expect(
      buildHeatCells([track], gridDeg: 0).map((c) => c.weight),
      buildHeatCells([track], gridDeg: kDefaultGridDeg).map((c) => c.weight),
    );
    expect(
      buildHeatCells([track], gridDeg: -5).first.lat,
      buildHeatCells([track], gridDeg: kDefaultGridDeg).first.lat,
    );
  });
}
