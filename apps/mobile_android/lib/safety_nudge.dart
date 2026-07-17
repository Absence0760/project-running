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

/// Dusk / dawn boundaries, in local minutes since midnight, marking the
/// "after dark" window. A simple fixed window (20:00–06:00) rather than
/// astronomical sunset/sunrise: no astronomy dependency, deterministic,
/// and close enough for a safety prompt — erring toward nudging slightly
/// too early in summer is harmless, silently missing a genuinely dark run
/// is not.
const int safetyNudgeDuskMinutes = 20 * 60;
const int safetyNudgeDawnMinutes = 6 * 60;

/// How long ACTING on the nudge (sharing a link or explicitly dismissing
/// it) suppresses it before it can resurface. Long enough that a runner who
/// has engaged with the prompt is not nagged every night, short enough that
/// a lapsed habit gets an occasional reminder. Deliberately anchored on the
/// runner's *action*, not on merely surfacing the banner — a nudge a runner
/// never engaged with (a transient banner they missed) must NOT be
/// suppressed for a month.
const int safetyNudgeThrottleMs = 30 * 24 * 60 * 60 * 1000;

/// True when [nowLocalMinutes] falls in the dusk→dawn window. Wraps
/// midnight: night if at/after dusk OR before dawn. Input is normalised
/// into [0, 1440) so a caller passing a raw hour*60+min never trips on a
/// stray out-of-range value.
bool isNightWindow(int nowLocalMinutes) {
  final m = ((nowLocalMinutes % 1440) + 1440) % 1440;
  return m >= safetyNudgeDuskMinutes || m < safetyNudgeDawnMinutes;
}

/// True when the nudge was last ACTED on (shared or dismissed) recently
/// enough that it should stay suppressed. [actedAtMs] null (never acted on,
/// including a nudge that was merely shown and then missed) is never
/// throttled; a future-dated stamp (clock skew) reads as recent and
/// throttles rather than spamming.
bool nudgeThrottled(int? actedAtMs, int nowMs) {
  if (actedAtMs == null) return false;
  return nowMs - actedAtMs < safetyNudgeThrottleMs;
}

class SoloSafetyNudgeInput {
  /// Local time of day the run started, in minutes since midnight.
  final int nowLocalMinutes;

  /// The `auto_live_share` device pref — when on, every run already
  /// broadcasts, so there is nothing to nudge.
  final bool autoLiveShareOn;

  /// Whether a live broadcast is already active for this run (the
  /// runner shared a link manually before pressing GO).
  final bool isBroadcast;

  /// Whether the nudge is currently throttled (acted on within the
  /// window). Compute with [nudgeThrottled].
  final bool nudgeDismissed;

  const SoloSafetyNudgeInput({
    required this.nowLocalMinutes,
    required this.autoLiveShareOn,
    required this.isBroadcast,
    required this.nudgeDismissed,
  });
}

/// The decision. Nudge only when the run is genuinely unprotected AND
/// after dark AND not throttled — every guard is fail-closed (any true
/// suppressor wins), so a runner already covered is never prompted.
bool shouldNudgeSoloSafety(SoloSafetyNudgeInput input) {
  if (input.autoLiveShareOn) return false;
  if (input.isBroadcast) return false;
  if (input.nudgeDismissed) return false;
  return isNightWindow(input.nowLocalMinutes);
}

class SoloSafetyNudgeSurfaceInput {
  /// Local time of day the run started, in minutes since midnight.
  final int nowLocalMinutes;

  /// The `auto_live_share` device pref — when on, every run already
  /// broadcasts, so there is nothing to nudge.
  final bool autoLiveShareOn;

  /// Whether a live broadcast is already active for this run.
  final bool isBroadcast;

  /// When the runner last ACTED on the nudge (shared or dismissed it),
  /// epoch ms, or null if they never have. This is deliberately NOT the
  /// time the nudge was last *shown* — a persistent banner a runner never
  /// engaged with must resurface, not stay suppressed for the full
  /// throttle window.
  final int? lastActedAtMs;

  /// Current wall-clock, epoch ms — the throttle reference.
  final int nowMs;

  const SoloSafetyNudgeSurfaceInput({
    required this.nowLocalMinutes,
    required this.autoLiveShareOn,
    required this.isBroadcast,
    required this.lastActedAtMs,
    required this.nowMs,
  });
}

/// Whether to surface the persistent solo-safety banner right now. Folds
/// the throttle composition ([nudgeThrottled] on the acted-on stamp) into
/// the [shouldNudgeSoloSafety] guards so the caller can't re-introduce the
/// "throttle from shown, not from acted-on" bug by feeding a shown-at
/// timestamp — the parameter is named [SoloSafetyNudgeSurfaceInput.lastActedAtMs]
/// to make the contract explicit at the call site.
bool shouldSurfaceSoloSafetyNudge(SoloSafetyNudgeSurfaceInput input) {
  return shouldNudgeSoloSafety(SoloSafetyNudgeInput(
    nowLocalMinutes: input.nowLocalMinutes,
    autoLiveShareOn: input.autoLiveShareOn,
    isBroadcast: input.isBroadcast,
    nudgeDismissed: nudgeThrottled(input.lastActedAtMs, input.nowMs),
  ));
}
