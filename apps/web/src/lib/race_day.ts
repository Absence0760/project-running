/**
 * Race-day mode helpers: days-until, pacing strategy, and the
 * pre-race checklist. The Svelte panel on `/plans/[id]` reads off
 * these pure functions.
 *
 * Predictions come from `riegelPredict` in `lib/training.ts`. We
 * don't redo the math here; this module focuses on what the runner
 * actually needs to plan around — pacing splits, kit, fuel.
 *
 * Pure module — no DOM, no Supabase. Tested in `race_day.test.ts`.
 */

export interface PacingStrategy {
	/** Average pace target across the whole race, in seconds per km. */
	avgSecPerKm: number;
	/** Per-km splits as seconds. Length === ceil(distance_m / 1000). */
	splitsSec: number[];
	/** Human-readable strategy name. */
	label: 'even' | 'negative-split' | 'positive-split';
}

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
 * Even-split pacing — every km at the same pace. Total seconds is
 * preserved; rounding shaves only on the last split.
 */
export function evenSplitPacing(distanceM: number, totalSec: number): PacingStrategy {
	if (distanceM <= 0 || totalSec <= 0) {
		return { avgSecPerKm: 0, splitsSec: [], label: 'even' };
	}
	const km = Math.ceil(distanceM / 1000);
	const avg = totalSec / (distanceM / 1000);
	const splits: number[] = [];
	for (let i = 0; i < km - 1; i++) {
		splits.push(Math.round(avg));
	}
	// Last split takes any rounding remainder (and is a partial km if the
	// race distance isn't a whole-km multiple).
	const remainderKm = distanceM / 1000 - (km - 1);
	splits.push(Math.round(avg * remainderKm));
	return { avgSecPerKm: avg, splitsSec: splits, label: 'even' };
}

/**
 * Negative-split pacing — second half faster than the first by
 * `deltaPercent`. A 2% negative split for a 4:30/km marathon means
 * first half ~4:33, second half ~4:27. Halves are by *distance*, not
 * km count, so the math works on 5k as well as on full marathons.
 */
export function negativeSplitPacing(
	distanceM: number,
	totalSec: number,
	deltaPercent = 2,
): PacingStrategy {
	if (distanceM <= 0 || totalSec <= 0) {
		return { avgSecPerKm: 0, splitsSec: [], label: 'negative-split' };
	}
	const avg = totalSec / (distanceM / 1000);
	const delta = (avg * deltaPercent) / 100;
	const firstHalfPace = avg + delta;
	const secondHalfPace = avg - delta;
	const km = Math.ceil(distanceM / 1000);
	const halfKm = (distanceM / 1000) / 2;
	const splits: number[] = [];
	for (let i = 0; i < km; i++) {
		const startKm = i;
		const endKm = Math.min(i + 1, distanceM / 1000);
		const segKm = endKm - startKm;
		// Pace for the split is the pace at its midpoint km.
		const midKm = startKm + segKm / 2;
		const pace = midKm < halfKm ? firstHalfPace : secondHalfPace;
		splits.push(Math.round(pace * segKm));
	}
	return { avgSecPerKm: avg, splitsSec: splits, label: 'negative-split' };
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

/** Pretty-print seconds as MM:SS (or H:MM:SS for splits > 1h). */
export function fmtSplitTime(seconds: number): string {
	const total = Math.round(seconds);
	const h = Math.floor(total / 3600);
	const m = Math.floor((total % 3600) / 60);
	const s = total % 60;
	if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
	return `${m}:${String(s).padStart(2, '0')}`;
}
