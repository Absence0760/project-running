/// Spectator motion state: is the runner we CAN see actually moving?
///
/// `live_freshness` answers "can we see them at all" and the surface is
/// scrupulous about it — a lost-signal runner reads DELAYED, never LIVE.
/// The complementary question had no answer: a runner whose phone is still
/// pinging every few seconds from the same spot renders as a fresh green
/// LIVE dot, and the one derived stat that would have exposed it (recent
/// pace) computes a zero distance delta and returns null, so the readout
/// simply disappears. Silence about "not moving" and silence about "no
/// data yet" looked identical, and the more alarming of the two is the one
/// that vanished.
///
/// This grades a window of recent pings into `moving` / `stopped` /
/// `unknown`. It is deliberately a NEUTRAL report, not an alarm: a runner
/// stopped for six minutes is at an aid station, and one stopped for
/// ninety is a question for their crew. The surface states the fact and
/// the duration; it draws no conclusion the data cannot support.
///
/// Fail-closed in three directions. A stale fix yields `unknown` — the
/// last position being old is exactly the case where "they have not moved"
/// is unknowable, and reporting a stationary runner off pre-dropout pings
/// would be the same lie in a new place. A gap inside the buffer yields
/// `unknown` too, for the same reason arriving through a different door: a
/// runner who reconnects near where they dropped out has not been observed
/// standing there, and the outage must not be counted as stillness. And
/// too short an observation window yields `unknown`, because a five-ping
/// buffer at a 5 s cadence spans twenty seconds and every runner alive
/// stands still for twenty seconds at a road crossing.
///
/// Web-only: this is a spectator-surface derivation with no mobile
/// consumer today (the Flutter `live_spectator_screen` renders the same
/// pings but has no motion readout). It is NOT a registered parity pair —
/// a Dart twin nothing calls is dead code the parity guard polices
/// forever.

/// The window must span at least this much WALL CLOCK before any claim is
/// made. Three minutes is past every ordinary pause a moving runner takes
/// (traffic light, gate, shoe, photo) and well inside the time a spectator
/// would want to know about a genuine stop.
export const MOTION_MIN_WINDOW_MS = 180_000;

/// Ground covered across the window at or below which the runner counts as
/// stopped. GPS jitter walks a stationary phone a few metres per fix and
/// does not average out, so the floor has to absorb an accumulating
/// random walk over minutes rather than a single fix's error.
export const MOTION_STOPPED_DISTANCE_M = 25;

/// The longest gap between two consecutive pings the window may span. A
/// claim about a runner staying put is a claim about every moment in
/// between, and a hole in the telemetry is precisely where they could have
/// left and come back. Everything before a longer gap is discarded rather
/// than vouched for, so a reconnection after an hour off-grid starts the
/// observation again instead of reading the whole outage as stillness.
/// Kept below `MOTION_MIN_WINDOW_MS` so no accepted gap can be most of a
/// minimum-length claim. Two minutes still absorbs the ordinary cellular
/// flakiness a ~5 s broadcast cadence sees.
export const MOTION_MAX_GAP_MS = 120_000;

export type MotionState = 'moving' | 'stopped' | 'unknown';

export interface MotionSample {
	/// Run odometer at this ping, metres.
	distanceM: number;
	/// Wall-clock time the ping was sent, ms. Deliberately NOT the ping's
	/// `elapsed_s`: a recorder that auto-paused freezes elapsed while the
	/// runner is genuinely standing still, which would shrink the observed
	/// window to nothing in exactly the case worth reporting.
	atMs: number;
}

export interface LiveMotionInput {
	/// Recent pings, oldest first. Out-of-order or duplicate entries are
	/// tolerated; only the span between the oldest qualifying sample and
	/// the newest is used.
	samples: MotionSample[];
	/// From `live_freshness` — the last fix can no longer be trusted as
	/// current.
	stale: boolean;
}

export interface LiveMotion {
	state: MotionState;
	/// How long the runner has been continuously within
	/// `MOTION_STOPPED_DISTANCE_M` of where they are now, ms. Null unless
	/// `state === 'stopped'`. It reaches back through the final metres of
	/// the approach, so it can exceed the moment they actually halted by
	/// the time it took them to cover that radius — bounded, and the right
	/// side to err on for a claim phrased as "has not left this spot".
	stoppedForMs: number | null;
	/// The stopped span reached the start of the vouched window — either
	/// the oldest sample held or the far side of a gap — so the real
	/// duration is at least `stoppedForMs` and possibly longer. The
	/// surface must say "at least" rather than state the figure flat.
	atLeast: boolean;
	/// Wall-clock span actually observed, ms. Null when no claim is made.
	windowMs: number | null;
	/// Ground covered across that span, metres. Null when no claim is made.
	windowDistanceM: number | null;
}

const UNKNOWN: LiveMotion = {
	state: 'unknown',
	stoppedForMs: null,
	atLeast: false,
	windowMs: null,
	windowDistanceM: null,
};

function usable(s: MotionSample): boolean {
	return Number.isFinite(s.distanceM) && Number.isFinite(s.atMs);
}

export function motionFor(input: LiveMotionInput): LiveMotion {
	if (input.stale) return UNKNOWN;

	const all = input.samples.filter(usable).sort((a, b) => a.atMs - b.atMs);
	if (all.length < 2) return UNKNOWN;

	// Only the contiguous run ending at the newest ping is evidence. A
	// caller holding a buffer that straddles an outage would otherwise hand
	// us a pre-gap sample as the start of an unbroken stop.
	let firstVouched = 0;
	for (let i = all.length - 1; i > 0; i--) {
		if (all[i].atMs - all[i - 1].atMs > MOTION_MAX_GAP_MS) {
			firstVouched = i;
			break;
		}
	}
	const samples = all.slice(firstVouched);
	if (samples.length < 2) return UNKNOWN;

	const newest = samples[samples.length - 1];
	const oldest = samples[0];
	const windowMs = newest.atMs - oldest.atMs;
	if (windowMs < MOTION_MIN_WINDOW_MS) return UNKNOWN;

	// A rewound odometer (a re-armed recorder, a replayed backlog) would
	// otherwise read as negative ground covered and grade as stopped.
	const windowDistanceM = Math.abs(newest.distanceM - oldest.distanceM);

	// Walk back from the newest sample while the runner stayed within the
	// stopped radius of where they are now. The first sample that breaks
	// out bounds the stop; reaching the oldest held sample means the stop
	// began before our window and the duration is a floor, not a figure.
	let stopStartIndex = samples.length - 1;
	for (let i = samples.length - 2; i >= 0; i--) {
		if (Math.abs(newest.distanceM - samples[i].distanceM) > MOTION_STOPPED_DISTANCE_M) break;
		stopStartIndex = i;
	}
	const stoppedForMs = newest.atMs - samples[stopStartIndex].atMs;

	// The stop must itself clear the minimum window: a runner who covered
	// ground for most of the observed span and has been still for forty
	// seconds is moving, not stopped.
	if (stoppedForMs < MOTION_MIN_WINDOW_MS) {
		return { state: 'moving', stoppedForMs: null, atLeast: false, windowMs, windowDistanceM };
	}

	return {
		state: 'stopped',
		stoppedForMs,
		atLeast: stopStartIndex === 0,
		windowMs,
		windowDistanceM,
	};
}
