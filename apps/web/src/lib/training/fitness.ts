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

import type { Run } from '../types';
import { kLayoffResetDays } from './training_load';

export interface FitnessSnapshot {
	vdot: number | null;
	vo2Max: number | null;
	acuteLoad: number | null;
	chronicLoad: number | null;
	trainingStressBal: number | null;
	qualifyingRunCount: number;
}

/// Whether the runner is returning from a layoff: their most recent
/// qualifying run is recent (≤ 14 days before `nowMs`) but the gap
/// before it was ≥ kLayoffResetDays. Drives the gentle "rebuild
/// gradually" framing on the recovery card so a returning runner isn't
/// told they're "very fresh — race soon". Persona-hunt comeback #29.
export function isReturningFromLayoff(runs: Run[], nowMs: number = Date.now()): boolean {
	const days = qualifyingRuns(runs)
		.map((r) => new Date(r.started_at).getTime())
		.filter((t) => Number.isFinite(t) && t <= nowMs)
		.sort((a, b) => a - b);
	if (days.length === 0) return false;
	const dayMs = 24 * 3600_000;
	const latest = days[days.length - 1];
	if (nowMs - latest > 14 * dayMs) return false; // not currently active
	if (days.length === 1) return false; // one run can't prove a prior gap (new runner, not returning)
	const prev = days[days.length - 2];
	return latest - prev >= kLayoffResetDays * dayMs;
}

/// Minimum qualifying-run distance (metres) for fitness math. Lowered from
/// 3 km to 1.5 km so a comeback / new runner rebuilding at 1-2 km per outing
/// still gets a fitness + volume signal instead of an empty Fitness card
/// forever (persona round-5 runner-comeback). 1.5 km paired with the 5-min
/// duration floor below means a qualifying run is a sustained effort of at
/// least ~3:20/km — noisy 1 km all-out sprints (which would inflate the
/// VDOT ceiling, since `currentVdot` takes the max over runs) stay excluded,
/// and a true sprint is also caught by `vdotFromRun`'s own 1 km / 2 min gate.
/// We deliberately did NOT drop to 1 km: the gap between 1 and 1.5 km is
/// where short all-out efforts produce the most VDOT inflation.
const MIN_QUALIFYING_DISTANCE_M = 1500;

/// Whether the runner is mid-gap returning: they have at least one run
/// in their history but the most recent is older than `gapDays`. This is
/// the inverse case to `isReturningFromLayoff` — that one fires once a
/// recent run follows a gap (they're already back), this one fires while
/// the gap is still open (they're reopening the app cold). Drives the
/// gentle "Welcome back" surface on the dashboard so a long-absent runner
/// isn't met with an empty-looking grid. Persona round-5 comeback. Counts
/// every run (not just qualifying ones) — any logged activity proves prior
/// history, and a treadmill / short run shouldn't read as "never ran".
export function isReturningFromGap(
	runs: Run[],
	gapDays = 60,
	nowMs: number = Date.now(),
): boolean {
	let latest = -Infinity;
	for (const r of runs) {
		const t = new Date(r.started_at).getTime();
		if (Number.isFinite(t) && t <= nowMs && t > latest) latest = t;
	}
	if (!Number.isFinite(latest)) return false;
	return nowMs - latest >= gapDays * 24 * 3600_000;
}

/// Qualifying runs for fitness math: source is an actual recording or
/// reliable import, distance is >= MIN_QUALIFYING_DISTANCE_M, duration / distance
/// both sane. Indoor / treadmill runs are excluded — their distance is
/// belt-/estimate-derived, not measured, so feeding it to VDOT inflates the
/// runner's fitness ceiling (#16).
export function qualifyingRuns(runs: Run[]): Run[] {
	return runs.filter(
		(r) =>
			r.distance_m >= MIN_QUALIFYING_DISTANCE_M &&
			r.duration_s >= 300 &&
			(r.metadata as Record<string, unknown> | null)?.indoor !== true &&
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

/// Threshold pace (s/km) from VDOT — Daniels T-pace. Solve the VO2
/// demand quadratic at 88% of VDOT (Daniels' "T-pace ≈ 88% vVO2max"
/// rule of thumb) for velocity in m/min, then convert to s/km:
///
///     demand(v) = -4.6 + 0.182258 v + 0.000104 v² = 0.88 × VDOT
///
/// Spot checks against Daniels' published table — VDOT 50 → 4:15/km,
/// VDOT 60 → 3:40/km, VDOT 70 → 3:14/km — match within a couple of
/// seconds across VDOT 30-70. Returns null for null / non-positive
/// input.
export function thresholdPaceSecPerKmFromVdot(vdot: number | null): number | null {
	if (vdot == null || vdot <= 0) return null;
	const target = 0.88 * vdot + 4.6;
	const a = 0.000104;
	const b = 0.182258;
	const disc = b * b + 4 * a * target;
	if (disc < 0) return null;
	const vMpm = (-b + Math.sqrt(disc)) / (2 * a);
	if (vMpm <= 0) return null;
	const mps = vMpm / 60;
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
		// UTC-keyed intentionally: started_at is UTC; the EWMA loop uses UTC day
		// boundaries too. This is the one place where UTC bucketing is correct —
		// matches fitness.dart's _dayKey(r.startedAt.toUtc()).
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
	// After a sustained layoff (kLayoffResetDays of no runs) fitness is
	// genuinely lost — zero the EWMAs so a returning runner doesn't carry
	// a phantom CTL that, paired with a cratered ATL, fakes a high TSB and
	// triggers "very fresh, build again / race soon" advice. Persona-hunt
	// comeback #29.
	let zeroStreak = 0;
	const dayMs = 24 * 3600_000;
	for (let t = startDay.getTime(); t <= endDay.getTime(); t += dayMs) {
		const key = new Date(t).toISOString().slice(0, 10);
		const tss = byDay.get(key) ?? 0;
		if (tss > 0) {
			zeroStreak = 0;
		} else if (++zeroStreak >= kLayoffResetDays) {
			atl = 0;
			ctl = 0;
		}
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
export function recoveryAdvice(
	tsb: number | null,
	ctl: number | null,
	returningFromLayoff = false,
): string {
	if (tsb == null || ctl == null) {
		return 'Not enough data yet — log a few runs with HR and try again.';
	}
	// A returning runner can show a high TSB purely because ATL decayed
	// faster than CTL during the break — that's detraining, not freshness.
	// Override the freshness rungs with rebuild-gradually framing.
	// Persona-hunt comeback #29.
	if (returningFromLayoff) {
		return 'Welcome back. Your form numbers reset after the break — rebuild gradually with easy, consistent running before any hard sessions.';
	}
	// Heavy acute overload warrants a rest warning even at low chronic load.
	// A new runner who just spiked a hard week (low CTL, deeply negative TSB)
	// is exactly the at-injury-risk case the ctl<10 "still building" message
	// would otherwise mask — so the overload guard comes first.
	if (tsb < -30) {
		return 'You\'re heavily loaded — easy running or a rest day today.';
	}
	if (ctl < 10) {
		return 'Fitness is still building. Focus on consistency; one quality session a week is plenty for now.';
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

/// TSB at or above which a hard / quality session (intervals, tempo,
/// race) is advisable. Below this the runner is still loaded enough
/// that the next session should stay easy. Matches the boundary in
/// `recoveryAdvice` where the advice flips from "easy / steady is
/// right" to "a steady run or a tempo effort works".
export const HARD_SESSION_TSB_THRESHOLD = -10;

/// Estimate how many easy / rest days until Form (TSB) recovers enough
/// for the next hard session. Projects the ATL / CTL EWMAs forward
/// assuming zero added stress — the fastest realistic recovery — so the
/// answer is a floor, not a promise (any running in between slows it).
///
/// Returns 0 when the runner is already recovered (TSB ≥ threshold), a
/// positive day count when recovery lands within `maxDays`, or null
/// when it would take longer than `maxDays` (too deep in the hole for a
/// single "in N days" number to be meaningful — the recovery-advice
/// string already says "easy running or a rest day" in that case).
///
/// Decay factors are exp(-1/halflife) with the same 7-day ATL / 42-day
/// CTL halflives the load curves use, so this stays consistent with the
/// TSB shown on the dashboard. With rest ATL decays faster than CTL, so
/// TSB always rises — the loop is guaranteed to terminate or hit the cap.
export function daysUntilNextHardSession(
	atl: number | null,
	ctl: number | null,
	maxDays = 21,
): number | null {
	if (atl == null || ctl == null) return null;
	const atlDecay = Math.exp(-1 / 7);
	const ctlDecay = Math.exp(-1 / 42);
	let a = atl;
	let c = ctl;
	for (let d = 0; d <= maxDays; d++) {
		if (c - a >= HARD_SESSION_TSB_THRESHOLD) return d;
		a *= atlDecay;
		c *= ctlDecay;
	}
	return null;
}
