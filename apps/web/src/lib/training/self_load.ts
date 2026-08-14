/**
 * The runner's own acute:chronic workload ratio, and what it means.
 *
 * ACWR and its injury-risk bands already exist in `coach_load.ts`, but only a
 * *coach* ever saw them — the roster classifies other people's athletes, and
 * `plan_ramp.ts` grades a hypothetical future plan. The runner looking at
 * their own dashboard, who mostly has no coach at all, was never told that
 * their last seven days run 60 % above their month's average.
 *
 * This is a different question from readiness. `readiness.ts` scores today
 * (form, sleep, resting HR) — "should I run hard this morning". ACWR scores
 * the last month's ramp — "have I built too fast to keep getting away with
 * it". A runner can be fully recovered today and still sitting in the spike
 * zone that shows up as an injury three weeks from now.
 *
 * Pure (no Svelte / Supabase) so it runs under `npx tsx --test`. Web-only for
 * now: mobile has the `coach_load` twin but no self-facing surface, so a Dart
 * twin of this composition would be dead code (mirror tracked in
 * docs/product/followups.md).
 */

import {
	acwr,
	injuryRiskBand,
	loadTrend,
	type InjuryRiskBand,
	type LoadTrend,
} from './coach_load';
import { MIN_ACTIVE_WEEKS, recentRunVolume, type RunForVolume } from './plan_ramp';

export interface SelfLoad {
	/// 'insufficient' whenever the ratio would be arithmetic on noise — the
	/// caller renders nothing rather than a band it cannot stand behind.
	band: InjuryRiskBand;
	trend: LoadTrend;
	/// acute / chronic. 0 when the band is 'insufficient'.
	ratio: number;
	/// Last 7 days' running distance, metres.
	acuteM: number;
	/// Mean weekly running distance over the chronic window, metres.
	chronicWeeklyM: number;
	activeWeeks: number;
}

/**
 * Grade the runner's current load ramp from their recent runs.
 *
 * The ratio is taken over **distance**, not the coach roster's km×10 stress
 * proxy. That proxy is linear in distance, so the quotient is identical — the
 * ×10 cancels — and reproducing the constant here would be a second place for
 * it to drift. `acwr` is still the one implementation doing the division.
 *
 * Requires `MIN_ACTIVE_WEEKS` of the chronic window to carry a run, for the
 * reason `plan_ramp` already documents: one 3 km jog in a month is not a
 * chronic base, and dividing by it manufactures a terrifying ratio out of a
 * runner who has barely trained. Under-reporting a real spike is the failure
 * that hurts here, but inventing one is how a safety signal gets ignored.
 */
export function selfLoad(runs: RunForVolume[], nowMs: number): SelfLoad {
	const recent = recentRunVolume(runs, nowMs);
	const base = {
		acuteM: recent.acuteM,
		chronicWeeklyM: recent.weeklyM,
		activeWeeks: recent.activeWeeks,
	};
	if (recent.activeWeeks < MIN_ACTIVE_WEEKS) {
		return { ...base, band: 'insufficient', trend: 'steady', ratio: 0 };
	}
	const band = injuryRiskBand(recent.acuteM, recent.weeklyM);
	if (band === 'insufficient') {
		return { ...base, band, trend: 'steady', ratio: 0 };
	}
	return {
		...base,
		band,
		trend: loadTrend(recent.acuteM, recent.weeklyM),
		ratio: acwr(recent.acuteM, recent.weeklyM),
	};
}

/// Whether the dashboard has a load ramp worth showing. Only the gradeable
/// bands earn the card; 'insufficient' renders nothing at all, matching how
/// every other analytics card on that page self-hides rather than showing a
/// zeroed stat.
export function shouldSurfaceSelfLoad(load: SelfLoad): boolean {
	return load.band !== 'insufficient';
}
