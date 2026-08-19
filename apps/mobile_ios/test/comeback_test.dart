import 'package:flutter_test/flutter_test.dart';

import '../lib/comeback.dart';
import '../lib/plan_ramp.dart';
import '../lib/self_load.dart';
import '../lib/training_load.dart' show kLayoffResetDays;

const int _dayMs = 86400000;
final int _now = DateTime.parse('2026-08-14T12:00:00.000Z').millisecondsSinceEpoch;

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

RunForVolume _run(num daysAgo, double distanceM, [String activityType = 'run']) {
  return RunForVolume(
    startedAt: _iso(_now - (daysAgo * _dayMs).round()),
    distanceM: distanceM,
    activityType: activityType,
  );
}

/// A runner who trained 40 km a week for four weeks, took [layoffDays] off,
/// and has just logged [thisWeekM] in the last seven days.
List<RunForVolume> _comebackRunner(
  num layoffDays,
  double thisWeekM, [
  double baseWeeklyM = 40000,
]) {
  final lastBefore = 1 + layoffDays;
  return [
    _run(1, thisWeekM),
    _run(lastBefore, baseWeeklyM),
    _run(lastBefore + 7, baseWeeklyM),
    _run(lastBefore + 14, baseWeeklyM),
    _run(lastBefore + 21, baseWeeklyM),
  ];
}

void _expectSame(ComebackLoad a, ComebackLoad b) {
  expect(a.verdict, b.verdict);
  expect(a.layoffDays, b.layoffDays);
  expect(a.layoffWeeks, b.layoffWeeks);
  expect(a.thisWeekM, b.thisWeekM);
  expect(a.preLayoffWeeklyM, b.preLayoffWeeklyM);
  expect(a.share, b.share);
}

void main() {
  test('the layoff threshold is the fitness-reset one, not a second number', () {
    expect(kLayoffMinDays, kLayoffResetDays);
  });

  test('a gentle first week back is graded easing_in', () {
    final load = comebackLoad(_comebackRunner(70, 12000), _now);
    expect(load.verdict, ComebackVerdict.easingIn);
    expect(load.thisWeekM, 12000);
    expect(load.preLayoffWeeklyM, 160000 / kChronicWindowWeeks);
    expect((load.share - 0.3).abs() < 1e-9, isTrue);
    expect(load.layoffDays, 70);
    expect(load.layoffWeeks, 10);
  });

  test('a big first week back is graded steep', () {
    final load = comebackLoad(_comebackRunner(70, 36000), _now);
    expect(load.verdict, ComebackVerdict.steep);
    expect((load.share - 0.9).abs() < 1e-9, isTrue);
  });

  test('the steep threshold is exclusive — exactly half the old base still eases in', () {
    final half = kReturnWeekShare * 40000;
    expect(comebackLoad(_comebackRunner(70, half), _now).verdict,
        ComebackVerdict.easingIn);
    expect(comebackLoad(_comebackRunner(70, half + 1), _now).verdict,
        ComebackVerdict.steep);
  });

  test('layoff weeks round to nearest so a break is never understated', () {
    // 32 days is 4.57 weeks — the case that separates rounding from flooring,
    // which would report 4 and undersell the break by most of a week.
    expect(comebackLoad(_comebackRunner(32, 12000), _now).layoffWeeks, 5);
    expect(comebackLoad(_comebackRunner(45, 12000), _now).layoffWeeks, 6);
  });

  test('a rest week shorter than the layoff threshold is not a comeback', () {
    final load = comebackLoad(_comebackRunner(kLayoffMinDays - 2, 30000), _now);
    expect(load.verdict, ComebackVerdict.insufficient);
  });

  test('a break long enough to reset fitness is a comeback', () {
    final load = comebackLoad(_comebackRunner(kLayoffMinDays, 30000), _now);
    expect(load.verdict, isNot(ComebackVerdict.insufficient));
  });

  test('a base too stale to anchor against says nothing rather than reassuring', () {
    final stale = comebackLoad(_comebackRunner(kLayoffMaxDays + 1, 30000), _now);
    expect(stale.verdict, ComebackVerdict.insufficient);
    expect(stale.share, 0);
    expect(stale.layoffDays, 0);
    final fresh = comebackLoad(_comebackRunner(kLayoffMaxDays, 30000), _now);
    expect(fresh.verdict, isNot(ComebackVerdict.insufficient));
  });

  test('a single run before the break is not a base to come back to', () {
    final load = comebackLoad([_run(1, 30000), _run(71, 40000)], _now);
    expect(load.verdict, ComebackVerdict.insufficient);
  });

  test('the pre-break base needs kMinActiveWeeks of its own windows', () {
    final twoWeeks = [_run(1, 30000), _run(71, 40000), _run(78, 40000)];
    expect(comebackLoad(twoWeeks, _now).verdict, ComebackVerdict.insufficient);
    expect(kMinActiveWeeks, 3);
    final threeWeeks = [...twoWeeks, _run(85, 40000)];
    expect(comebackLoad(threeWeeks, _now).verdict,
        isNot(ComebackVerdict.insufficient));
  });

  test('a week with no running is not graded as a gentle return', () {
    final idle = _comebackRunner(70, 12000).sublist(1);
    expect(comebackLoad(idle, _now).verdict, ComebackVerdict.insufficient);
  });

  test('a runner who never stopped is not on a comeback', () {
    final steady = [_run(1, 40000), _run(8, 40000), _run(15, 40000), _run(22, 40000)];
    expect(comebackLoad(steady, _now).verdict, ComebackVerdict.insufficient);
  });

  test('an empty history says nothing', () {
    expect(comebackLoad(const [], _now).verdict, ComebackVerdict.insufficient);
  });

  test('a run stamped in the future does not inflate the break it appears to open', () {
    // A clock 40 days ahead puts today's run in the future; the hole between
    // it and the runner's last real session reads as 70 days unclamped, and
    // 30 — the break they actually took — once the stamp is pulled back to now.
    final runs = [
      _run(-40, 10000),
      _run(30, 40000),
      _run(37, 40000),
      _run(44, 40000),
      _run(51, 40000),
    ];
    final load = comebackLoad(runs, _now);
    expect(load.layoffDays, 30);
    expect(load.thisWeekM, 10000);
  });

  test('a skewed stamp grades identically to an honest one', () {
    final base = [_run(60, 40000), _run(67, 40000), _run(74, 40000), _run(81, 40000)];
    final skewed = comebackLoad([_run(-100, 8000), ...base], _now);
    final honest = comebackLoad([_run(0, 8000), ...base], _now);
    _expectSame(skewed, honest);
    expect(honest.layoffDays, 60);
  });

  test('the two load cards are mutually exclusive by construction', () {
    final cases = <List<RunForVolume>>[
      _comebackRunner(70, 36000),
      _comebackRunner(70, 12000),
      _comebackRunner(kLayoffMinDays - 2, 30000),
      [_run(1, 40000), _run(8, 40000), _run(15, 40000), _run(22, 40000)],
      // Back for three consecutive weeks: the ratio can carry the question
      // again, so the comeback card must stand down.
      [
        _run(1, 30000),
        _run(8, 20000),
        _run(15, 10000),
        _run(80, 40000),
        _run(87, 40000),
        _run(94, 40000),
      ],
      const [],
    ];
    for (final runs in cases) {
      final ratio = shouldSurfaceSelfLoad(selfLoad(runs, _now));
      final comeback = shouldSurfaceComeback(comebackLoad(runs, _now));
      expect(ratio && comeback, isFalse,
          reason: 'both load cards surfaced for the same history');
    }
  });

  test('a returned runner with three active weeks is handed back to the ratio card', () {
    final runs = [
      _run(1, 30000),
      _run(8, 20000),
      _run(15, 10000),
      _run(80, 40000),
      _run(87, 40000),
      _run(94, 40000),
    ];
    expect(comebackLoad(runs, _now).verdict, ComebackVerdict.insufficient);
    expect(shouldSurfaceSelfLoad(selfLoad(runs, _now)), isTrue);
  });

  test('the most recent break is the one graded, not an older one', () {
    final runs = [
      _run(1, 30000),
      _run(41, 40000),
      _run(48, 40000),
      _run(55, 40000),
      _run(62, 40000),
      // An older, longer break sits behind a full pre-break base.
      _run(400, 90000),
    ];
    final load = comebackLoad(runs, _now);
    expect(load.layoffDays, 40);
    expect(load.preLayoffWeeklyM, 160000 / kChronicWindowWeeks);
  });

  test('cycling is not running volume on either side of the break', () {
    final runs = [
      _run(1, 12000),
      _run(2, 60000, 'cycle'),
      _run(71, 40000),
      _run(78, 40000),
      _run(85, 40000),
      _run(86, 100000, 'cycle'),
    ];
    final load = comebackLoad(runs, _now);
    expect(load.thisWeekM, 12000);
    expect(load.preLayoffWeeklyM, 120000 / kChronicWindowWeeks);
  });

  test('unparseable and non-positive rows are dropped rather than read as a break', () {
    final runs = [
      _run(1, 12000),
      const RunForVolume(
        startedAt: 'not-a-date',
        distanceM: 50000,
        activityType: 'run',
      ),
      RunForVolume(
        startedAt: _iso(_now - 35 * _dayMs),
        distanceM: 0,
        activityType: 'run',
      ),
      _run(71, 40000),
      _run(78, 40000),
      _run(85, 40000),
    ];
    final load = comebackLoad(runs, _now);
    expect(load.verdict, ComebackVerdict.easingIn);
    expect(load.layoffDays, 70);
  });

  test('shouldSurfaceComeback narrows to the verdicts the card has copy for', () {
    // Web's predicate makes an unlabelled verdict a compile error; Dart cannot
    // narrow through a bool, so the guarantee is pinned here instead.
    final load = comebackLoad(_comebackRunner(70, 36000), _now);
    expect(shouldSurfaceComeback(load), isTrue);
    final verdict = switch (load.verdict) {
      ComebackVerdict.easingIn => 'easing_in',
      ComebackVerdict.steep => 'steep',
      ComebackVerdict.insufficient => fail('a steep return should surface'),
    };
    expect(verdict, 'steep');
    expect(shouldSurfaceComeback(comebackLoad(const [], _now)), isFalse);
  });
}
