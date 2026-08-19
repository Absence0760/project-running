import 'package:flutter_test/flutter_test.dart';

import '../lib/coach_load.dart';
import '../lib/plan_ramp.dart';
import '../lib/self_load.dart';

const int _dayMs = 86400000;
final int _now = DateTime.parse('2026-08-14T12:00:00.000Z').millisecondsSinceEpoch;

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

/// A run [daysAgo] days back carrying [distanceM] metres.
RunForVolume _run(num daysAgo, double distanceM, [String activityType = 'run']) {
  return RunForVolume(
    startedAt: _iso(_now - (daysAgo * _dayMs).round()),
    distanceM: distanceM,
    activityType: activityType,
  );
}

/// One run in each of the four chronic windows, so `activeWeeks` clears the
/// gate; the acute window's distance is the caller's to choose.
List<RunForVolume> _withBase(double acuteM, [double weeklyM = 40000]) => [
      _run(1, acuteM),
      _run(8, weeklyM),
      _run(15, weeklyM),
      _run(22, weeklyM),
    ];

void main() {
  test('a steady month sits in the optimal band', () {
    final load = selfLoad(_withBase(40000), _now);
    expect(load.band, InjuryRiskBand.optimal);
    expect(load.trend, LoadTrend.steady);
    expect((load.ratio - 1).abs() < 1e-9, isTrue);
    expect(load.acuteM, 40000);
    expect(load.chronicWeeklyM, 160000 / kChronicWindowWeeks);
  });

  test('a spike week is graded high and reads as ramping', () {
    final load = selfLoad(_withBase(120000, 40000), _now);
    // The chronic window includes the acute week: (120 + 3*40)/4 = 60 km/wk.
    expect(load.chronicWeeklyM, 60000);
    expect((load.ratio - 2).abs() < 1e-9, isTrue);
    expect(load.band, InjuryRiskBand.high);
    expect(load.trend, LoadTrend.ramping);
  });

  test('a down week is graded low and reads as tapering', () {
    final load = selfLoad(_withBase(10000, 40000), _now);
    expect(load.band, InjuryRiskBand.low);
    expect(load.trend, LoadTrend.tapering);
    expect(load.ratio < acwrLowMax, isTrue);
  });

  test('the band edges are the coach roster edges, not a second set', () {
    // Drive the ratio to each boundary and check the label flips where
    // coach_load says it does — the whole point of composing rather than
    // re-deriving. The chronic average includes the acute week, so hitting a
    // target ratio r against a base W needs an acute of 3rW/(4-r):
    // r = 4A/(A+3W)  =>  A = 3rW/(4 - r).
    const w = 40000.0;
    double acuteFor(double r) => (3 * r * w) / (4 - r);
    InjuryRiskBand at(double r) => selfLoad(_withBase(acuteFor(r), w), _now).band;
    // Sanity-check the inversion itself before trusting the boundaries.
    expect(
      (selfLoad(_withBase(acuteFor(1.2), w), _now).ratio - 1.2).abs() < 1e-9,
      isTrue,
    );

    // Probed either side of each edge rather than exactly on it: the acute
    // distance that lands on a boundary is irrational through this inversion,
    // so a float round-trip settles a hair below and the on-edge case tests
    // binary rounding, not the policy.
    final edges = <List<Object>>[
      [acwrLowMax, InjuryRiskBand.low, InjuryRiskBand.optimal],
      [acwrOptimalMax, InjuryRiskBand.optimal, InjuryRiskBand.elevated],
      [acwrElevatedMax, InjuryRiskBand.elevated, InjuryRiskBand.high],
    ];
    for (final row in edges) {
      final edge = row[0] as double;
      expect(at(edge - 0.01), row[1], reason: 'just below $edge');
      expect(at(edge + 0.01), row[2], reason: 'just above $edge');
    }
  });

  test('a thin history is refused rather than graded', () {
    // One big run in an otherwise empty month is exactly the shape that
    // manufactures a terrifying ratio out of a runner who has barely trained.
    final load = selfLoad([_run(1, 30000)], _now);
    expect(load.band, InjuryRiskBand.insufficient);
    expect(load.ratio, 0);
    expect(shouldSurfaceSelfLoad(load), isFalse);
  });

  test('the active-week gate is exactly kMinActiveWeeks, inclusive', () {
    final justUnder = [_run(1, 40000), _run(8, 40000)]; // 2 active weeks
    expect(selfLoad(justUnder, _now).activeWeeks, kMinActiveWeeks - 1);
    expect(selfLoad(justUnder, _now).band, InjuryRiskBand.insufficient);

    final justEnough = [_run(1, 40000), _run(8, 40000), _run(15, 40000)];
    expect(selfLoad(justEnough, _now).activeWeeks, kMinActiveWeeks);
    expect(selfLoad(justEnough, _now).band, isNot(InjuryRiskBand.insufficient));
  });

  test('no runs at all is insufficient, never a reassuring low', () {
    final load = selfLoad(const [], _now);
    expect(load.band, InjuryRiskBand.insufficient);
    expect(load.acuteM, 0);
    expect(load.chronicWeeklyM, 0);
    expect(shouldSurfaceSelfLoad(load), isFalse);
  });

  test('a rest week on a real base is graded, not refused', () {
    // Zero acute distance against a genuine chronic base is a meaningful
    // reading — a taper — not missing data.
    final load = selfLoad([_run(8, 40000), _run(15, 40000), _run(22, 40000)], _now);
    expect(load.acuteM, 0);
    expect(load.band, InjuryRiskBand.low);
    expect(load.trend, LoadTrend.tapering);
    expect(shouldSurfaceSelfLoad(load), isTrue);
  });

  test('cycling is not running volume, on either side of the ratio', () {
    final withRide = [
      ..._withBase(40000),
      _run(2, 100000, 'cycle'),
      _run(9, 100000, 'cycle'),
    ];
    final ride = selfLoad(withRide, _now);
    final plain = selfLoad(_withBase(40000), _now);
    expect(ride.band, plain.band);
    expect(ride.trend, plain.trend);
    expect(ride.ratio, plain.ratio);
    expect(ride.acuteM, plain.acuteM);
    expect(ride.chronicWeeklyM, plain.chronicWeeklyM);
    expect(ride.activeWeeks, plain.activeWeeks);
  });

  test('a DNF still counts the distance the runner covered', () {
    // Deliberately divergent from the coach roster, which excludes DNFs.
    // Nothing rewrites distanceM when the flag is set, so the load was
    // absorbed; dropping it would under-report a spike, which is the
    // dangerous direction for a safety signal (decisions § 592).
    final dnf = [
      RunForVolume(
        startedAt: _iso(_now - _dayMs),
        distanceM: 80000,
        activityType: 'run',
        isDnf: true,
      ),
      _run(8, 40000),
      _run(15, 40000),
      _run(22, 40000),
    ];
    final load = selfLoad(dnf, _now);
    expect(load.acuteM, 80000);
    expect(load.band, InjuryRiskBand.high);
  });

  test('the distance ratio equals the coach roster stress ratio', () {
    // The roster divides km*10 stress sums; this divides metres. The proxy is
    // linear in distance, so the quotient is identical — which is why the
    // constant is not duplicated here. If someone makes the roster's stress
    // non-linear, this equality breaks and this test is the warning.
    final runs = _withBase(52000, 37000);
    final load = selfLoad(runs, _now);
    final recent = recentRunVolume(runs, _now);
    double stress(double metres) => (metres / 1000) * 10;
    expect(
      (load.ratio - acwr(stress(recent.acuteM), stress(recent.weeklyM))).abs() < 1e-9,
      isTrue,
    );
  });

  test('a run stamped in the future counts as this week, not as a dropped row', () {
    final ahead = [_run(-1, 40000), _run(8, 40000), _run(15, 40000), _run(22, 40000)];
    expect(selfLoad(ahead, _now).acuteM, 40000);
  });

  test('runs older than the chronic window do not dilute the base', () {
    final stale = [..._withBase(40000), _run(40, 200000), _run(90, 200000)];
    final aged = selfLoad(stale, _now);
    final plain = selfLoad(_withBase(40000), _now);
    expect(aged.band, plain.band);
    expect(aged.ratio, plain.ratio);
    expect(aged.chronicWeeklyM, plain.chronicWeeklyM);
    expect(aged.activeWeeks, plain.activeWeeks);
  });

  test('shouldSurfaceSelfLoad admits every gradeable band', () {
    for (final acuteM in [10000.0, 40000.0, 55000.0, 80000.0]) {
      final load = selfLoad(_withBase(acuteM), _now);
      expect(load.band, isNot(InjuryRiskBand.insufficient));
      expect(shouldSurfaceSelfLoad(load), isTrue, reason: '$acuteM');
    }
  });

  test('shouldSurfaceSelfLoad narrows the band to the ones a caller has copy for', () {
    // Web's predicate makes an unlabelled band a compile error; Dart cannot
    // narrow a field's enum through a bool, so the guarantee is pinned here
    // instead — a surfaced band always lands on one of the four with copy.
    final load = selfLoad(_withBase(40000), _now);
    expect(shouldSurfaceSelfLoad(load), isTrue);
    final band = switch (load.band) {
      InjuryRiskBand.low => 'low',
      InjuryRiskBand.optimal => 'optimal',
      InjuryRiskBand.elevated => 'elevated',
      InjuryRiskBand.high => 'high',
      InjuryRiskBand.insufficient => fail('a graded month should surface'),
    };
    expect(band, 'optimal');
  });
}
