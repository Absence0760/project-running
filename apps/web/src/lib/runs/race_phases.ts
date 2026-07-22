/**
 * Race pacing-strategy phase plans — pure, locale/unit-agnostic. Slices a
 * race distance into intent phases (hold back / settle / race) whose pace
 * factors multiply the goal pace, with the derived final factor chosen so the
 * distance-weighted mean factor is exactly 1.0 — the plan still lands the
 * goal time.
 *
 * Presets: 'even' (one flat phase), 'negative_split' (2% held-back first
 * half, derived-faster second half), and 'ten_ten_ten' (the classic marathon
 * 10 mi / 10 mi / 10 K strategy generalised proportionally to any distance).
 * Intent is an identifier — i18n labels resolve at the render layer and are
 * not part of the pair.
 *
 * Twin of `apps/mobile_android/lib/race_phases.dart` — keep logic, edge
 * cases, and test count in lockstep.
 */

export type RacePhasePreset = 'ten_ten_ten' | 'negative_split' | 'even';

export type RacePhaseIntent = 'hold_back' | 'settle' | 'race' | 'even';

export interface RacePhase {
	startM: number;
	endM: number;
	intent: RacePhaseIntent;
	paceFactor: number;
}

const TEN_MILE_FRACTION = 16_093.44 / 42_195;
const HOLD_BACK_FACTOR = 1.02;

export function buildPhasePlan(distanceM: number, preset: RacePhasePreset): RacePhase[] {
	if (!Number.isFinite(distanceM) || distanceM <= 0) return [];

	if (preset === 'even') {
		return [{ startM: 0, endM: distanceM, intent: 'even', paceFactor: 1 }];
	}

	if (preset === 'negative_split') {
		const raceFactor = (1 - 0.5 * HOLD_BACK_FACTOR) / 0.5;
		return [
			{ startM: 0, endM: distanceM / 2, intent: 'hold_back', paceFactor: HOLD_BACK_FACTOR },
			{ startM: distanceM / 2, endM: distanceM, intent: 'race', paceFactor: raceFactor }
		];
	}

	const f1 = TEN_MILE_FRACTION;
	const f2 = TEN_MILE_FRACTION;
	const f3 = 1 - f1 - f2;
	const raceFactor = (1 - f1 * HOLD_BACK_FACTOR - f2 * 1) / f3;
	return [
		{ startM: 0, endM: distanceM * f1, intent: 'hold_back', paceFactor: HOLD_BACK_FACTOR },
		{ startM: distanceM * f1, endM: distanceM * (f1 + f2), intent: 'settle', paceFactor: 1 },
		{ startM: distanceM * (f1 + f2), endM: distanceM, intent: 'race', paceFactor: raceFactor }
	];
}

/**
 * Index of the phase containing `distanceM` (start-inclusive, end-exclusive;
 * >= the last end clamps to the last index, < 0 clamps to the first).
 * Empty plan → -1.
 */
export function phaseAt(phases: RacePhase[], distanceM: number): number {
	if (phases.length === 0) return -1;
	if (distanceM < 0) return 0;
	for (let i = 0; i < phases.length; i++) {
		if (distanceM >= phases[i].startM && distanceM < phases[i].endM) return i;
	}
	return phases.length - 1;
}

export function phaseTargetPaceSecPerKm(
	phase: RacePhase,
	goalPaceSecPerKm: number | null
): number | null {
	if (
		goalPaceSecPerKm == null ||
		!Number.isFinite(goalPaceSecPerKm) ||
		goalPaceSecPerKm <= 0
	) {
		return null;
	}
	return goalPaceSecPerKm * phase.paceFactor;
}

export function goalPaceSecPerKm(distanceM: number, goalTimeS: number): number | null {
	if (!Number.isFinite(distanceM) || distanceM <= 0) return null;
	if (!Number.isFinite(goalTimeS) || goalTimeS <= 0) return null;
	return goalTimeS / (distanceM / 1000);
}
