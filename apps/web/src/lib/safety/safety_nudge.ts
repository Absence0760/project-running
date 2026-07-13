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
/// "after dark" window. A simple fixed window (20:00–06:00) rather than
/// astronomical sunset/sunrise: no astronomy dependency, deterministic,
/// and close enough for a safety prompt — erring toward nudging slightly
/// too early in summer is harmless, silently missing a genuinely dark run
/// is not.
export const SAFETY_NUDGE_DUSK_MINUTES = 20 * 60;
export const SAFETY_NUDGE_DAWN_MINUTES = 6 * 60;

/// How long surfacing the nudge suppresses it before it can resurface.
/// Long enough that a runner who has seen (and understood) the prompt is
/// not nagged every night, short enough that a lapsed habit gets an
/// occasional reminder. The nudge is otherwise dismissible on sight.
export const SAFETY_NUDGE_THROTTLE_MS = 30 * 24 * 60 * 60 * 1000;

/// True when `nowLocalMinutes` falls in the dusk→dawn window. Wraps
/// midnight: night if at/after dusk OR before dawn. Input is normalised
/// into [0, 1440) so a caller passing a raw hour*60+min never trips on a
/// stray out-of-range value.
export function isNightWindow(nowLocalMinutes: number): boolean {
	const m = ((Math.trunc(nowLocalMinutes) % 1440) + 1440) % 1440;
	return m >= SAFETY_NUDGE_DUSK_MINUTES || m < SAFETY_NUDGE_DAWN_MINUTES;
}

/// True when the nudge was last surfaced recently enough that it should
/// stay suppressed. `dismissedAtMs` null (never surfaced) is never
/// throttled; a future-dated stamp (clock skew) reads as recent and
/// throttles rather than spamming.
export function nudgeThrottled(dismissedAtMs: number | null, nowMs: number): boolean {
	if (dismissedAtMs == null) return false;
	return nowMs - dismissedAtMs < SAFETY_NUDGE_THROTTLE_MS;
}

export interface SoloSafetyNudgeInput {
	/// Local time of day the run started, in minutes since midnight.
	nowLocalMinutes: number;
	/// The `auto_live_share` device pref — when on, every run already
	/// broadcasts, so there is nothing to nudge.
	autoLiveShareOn: boolean;
	/// Whether a live broadcast is already active for this run (the
	/// runner shared a link manually before pressing GO).
	isBroadcast: boolean;
	/// Whether the nudge is currently throttled (surfaced within the
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
	return isNightWindow(input.nowLocalMinutes);
}
