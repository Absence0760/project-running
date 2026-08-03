/**
 * Dashboard streak-card state. Web-only (the fetch + card are a web
 * surface; mobile's card reads its full local store) — deliberately NOT
 * in streaks.ts, which is a TS<->Dart parity pair.
 *
 * The card's headline + sub-label prefer the server-side all-time
 * aggregate (`run_streaks_for_user`, decisions § 471). When that fetch
 * has not resolved — loading or failed — the windowed client compute is
 * only trusted for claims it can actually prove: a numeric "Best: N" or
 * an "All-time best!" from a ~2-year window is exactly the silently-low
 * number § 470 forbids, so those render as nothing instead.
 */

import type { RunStreaks } from './streaks';

export type StreakSub =
	| { kind: 'best'; n: number }
	| { kind: 'allTimeBest' }
	| { kind: 'restart' }
	| { kind: 'start' }
	| { kind: 'none' };

export interface StreakCardState {
	current: number;
	sub: StreakSub;
}

export function streakCardState(
	allTime: RunStreaks | null,
	windowed: RunStreaks,
): StreakCardState {
	if (allTime) {
		// best >= current by construction (the current island counts toward
		// best), so equality is the only non-"best" case: an active streak
		// that IS the record, or no run days at all.
		const { current, best } = allTime;
		if (best > current) return { current, sub: { kind: 'best', n: best } };
		if (current > 0) return { current, sub: { kind: 'allTimeBest' } };
		return { current, sub: { kind: 'start' } };
	}
	const { current, best } = windowed;
	if (current > 0) return { current, sub: { kind: 'none' } };
	if (best > 0) return { current, sub: { kind: 'restart' } };
	return { current, sub: { kind: 'start' } };
}
