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
/// testable and the mobile surface can inject `now`. TS↔Dart parity pair
/// with `apps/mobile_android/lib/safety_nudge.dart` — keep in lockstep.
///
/// Recording is mobile-only, so the *surface* lives on the Flutter run
/// screen; this decision helper is the twinned logic (decisions §24 —
/// the pure core is canonical, the banner is the platform-additive
/// surface).

/// Dusk / dawn boundaries, in local minutes since midnight, marking the
/// fixed "after dark" window that is always treated as night regardless of
/// latitude or season. This is the deterministic FLOOR: a run in this
/// window nudges everywhere on earth with no GPS fix required. Seasonal
/// darkness (dark winter mornings / evenings at higher latitudes) is added
/// ON TOP of it by `isSunDown` when a latitude + day-of-year are known — the
/// window only ever widens, never narrows, so behaviour can't regress and
/// the fixed window absorbs the solar model's noon-assumption error.
export const SAFETY_NUDGE_DUSK_MINUTES = 20 * 60;
export const SAFETY_NUDGE_DAWN_MINUTES = 6 * 60;

/// Sun altitude (degrees) at/below which it counts as dark for the nudge.
/// The standard sunrise/sunset value (−0.833° = geometric horizon − mean
/// atmospheric refraction − solar semidiameter): "the sun has gone down".
/// Slightly below the horizon rather than into twilight so we err toward
/// nudging (start at sunset), never toward missing a dark run.
export const SUN_DOWN_ALTITUDE_DEG = -0.833;

/// How long ACTING on the nudge (sharing a link or explicitly dismissing
/// it) suppresses it before it can resurface. Long enough that a runner who
/// has engaged with the prompt is not nagged every night, short enough that
/// a lapsed habit gets an occasional reminder. Deliberately anchored on the
/// runner's *action*, not on merely surfacing the banner — a nudge a runner
/// never engaged with (a transient banner they missed) must NOT be
/// suppressed for a month.
export const SAFETY_NUDGE_THROTTLE_MS = 30 * 24 * 60 * 60 * 1000;

/// True when `nowLocalMinutes` falls in the fixed dusk→dawn window. Wraps
/// midnight: night if at/after dusk OR before dawn. Input is normalised
/// into [0, 1440) so a caller passing a raw hour*60+min never trips on a
/// stray out-of-range value.
export function isNightWindow(nowLocalMinutes: number): boolean {
	const m = ((Math.trunc(nowLocalMinutes) % 1440) + 1440) % 1440;
	return m >= SAFETY_NUDGE_DUSK_MINUTES || m < SAFETY_NUDGE_DAWN_MINUTES;
}

/// Solar declination (degrees) for a 1-based day-of-year (Cooper's
/// approximation). Normalised into 1..365 so an out-of-range day can't
/// throw the trig off. Positive near the June solstice, negative near
/// December.
function solarDeclinationDeg(dayOfYear: number): number {
	const d = (((Math.trunc(dayOfYear) - 1) % 365) + 365) % 365 + 1;
	return -23.44 * Math.cos((2 * Math.PI / 365) * (d + 10));
}

/// True when the sun is at/below `SUN_DOWN_ALTITUDE_DEG` at `latitude` on
/// `dayOfYear` at `nowLocalMinutes` — the seasonal, latitude-aware "is it
/// dark" test that catches dark pre-dawn winter runs at higher latitudes
/// (the gap the fixed window misses). Models solar noon at local 12:00 and
/// derives symmetric sunrise/sunset from the day's half-arc; it deliberately
/// ignores longitude-within-timezone / equation-of-time / DST (up to ~1 h of
/// clock error) because the fixed `isNightWindow` floor absorbs that — this
/// only ever ADDS darkness. Handles the polar cases: sun never rises →
/// always dark, sun never sets → never dark.
export function isSunDown(nowLocalMinutes: number, latitude: number, dayOfYear: number): boolean {
	const m = ((Math.trunc(nowLocalMinutes) % 1440) + 1440) % 1440;
	const rad = Math.PI / 180;
	const decl = solarDeclinationDeg(dayOfYear) * rad;
	const lat = latitude * rad;
	const h0 = SUN_DOWN_ALTITUDE_DEG * rad;
	const cosH = (Math.sin(h0) - Math.sin(lat) * Math.sin(decl)) / (Math.cos(lat) * Math.cos(decl));
	if (Number.isNaN(cosH)) return true; // degenerate (pole) → fail-safe dark
	if (cosH <= -1) return false; // polar day: sun never sets
	if (cosH >= 1) return true; // polar night: sun never rises
	const halfDayMinutes = (Math.acos(cosH) / rad) * 4; // 4 minutes of clock per degree
	const sunrise = 720 - halfDayMinutes;
	const sunset = 720 + halfDayMinutes;
	return m < sunrise || m >= sunset;
}

/// The combined "after dark" decision: the fixed window OR — when a latitude
/// + day-of-year are known — the seasonal sun-down test. A null `latitude`
/// or `dayOfYear` (no GPS fix yet) degrades to exactly the fixed window, so
/// the nudge never depends on a fix being available.
export function isDarkOutside(
	nowLocalMinutes: number,
	latitude: number | null,
	dayOfYear: number | null,
): boolean {
	if (isNightWindow(nowLocalMinutes)) return true;
	if (latitude == null || dayOfYear == null) return false;
	return isSunDown(nowLocalMinutes, latitude, dayOfYear);
}

/// True when the nudge was last ACTED on (shared or dismissed) recently
/// enough that it should stay suppressed. `actedAtMs` null (never acted on,
/// including a nudge that was merely shown and then missed) is never
/// throttled; a future-dated stamp (clock skew) reads as recent and
/// throttles rather than spamming.
export function nudgeThrottled(actedAtMs: number | null, nowMs: number): boolean {
	if (actedAtMs == null) return false;
	return nowMs - actedAtMs < SAFETY_NUDGE_THROTTLE_MS;
}

export interface SoloSafetyNudgeInput {
	/// Local time of day the run started, in minutes since midnight.
	nowLocalMinutes: number;
	/// The runner's latitude in degrees, or null when there is no GPS fix
	/// yet — null degrades the darkness test to the fixed window.
	latitude: number | null;
	/// 1-based day of the local year (1–366), paired with `latitude`; null
	/// when unknown.
	dayOfYear: number | null;
	/// The `auto_live_share` device pref — when on, every run already
	/// broadcasts, so there is nothing to nudge.
	autoLiveShareOn: boolean;
	/// Whether a live broadcast is already active for this run (the
	/// runner shared a link manually before pressing GO).
	isBroadcast: boolean;
	/// Whether the nudge is currently throttled (acted on within the
	/// window). Compute with `nudgeThrottled`.
	nudgeDismissed: boolean;
}

/// The decision. Nudge only when the run is genuinely unprotected AND
/// after dark AND not throttled — every guard is fail-closed (any true
/// suppressor wins), so a runner already covered is never prompted.
export function shouldNudgeSoloSafety(input: SoloSafetyNudgeInput): boolean {
	if (input.autoLiveShareOn) return false;
	if (input.isBroadcast) return false;
	if (input.nudgeDismissed) return false;
	return isDarkOutside(input.nowLocalMinutes, input.latitude, input.dayOfYear);
}

export interface SoloSafetyNudgeSurfaceInput {
	/// Local time of day the run started, in minutes since midnight.
	nowLocalMinutes: number;
	/// The runner's latitude in degrees, or null when there is no GPS fix
	/// yet — null degrades the darkness test to the fixed window.
	latitude: number | null;
	/// 1-based day of the local year (1–366), paired with `latitude`; null
	/// when unknown.
	dayOfYear: number | null;
	/// The `auto_live_share` device pref — when on, every run already
	/// broadcasts, so there is nothing to nudge.
	autoLiveShareOn: boolean;
	/// Whether a live broadcast is already active for this run.
	isBroadcast: boolean;
	/// When the runner last ACTED on the nudge (shared or dismissed it),
	/// epoch ms, or null if they never have. This is deliberately NOT the
	/// time the nudge was last *shown* — a persistent banner a runner
	/// never engaged with must resurface, not stay suppressed for the
	/// full throttle window.
	lastActedAtMs: number | null;
	/// Current wall-clock, epoch ms — the throttle reference.
	nowMs: number;
}

/// Whether to surface the persistent solo-safety banner right now. Folds
/// the throttle composition (`nudgeThrottled` on the acted-on stamp) into
/// the `shouldNudgeSoloSafety` guards so the caller can't re-introduce the
/// "throttle from shown, not from acted-on" bug by feeding a shown-at
/// timestamp — the parameter is named `lastActedAtMs` to make the contract
/// explicit at the call site.
export function shouldSurfaceSoloSafetyNudge(input: SoloSafetyNudgeSurfaceInput): boolean {
	return shouldNudgeSoloSafety({
		nowLocalMinutes: input.nowLocalMinutes,
		latitude: input.latitude,
		dayOfYear: input.dayOfYear,
		autoLiveShareOn: input.autoLiveShareOn,
		isBroadcast: input.isBroadcast,
		nudgeDismissed: nudgeThrottled(input.lastActedAtMs, input.nowMs),
	});
}
