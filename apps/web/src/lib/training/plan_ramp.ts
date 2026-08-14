/**
 * Does the plan the wizard just generated match the training the runner is
 * actually doing?
 *
 * `generatePlan` sizes every week off the goal race, the training days, and a
 * fitness anchor — it never looks at the runner's history. So a runner
 * averaging 20 km a week can generate a marathon plan whose first week asks
 * for 37 km and nothing says a word. That opening step is the classic
 * training injury, and the app already owns a tested policy for exactly this
 * shape of question: the coach roster's acute:chronic workload ratio. A
 * plan week IS an acute (7-day) load; the runner's trailing 28-day average IS
 * the chronic base. So the bands come from `coach_load` rather than from new
 * numbers invented here, and the two surfaces cannot drift.
 *
 * Web-only (the wizard surface it backs is `PlanEditor.svelte`); the mobile
 * mirror is tracked in docs/product/followups.md.
 */

import { acwr, injuryRiskBand } from './coach_load';

const DAY_MS = 86_400_000;

/// How many trailing 7-day windows make up the chronic base. Four weeks is
/// the ACWR convention `coach_load` already uses for its chronic average.
export const CHRONIC_WINDOW_WEEKS = 4;

/// How many of those windows must carry at least one run before the check
/// will say anything. ACWR needs ~28 days of *consistent* history to mean
/// anything; below that the ratio is arithmetic on noise. A runner with one
/// 3 km jog in a month otherwise divides a beginner plan's opening week by
/// 0.75 km and gets told their C25K is a high injury risk.
export const MIN_ACTIVE_WEEKS = 3;

export interface RunForVolume {
	started_at: string;
	distance_m: number | null;
	activity_type?: string | null;
	/// Carried by every `runs` row and deliberately NOT filtered on, unlike the
	/// coach roster, which excludes DNFs. Declared here so its absence from the
	/// filter below reads as the decision it is rather than an oversight — see
	/// decisions § 592. A DNF is only ever a post-hoc flag on an already-recorded
	/// run; nothing rewrites `distance_m` when it is set, so the distance is what
	/// the runner actually covered before stopping, and legs do not un-absorb it.
	is_dnf?: boolean | null;
}

export interface RecentVolume {
	/// Mean weekly running distance (metres) across the chronic window.
	weeklyM: number;
	/// Running distance (metres) in the most recent 7-day window alone — the
	/// acute half of an ACWR pair whose chronic half is `weeklyM`. Same
	/// traversal and same rules, so the two can never be reduced from
	/// different run sets.
	acuteM: number;
	/// How many of the trailing windows carried at least one counted run.
	activeWeeks: number;
}

/// The runner's chronic weekly running volume from their recent runs.
///
/// Windows are rolling 7-day buckets counted back from `nowMs`, not calendar
/// weeks: a calendar week straddling today is only partly elapsed, so it
/// under-reports volume and would drag the average down for no reason. Cycling
/// is excluded (a bike ride is not running volume — the same rule `goals.ts`
/// and `fitness.ts` apply); everything else that carries distance counts,
/// including treadmill runs, which are real load even though they are barred
/// from anchoring fitness.
export function recentRunVolume(runs: RunForVolume[], nowMs: number): RecentVolume {
	let totalM = 0;
	let acuteM = 0;
	const active = new Set<number>();
	for (const r of runs) {
		if (r.activity_type === 'cycle') continue;
		const distance = r.distance_m;
		if (distance == null || !Number.isFinite(distance) || distance <= 0) continue;
		const started = Date.parse(r.started_at);
		if (!Number.isFinite(started)) continue;
		// A device whose clock runs ahead stamps a just-finished run in the
		// future; that is this week's load, not a row to drop.
		const age = Math.max(0, nowMs - started);
		const week = Math.floor(age / (7 * DAY_MS));
		if (week >= CHRONIC_WINDOW_WEEKS) continue;
		totalM += distance;
		if (week === 0) acuteM += distance;
		active.add(week);
	}
	return { weeklyM: totalM / CHRONIC_WINDOW_WEEKS, acuteM, activeWeeks: active.size };
}

export type PlanRampVerdict = 'unknown' | 'under' | 'matched' | 'elevated' | 'high';

export interface PlanRampCheck {
	verdict: PlanRampVerdict;
	/// Opening week ÷ chronic weekly average, and peak week ÷ the same. Both
	/// are 0 when the verdict is unknown, so a caller can never render a ratio
	/// the check refused to stand behind.
	openingRatio: number;
	peakRatio: number;
	openingWeekM: number;
	peakWeekM: number;
	recentWeeklyM: number;
	activeWeeks: number;
}

/// The plan's opening ask, in metres. Taken by lowest `week_index` rather
/// than by array position — the generator emits weeks in order but a pasted
/// or re-read plan carries no such guarantee.
export function openingWeekVolumeM(
	weeks: { week_index: number; target_volume_m: number }[],
): number {
	let opening: { index: number; volume: number } | null = null;
	for (const w of weeks) {
		if (!Number.isFinite(w.week_index) || !Number.isFinite(w.target_volume_m)) continue;
		if (opening == null || w.week_index < opening.index) {
			opening = { index: w.week_index, volume: w.target_volume_m };
		}
	}
	return opening?.volume ?? 0;
}

/// The plan's heaviest week, in metres — what it is ultimately asking the
/// runner to absorb.
export function peakWeekVolumeM(weeks: { target_volume_m: number }[]): number {
	let peak = 0;
	for (const w of weeks) {
		if (!Number.isFinite(w.target_volume_m)) continue;
		if (w.target_volume_m > peak) peak = w.target_volume_m;
	}
	return peak;
}

/// Grade the plan against the runner's chronic base.
///
/// The two directions are not the same question and are deliberately not
/// graded off the same week. **Too much** is about the first step, so it
/// grades the opening week — that is where a plan injures someone. **Too
/// little** is about the whole plan, so it grades the PEAK week: every
/// well-formed plan opens well below its own peak (the generator's week 0 is
/// 0.6x), so grading "under" off the opening week would tell a runner already
/// training at the plan's peak volume that the plan is too light for them,
/// which is exactly backwards.
///
/// Safety wins the tie: an opening week that is too big is reported even if
/// the peak is also modest.
///
/// Fail-closed in both directions: too little history, or a plan with no
/// volume to grade, returns `unknown` — the caller shows nothing rather than
/// guessing, and in particular never reports a reassuring "matched" it has no
/// evidence for.
export function planRampCheck(
	openingWeekM: number,
	peakWeekM: number,
	// Only the chronic half is consumed here: the plan's own opening week is
	// the acute term, so `acuteM` (what the runner has actually just done)
	// would be the wrong numerator for a question about a hypothetical plan.
	recent: Pick<RecentVolume, 'weeklyM' | 'activeWeeks'>,
): PlanRampCheck {
	const base = {
		openingWeekM,
		peakWeekM,
		recentWeeklyM: recent.weeklyM,
		activeWeeks: recent.activeWeeks,
	};
	const ungraded = { ...base, verdict: 'unknown' as const, openingRatio: 0, peakRatio: 0 };
	if (!Number.isFinite(openingWeekM) || openingWeekM <= 0) return ungraded;
	if (!Number.isFinite(peakWeekM) || peakWeekM <= 0) return ungraded;
	if (recent.activeWeeks < MIN_ACTIVE_WEEKS) return ungraded;
	const openingBand = injuryRiskBand(openingWeekM, recent.weeklyM);
	if (openingBand === 'insufficient') return ungraded;
	const graded = {
		...base,
		openingRatio: acwr(openingWeekM, recent.weeklyM),
		peakRatio: acwr(peakWeekM, recent.weeklyM),
	};
	if (openingBand === 'elevated' || openingBand === 'high') {
		return { ...graded, verdict: openingBand };
	}
	if (injuryRiskBand(peakWeekM, recent.weeklyM) === 'low') {
		return { ...graded, verdict: 'under' };
	}
	return { ...graded, verdict: 'matched' };
}

/// Whether the wizard should say anything at all.
///
/// Silence on `matched` is the point: a note that renders on every plan is
/// noise a runner learns to skip, and the check only earns its place when it
/// has something to report. `under` is an optimisation nudge rather than a
/// safety one, so it is withheld from a beginner walk-run plan — that runner
/// deliberately asked for the gentlest possible on-ramp and does not need to
/// be told it is gentle.
export function shouldSurfaceRampNote(
	check: PlanRampCheck,
	opts?: { beginnerWalkRun?: boolean },
): boolean {
	if (check.verdict === 'unknown' || check.verdict === 'matched') return false;
	if (check.verdict === 'under' && opts?.beginnerWalkRun === true) return false;
	return true;
}
