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

/// How long ACTING on the nudge (sharing a link or explicitly dismissing
/// it) suppresses it before it can resurface. Long enough that a runner who
/// has engaged with the prompt is not nagged every night, short enough that
/// a lapsed habit gets an occasional reminder. Deliberately anchored on the
/// runner's *action*, not on merely surfacing the banner — a nudge a runner
/// never engaged with (a transient banner they missed) must NOT be
/// suppressed for a month.
export const SAFETY_NUDGE_THROTTLE_MS = 30 * 24 * 60 * 60 * 1000;

/// True when `nowLocalMinutes` falls in the dusk→dawn window. Wraps
/// midnight: night if at/after dusk OR before dawn. Input is normalised
/// into [0, 1440) so a caller passing a raw hour*60+min never trips on a
/// stray out-of-range value.
export function isNightWindow(nowLocalMinutes: number): boolean {
	const m = ((Math.trunc(nowLocalMinutes) % 1440) + 1440) % 1440;
	return m >= SAFETY_NUDGE_DUSK_MINUTES || m < SAFETY_NUDGE_DAWN_MINUTES;
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
	return isNightWindow(input.nowLocalMinutes);
}

export interface SoloSafetyNudgeSurfaceInput {
	/// Local time of day the run started, in minutes since midnight.
	nowLocalMinutes: number;
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
		autoLiveShareOn: input.autoLiveShareOn,
		isBroadcast: input.isBroadcast,
		nudgeDismissed: nudgeThrottled(input.lastActedAtMs, input.nowMs),
	});
}
