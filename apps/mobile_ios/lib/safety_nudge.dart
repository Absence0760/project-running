/// Solo-run safety nudge decision: should the run screen prompt a runner
/// who is recording a solo, non-broadcast run after dark to share a live
/// link? The auto-live-share + overdue-escalation net (safety.md) only
/// protects live-broadcast runs — a runner who never turned on
/// `auto_live_share` and never shared a link gets no safety net at all,
/// which is exactly the persona-woman "off-route / no-live-share solo
/// run" gap. This is the one-time, throttled, dismissible prompt that
/// closes it without adding start-flow friction.
///
/// Pure + structured (no language, no clock, no I/O) so it is trivially
/// testable and the run screen can inject `now`. TS↔Dart parity pair with
/// `apps/web/src/lib/safety/safety_nudge.ts` — keep in lockstep.
///
/// Recording is mobile-only, so the *surface* lives on the run screen;
/// this decision helper is the twinned logic (decisions §24 — the pure
/// core is canonical, the banner is the platform-additive surface).
library;

import 'dart:math' as math;

/// Dusk / dawn boundaries, in local minutes since midnight, marking the
/// fixed "after dark" window that is always treated as night regardless of
/// latitude or season. This is the deterministic FLOOR: a run in this
/// window nudges everywhere on earth with no GPS fix required. Seasonal
/// darkness (dark winter mornings / evenings at higher latitudes) is added
/// ON TOP of it by [isSunDown] when a latitude + day-of-year are known — the
/// window only ever widens, never narrows, so behaviour can't regress and
/// the fixed window absorbs the solar model's noon-assumption error.
const int safetyNudgeDuskMinutes = 20 * 60;
const int safetyNudgeDawnMinutes = 6 * 60;

/// Sun altitude (degrees) at/below which it counts as dark for the nudge.
/// The standard sunrise/sunset value (−0.833° = geometric horizon − mean
/// atmospheric refraction − solar semidiameter): "the sun has gone down".
/// Slightly below the horizon rather than into twilight so we err toward
/// nudging (start at sunset), never toward missing a dark run.
const double sunDownAltitudeDeg = -0.833;

/// How long surfacing the nudge suppresses it before it can resurface.
/// Long enough that a runner who has seen (and understood) the prompt is
/// not nagged every night, short enough that a lapsed habit gets an
/// occasional reminder. The nudge is otherwise dismissible on sight.
const int safetyNudgeThrottleMs = 30 * 24 * 60 * 60 * 1000;

/// True when [nowLocalMinutes] falls in the fixed dusk→dawn window. Wraps
/// midnight: night if at/after dusk OR before dawn. Input is normalised
/// into [0, 1440) so a caller passing a raw hour*60+min never trips on a
/// stray out-of-range value.
bool isNightWindow(int nowLocalMinutes) {
  final m = ((nowLocalMinutes % 1440) + 1440) % 1440;
  return m >= safetyNudgeDuskMinutes || m < safetyNudgeDawnMinutes;
}

/// Solar declination (degrees) for a 1-based day-of-year (Cooper's
/// approximation). Normalised into 1..365 so an out-of-range day can't
/// throw the trig off. Positive near the June solstice, negative near
/// December.
double _solarDeclinationDeg(int dayOfYear) {
  final d = (((dayOfYear - 1) % 365) + 365) % 365 + 1;
  return -23.44 * math.cos((2 * math.pi / 365) * (d + 10));
}

/// True when the sun is at/below [sunDownAltitudeDeg] at [latitude] on
/// [dayOfYear] at [nowLocalMinutes] — the seasonal, latitude-aware "is it
/// dark" test that catches dark pre-dawn winter runs at higher latitudes
/// (the gap the fixed window misses). Models solar noon at local 12:00 and
/// derives symmetric sunrise/sunset from the day's half-arc; it deliberately
/// ignores longitude-within-timezone / equation-of-time / DST (up to ~1 h of
/// clock error) because the fixed [isNightWindow] floor absorbs that — this
/// only ever ADDS darkness. Handles the polar cases: sun never rises →
/// always dark, sun never sets → never dark.
bool isSunDown(int nowLocalMinutes, double latitude, int dayOfYear) {
  final m = ((nowLocalMinutes % 1440) + 1440) % 1440;
  const rad = math.pi / 180;
  final decl = _solarDeclinationDeg(dayOfYear) * rad;
  final lat = latitude * rad;
  const h0 = sunDownAltitudeDeg * rad;
  final cosH = (math.sin(h0) - math.sin(lat) * math.sin(decl)) /
      (math.cos(lat) * math.cos(decl));
  if (cosH.isNaN) return true; // degenerate (pole) → fail-safe dark
  if (cosH <= -1) return false; // polar day: sun never sets
  if (cosH >= 1) return true; // polar night: sun never rises
  final halfDayMinutes = (math.acos(cosH) / rad) * 4; // 4 minutes of clock per degree
  final sunrise = 720 - halfDayMinutes;
  final sunset = 720 + halfDayMinutes;
  return m < sunrise || m >= sunset;
}

/// The combined "after dark" decision: the fixed window OR — when a latitude
/// + day-of-year are known — the seasonal sun-down test. A null [latitude]
/// or [dayOfYear] (no GPS fix yet) degrades to exactly the fixed window, so
/// the nudge never depends on a fix being available.
bool isDarkOutside(int nowLocalMinutes, double? latitude, int? dayOfYear) {
  if (isNightWindow(nowLocalMinutes)) return true;
  if (latitude == null || dayOfYear == null) return false;
  return isSunDown(nowLocalMinutes, latitude, dayOfYear);
}

/// True when the nudge was last surfaced recently enough that it should
/// stay suppressed. [dismissedAtMs] null (never surfaced) is never
/// throttled; a future-dated stamp (clock skew) reads as recent and
/// throttles rather than spamming.
bool nudgeThrottled(int? dismissedAtMs, int nowMs) {
  if (dismissedAtMs == null) return false;
  return nowMs - dismissedAtMs < safetyNudgeThrottleMs;
}

class SoloSafetyNudgeInput {
  /// Local time of day the run started, in minutes since midnight.
  final int nowLocalMinutes;

  /// The runner's latitude in degrees, or null when there is no GPS fix
  /// yet — null degrades the darkness test to the fixed window.
  final double? latitude;

  /// 1-based day of the local year (1–366), paired with [latitude]; null
  /// when unknown.
  final int? dayOfYear;

  /// The `auto_live_share` device pref — when on, every run already
  /// broadcasts, so there is nothing to nudge.
  final bool autoLiveShareOn;

  /// Whether a live broadcast is already active for this run (the
  /// runner shared a link manually before pressing GO).
  final bool isBroadcast;

  /// Whether the nudge is currently throttled (surfaced within the
  /// window). Compute with [nudgeThrottled].
  final bool nudgeDismissed;

  const SoloSafetyNudgeInput({
    required this.nowLocalMinutes,
    required this.autoLiveShareOn,
    required this.isBroadcast,
    required this.nudgeDismissed,
    this.latitude,
    this.dayOfYear,
  });
}

/// The decision. Nudge only when the run is genuinely unprotected AND
/// after dark AND not throttled — every guard is fail-closed (any true
/// suppressor wins), so a runner already covered is never prompted.
bool shouldNudgeSoloSafety(SoloSafetyNudgeInput input) {
  if (input.autoLiveShareOn) return false;
  if (input.isBroadcast) return false;
  if (input.nudgeDismissed) return false;
  return isDarkOutside(input.nowLocalMinutes, input.latitude, input.dayOfYear);
}
