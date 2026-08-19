/**
 * The load signal for a runner who has just come back from a break.
 *
 * `self_load.ts` grades the runner's acute:chronic workload ratio and refuses
 * to say anything below `MIN_ACTIVE_WEEKS` of the chronic window — correctly,
 * because dividing a comeback week by a near-empty month manufactures a
 * terrifying ratio out of thin air. But that refusal is silent exactly where
 * the runner is most exposed: someone back from three months off, logging a
 * 30 km first week, sees no card at all.
 *
 * The gap is the *instrument*, not the threshold. ACWR asks "how does this
 * week compare with the month you just trained", and a comeback runner has no
 * such month. This asks a question their history can actually answer: "how
 * does this week compare with the weeks you were running before the break".
 * Their own pre-break average is real data; the near-zero month is not.
 *
 * It fires only where `selfLoad` is silent — the same `activeWeeks` gate, read
 * the other way round — so the two cards are mutually exclusive by
 * construction rather than by the dashboard remembering to choose.
 *
 * Pure (no Svelte / Supabase) so it runs under `npx tsx --test`.
 *
 * Dart twin: apps/mobile_android/lib/comeback.dart (parity pair — keep the
 * algorithm, thresholds, gates, and test counts in lockstep). The web surface
 * is `ComebackCard.svelte`.
 */

import { kLayoffResetDays } from './training_load';
import {
	CHRONIC_WINDOW_WEEKS,
	MIN_ACTIVE_WEEKS,
	recentRunVolume,
	volumeSample,
	type RunForVolume,
} from './plan_ramp';

const DAY_MS = 86_400_000;
const WEEK_MS = 7 * DAY_MS;

/// How long a run-less stretch has to be before it counts as a break rather
/// than a rest week. Deliberately `training_load`'s own layoff constant: that
/// is already the point at which the app writes the runner's fitness EWMAs
/// down to zero, and a break big enough to erase their modelled fitness is
/// the same break this card is about. Two numbers for one idea would drift.
export const LAYOFF_MIN_DAYS = kLayoffResetDays;

/// Past this, the pre-break average stops being a usable anchor and the card
/// says nothing. A base two years stale describes a body that no longer
/// exists, and grading a return against it would produce a *reassuring*
/// number for a runner who is effectively starting over — over-reporting
/// safety is the failure that hurts here.
export const LAYOFF_MAX_DAYS = 365;

/// The share of the pre-break weekly average above which a first week back is
/// called steep. An editorial line, not a clinical one: the widely-taught
/// return-to-running shape is to resume at around half of what you were doing
/// and rebuild from there. It is deliberately one flat threshold rather than a
/// curve decaying with layoff length — a decay function would invent precision
/// the underlying evidence does not have, and a runner can reason about "half".
export const RETURN_WEEK_SHARE = 0.5;

export type ComebackVerdict = 'insufficient' | 'easing_in' | 'steep';

export interface ComebackLoad {
	/// 'insufficient' whenever there is no break, no usable pre-break base, or
	/// no running this week — the caller renders nothing rather than a claim it
	/// cannot stand behind.
	verdict: ComebackVerdict;
	/// Whole days between the last run before the break and the first run
	/// after it. 0 when the verdict is 'insufficient'.
	layoffDays: number;
	/// `layoffDays` as whole weeks, rounded to nearest — the figure the copy
	/// renders. Rounded rather than floored because overstating a break is the
	/// conservative direction for a safety claim. Never below 4, since
	/// `LAYOFF_MIN_DAYS` is 28.
	layoffWeeks: number;
	/// Last 7 days' running distance, metres.
	thisWeekM: number;
	/// Mean weekly running distance over the four windows before the break.
	preLayoffWeeklyM: number;
	/// `thisWeekM` / `preLayoffWeeklyM`. 0 when the verdict is 'insufficient'.
	share: number;
}

const UNGRADED: ComebackLoad = {
	verdict: 'insufficient',
	layoffDays: 0,
	layoffWeeks: 0,
	thisWeekM: 0,
	preLayoffWeeklyM: 0,
	share: 0,
};

/**
 * Grade the runner's first weeks back against the weeks they were running
 * before the break.
 *
 * Fail-closed at every step. No run this week, no break in the history, a
 * break too old to anchor against, or too thin a pre-break base all return
 * `insufficient` — the caller shows nothing, exactly as it does today, rather
 * than a number derived from a history that cannot carry it.
 */
export function comebackLoad(runs: RunForVolume[], nowMs: number): ComebackLoad {
	const recent = recentRunVolume(runs, nowMs);
	// The ratio card owns any runner whose recent history can carry it; this
	// one exists for the hole that refusal leaves, and two load cards claiming
	// the same week would be worse than either alone.
	if (recent.activeWeeks >= MIN_ACTIVE_WEEKS) return UNGRADED;
	// A week with no running has no load to grade, and an "easing in" verdict
	// off zero kilometres would read as praise for not running.
	if (recent.acuteM <= 0) return UNGRADED;

	// A device whose clock runs ahead stamps a just-finished run in the future.
	// `recentRunVolume` absorbs that by clamping the age to zero; the same
	// clamp has to happen here, because an unclamped future stamp opens a gap
	// to the run before it and would be read as a layoff that never happened.
	const samples = runs
		.map(volumeSample)
		.filter((s): s is NonNullable<typeof s> => s !== null)
		.map((s) => ({ ...s, startedMs: Math.min(s.startedMs, nowMs) }))
		.sort((a, b) => b.startedMs - a.startedMs);

	// The most recent run-less stretch long enough to count, walking back from
	// today. Later breaks are the ones the runner is living through; an older
	// one is history they have already trained past.
	let gapIndex = -1;
	for (let i = 0; i < samples.length - 1; i++) {
		if (samples[i].startedMs - samples[i + 1].startedMs >= LAYOFF_MIN_DAYS * DAY_MS) {
			gapIndex = i;
			break;
		}
	}
	if (gapIndex < 0) return UNGRADED;

	const layoffDays = Math.floor(
		(samples[gapIndex].startedMs - samples[gapIndex + 1].startedMs) / DAY_MS,
	);
	if (layoffDays > LAYOFF_MAX_DAYS) return UNGRADED;

	// The base is reduced over the same rolling 7-day windows as the acute
	// week, anchored on the last run before the break instead of on today.
	const anchorMs = samples[gapIndex + 1].startedMs;
	let baseTotalM = 0;
	const baseWeeks = new Set<number>();
	for (const sample of samples) {
		const age = anchorMs - sample.startedMs;
		if (age < 0) continue;
		const week = Math.floor(age / WEEK_MS);
		if (week >= CHRONIC_WINDOW_WEEKS) continue;
		baseTotalM += sample.distanceM;
		baseWeeks.add(week);
	}
	// The same evidence bar `plan_ramp` sets, applied where the history is
	// real: a single run before the break is not a base to come back to.
	if (baseWeeks.size < MIN_ACTIVE_WEEKS) return UNGRADED;
	const preLayoffWeeklyM = baseTotalM / CHRONIC_WINDOW_WEEKS;
	if (preLayoffWeeklyM <= 0) return UNGRADED;

	const share = recent.acuteM / preLayoffWeeklyM;
	return {
		verdict: share > RETURN_WEEK_SHARE ? 'steep' : 'easing_in',
		layoffDays,
		layoffWeeks: Math.round(layoffDays / 7),
		thisWeekM: recent.acuteM,
		preLayoffWeeklyM,
		share,
	};
}

/// A comeback the caller may actually render copy for.
export type GradedComebackVerdict = Exclude<ComebackVerdict, 'insufficient'>;
export interface GradedComebackLoad extends ComebackLoad {
	verdict: GradedComebackVerdict;
}

/// Whether the dashboard has a comeback worth showing.
///
/// A type predicate rather than a bare boolean, for the reason
/// `shouldSurfaceSelfLoad` already documents: it narrows the verdict to the
/// two the card has copy for, so an unlabelled verdict is a compile error
/// rather than a missing-key render.
export function shouldSurfaceComeback(load: ComebackLoad): load is GradedComebackLoad {
	return load.verdict !== 'insufficient';
}
