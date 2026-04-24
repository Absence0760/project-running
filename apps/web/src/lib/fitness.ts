/// Fitness metrics — VO2 max + training-load math.
///
/// Shared by the dashboard cards (latest-snapshot summary +
/// trend chart) and the server-side recompute path. Pure functions —
/// inputs are plain run rows, outputs are scalars / small structs.
/// No Supabase or auth calls.
///
/// Keep the formulas honest. These are well-known running-science
/// heuristics, not proprietary research:
///
/// - **VO2 max (Daniels / Cooper 1-mile form):** derived from a run's
///   pace + heart rate when available. We use the Daniels "%VO2max at
///   race pace" curve because it behaves better at sub-maximal
///   running paces than the raw Cooper 12-minute test — most users
///   don't race a clean time trial, they just run.
/// - **Training stress score (TSS):** duration × intensity², where
///   intensity is current pace / threshold pace. No HR-based TSS yet
///   (HR is optional per run).
/// - **ATL / CTL / TSB:** standard exponentially-weighted moving
///   averages over daily TSS. 7-day ATL, 42-day CTL, TSB = CTL − ATL.

import type { Run } from './types';

export interface FitnessSnapshot {
	vdot: number | null;
	vo2Max: number | null;
	acuteLoad: number | null;
	chronicLoad: number | null;
	trainingStressBal: number | null;
	qualifyingRunCount: number;
}

/// Qualifying runs for fitness math: source is an actual recording or
/// reliable import, distance is >= 3 km (shorter runs are too noisy),
/// duration / distance both sane.
export function qualifyingRuns(runs: Run[]): Run[] {
	return runs.filter(
		(r) =>
			r.distance_m >= 3000 &&
			r.duration_s >= 300 &&
			(r.source === 'app' ||
				r.source === 'watch' ||
				r.source === 'strava' ||
				r.source === 'garmin' ||
				r.source === 'healthkit' ||
				r.source === 'healthconnect'),
	);
}

/// Runner's VDOT from their single best recent run. Takes pace (s/km)
/// and distance (m), returns Daniels' VDOT. The standard Daniels
/// formula, which inverts his "%VO2max at a given race pace" tables:
///
///     VO2 demand (ml/kg/min) = -4.60 + 0.182258·v + 0.000104·v²
///     %VO2max = 0.8 + 0.1894393·exp(-0.012778·t) + 0.2989558·exp(-0.1932605·t)
///     VDOT    = VO2 demand / %VO2max
///
/// where v is velocity in m/min and t is duration in minutes.
export function vdotFromRun(distanceM: number, durationS: number): number | null {
	if (distanceM < 1000 || durationS < 120) return null;
	const tMin = durationS / 60;
	const v = distanceM / tMin; // m/min
	const vo2Demand = -4.6 + 0.182258 * v + 0.000104 * v * v;
	const pctVo2Max =
		0.8 +
		0.1894393 * Math.exp(-0.012778 * tMin) +
		0.2989558 * Math.exp(-0.1932605 * tMin);
	if (pctVo2Max <= 0) return null;
	const vdot = vo2Demand / pctVo2Max;
	if (!Number.isFinite(vdot) || vdot <= 0) return null;
	return vdot;
}

/// Current VDOT = max over the user's qualifying runs in the last
/// ~90 days. Picks the best single effort rather than averaging; a
/// runner's fitness ceiling is what the hardest recent run proved they
/// can do. Returns null when no qualifying run exists.
export function currentVdot(runs: Run[], nowMs: number = Date.now()): number | null {
	const cutoff = nowMs - 90 * 24 * 3600_000;
	let best: number | null = null;
	for (const r of qualifyingRuns(runs)) {
		if (new Date(r.started_at).getTime() < cutoff) continue;
		const v = vdotFromRun(r.distance_m, r.duration_s);
		if (v != null && (best == null || v > best)) best = v;
	}
	return best;
}

/// Cooper-style VO2 max estimate. In practice this tracks VDOT 1:1 at
/// these input scales — we expose it as a separate number because
/// users recognise "VO2 max" as a label (VDOT doesn't show up in
/// consumer running apps). The value is the same; the name differs.
export function vo2MaxFromVdot(vdot: number | null): number | null {
	return vdot;
}

/// Training stress score for a single run. Needs a threshold pace to
/// divide by; we use a derived-from-VDOT threshold pace if available,
/// otherwise a fallback of 5:30 / km (seconds-per-km = 330).
///
/// TSS = (duration_h × normalised_intensity²) × 100
///     where intensity = threshold_pace / run_pace (inverted because
///     faster pace → smaller seconds-per-km → higher intensity).
export function runTss(
	distanceM: number,
	durationS: number,
	thresholdPaceSecPerKm: number,
): number {
	if (distanceM < 100 || durationS < 30 || thresholdPaceSecPerKm <= 0) return 0;
	const runPaceSecPerKm = durationS / (distanceM / 1000);
	if (runPaceSecPerKm <= 0) return 0;
	const intensity = thresholdPaceSecPerKm / runPaceSecPerKm;
	const durationH = durationS / 3600;
	return durationH * intensity * intensity * 100;
}

/// Threshold pace (s/km) from VDOT — Daniels T-pace. Rough inversion
/// of his pace tables: T-pace ≈ 1000 / (0.0003 × VDOT³ − 0.021 ×
/// VDOT² + 0.6 × VDOT + 2.0) in m/s. Returns null when VDOT is null.
export function thresholdPaceSecPerKmFromVdot(vdot: number | null): number | null {
	if (vdot == null) return null;
	const mps =
		0.0003 * vdot * vdot * vdot -
		0.021 * vdot * vdot +
		0.6 * vdot +
		2.0;
	if (mps <= 0) return null;
	return 1000 / mps;
}

/// EWMA: new = old + (sample − old) × (1 / tau). Scale is per-day.
function ewma(prev: number, sample: number, tau: number): number {
	return prev + (sample - prev) / tau;
}

/// Full training-load rollup: daily-bucketed TSS → 7-day ATL,
/// 42-day CTL, TSB = CTL − ATL, evaluated at `nowMs`. Returns nulls
/// when there's no data.
export function trainingLoad(
	runs: Run[],
	thresholdPaceSecPerKm: number | null,
	nowMs: number = Date.now(),
): { acuteLoad: number | null; chronicLoad: number | null; trainingStressBal: number | null } {
	if (thresholdPaceSecPerKm == null || runs.length === 0) {
		return { acuteLoad: null, chronicLoad: null, trainingStressBal: null };
	}
	// Walk forward day by day from the oldest run to now, pushing daily
	// TSS into both EWMAs. Days with no runs still tick — the decay is
	// what moves the averages down during rest.
	const byDay = new Map<string, number>();
	for (const r of qualifyingRuns(runs)) {
		const key = new Date(r.started_at).toISOString().slice(0, 10);
		const tss = runTss(r.distance_m, r.duration_s, thresholdPaceSecPerKm);
		byDay.set(key, (byDay.get(key) ?? 0) + tss);
	}
	if (byDay.size === 0) {
		return { acuteLoad: null, chronicLoad: null, trainingStressBal: null };
	}
	// Start from 60 days of pre-history (zeros) so the CTL has a chance
	// to establish a baseline, then march forward to `now`.
	const endDay = new Date(nowMs);
	endDay.setUTCHours(0, 0, 0, 0);
	const earliest = Math.min(...Array.from(byDay.keys()).map((k) => new Date(k).getTime()));
	const startDay = new Date(Math.min(earliest, endDay.getTime() - 42 * 24 * 3600_000));
	startDay.setUTCHours(0, 0, 0, 0);

	let atl = 0;
	let ctl = 0;
	const dayMs = 24 * 3600_000;
	for (let t = startDay.getTime(); t <= endDay.getTime(); t += dayMs) {
		const key = new Date(t).toISOString().slice(0, 10);
		const tss = byDay.get(key) ?? 0;
		atl = ewma(atl, tss, 7);
		ctl = ewma(ctl, tss, 42);
	}
	return { acuteLoad: atl, chronicLoad: ctl, trainingStressBal: ctl - atl };
}

/// Top-level snapshot: combine VDOT, VO2 max, training load into a
/// single object suitable for inserting into `fitness_snapshots`.
export function computeSnapshot(runs: Run[], nowMs: number = Date.now()): FitnessSnapshot {
	const vdot = currentVdot(runs, nowMs);
	const threshold = thresholdPaceSecPerKmFromVdot(vdot);
	const load = trainingLoad(runs, threshold, nowMs);
	return {
		vdot,
		vo2Max: vo2MaxFromVdot(vdot),
		acuteLoad: load.acuteLoad,
		chronicLoad: load.chronicLoad,
		trainingStressBal: load.trainingStressBal,
		qualifyingRunCount: qualifyingRuns(runs).length,
	};
}

/// Advice string for the Recovery advisor card. Rule-based on TSB —
/// the simplest honest signal we can give without getting into
/// performance-coach territory. Mirrors what Training Peaks / Zwift
/// show at a similar scope.
export function recoveryAdvice(tsb: number | null, ctl: number | null): string {
	if (tsb == null || ctl == null) {
		return 'Not enough data yet — log a few runs with HR and try again.';
	}
	if (ctl < 10) {
		return 'Fitness is still building. Focus on consistency; one quality session a week is plenty for now.';
	}
	if (tsb < -30) {
		return 'You\'re heavily loaded — easy running or a rest day today.';
	}
	if (tsb < -10) {
		return 'Loaded but within build territory. Easy / steady is right for today.';
	}
	if (tsb < 10) {
		return 'Sweet spot — a steady run or a tempo effort works.';
	}
	if (tsb < 25) {
		return 'Tapering / freshening up — a race or hard workout will land well in the next few days.';
	}
	return 'Very fresh — if you\'ve been tapering on purpose, race soon. Otherwise, it\'s time to build again.';
}
