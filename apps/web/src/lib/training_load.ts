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

/// Stress-model calibration for a window. Persona-hunt finding Pro #2
/// (decisions §34): a per-run "TRIMP when HR present, else distance"
/// fallback produces wildly different stress for the same effort —
/// an easy 12 km run = ~80 TRIMP with strap, 120 distance-fallback
/// without. A single strap-less day faked a 3× spike in the daily
/// series → TSB drifted tens of points → wrong tapering decisions.
///
/// The fix: pick ONE mode per window and calibrate the fallback so
/// runs without HR contribute comparable load. `mode='trimp'` uses
/// the runner's own data — median TRIMP-per-km across HR-eligible
/// runs in the window — as the fallback rate for runs that lack
/// HR. `mode='distance'` keeps the legacy 10-points/km behaviour for
/// users who don't carry HR. The mode is decided at series-level so
/// the chart can't internally switch and produce a discontinuity.
export interface StressCalibration {
	mode: 'trimp' | 'distance';
	/// Stress points per km used as the fallback for HR-less runs in
	/// 'trimp' mode. Null in 'distance' mode (legacy 10 pts/km applies).
	trimpPerKmFallback: number | null;
}

/// Decide the calibration for a window. If the user has the HR prefs
/// configured AND at least one run with avg_bpm in the window, mode
/// is 'trimp' — fallback rate is the median TRIMP-per-km of the
/// eligible runs (anchored to the user's own intensity profile). Else
/// mode is 'distance' (legacy 10 pts/km).
export function computeCalibration(
	runs: RunForLoad[],
	prefs: HrPrefs = {}
): StressCalibration {
	const rest = numericOrNull(prefs.resting_hr_bpm);
	const max = numericOrNull(prefs.max_hr_bpm);
	if (rest == null || max == null || max <= rest) {
		return { mode: 'distance', trimpPerKmFallback: null };
	}
	const trimpsPerKm: number[] = [];
	for (const r of runs) {
		const avgBpm = numericOrNull(r.metadata?.['avg_bpm']);
		const km = (r.distance_m ?? 0) / 1000;
		if (avgBpm == null || km <= 0 || (r.duration_s ?? 0) <= 0) continue;
		const trimp = banisterTrimp(r.duration_s, avgBpm, rest, max);
		if (trimp > 0) trimpsPerKm.push(trimp / km);
	}
	if (trimpsPerKm.length === 0) {
		return { mode: 'distance', trimpPerKmFallback: null };
	}
	return { mode: 'trimp', trimpPerKmFallback: median(trimpsPerKm) };
}

function banisterTrimp(
	durationS: number,
	avgBpm: number,
	rest: number,
	max: number
): number {
	const durationMin = durationS / 60;
	const hrr = Math.max(0, Math.min(1, (avgBpm - rest) / (max - rest)));
	const k = 1.92;
	return durationMin * hrr * 0.64 * Math.exp(k * hrr);
}

function median(xs: number[]): number {
	const sorted = [...xs].sort((a, b) => a - b);
	const mid = Math.floor(sorted.length / 2);
	return sorted.length % 2 === 0
		? (sorted[mid - 1] + sorted[mid]) / 2
		: sorted[mid];
}

/// Per-run training stress score. Pass a `calibration` to honour
/// the window-level mode (recommended via `aggregateDailyStress`,
/// which derives one calibration for the whole window). The legacy
/// per-run dispatch (no calibration arg) is kept for callers that
/// score a single isolated run, but emits a warning shape — mixing
/// TRIMP and distance in one daily series is what triggered Pro #2.
export function computeStress(
	run: RunForLoad,
	prefs: HrPrefs = {},
	calibration?: StressCalibration
): number {
	if ((run.distance_m ?? 0) <= 0 && (run.duration_s ?? 0) <= 0) return 0;

	// Fall back to the implicit per-run dispatch for callers that don't
	// pass a calibration. This is the legacy single-run shape; series
	// callers should always provide a calibration so the mode is
	// consistent across the window.
	const cal = calibration ?? computeCalibration([run], prefs);

	const avgBpm = numericOrNull(run.metadata?.['avg_bpm']);
	const rest = numericOrNull(prefs.resting_hr_bpm);
	const max = numericOrNull(prefs.max_hr_bpm);

	if (cal.mode === 'trimp') {
		if (avgBpm != null && rest != null && max != null && max > rest) {
			return banisterTrimp(run.duration_s, avgBpm, rest, max);
		}
		// HR-less run in TRIMP mode: use the window-calibrated fallback
		// rate so this run's load is on the same scale as its TRIMP
		// siblings, not the legacy 10 pts/km that would fake a spike.
		const km = (run.distance_m ?? 0) / 1000;
		const rate = cal.trimpPerKmFallback ?? 7; // sane default if cal is per-run + HR-less
		return km * rate;
	}

	// Distance fallback — used when the user has no HR prefs / no
	// HR-eligible runs in the window at all.
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
/// yyyy-mm-dd. Derives a single calibration for the whole window so
/// every run is scored on the same scale — see StressCalibration for
/// the persona-hunt finding behind this.
export function aggregateDailyStress(runs: RunForLoad[], prefs: HrPrefs = {}): Map<string, number> {
	const calibration = computeCalibration(runs, prefs);
	const out = new Map<string, number>();
	for (const r of runs) {
		const stress = computeStress(r, prefs, calibration);
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
