// Per-exercise progression over time (Phase 4 multi-modal, decisions §63;
// spec: docs/features/multi_modal.md § Gym). Drives the /gym/exercise drill-down
// linked from each /gym/records card.
//
// Records (exercise_records.ts) answer "what's my current best?". This answers
// the next question — "am I getting stronger?" — by collapsing every session
// that included one exercise into a chronological series: each session's top
// set, best estimated 1RM, total volume, and whether that session set a new
// e1RM PR at the time. The headline est.-1RM delta (latest vs first) is the
// "are you progressing" signal.
//
// Pure functions — no Svelte / Supabase. Reuses the gym_prs primitives
// (estimatedOneRepMax, normaliseExerciseName, computeExercisePrs) so the
// numbers and the display spelling stay consistent with the records + badge
// surfaces. Web-only for now (mobile has no equivalent surface yet — mirror
// tracked in docs/product/followups.md); no Dart twin, so don't create a dead
// one.

import {
	computeExercisePrs,
	estimatedOneRepMax,
	normaliseExerciseName,
	type GymSetLike,
} from './gym_prs';
import type { DatedGymSet } from './exercise_records';

export interface ExerciseSession {
	workoutId: string;
	/// started_at of the workout (ISO).
	startedAt: string;
	/// Heaviest single weighted set in this session, kg. Always non-null (a
	/// session only qualifies once it has at least one weighted set).
	topWeightKg: number;
	/// Reps at the heaviest set (for "100 kg × 5" display).
	topWeightReps: number | null;
	/// Best estimated 1RM in this session, kg. Null if no set had reps.
	bestEst1RmKg: number | null;
	/// Total working volume (Σ reps·weight over weighted sets), kg.
	volumeKg: number;
	/// Weighted sets of this exercise logged in the session.
	setCount: number;
	/// True when this session's best e1RM strictly beat every earlier session's
	/// — i.e. it set a new estimated-1RM PR at the time.
	isEst1RmPr: boolean;
}

export interface ExerciseProgress {
	/// Display spelling — inherited from the PR engine so it matches the
	/// records card the user clicked.
	exerciseName: string;
	/// Chronological (oldest first), one entry per qualifying session.
	sessions: ExerciseSession[];
	/// e1RM of the first session that had one (kg). Null if none ever did.
	firstEst1RmKg: number | null;
	/// e1RM of the most recent session that had one (kg).
	latestEst1RmKg: number | null;
	/// Best e1RM across all sessions (kg).
	bestEst1RmKg: number | null;
	/// latest − first, kg, rounded to 1 dp. Null unless at least two sessions
	/// carried an e1RM (no delta to report from a single data point).
	est1RmDeltaKg: number | null;
}

function round1(n: number): number {
	return Math.round(n * 10) / 10;
}

/// Build one exercise's progression from a flat, dated set list. Returns null
/// when the name resolves to no qualifying (weighted) session — the same
/// bodyweight-only exclusion the records + PR surfaces apply. Sessions are
/// sorted oldest-first; ties (same started_at) break by workout id so the
/// order is deterministic.
export function exerciseProgress(
	sets: DatedGymSet[],
	exerciseName: string,
): ExerciseProgress | null {
	const key = normaliseExerciseName(exerciseName);
	if (key === '') return null;

	interface Group {
		workoutId: string;
		startedAt: string;
		topWeightKg: number;
		topWeightReps: number | null;
		bestEst1RmKg: number | null;
		volumeKg: number;
		setCount: number;
	}
	const groups = new Map<string, Group>();
	for (const s of sets) {
		if (normaliseExerciseName(s.exercise_name ?? '') !== key) continue;
		const weight = numericOrNull(s.weight_kg);
		if (weight == null || weight <= 0) continue; // bodyweight set — no weighted record
		const reps = numericOrNull(s.reps);

		let g = groups.get(s.workout_id);
		if (!g) {
			g = {
				workoutId: s.workout_id,
				startedAt: s.started_at,
				topWeightKg: 0,
				topWeightReps: null,
				bestEst1RmKg: null,
				volumeKg: 0,
				setCount: 0,
			};
			groups.set(s.workout_id, g);
		}
		g.setCount += 1;
		// Heaviest set; ties broken by more reps (mirrors computeExercisePrs).
		if (weight > g.topWeightKg || (weight === g.topWeightKg && (reps ?? 0) > (g.topWeightReps ?? 0))) {
			g.topWeightKg = weight;
			g.topWeightReps = reps ?? null;
		}
		if (reps != null && reps > 0) {
			g.volumeKg += weight * reps;
			const e1rm = estimatedOneRepMax(weight, reps);
			if (g.bestEst1RmKg == null || e1rm > g.bestEst1RmKg) g.bestEst1RmKg = e1rm;
		}
	}

	if (groups.size === 0) return null;

	const ordered = [...groups.values()].sort((a, b) => {
		if (a.startedAt !== b.startedAt) return a.startedAt.localeCompare(b.startedAt);
		return a.workoutId.localeCompare(b.workoutId);
	});

	let runningBest = -Infinity;
	const sessions: ExerciseSession[] = ordered.map((g) => {
		const e1rm = g.bestEst1RmKg;
		const isPr = e1rm != null && e1rm > runningBest;
		if (e1rm != null && e1rm > runningBest) runningBest = e1rm;
		return {
			workoutId: g.workoutId,
			startedAt: g.startedAt,
			topWeightKg: g.topWeightKg,
			topWeightReps: g.topWeightReps,
			bestEst1RmKg: e1rm == null ? null : round1(e1rm),
			volumeKg: Math.round(g.volumeKg),
			setCount: g.setCount,
			isEst1RmPr: isPr,
		};
	});

	const withE1rm = sessions.filter((s) => s.bestEst1RmKg != null);
	const firstEst1RmKg = withE1rm.length > 0 ? withE1rm[0].bestEst1RmKg : null;
	const latestEst1RmKg = withE1rm.length > 0 ? withE1rm[withE1rm.length - 1].bestEst1RmKg : null;
	const bestEst1RmKg = withE1rm.reduce<number | null>(
		(best, s) => (best == null || (s.bestEst1RmKg as number) > best ? s.bestEst1RmKg : best),
		null,
	);
	const est1RmDeltaKg =
		withE1rm.length >= 2 ? round1((latestEst1RmKg as number) - (firstEst1RmKg as number)) : null;

	return {
		exerciseName: displayName(sets, key, exerciseName),
		sessions,
		firstEst1RmKg,
		latestEst1RmKg,
		bestEst1RmKg,
		est1RmDeltaKg,
	};
}

/// The most recent qualifying (weighted) session of an exercise strictly
/// before `beforeStartedAt` — the "last time" a workout's detail screen
/// compares against for a progressive-overload hint. Returns null when there
/// is no earlier session. Because sessions sharing the compared workout's
/// `started_at` are excluded by the strict `<`, passing that workout's own
/// started_at naturally drops its own session from the lookup.
export function previousExerciseSession(
	sets: DatedGymSet[],
	exerciseName: string,
	beforeStartedAt: string,
): ExerciseSession | null {
	const prog = exerciseProgress(sets, exerciseName);
	if (!prog) return null;
	let prev: ExerciseSession | null = null;
	for (const s of prog.sessions) {
		if (s.startedAt < beforeStartedAt) prev = s;
		else break; // sessions are chronological — nothing later qualifies
	}
	return prev;
}

/// Resolve the display spelling the same way the records + badge surfaces do —
/// via the PR engine (first set, in input order, that maps to the key) — so the
/// drill-down title matches the card the user clicked. Falls back to the
/// caller-supplied name if the PR engine has no entry (shouldn't happen once a
/// qualifying session exists).
function displayName(sets: GymSetLike[], key: string, fallback: string): string {
	return computeExercisePrs(sets).get(key)?.exerciseName ?? fallback;
}

function numericOrNull(v: unknown): number | null {
	if (typeof v === 'number' && Number.isFinite(v)) return v;
	if (typeof v === 'string') {
		const n = Number(v);
		return Number.isFinite(n) ? n : null;
	}
	return null;
}
