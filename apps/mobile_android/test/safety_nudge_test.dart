import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/safety_nudge.dart';

const int now = 1700000000000;

// A December day (mid-winter, northern hemisphere) and a June day.
const int dec21 = 355;
const int jun21 = 172;

bool nudgeAt(
  int minutes, {
  double? latitude,
  int? dayOfYear,
  bool autoLiveShareOn = false,
  bool isBroadcast = false,
  bool nudgeDismissed = false,
}) {
  return shouldNudgeSoloSafety(SoloSafetyNudgeInput(
    nowLocalMinutes: minutes,
    latitude: latitude,
    dayOfYear: dayOfYear,
    autoLiveShareOn: autoLiveShareOn,
    isBroadcast: isBroadcast,
    nudgeDismissed: nudgeDismissed,
  ));
}

void main() {
  test('midday is not night', () {
    expect(isNightWindow(12 * 60), false);
  });

  test('dusk boundary is inclusive, one minute before is not night', () {
    expect(isNightWindow(safetyNudgeDuskMinutes), true, reason: 'exactly 20:00 is night');
    expect(isNightWindow(safetyNudgeDuskMinutes - 1), false, reason: '19:59 is still daylight');
  });

  test('dawn boundary is exclusive, one minute before is still night', () {
    expect(isNightWindow(safetyNudgeDawnMinutes - 1), true, reason: '05:59 is night');
    expect(isNightWindow(safetyNudgeDawnMinutes), false, reason: 'exactly 06:00 is daylight');
  });

  test('the window wraps midnight', () {
    expect(isNightWindow(0), true, reason: 'midnight is night');
    expect(isNightWindow(23 * 60), true, reason: '23:00 is night');
    expect(isNightWindow(2 * 60), true, reason: '02:00 is night');
  });

  test('out-of-range minutes normalise into the day', () {
    expect(isNightWindow(24 * 60), true, reason: '1440 wraps to 00:00, night');
    expect(isNightWindow(24 * 60 + 12 * 60), false, reason: '36:00 wraps to noon');
    expect(isNightWindow(-1), true, reason: '-1 wraps to 23:59, night');
  });

  test('never-surfaced nudge is not throttled', () {
    expect(nudgeThrottled(null, now), false);
  });

  test('throttle window is exclusive at its far edge', () {
    expect(nudgeThrottled(now - (safetyNudgeThrottleMs - 1), now), true,
        reason: 'just inside stays suppressed');
    expect(nudgeThrottled(now - safetyNudgeThrottleMs, now), false,
        reason: 'exactly at the window can resurface');
  });

  test('a future-dated stamp (clock skew) throttles rather than spams', () {
    expect(nudgeThrottled(now + 5000, now), true);
  });

  test('nudges a solo after-dark run with no live share and no throttle', () {
    expect(nudgeAt(22 * 60), true);
  });

  test('does not nudge during daylight', () {
    expect(nudgeAt(12 * 60), false);
  });

  test('auto-live-share on suppresses the nudge even after dark', () {
    expect(nudgeAt(22 * 60, autoLiveShareOn: true), false);
  });

  test('an already-broadcasting run is not nudged', () {
    expect(nudgeAt(22 * 60, isBroadcast: true), false);
  });

  test('a throttled (recently surfaced) nudge stays suppressed', () {
    expect(nudgeAt(22 * 60, nudgeDismissed: true), false);
  });

  test('every suppressor is independent — daylight alone suppresses', () {
    expect(nudgeAt(9 * 60, autoLiveShareOn: false, isBroadcast: false), false);
  });

  test('winter pre-dawn at high latitude is dark (sun still down)', () {
    expect(isSunDown(7 * 60, 60, dec21), true,
        reason: '07:00 at 60°N in December is before sunrise');
  });

  test('winter midday at high latitude is light', () {
    expect(isSunDown(12 * 60, 60, dec21), false,
        reason: 'the sun is up at solar noon even in deep winter');
  });

  test('summer 06:30 at high latitude is already light', () {
    expect(isSunDown(6 * 60 + 30, 60, jun21), false,
        reason: 'high-latitude summer sun rises well before 06:30');
  });

  test('polar night is always dark', () {
    expect(isSunDown(12 * 60, 80, dec21), true,
        reason: 'the sun never rises at 80°N in December');
  });

  test('polar day (midnight sun) is never dark', () {
    expect(isSunDown(0, 80, jun21), false,
        reason: 'the sun never sets at 80°N in June');
  });

  test('isDarkOutside falls back to the fixed window when latitude is unknown', () {
    expect(isDarkOutside(22 * 60, null, null), true,
        reason: 'the fixed dusk window still fires');
    expect(isDarkOutside(12 * 60, null, null), false,
        reason: 'midday with no fix is not dark');
  });

  test('isDarkOutside adds seasonal darkness the fixed window misses', () {
    expect(isDarkOutside(7 * 60, 60, dec21), true,
        reason: 'a dark winter pre-dawn run is now dark');
    expect(isDarkOutside(6 * 60 + 30, 60, jun21), false,
        reason: 'a bright summer dawn run is not');
  });

  test('nudges a dark winter pre-7am run at high latitude (the issue #265 case)', () {
    expect(nudgeAt(7 * 60, latitude: 60, dayOfYear: dec21), true);
  });

  test('does not nudge a bright summer 06:30 run at high latitude', () {
    expect(nudgeAt(6 * 60 + 30, latitude: 60, dayOfYear: jun21), false);
  });

  test('a covered runner is not nudged even in winter darkness', () {
    expect(nudgeAt(7 * 60, latitude: 60, dayOfYear: dec21, autoLiveShareOn: true),
        false);
  });
}
