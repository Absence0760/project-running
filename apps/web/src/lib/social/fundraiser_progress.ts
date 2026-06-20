/**
 * Fundraiser thermometer math (fundraising.md).
 *
 * Pure, deterministic, no I/O — computes the goal-thermometer state from
 * `(raisedCents, goalCents)`: the bar fill percentage (clamped to 0–100 for
 * the bar geometry), the true uncapped percentage (so the UI can show
 * "118% — over goal!"), the cents still needed, and a coarse `ThermometerState`
 * that drives the bar styling + label.
 *
 * TS↔Dart parity pair: keep in lockstep with
 * `apps/mobile_android/lib/fundraiser_progress.dart` (+ iOS twin) — same
 * algorithm, same edge cases, same test count.
 */

export type ThermometerState = 'starting' | 'progressing' | 'met' | 'exceeded';

export interface FundraiserProgress {
	/** Bar fill 0–100 (clamped), for the thermometer geometry. */
	fillPct: number;
	/** True percentage of goal raised, uncapped (can exceed 100). */
	rawPct: number;
	/** Cents still needed to reach the goal; 0 once met or exceeded. */
	remainingCents: number;
	state: ThermometerState;
}

/** Below this fill the bar reads as "just getting started". */
export const STARTING_THRESHOLD_PCT = 10;

/**
 * Resolve the thermometer state from raised vs goal.
 *
 * Defensive: a non-finite or non-positive goal yields a zeroed,
 * `'starting'` result (the bar renders empty rather than dividing by zero);
 * negative raised is floored to 0.
 */
export function fundraiserProgress(
	raisedCents: number,
	goalCents: number,
): FundraiserProgress {
	const raised = Number.isFinite(raisedCents) && raisedCents > 0 ? raisedCents : 0;
	if (!Number.isFinite(goalCents) || goalCents <= 0) {
		return { fillPct: 0, rawPct: 0, remainingCents: 0, state: 'starting' };
	}

	const rawPct = (raised / goalCents) * 100;
	const fillPct = Math.max(0, Math.min(100, rawPct));
	const remainingCents = Math.max(0, goalCents - raised);

	let state: ThermometerState;
	if (raised > goalCents) {
		state = 'exceeded';
	} else if (raised >= goalCents) {
		state = 'met';
	} else if (rawPct < STARTING_THRESHOLD_PCT) {
		state = 'starting';
	} else {
		state = 'progressing';
	}

	return { fillPct, rawPct, remainingCents, state };
}
