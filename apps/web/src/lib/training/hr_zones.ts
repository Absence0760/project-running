/// Default heart-rate zone derivation, shared by the run-detail
/// zone breakdown (`runs/[id]/+page.svelte`). Kept algorithmically in
/// lockstep with the Dart twin `apps/mobile_android/lib/hr_zones.dart`
/// (`tanakaMaxHr` / `zoneCutoffsFromMaxHr` / `defaultZoneCutoffs`) and
/// the Wear OS `resolveZoneCutoffs` in `SupabaseClient.kt`.
///
/// These produce the *default* cutoffs only — when the runner has set
/// explicit `hr_zones` those win and never reach this module.

export type ZoneCutoffs = [number, number, number, number, number];

/// Tanaka (2001) age-predicted maximal heart rate: 208 − 0.7 × age.
/// More accurate for masters runners than the classic 220 − age, which
/// systematically overestimates HR-max past ~40 and pushed older
/// runners into falsely-low zones (persona-hunt Older #8).
export function tanakaMaxHr(ageYears: number): number {
	return Math.round(208 - 0.7 * ageYears);
}

/// Zone upper bounds (Z1..Z5) at 60/70/80/90/100 % of a max HR.
export function zoneCutoffsFromMaxHr(maxHr: number): ZoneCutoffs {
	return [0.6, 0.7, 0.8, 0.9, 1.0].map((p) => Math.round(maxHr * p)) as ZoneCutoffs;
}

/// Default zone cutoffs when the runner hasn't set explicit `hr_zones`.
/// Precedence: an explicit `max_hr_bpm` override → Tanaka from age →
/// the legacy 190-bpm fallback (`zoneCutoffsFromMaxHr(190)` ==
/// `[114, 133, 152, 171, 190]`, the historic hardcoded default).
export function defaultZoneCutoffs(opts: {
	maxHrBpm?: number | null;
	ageYears?: number | null;
}): ZoneCutoffs {
	const { maxHrBpm, ageYears } = opts;
	if (typeof maxHrBpm === 'number' && maxHrBpm >= 80 && maxHrBpm <= 240) {
		return zoneCutoffsFromMaxHr(maxHrBpm);
	}
	if (typeof ageYears === 'number' && ageYears >= 5 && ageYears <= 120) {
		return zoneCutoffsFromMaxHr(tanakaMaxHr(ageYears));
	}
	return zoneCutoffsFromMaxHr(190);
}
