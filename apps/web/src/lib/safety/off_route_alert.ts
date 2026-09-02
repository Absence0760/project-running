/// Off-route → auto-notify-contact detection helper (docs/features/safety.md,
/// persona-woman). The overdue-escalation net only fires on telemetry
/// *silence*; this is the complementary trigger for a runner who is still
/// moving and still pinging but has left — and stayed off — their planned
/// route. It decides WHEN a sustained off-route condition should escalate to
/// the runner's trusted contacts, reusing the same server-side notify path
/// (the `escalate_run_off_route` RPC → `safety_email` / `safety_sms` jobs).
///
/// Pure + stateful (no clock, no I/O): the caller feeds it the per-snapshot
/// off-route distance + a `nowMs`, so it is trivially testable and the mobile
/// run screen can drive it from the recorder's snapshot stream. TS↔Dart parity
/// pair with `apps/mobile_android/lib/off_route_alert.dart` — keep in lockstep.
///
/// Recording is mobile-only, so the *trigger surface* lives on the Flutter run
/// screen; this detector is the twinned decision logic (decisions §24 — the
/// pure core is canonical, the wiring is the platform-additive surface).

import { isTruthyFlagValue } from '../core/env_flag';

/// How far off the planned route (metres) the runner must be for the alert
/// clock to run. Deliberately larger than the 40 m off-route *banner*
/// threshold (`_offRouteThresholdMetres` on the run screen): the banner is a
/// gentle "you've drifted" nudge, this is the stronger "genuinely off course"
/// signal that justifies pinging a contact.
export const OFF_ROUTE_ALERT_DISTANCE_M = 75;

/// How long (ms) the runner must stay continuously beyond the distance
/// threshold before the alert fires. Debounce: a single GPS spike or a brief
/// corner-cut dips back under the threshold and resets the clock, so only a
/// sustained departure escalates.
export const OFF_ROUTE_ALERT_SUSTAIN_MS = 90 * 1000;

/// Stateful sustained-off-route detector. One instance per recording run.
/// `update` returns true EXACTLY ONCE — the first snapshot at which the runner
/// has been continuously off-route beyond the threshold for the sustain
/// window. It latches after firing (`hasFired`), because the escalation is
/// once-per-run (the server stamps `metadata.safety_escalated_at`); a runner
/// who returns on-route and leaves again does not re-alert.
export class OffRouteAlertDetector {
	private sinceMs: number | null = null;
	private fired = false;

	constructor(
		private readonly thresholdM: number = OFF_ROUTE_ALERT_DISTANCE_M,
		private readonly sustainMs: number = OFF_ROUTE_ALERT_SUSTAIN_MS,
	) {}

	get hasFired(): boolean {
		return this.fired;
	}

	/// Feed the latest off-route distance (null = on-route / no route selected /
	/// no GPS fix) and the current wall-clock ms. Returns true only on the
	/// transition into "sustained off-route" — false forever after (latched)
	/// and false while on-route or still within the debounce window.
	update(offRouteDistanceMetres: number | null, nowMs: number): boolean {
		if (this.fired) return false;
		// A non-finite reading is the SAME epistemic state as null — we do not
		// know how far off route the runner is — and must be read that way
		// rather than fall through the `<=` comparison, which every non-finite
		// value fails. Treating one as "off route" starts the sustain clock and
		// then spends the once-per-run latch on a reading that measured
		// nothing, leaving a runner who later goes genuinely off course with a
		// silently dead safety net. Reachable: the recorder's route projection
		// leaves its running minimum at +Infinity when every segment yields a
		// NaN distance, which a route whose waypoints carry non-finite
		// coordinates does.
		if (
			offRouteDistanceMetres == null ||
			!Number.isFinite(offRouteDistanceMetres) ||
			offRouteDistanceMetres <= this.thresholdM
		) {
			// Back on (or near enough) the route — reset the sustain clock.
			this.sinceMs = null;
			return false;
		}
		// Beyond the threshold. Start the clock on the first such snapshot, and
		// re-anchor it whenever the wall clock steps BACKWARDS (an NTP
		// correction, a manual clock change, a timezone-database update mid
		// run). Without the re-anchor the anchor stays stranded in the future
		// and the elapsed comparison stays negative for as long as the step was
		// large — an hour's correction disarms the alert for an hour of genuine
		// off-course running. Restarting the measurement is the honest answer:
		// across a clock jump we cannot say how long the departure has lasted.
		if (this.sinceMs == null || nowMs < this.sinceMs) {
			this.sinceMs = nowMs;
			return false;
		}
		if (nowMs - this.sinceMs >= this.sustainMs) {
			this.fired = true;
			return true;
		}
		return false;
	}

	/// Clear all state (e.g. the run screen re-arming for a fresh recording).
	reset(): void {
		this.sinceMs = null;
		this.fired = false;
	}
}

/// Pure parse of the off-route-escalation deploy flag, delegating to the one
/// canonical `isTruthyFlagValue` so the accepted-affirmative set is a single
/// contract across every gate on both platforms (decisions § 709).
/// Fail-closed: the whole off-route auto-notify path stays unreachable until
/// owner + CISO + counsel sign-off flips the flag at deploy time. The web env
/// binding lives in `off_route_flag.ts`; the mobile binding reads dotenv.
export function offRouteEscalationEnabled(raw: string | null | undefined): boolean {
	return isTruthyFlagValue(raw);
}
