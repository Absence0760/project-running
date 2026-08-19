import 'package:flutter_test/flutter_test.dart';

import '../lib/race_plan_preset.dart';
import '../lib/training.dart';

const String _today = '2026-08-14'; // a Friday
const int _dayMs = 86400000;

int _utcDay(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]).millisecondsSinceEpoch ~/ _dayMs;
}

RacePlanPreset _ok(RacePlanPresetResult r) {
  expect(r.ok, isTrue, reason: 'expected a preset, got ${r.reason}');
  return r.preset!;
}

/// Every preset must start on a Sunday (the generator anchors day 0 of the
/// start week to the Sunday long run) and must place race day inside the
/// final — "race" — week.
void _assertAnchoring(RacePlanPreset preset, String raceDateIso) {
  final start = _utcDay(preset.startDate);
  expect(((start + 4) % 7 + 7) % 7, 0,
      reason: '${preset.startDate} is not a Sunday');
  final race = _utcDay(raceDateIso);
  final raceWeekStart = start + (preset.weeks - 1) * 7;
  expect(
    race >= raceWeekStart && race <= raceWeekStart + 6,
    isTrue,
    reason:
        'race $raceDateIso falls outside the final week of a ${preset.weeks}-week plan from ${preset.startDate}',
  );
}

void main() {
  test('a half marathon far out gets the goal default week count, anchored on race week',
      () {
    final preset = _ok(racePlanPreset(
        raceDateIso: '2026-11-15', distanceM: 21097.5, todayIso: _today));
    expect(preset.goalEvent, GoalEvent.distanceHalf);
    expect(preset.weeks, defaultPlanWeeks(GoalEvent.distanceHalf));
    expect(preset.startDate, '2026-08-30');
    _assertAnchoring(preset, '2026-11-15');
  });

  test('weeks are capped at the goal default rather than filling the whole gap', () {
    // A marathon over half a year out: 16 weeks starting later, not a 30-week grind.
    final preset = _ok(racePlanPreset(
        raceDateIso: '2027-03-14', distanceM: 42195, todayIso: _today));
    expect(preset.goalEvent, GoalEvent.distanceFull);
    expect(preset.weeks, defaultPlanWeeks(GoalEvent.distanceFull));
    expect(preset.startDate, '2026-11-29');
    _assertAnchoring(preset, '2027-03-14');
  });

  test('a nearer race shortens the plan instead of starting in the past', () {
    // Sunday 2026-10-11 is 8 race-weeks out from the first legal start.
    final preset = _ok(racePlanPreset(
        raceDateIso: '2026-10-11', distanceM: 21097.5, todayIso: _today));
    expect(preset.weeks < defaultPlanWeeks(GoalEvent.distanceHalf), isTrue);
    expect(preset.startDate, '2026-08-16'); // the first Sunday on/after today
    _assertAnchoring(preset, '2026-10-11');
  });

  test('race day mid-week still lands inside the final race week', () {
    // Wednesday. The race week starts on the Sunday *before* race day, so the
    // plan must not be sized to the Sunday after it.
    final preset = _ok(racePlanPreset(
        raceDateIso: '2026-11-11', distanceM: 10000, todayIso: _today));
    expect(preset.goalEvent, GoalEvent.distance10k);
    _assertAnchoring(preset, '2026-11-11');
    // The Sunday before 2026-11-11 is 2026-11-08.
    expect(_utcDay(preset.startDate) + (preset.weeks - 1) * 7,
        _utcDay('2026-11-08'));
  });

  test('a Saturday race is anchored to the same week as the Sunday before it', () {
    final sat = _ok(racePlanPreset(
        raceDateIso: '2026-11-14', distanceM: 5000, todayIso: _today));
    final sun = _ok(racePlanPreset(
        raceDateIso: '2026-11-08', distanceM: 5000, todayIso: _today));
    expect(sat.startDate, sun.startDate);
    _assertAnchoring(sat, '2026-11-14');
  });

  test('today may be the start date when today is a Sunday', () {
    // Exactly defaultPlanWeeks(distance5k) race-weeks out, so the cap doesn't
    // push the start later and the plan can begin today.
    final preset = _ok(racePlanPreset(
        raceDateIso: '2026-10-04', distanceM: 5000, todayIso: '2026-08-16'));
    expect(preset.weeks, defaultPlanWeeks(GoalEvent.distance5k));
    expect(preset.startDate, '2026-08-16');
  });

  test('a past race, and a race today, are refused', () {
    final past = racePlanPreset(raceDateIso: '2026-08-13', todayIso: _today);
    expect(past.ok, isFalse);
    expect(past.reason, RacePlanRefusal.past);
    final todayRace = racePlanPreset(raceDateIso: _today, todayIso: _today);
    expect(todayRace.ok, isFalse);
    expect(todayRace.reason, RacePlanRefusal.past);
  });

  test('a race too close to build a plan for is refused, not squeezed', () {
    for (final iso in ['2026-08-30', '2026-08-18']) {
      final r = racePlanPreset(raceDateIso: iso, todayIso: _today);
      expect(r.ok, isFalse, reason: iso);
      expect(r.reason, RacePlanRefusal.tooSoon, reason: iso);
    }
  });

  test('the minimum-week boundary is inclusive', () {
    // The Sunday kRacePlanMinWeeks - 1 weeks after the first legal start
    // (2026-08-16) is the first race a plan may be built for.
    final preset =
        _ok(racePlanPreset(raceDateIso: '2026-09-06', todayIso: _today));
    expect(preset.weeks, kRacePlanMinWeeks);
    expect(preset.startDate, '2026-08-16');
    final justUnder =
        racePlanPreset(raceDateIso: '2026-08-30', todayIso: _today);
    expect(justUnder.reason, RacePlanRefusal.tooSoon);
  });

  test('an unusable date is refused as invalid, never silently treated as past', () {
    const bad = ['', 'tomorrow', '2026-13-01', '2026-02-31', '26-11-15', '2026-11-15T00:00'];
    for (final iso in bad) {
      final r = racePlanPreset(raceDateIso: iso, todayIso: _today);
      expect(r.ok, isFalse, reason: iso);
      expect(r.reason, RacePlanRefusal.invalid, reason: iso);
    }
    final badToday =
        racePlanPreset(raceDateIso: '2026-11-15', todayIso: 'nope');
    expect(badToday.reason, RacePlanRefusal.invalid);
  });

  test('a distance matching no standard rung claims no goal event', () {
    // A 50k trail ultra: the wizard has no custom-distance input, so calling
    // this a marathon would train the runner for the wrong race.
    final preset = _ok(racePlanPreset(
        raceDateIso: '2027-03-14', distanceM: 50000, todayIso: _today));
    expect(preset.goalEvent, isNull);
    expect(preset.weeks, defaultPlanWeeks(GoalEvent.custom));
  });

  test('a listing with no distance still presets the dates', () {
    final preset = _ok(racePlanPreset(
        raceDateIso: '2027-03-14', distanceM: null, todayIso: _today));
    expect(preset.goalEvent, isNull);
    _assertAnchoring(preset, '2027-03-14');
  });

  test('a zero distance is read as absent, not as a zero-metre race', () {
    // A caller parsing a listing can hand us a 0 meaning "no distance". It
    // must land on exactly the no-distance result rather than on some
    // zero-length event.
    final absent = _ok(racePlanPreset(
        raceDateIso: '2027-03-14', distanceM: null, todayIso: _today));
    for (final zeroish in <num?>[0, -0.0, null]) {
      final r = _ok(racePlanPreset(
          raceDateIso: '2027-03-14', distanceM: zeroish, todayIso: _today));
      expect(r.goalEvent, absent.goalEvent, reason: '$zeroish');
      expect(r.weeks, absent.weeks, reason: '$zeroish');
      expect(r.startDate, absent.startDate, reason: '$zeroish');
    }
  });

  test('goalEventForDistance tolerates rounded listings but not neighbouring rungs',
      () {
    expect(goalEventForDistance(21100), GoalEvent.distanceHalf);
    expect(goalEventForDistance(42200), GoalEvent.distanceFull);
    expect(goalEventForDistance(5000), GoalEvent.distance5k);
    expect(goalEventForDistance(10000), GoalEvent.distance10k);
    // A 10-miler sits between rungs and gets neither.
    expect(goalEventForDistance(16093), isNull);
    for (final rung in kGoalDistancesM.values) {
      // 1.02 is the boundary itself and lands on either side of it under
      // binary rounding, so probe just inside and well outside instead.
      expect(goalEventForDistance(rung * 1.019), goalEventForDistance(rung));
      expect(goalEventForDistance(rung * 1.05), isNull);
    }
  });

  test('goalEventForDistance rejects absent and nonsense distances', () {
    for (final bad in <num?>[null, 0, -5000, double.nan, double.infinity]) {
      expect(goalEventForDistance(bad), isNull, reason: '$bad');
    }
  });

  test('a window spanning a DST transition is still counted in whole weeks', () {
    // Northern-hemisphere clocks change on 2026-11-01 (US) and 2026-10-25
    // (EU); both fall inside this window. An elapsed-time count would truncate
    // a day short and shift the anchor by a week.
    final preset = _ok(racePlanPreset(
        raceDateIso: '2026-12-06', distanceM: 42195, todayIso: '2026-08-14'));
    expect(preset.weeks, defaultPlanWeeks(GoalEvent.distanceFull));
    _assertAnchoring(preset, '2026-12-06');
    expect(preset.startDate, '2026-08-23');
  });

  test('the anchoring invariant holds for every weekday and a year of race dates',
      () {
    final start = _utcDay('2026-08-15');
    for (var offset = 0; offset < 400; offset++) {
      final iso = DateTime.fromMillisecondsSinceEpoch(
              (start + offset) * _dayMs,
              isUtc: true)
          .toIso8601String()
          .substring(0, 10);
      final r =
          racePlanPreset(raceDateIso: iso, distanceM: 21097.5, todayIso: _today);
      if (!r.ok) {
        expect(r.reason, RacePlanRefusal.tooSoon, reason: iso);
        continue;
      }
      _assertAnchoring(r.preset!, iso);
      expect(r.preset!.weeks >= kRacePlanMinWeeks, isTrue, reason: iso);
      expect(r.preset!.weeks <= defaultPlanWeeks(GoalEvent.distanceHalf), isTrue,
          reason: iso);
      expect(r.preset!.startDate.compareTo(_today) >= 0, isTrue,
          reason: '$iso starts in the past');
    }
  });
}
