/**
 * Race-day mode helpers: days-until, pacing strategy, and the
 * pre-race checklist. The Svelte panel on `/plans/[id]` reads off
 * these pure functions.
 *
 * Predictions come from `riegelPredict` in `lib/training/training.ts`. We
 * don't redo the math here; this module focuses on what the runner
 * actually needs to plan around — pacing splits, kit, fuel.
 *
 * Pure module — no DOM, no Supabase. Tested in `race_day.test.ts`.
 */

export interface PacingStrategy {
	/** Average pace target across the whole race, in seconds per km. */
	avgSecPerKm: number;
	/**
	 * Per-split seconds, one per `unitMetres` of distance. Default
	 * `unitMetres` (1000) yields per-km splits; passing 1609.344
	 * yields per-mile splits for imperial users. Length is
	 * `ceil(distanceM / unitMetres)`.
	 */
	splitsSec: number[];
	/** Human-readable strategy name. */
	label: 'even' | 'negative-split' | 'positive-split';
}

/// 1 mile in metres. Pass `MILE_METRES` as the `unitMetres` arg on
/// pacing helpers to switch from per-km to per-mile splits.
export const MILE_METRES = 1609.344;

/**
 * Days from `today` to `raceDate`, both treated as local dates.
 * Returns a non-negative count; race day itself is 0. A race in the
 * past returns a negative number so the caller can hide the panel.
 */
export function daysUntilRace(raceDateIso: string, today: Date): number {
	const race = parseLocalDate(raceDateIso);
	const todayLocal = new Date(today.getFullYear(), today.getMonth(), today.getDate());
	const diffMs = race.getTime() - todayLocal.getTime();
	return Math.round(diffMs / (24 * 60 * 60 * 1000));
}

function parseLocalDate(iso: string): Date {
	// `YYYY-MM-DD` strings should parse as local midnight, not UTC.
	const [y, m, d] = iso.slice(0, 10).split('-').map((s) => parseInt(s, 10));
	return new Date(y, m - 1, d);
}

/**
 * Even-split pacing — every unit at the same pace. Total seconds is
 * preserved; rounding shaves only on the last split. Pass
 * `unitMetres=1000` for per-km splits (default) or `MILE_METRES` for
 * per-mile splits when the user prefers imperial.
 */
export function evenSplitPacing(
	distanceM: number,
	totalSec: number,
	unitMetres = 1000,
): PacingStrategy {
	if (distanceM <= 0 || totalSec <= 0) {
		return { avgSecPerKm: 0, splitsSec: [], label: 'even' };
	}
	const units = Math.ceil(distanceM / unitMetres);
	const avgSecPerKm = totalSec / (distanceM / 1000);
	const avgPerUnit = totalSec / (distanceM / unitMetres);
	const splits: number[] = [];
	for (let i = 0; i < units - 1; i++) {
		splits.push(Math.round(avgPerUnit));
	}
	// Last split absorbs the leftover — the partial-unit tail (when the race
	// distance isn't a whole-unit multiple) AND the accumulated per-split
	// rounding error. Rounding each full split independently drifts the total
	// by up to ~units/2 seconds (e.g. 10 km at 300.5 s/km → 10×301 = 3010,
	// not 3005), so derive the last split from the running total to preserve
	// the documented invariant that the splits sum to the target time.
	const summed = splits.reduce((a, b) => a + b, 0);
	splits.push(Math.round(totalSec) - summed);
	return { avgSecPerKm, splitsSec: splits, label: 'even' };
}

/**
 * Negative-split pacing — second half faster than the first by
 * `deltaPercent`. A 2% negative split for a 4:30/km marathon means
 * first half ~4:33, second half ~4:27. Halves are by *distance*, not
 * unit count, so the math works on 5k as well as on full marathons.
 * Pass `unitMetres=1000` for per-km splits (default) or `MILE_METRES`
 * for per-mile splits.
 */
export function negativeSplitPacing(
	distanceM: number,
	totalSec: number,
	deltaPercent = 2,
	unitMetres = 1000,
): PacingStrategy {
	if (distanceM <= 0 || totalSec <= 0) {
		return { avgSecPerKm: 0, splitsSec: [], label: 'negative-split' };
	}
	const avgSecPerKm = totalSec / (distanceM / 1000);
	const avgPerUnit = totalSec / (distanceM / unitMetres);
	const delta = (avgPerUnit * deltaPercent) / 100;
	const firstHalfPace = avgPerUnit + delta;
	const secondHalfPace = avgPerUnit - delta;
	const units = Math.ceil(distanceM / unitMetres);
	const totalUnits = distanceM / unitMetres;
	const halfUnits = totalUnits / 2;
	const splits: number[] = [];
	for (let i = 0; i < units; i++) {
		const startU = i;
		const endU = Math.min(i + 1, totalUnits);
		const segU = endU - startU;
		// Pace for the split is the pace at its midpoint unit.
		const midU = startU + segU / 2;
		const pace = midU < halfUnits ? firstHalfPace : secondHalfPace;
		splits.push(Math.round(pace * segU));
	}
	return { avgSecPerKm, splitsSec: splits, label: 'negative-split' };
}

export interface ChecklistItem {
	name: string;
	/** Short clarification, optional. */
	detail?: string;
}

export interface ChecklistSection {
	title: string;
	items: ChecklistItem[];
}

/**
 * Distance-aware pre-race checklist. Marathon distances pick up fuel
 * + gear items that a 5k doesn't need; everything <=10k stays light.
 *
 * Weather is left to the caller — the forecast pull lives in the
 * UI layer because it's async and surface-specific.
 */
export function raceChecklist(distanceM: number): ChecklistSection[] {
	const isShort = distanceM <= 10_500;
	const isHalf = distanceM > 10_500 && distanceM <= 22_000;
	const isFull = distanceM > 22_000;

	const fuel: ChecklistItem[] = [];
	if (isShort) {
		fuel.push({
			name: 'Light breakfast 2 h before',
			detail: 'Toast + banana, 300-400 kcal. No gels needed.',
		});
	} else if (isHalf) {
		fuel.push(
			{ name: 'Light breakfast 2-3 h before', detail: 'Oats + banana, 400-500 kcal.' },
			{ name: '1-2 gels', detail: 'Take at km 10 and km 16.' },
			{ name: 'Pre-race coffee or caffeine gel' },
		);
	} else if (isFull) {
		fuel.push(
			{ name: 'Carb load 24-48 h out', detail: '8-10 g/kg per day in the final 2 days.' },
			{ name: 'Big breakfast 3 h before', detail: '500-700 kcal, low fat / fibre.' },
			{ name: '4-6 gels', detail: 'Take every 5-7 km after km 10. Practice this in long runs first.' },
			{ name: 'Electrolyte at every aid station', detail: 'Especially after km 25.' },
		);
	}

	const gear: ChecklistItem[] = [
		{ name: 'Race-day shoes (broken in, never new)' },
		{ name: 'Watch / HR strap, charged the night before' },
		{ name: 'Race bib + safety pins / belt' },
		{ name: 'Anti-chafe + body lube on hotspots' },
		{ name: 'Socks (the pair you trust)' },
	];
	if (!isShort) {
		gear.push({ name: 'Spare laces + small pin/tape', detail: 'In case of last-mile mishaps.' });
	}
	if (isFull) {
		gear.push({ name: 'Toilet plan', detail: 'Know where the porta-loos are along the route.' });
	}

	const morningOf: ChecklistItem[] = [
		{ name: 'Wake-up 3 h before gun time' },
		{ name: 'Hydrate 500 ml + electrolyte, then stop drinking 90 min out' },
		{ name: 'Arrive 60 min early', detail: 'Bag drop + warm-up + final pee.' },
		{ name: 'Warm-up: 10 min easy jog + strides' },
	];

	return [
		{ title: 'Morning of', items: morningOf },
		{ title: 'Gear', items: gear },
		{ title: 'Fueling', items: fuel },
	];
}

export type GoalFeasibilityVerdict = 'ahead' | 'on_track' | 'behind' | 'far_behind';

export interface GoalFeasibility {
	verdict: GoalFeasibilityVerdict;
	/**
	 * `predictedSec - goalSec`, rounded. Negative = the fitness projection is
	 * faster than the goal (ahead of it); positive = slower (behind it).
	 */
	deltaSec: number;
}

/**
 * Band, as a fraction of the goal time, within which a fitness projection
 * counts as "on track" for the goal. ±2 % of a 3:30 marathon is ~±4 min —
 * inside the day-to-day noise of a Riegel projection off a single effort, so
 * a runner isn't told they're off-pace over a rounding-scale gap.
 */
export const GOAL_ONTRACK_BAND = 0.02;
/**
 * Slower than goal by more than this fraction → "far behind" (a materially
 * out-of-reach goal, ~+17 min on a 3:30). Between the on-track band and this
 * is a recoverable "behind".
 */
export const GOAL_FARBEHIND_BAND = 0.08;

/**
 * Grade a runner's goal time against a fitness-derived prediction for the
 * same distance. `goalSec` is what they're aiming for; `predictedSec` is the
 * Riegel projection off their recent efforts. Returns null when either input
 * is missing / non-positive (the caller hides the signal rather than showing
 * a verdict off no data). Verdicts:
 *   - `ahead`      — projection faster than goal by more than the on-track band
 *   - `on_track`   — projection within ±`GOAL_ONTRACK_BAND` of the goal
 *   - `behind`     — projection slower, but within `GOAL_FARBEHIND_BAND`
 *   - `far_behind` — projection slower by more than `GOAL_FARBEHIND_BAND`
 */
export function goalFeasibility(goalSec: number, predictedSec: number): GoalFeasibility | null {
	if (!(goalSec > 0) || !(predictedSec > 0)) return null;
	const deltaSec = predictedSec - goalSec;
	const ratio = deltaSec / goalSec;
	let verdict: GoalFeasibilityVerdict;
	if (ratio < -GOAL_ONTRACK_BAND) verdict = 'ahead';
	else if (ratio <= GOAL_ONTRACK_BAND) verdict = 'on_track';
	else if (ratio <= GOAL_FARBEHIND_BAND) verdict = 'behind';
	else verdict = 'far_behind';
	return { verdict, deltaSec: Math.round(deltaSec) };
}

/** Pretty-print seconds as MM:SS (or H:MM:SS for splits > 1h). */
export function fmtSplitTime(seconds: number): string {
	const total = Math.round(seconds);
	const h = Math.floor(total / 3600);
	const m = Math.floor((total % 3600) / 60);
	const s = total % 60;
	if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
	return `${m}:${String(s).padStart(2, '0')}`;
}
