/// Default heart-rate zone derivation, shared by the run-detail
/// zone breakdown (`runs/[id]/+page.svelte`). Kept algorithmically in
/// lockstep with the Dart twin `apps/mobile_android/lib/hr_zones.dart`
/// (`tanakaMaxHr` / `zoneCutoffsFromMaxHr` / `defaultZoneCutoffs`) and,
/// as a THIRD rail outside that enforced pair, the Wear OS
/// `resolveZoneCutoffs` in `SupabaseClient.kt`.
///
/// These produce the *default* cutoffs only — when the runner has set
/// explicit `hr_zones` those win and never reach this module.
///
/// The three rails share the derivation and the input range, and differ in
/// exactly one stated place: with NO usable signal at all these two return
/// the legacy 190 ladder, where the watch returns null and shows no zones.
/// That is deliberate on the watch — a wrist face has no room to caveat a
/// number, and inventing a stranger's max HR there is worse than an absent
/// panel — and it is stated on all three rails rather than left to be
/// rediscovered under a header claiming lockstep (decisions § 1245).

export type ZoneCutoffs = [number, number, number, number, number];

/// The range a stored `max_hr_bpm` has to fall in to be used as one. It is a
/// jsonb prefs key with no column and therefore no CHECK, so every reader
/// carries this bound itself; a value outside it is ignored rather than
/// trusted, and the derivation falls through to age or to the legacy ladder.
export const MAX_HR_BPM_MIN = 80;
export const MAX_HR_BPM_MAX = 240;

/// The age range Tanaka is applied over, for the same reason.
export const TANAKA_AGE_MIN = 5;
export const TANAKA_AGE_MAX = 120;

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
	if (typeof maxHrBpm === 'number' && maxHrBpm >= MAX_HR_BPM_MIN && maxHrBpm <= MAX_HR_BPM_MAX) {
		return zoneCutoffsFromMaxHr(maxHrBpm);
	}
	if (typeof ageYears === 'number' && ageYears >= TANAKA_AGE_MIN && ageYears <= TANAKA_AGE_MAX) {
		return zoneCutoffsFromMaxHr(tanakaMaxHr(ageYears));
	}
	return zoneCutoffsFromMaxHr(190);
}
