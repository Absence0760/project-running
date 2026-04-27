// Training-load curves (decisions.md §34).
//
// Pure functions — no Svelte / Supabase dependencies. Computes a per-run
// training stress score, aggregates to daily totals, runs the
// CTL / ATL / TSB EWMA trio, and returns a 90-day daily series ready
// for chart rendering.
//
// We don't import the Run type from $lib/types here so the module
// stays runnable under `npx tsx --test` without dragging in the
// Supabase generated types. Callers shape Run rows into RunForLoad.

export interface RunForLoad {
	started_at: string;
	duration_s: number;
	distance_m: number;
	metadata?: Record<string, unknown> | null;
}

export interface HrPrefs {
	resting_hr_bpm?: number | null;
	max_hr_bpm?: number | null;
}

/// Per-run training stress score. Tier ladder per §34:
///   1. Banister TRIMP when avg_bpm + resting + max are all known.
///   2. Distance proxy: 10 points per kilometre (≈ 50 for an easy 5k).
///   3. Zero when neither distance nor duration is set.
export function computeStress(run: RunForLoad, prefs: HrPrefs = {}): number {
	if ((run.distance_m ?? 0) <= 0 && (run.duration_s ?? 0) <= 0) return 0;

	const avgBpm = numericOrNull(run.metadata?.['avg_bpm']);
	const rest = numericOrNull(prefs.resting_hr_bpm);
	const max = numericOrNull(prefs.max_hr_bpm);

	if (avgBpm != null && rest != null && max != null && max > rest) {
		// Banister TRIMP. Standard male-default 1.92 weighting; close
		// enough for v1, and easy to swap for sex-specific later if we
		// add it to user_settings.
		const durationMin = run.duration_s / 60;
		const hrr = Math.max(0, Math.min(1, (avgBpm - rest) / (max - rest)));
		const k = 1.92;
		return durationMin * hrr * 0.64 * Math.exp(k * hrr);
	}

	// Distance fallback.
	return (run.distance_m / 1000) * 10;
}

function numericOrNull(v: unknown): number | null {
	if (typeof v === 'number' && Number.isFinite(v)) return v;
	if (typeof v === 'string') {
		const n = Number(v);
		return Number.isFinite(n) ? n : null;
	}
	return null;
}

/// yyyy-mm-dd in local time. Not via toISOString — that rolls the
/// date back across UTC midnight in positive-offset zones.
export function localDateKey(d: Date): string {
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/// Sum stresses by local calendar day. Returns a Map keyed by
/// yyyy-mm-dd.
export function aggregateDailyStress(runs: RunForLoad[], prefs: HrPrefs = {}): Map<string, number> {
	const out = new Map<string, number>();
	for (const r of runs) {
		const stress = computeStress(r, prefs);
		if (stress <= 0) continue;
		const key = localDateKey(new Date(r.started_at));
		out.set(key, (out.get(key) ?? 0) + stress);
	}
	return out;
}

export interface TrainingLoadPoint {
	date: string;
	stress: number;
	atl: number;
	ctl: number;
	tsb: number;
}

/// EWMA trio over a fixed-length daily window ending today (local tz).
/// Days with no stress still tick the decay — that's the whole point.
/// alpha = 1 - exp(-1/halflife). ATL halflife = 7, CTL halflife = 42.
export function computeTrainingLoadSeries(
	runs: RunForLoad[],
	prefs: HrPrefs = {},
	windowDays = 90,
	endDate: Date = new Date()
): TrainingLoadPoint[] {
	const daily = aggregateDailyStress(runs, prefs);
	const atlAlpha = 1 - Math.exp(-1 / 7);
	const ctlAlpha = 1 - Math.exp(-1 / 42);

	let atl = 0;
	let ctl = 0;
	const points: TrainingLoadPoint[] = [];
	const cursor = new Date(endDate);
	cursor.setHours(0, 0, 0, 0);
	cursor.setDate(cursor.getDate() - (windowDays - 1));

	for (let i = 0; i < windowDays; i++) {
		const key = localDateKey(cursor);
		const stress = daily.get(key) ?? 0;
		atl = atl + atlAlpha * (stress - atl);
		ctl = ctl + ctlAlpha * (stress - ctl);
		points.push({
			date: key,
			stress,
			atl: round2(atl),
			ctl: round2(ctl),
			tsb: round2(ctl - atl),
		});
		cursor.setDate(cursor.getDate() + 1);
	}
	return points;
}

function round2(n: number): number {
	return Math.round(n * 100) / 100;
}

/// Convenience: did any of the runs we computed have a TRIMP-eligible
/// HR signal? Used to label the chart honestly.
export function hasTrimpSignal(runs: RunForLoad[], prefs: HrPrefs = {}): boolean {
	if (prefs.resting_hr_bpm == null || prefs.max_hr_bpm == null) return false;
	for (const r of runs) {
		if (numericOrNull(r.metadata?.['avg_bpm']) != null) return true;
	}
	return false;
}
