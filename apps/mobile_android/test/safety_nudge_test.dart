import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/safety_nudge.dart';

const int now = 1700000000000;

bool nudgeAt(
  int minutes, {
  bool autoLiveShareOn = false,
  bool isBroadcast = false,
  bool nudgeDismissed = false,
}) {
  return shouldNudgeSoloSafety(SoloSafetyNudgeInput(
    nowLocalMinutes: minutes,
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
}
