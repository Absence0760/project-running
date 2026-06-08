// Per-exercise personal-record roll-up (Phase 4 multi-modal, decisions §63;
// spec: docs/features/multi_modal.md § Gym). Drives the /gym/records surface.
//
// The PR engine (gym_prs.ts) already computes each exercise's bests, but only
// transiently — to decide whether a workout earned a badge. There was no place
// to answer "what's my best bench press, and when did I last hit it?". This
// helper joins gym_prs' per-exercise bests with each exercise's last-performed
// date + distinct-session count so a lifter can scan their current strength.
//
// Pure functions — no Svelte / Supabase. Reuses computeExercisePrs so the PR
// numbers shown here can never drift from the badge engine. Web-only for now
// (mobile has no equivalent surface yet — mirror tracked in
// docs/product/followups.md); no Dart twin, so don't create a dead one.

import {
	computeExercisePrs,
	normaliseExerciseName,
	type ExercisePr,
	type GymSetLike,
} from './gym_prs';

/// A logged set carrying the columns the records roll-up needs: the PR metrics
/// (via GymSetLike) plus the workout it belongs to and when that workout
/// happened. Matches the shape of `GymSetWithDate` from core/data.ts.
export interface DatedGymSet extends GymSetLike {
	workout_id: string;
	started_at: string;
}

export interface ExerciseRecord {
	/// Display spelling — inherited from the PR engine (first set, in input
	/// order, that maps to the normalised key) so it stays deterministic and
	/// consistent with the per-workout badges.
	exerciseName: string;
	/// Heaviest single-set weight, kg. Always non-null for a record (a record
	/// only exists once at least one weighted set has been logged).
	heaviestWeightKg: number;
	/// Reps performed at the heaviest weight, for "100 kg × 5" display.
	heaviestWeightReps: number | null;
	/// Best single-set volume (reps × weight_kg), kg. Null if no set had reps.
	bestVolumeKg: number | null;
	/// Best estimated one-rep-max (Epley), kg. Null if no set had reps.
	bestEst1RmKg: number | null;
	/// started_at of the most recent workout that included this exercise (ISO).
	lastPerformedAt: string;
	/// Distinct workouts that included this exercise.
	sessionCount: number;
}

/// Build the records table from a flat, dated set list. One row per exercise
/// that has at least one weighted set (bodyweight-only exercises are excluded,
/// exactly as they're excluded from the PR engine's weight/volume/e1rm
/// metrics). Sorted most-recently-performed first, ties broken alphabetically
/// by display name so the order is deterministic.
export function exerciseRecords(sets: DatedGymSet[]): ExerciseRecord[] {
	const prs = computeExercisePrs(sets);

	interface Agg {
		lastPerformedAt: string;
		workouts: Set<string>;
	}
	const agg = new Map<string, Agg>();
	for (const s of sets) {
		const key = normaliseExerciseName(s.exercise_name ?? '');
		if (key === '') continue;
		let a = agg.get(key);
		if (!a) {
			a = { lastPerformedAt: '', workouts: new Set<string>() };
			agg.set(key, a);
		}
		if (s.workout_id) a.workouts.add(s.workout_id);
		// ISO timestamps compare chronologically as strings.
		if (s.started_at && s.started_at > a.lastPerformedAt) a.lastPerformedAt = s.started_at;
	}

	const records: ExerciseRecord[] = [];
	for (const [key, pr] of prs) {
		if (pr.heaviestWeightKg == null) continue; // bodyweight-only — no weighted record
		const a = agg.get(key);
		records.push(toRecord(pr, a?.lastPerformedAt ?? '', a?.workouts.size ?? 0));
	}

	records.sort((x, y) => {
		if (x.lastPerformedAt !== y.lastPerformedAt) {
			return y.lastPerformedAt.localeCompare(x.lastPerformedAt);
		}
		return x.exerciseName.localeCompare(y.exerciseName);
	});
	return records;
}

function toRecord(pr: ExercisePr, lastPerformedAt: string, sessionCount: number): ExerciseRecord {
	return {
		exerciseName: pr.exerciseName,
		heaviestWeightKg: pr.heaviestWeightKg as number,
		heaviestWeightReps: pr.heaviestWeightReps,
		bestVolumeKg: pr.bestVolumeKg,
		bestEst1RmKg: pr.bestEst1RmKg,
		lastPerformedAt,
		sessionCount,
	};
}
