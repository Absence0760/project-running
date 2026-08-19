import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_ramp.dart';

const int _dayMs = 86400000;
final int _now = DateTime.parse('2026-08-13T09:00:00.000Z').millisecondsSinceEpoch;

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

RunForVolume _run(num daysAgo, double distanceM, [String activityType = 'run']) {
  return RunForVolume(
    startedAt: _iso(_now - (daysAgo * _dayMs).round()),
    distanceM: distanceM,
    activityType: activityType,
  );
}

/// One run in each of the four trailing windows, so the active-weeks gate
/// passes and the chronic average is exactly [perWeekM].
List<RunForVolume> _fourActiveWeeks(double perWeekM) => [
      _run(1, perWeekM),
      _run(8, perWeekM),
      _run(15, perWeekM),
      _run(22, perWeekM),
    ];

void main() {
  // ─────────────────────── recentRunVolume ───────────────────────

  test('recentRunVolume: totals the window and divides by its width', () {
    final v = recentRunVolume(_fourActiveWeeks(20000), _now);
    expect(v.weeklyM, 20000);
    expect(v.activeWeeks, 4);
  });

  test('recentRunVolume: no runs is a zero base with no active weeks', () {
    final v = recentRunVolume(const [], _now);
    expect(v.weeklyM, 0);
    expect(v.activeWeeks, 0);
  });

  test('recentRunVolume: runs older than the window are excluded', () {
    // 28 days ago is the first instant outside the four 7-day windows.
    final v = recentRunVolume([_run(28, 50000), _run(3, 10000)], _now);
    expect(v.weeklyM, 10000 / kChronicWindowWeeks);
    expect(v.activeWeeks, 1);
  });

  test('recentRunVolume: the last instant inside the window still counts', () {
    final v = recentRunVolume([
      RunForVolume(startedAt: _iso(_now - 28 * _dayMs + 1), distanceM: 8000),
    ], _now);
    expect(v.activeWeeks, 1);
    expect(v.weeklyM, 2000);
  });

  test('recentRunVolume: several runs in one window count once toward active weeks',
      () {
    final v = recentRunVolume([_run(1, 5000), _run(2, 5000), _run(3, 5000)], _now);
    expect(v.activeWeeks, 1);
    expect(v.weeklyM, 15000 / kChronicWindowWeeks);
  });

  test('recentRunVolume: cycling is not running volume', () {
    final v = recentRunVolume([_run(1, 60000, 'cycle'), _run(2, 8000)], _now);
    expect(v.weeklyM, 2000);
    expect(v.activeWeeks, 1);
  });

  test('recentRunVolume: a DNF is distance the runner covered, so it counts', () {
    // The coach roster excludes is_dnf runs; its question is which efforts the
    // athlete COMPLETED. This check's question is what the legs absorbed, and a
    // race abandoned at 30 km still put 30 km through them. The flag is only
    // ever applied after the fact to a recorded run — nothing rewrites
    // `distance_m` when it is set. Excluding these would understate the base of
    // exactly the runners most likely to carry one, and warn them off a plan
    // their history supports. See decisions § 592.
    final v = recentRunVolume([
      RunForVolume(
        startedAt: _iso(_now - _dayMs),
        distanceM: 30000,
        activityType: 'run',
        isDnf: true,
      ),
    ], _now);
    expect(v.weeklyM, 7500);
    expect(v.activeWeeks, 1);
  });

  test('recentRunVolume: a DNF on a bike is still not running volume', () {
    // The two rules compose in the order that matters: covered-distance-counts
    // does not readmit a discipline the legs never ran.
    final v = recentRunVolume([
      RunForVolume(
        startedAt: _iso(_now - _dayMs),
        distanceM: 60000,
        activityType: 'cycle',
        isDnf: true,
      ),
    ], _now);
    expect(v.weeklyM, 0);
    expect(v.activeWeeks, 0);
  });

  test('recentRunVolume: walks, hikes and treadmill runs are load and do count',
      () {
    final v = recentRunVolume([
      _run(1, 4000, 'walk'),
      _run(2, 6000, 'hike'),
      _run(3, 10000),
    ], _now);
    expect(v.weeklyM, 5000);
  });

  test('recentRunVolume: missing / non-finite / non-positive distances are skipped',
      () {
    final v = recentRunVolume([
      RunForVolume(startedAt: _iso(_now - _dayMs), distanceM: null),
      RunForVolume(startedAt: _iso(_now - _dayMs), distanceM: double.nan),
      RunForVolume(startedAt: _iso(_now - _dayMs), distanceM: 0),
      _run(1, 12000),
    ], _now);
    expect(v.weeklyM, 3000);
    expect(v.activeWeeks, 1);
  });

  test('recentRunVolume: an unparseable timestamp is skipped, not bucketed at zero',
      () {
    final v = recentRunVolume(
      const [RunForVolume(startedAt: 'not-a-date', distanceM: 10000)],
      _now,
    );
    expect(v.weeklyM, 0);
    expect(v.activeWeeks, 0);
  });

  test('recentRunVolume: a future-stamped run counts as this week, not dropped',
      () {
    // A device clock running an hour fast must not lose the run just finished.
    final v = recentRunVolume([
      RunForVolume(startedAt: _iso(_now + 3600000), distanceM: 8000),
    ], _now);
    expect(v.activeWeeks, 1);
    expect(v.weeklyM, 2000);
  });

  // ─────────────────────── openingWeekVolumeM ───────────────────────

  test('openingWeekVolumeM: takes the lowest weekIndex, not the first element',
      () {
    expect(
      openingWeekVolumeM(const [
        PlanWeekVolume(weekIndex: 2, targetVolumeM: 40000),
        PlanWeekVolume(weekIndex: 0, targetVolumeM: 25000),
        PlanWeekVolume(weekIndex: 1, targetVolumeM: 30000),
      ]),
      25000,
    );
  });

  test('openingWeekVolumeM: empty plan is zero', () {
    expect(openingWeekVolumeM(const []), 0);
  });

  test('openingWeekVolumeM: non-finite rows are ignored', () {
    expect(
      openingWeekVolumeM([
        const PlanWeekVolume(weekIndex: 0, targetVolumeM: double.nan),
        const PlanWeekVolume(weekIndex: 1, targetVolumeM: 25000),
      ]),
      25000,
    );
  });

  // ─────────────────────── peakWeekVolumeM ───────────────────────

  test('peakWeekVolumeM: takes the heaviest week', () {
    expect(
      peakWeekVolumeM(const [
        PlanWeekVolume(weekIndex: 0, targetVolumeM: 25000),
        PlanWeekVolume(weekIndex: 1, targetVolumeM: 59000),
        PlanWeekVolume(weekIndex: 2, targetVolumeM: 32000),
      ]),
      59000,
    );
  });

  test('peakWeekVolumeM: empty plan is zero', () {
    expect(peakWeekVolumeM(const []), 0);
  });

  test('peakWeekVolumeM: non-finite rows are ignored', () {
    expect(
      peakWeekVolumeM(const [
        PlanWeekVolume(weekIndex: 0, targetVolumeM: double.nan),
        PlanWeekVolume(weekIndex: 1, targetVolumeM: 30000),
      ]),
      30000,
    );
  });

  // ─────────────────────── planRampCheck ───────────────────────

  test('planRampCheck: fewer than the minimum active weeks is unknown', () {
    final recent = recentRunVolume([_run(1, 20000), _run(8, 20000)], _now);
    expect(recent.activeWeeks, kMinActiveWeeks - 1);
    final check = planRampCheck(38000, 59000, recent);
    expect(check.verdict, PlanRampVerdict.unknown);
    expect(check.openingRatio, 0);
    expect(check.peakRatio, 0);
  });

  test('planRampCheck: exactly the minimum active weeks does grade', () {
    final recent = recentRunVolume(
      [_run(1, 20000), _run(8, 20000), _run(15, 20000)],
      _now,
    );
    expect(recent.activeWeeks, kMinActiveWeeks);
    expect(planRampCheck(38000, 59000, recent).verdict, PlanRampVerdict.high);
  });

  test('planRampCheck: a runner with no history is unknown, never high', () {
    // The beginner case the gate exists for: one short jog in a month must
    // not turn a C25K opening week into an injury-risk warning.
    final recent = recentRunVolume([_run(5, 3000)], _now);
    expect(planRampCheck(6000, 9000, recent).verdict, PlanRampVerdict.unknown);
  });

  test('planRampCheck: a plan with no volume to grade is unknown', () {
    final recent = recentRunVolume(_fourActiveWeeks(20000), _now);
    expect(planRampCheck(0, 59000, recent).verdict, PlanRampVerdict.unknown);
    expect(
      planRampCheck(double.nan, 59000, recent).verdict,
      PlanRampVerdict.unknown,
    );
    expect(planRampCheck(38000, 0, recent).verdict, PlanRampVerdict.unknown);
    expect(
      planRampCheck(38000, double.nan, recent).verdict,
      PlanRampVerdict.unknown,
    );
  });

  test('planRampCheck: band edges match the coach_load ACWR policy', () {
    const recent = RecentVolume(weeklyM: 100000, acuteM: 0, activeWeeks: 4);
    PlanRampVerdict at(double m) => planRampCheck(m, m, recent).verdict;
    expect(at(79000), PlanRampVerdict.under);
    expect(at(80000), PlanRampVerdict.matched);
    expect(at(129000), PlanRampVerdict.matched);
    expect(at(130000), PlanRampVerdict.elevated);
    expect(at(149000), PlanRampVerdict.elevated);
    expect(at(150000), PlanRampVerdict.high);
  });

  test('planRampCheck: reports both ratios it graded on', () {
    final check = planRampCheck(
      38000,
      59000,
      const RecentVolume(weeklyM: 20000, acuteM: 0, activeWeeks: 4),
    );
    expect(check.verdict, PlanRampVerdict.high);
    expect(check.openingRatio, 1.9);
    expect(check.peakRatio, 2.95);
    expect(check.openingWeekM, 38000);
    expect(check.peakWeekM, 59000);
    expect(check.recentWeeklyM, 20000);
  });

  test('planRampCheck: the real marathon-on-20km case reads high', () {
    // generatePlan(goalEvent: distanceFull, daysPerWeek: 4) with a goal time
    // emits a 38.0 km opening week and a 59.0 km peak. A runner averaging
    // 20 km a week is being asked for 1.9x their current load in week 1 — the
    // case this whole check exists for.
    final recent = recentRunVolume(_fourActiveWeeks(20000), _now);
    expect(planRampCheck(38000, 59000, recent).verdict, PlanRampVerdict.high);
  });

  test('planRampCheck: "under" is graded off the peak week, not the opening one',
      () {
    // A runner already at 55 km/week building the same marathon plan. Its
    // opening week (38 km) is BELOW their current load — every plan opens
    // below its own peak — but the plan builds past them, so it is not too
    // light. Grading "under" off the opening week would have called it so.
    final check = planRampCheck(
      38000,
      59000,
      const RecentVolume(weeklyM: 55000, acuteM: 0, activeWeeks: 4),
    );
    expect(check.openingRatio < 0.8, isTrue);
    expect(check.verdict, PlanRampVerdict.matched);
  });

  test('planRampCheck: a plan that never reaches the runner reads under', () {
    // The same 55 km/week runner picking a 5K plan: 14 km opening, 20 km peak.
    final check = planRampCheck(
      14000,
      20000,
      const RecentVolume(weeklyM: 55000, acuteM: 0, activeWeeks: 4),
    );
    expect(check.verdict, PlanRampVerdict.under);
  });

  test('planRampCheck: an oversized opening week wins over a light peak', () {
    // Not reachable from the generator (peak >= opening always), but a pasted
    // or hand-edited plan can invert them, and safety is the arm that must win.
    final check = planRampCheck(
      200000,
      50000,
      const RecentVolume(weeklyM: 100000, acuteM: 0, activeWeeks: 4),
    );
    expect(check.verdict, PlanRampVerdict.high);
  });

  // ─────────────────────── shouldSurfaceRampNote ───────────────────────

  test('shouldSurfaceRampNote: silent when the plan matches the runner', () {
    expect(
      shouldSurfaceRampNote(planRampCheck(100000, 100000,
          const RecentVolume(weeklyM: 100000, acuteM: 0, activeWeeks: 4))),
      isFalse,
    );
  });

  test('shouldSurfaceRampNote: silent when there is not enough history to speak',
      () {
    expect(
      shouldSurfaceRampNote(planRampCheck(38000, 59000,
          const RecentVolume(weeklyM: 0, acuteM: 0, activeWeeks: 0))),
      isFalse,
    );
  });

  test('shouldSurfaceRampNote: speaks on both elevated and high', () {
    expect(
      shouldSurfaceRampNote(planRampCheck(140000, 140000,
          const RecentVolume(weeklyM: 100000, acuteM: 0, activeWeeks: 4))),
      isTrue,
    );
    expect(
      shouldSurfaceRampNote(planRampCheck(200000, 200000,
          const RecentVolume(weeklyM: 100000, acuteM: 0, activeWeeks: 4))),
      isTrue,
    );
  });

  test('shouldSurfaceRampNote: an under-cooked plan is worth saying', () {
    expect(
      shouldSurfaceRampNote(planRampCheck(40000, 40000,
          const RecentVolume(weeklyM: 100000, acuteM: 0, activeWeeks: 4))),
      isTrue,
    );
  });

  test('shouldSurfaceRampNote: but not to a runner who asked for a walk-run plan',
      () {
    final check = planRampCheck(40000, 40000,
        const RecentVolume(weeklyM: 100000, acuteM: 0, activeWeeks: 4));
    expect(check.verdict, PlanRampVerdict.under);
    expect(shouldSurfaceRampNote(check, beginnerWalkRun: true), isFalse);
  });

  test('shouldSurfaceRampNote: a walk-run plan still gets the safety warnings',
      () {
    final check = planRampCheck(200000, 200000,
        const RecentVolume(weeklyM: 100000, acuteM: 0, activeWeeks: 4));
    expect(shouldSurfaceRampNote(check, beginnerWalkRun: true), isTrue);
  });
}
