// Gym routine plan ↔ log shaping (gym_programming.md slice P1).
//
// Two pure transforms with no Svelte / Supabase dependencies (runs under
// `npx tsx --test`). The Dart twin is apps/mobile_android/lib/gym_routine.dart
// (parity pair — keep algorithm, edge cases, outputs, and test counts in
// lockstep).
//
//   routineFromWorkout — promote a logged session's grouped exercises into a
//     routine draft (title + ordered exercise blocks, each with planned sets
//     carrying the logged reps/weight as targets). The "Save as routine" path.
//   prefillFromRoutine — expand a saved routine's planned targets into editable
//     in-memory exercise blocks for the GymEditor. The "Repeat last" / "Start
//     routine" prefill path (prefill-only — no execution loop in P1).
//
// Binding plan ↔ log is by `normaliseExerciseName` + order, never by FK.
// `normaliseExerciseName` is imported from gym_prs so the normalisation that
// stamps `exercise_key` can never drift from the PR grouping that reads it. P1
// builds NO expandRoutineSteps / superset handling / progression prescriber —
// those are P2-P4.

import { normaliseExerciseName } from './gym_prs';
import type { GymSetType } from '../types';

/// A logged gym set, as it arrives from `gym_sets` (free-text exercise name,
/// nullable reps/weight). The minimal shape the promotion reads.
export interface LoggedSet {
	exercise_name: string;
	reps: number | null;
	weight_kg: number | null;
	rpe?: number | null;
}

/// One planned set within a routine draft exercise. Targets only — a single
/// rep value lives in `targetRepsMin` with `targetRepsMax` null (the canonical
/// single-target rep shape; a range fills both).
export interface RoutineDraftSet {
	setIndex: number;
	setType: 'working';
	targetRepsMin: number | null;
	targetRepsMax: number | null;
	targetWeightKg: number | null;
	targetRpe: number | null;
}

/// One planned exercise within a routine draft.
export interface RoutineDraftExercise {
	exerciseName: string;
	exerciseKey: string;
	position: number;
	sets: RoutineDraftSet[];
}

/// The in-memory routine shape "Save as routine" hands to the create call.
/// `exerciseCount` is the client-stamped denormalised count (gym_routines
/// non-authoritative cache — derived_state.md).
export interface RoutineDraft {
	title: string;
	exerciseCount: number;
	exercises: RoutineDraftExercise[];
}

/// A persisted routine, flattened for prefill: its exercises (ordered by
/// `position`) each with their planned sets (ordered by `setIndex`).
export interface PlannedRoutine {
	title: string;
	exercises: PlannedExercise[];
}

export interface PlannedExercise {
	exerciseName: string;
	position: number;
	sets: PlannedSet[];
	supersetGroup?: number | null;
	supersetOrder?: number | null;
}

export interface PlannedSet {
	setIndex: number;
	targetRepsMin: number | null;
	targetRepsMax: number | null;
	targetWeightKg: number | null;
	targetRpe: number | null;
	setType?: GymSetType | null;
	restS?: number | null;
	targetDurationS?: number | null;
}

/// One flattened per-set step of an expanded routine (gym_programming.md P2).
/// Targets only — weight stays canonical kg. A superset member carries its
/// group + intra-group order so the runner can interleave rounds.
export interface RoutineStep {
	exerciseName: string;
	exerciseKey: string;
	position: number;
	supersetGroup: number | null;
	supersetOrder: number | null;
	setIndex: number;
	setType: GymSetType;
	targetRepsMin: number | null;
	targetRepsMax: number | null;
	targetWeightKg: number | null;
	targetRpe: number | null;
	restS: number | null;
	targetDurationS: number | null;
}

export interface ExpandedRoutine {
	steps: RoutineStep[];
	totalSets: number;
	supersetGroups: number;
}

/// An editable set row for the GymEditor (strings, display-unit-agnostic —
/// the caller formats `weightKg` through the weight pref). Mirrors the
/// editor's `{ reps, weight, rpe }` triad but keeps weight as canonical kg so
/// the pure layer stays unit-free.
export interface PrefillSet {
	reps: string;
	weightKg: number | null;
	rpe: string;
}

/// An editable exercise block for the GymEditor.
export interface PrefillExercise {
	name: string;
	sets: PrefillSet[];
}

function numericOrNull(v: unknown): number | null {
	if (typeof v === 'number' && Number.isFinite(v)) return v;
	if (typeof v === 'string') {
		const n = Number(v);
		return Number.isFinite(n) ? n : null;
	}
	return null;
}

/// Promote a logged session's sets into a routine draft. Sets are grouped into
/// exercise blocks by *consecutive* equal `exercise_name` (the same grouping
/// the GymEditor + the flat log use — a re-entered exercise later in the
/// session is its own block, matching how it was logged). Each logged set
/// becomes a planned `working` set with its reps/weight/RPE as the target.
/// Blank-named sets are dropped. `exercise_key` is stamped via
/// `normaliseExerciseName` at promotion time (frozen identity for plan↔log
/// binding). The title defaults to the workout's title, else "Routine".
export function routineFromWorkout(
	workoutTitle: string | null | undefined,
	sets: LoggedSet[],
	fallbackTitle = 'Routine',
): RoutineDraft {
	const exercises: RoutineDraftExercise[] = [];
	for (const s of sets) {
		const name = (s.exercise_name ?? '').trim();
		if (name === '') continue;
		const reps = numericOrNull(s.reps);
		const weight = numericOrNull(s.weight_kg);
		const rpe = numericOrNull(s.rpe);

		const last = exercises[exercises.length - 1];
		const block =
			last && last.exerciseName === name
				? last
				: (() => {
						const created: RoutineDraftExercise = {
							exerciseName: name,
							exerciseKey: normaliseExerciseName(name),
							position: exercises.length,
							sets: [],
						};
						exercises.push(created);
						return created;
					})();

		block.sets.push({
			setIndex: block.sets.length,
			setType: 'working',
			targetRepsMin: reps,
			targetRepsMax: null,
			targetWeightKg: weight,
			targetRpe: rpe,
		});
	}

	const title = (workoutTitle ?? '').trim() || fallbackTitle;
	return { title, exerciseCount: exercises.length, exercises };
}

/// Expand a saved routine's planned targets into editable GymEditor blocks.
/// Exercises are ordered by `position`, sets by `setIndex` (defensively sorted
/// — the caller may pass them in any order). Each planned set's target reps
/// (the min of the range, or the single value) prefills the reps field; the
/// target weight prefills the weight field; the target RPE prefills RPE. An
/// empty routine yields a single empty block so the editor always has a row.
export function prefillFromRoutine(routine: PlannedRoutine): PrefillExercise[] {
	const ordered = [...routine.exercises].sort((a, b) => a.position - b.position);
	const blocks: PrefillExercise[] = [];
	for (const ex of ordered) {
		const sets = [...ex.sets].sort((a, b) => a.setIndex - b.setIndex);
		blocks.push({
			name: ex.exerciseName,
			sets:
				sets.length === 0
					? [{ reps: '', weightKg: null, rpe: '' }]
					: sets.map((s) => ({
							reps: s.targetRepsMin == null ? '' : String(s.targetRepsMin),
							weightKg: s.targetWeightKg,
							rpe: s.targetRpe == null ? '' : String(s.targetRpe),
						})),
		});
	}
	if (blocks.length === 0) {
		return [{ name: '', sets: [{ reps: '', weightKg: null, rpe: '' }] }];
	}
	return blocks;
}

function stepFor(ex: PlannedExercise, s: PlannedSet): RoutineStep {
	return {
		exerciseName: ex.exerciseName,
		exerciseKey: normaliseExerciseName(ex.exerciseName),
		position: ex.position,
		supersetGroup: ex.supersetGroup ?? null,
		supersetOrder: ex.supersetOrder ?? null,
		setIndex: s.setIndex,
		setType: s.setType ?? 'working',
		targetRepsMin: s.targetRepsMin,
		targetRepsMax: s.targetRepsMax,
		targetWeightKg: s.targetWeightKg,
		targetRpe: s.targetRpe,
		restS: s.restS ?? null,
		targetDurationS: s.targetDurationS ?? null,
	};
}

/// Flatten a routine's exercises (ordered by `position`) × their sets (ordered
/// by `setIndex`) into ordered per-set steps (gym_programming.md P2 — the
/// expand-once helper the GymWorkoutRunner consumes). A standalone exercise
/// (`supersetGroup == null`) emits its sets sequentially. Members of a superset
/// group interleave round-robin by `setIndex` (A1, B1, A2, B2, …), the members
/// ordered by `supersetOrder`; the group's block is emitted at the position
/// where the group first appears in `position` order. `exerciseKey` is stamped
/// via `normaliseExerciseName` (frozen plan↔log identity).
export function expandRoutineSteps(routine: PlannedRoutine): ExpandedRoutine {
	const ordered = [...routine.exercises].sort((a, b) => a.position - b.position);
	const steps: RoutineStep[] = [];
	const seenGroups = new Set<number>();

	for (const ex of ordered) {
		const group = ex.supersetGroup ?? null;
		if (group == null) {
			const sets = [...ex.sets].sort((a, b) => a.setIndex - b.setIndex);
			for (const s of sets) steps.push(stepFor(ex, s));
			continue;
		}
		if (seenGroups.has(group)) continue;
		seenGroups.add(group);

		const members = ordered
			.filter((e) => (e.supersetGroup ?? null) === group)
			.sort((a, b) => (a.supersetOrder ?? 0) - (b.supersetOrder ?? 0));
		const rounds = members.reduce((max, m) => Math.max(max, m.sets.length), 0);
		for (let round = 0; round < rounds; round++) {
			for (const m of members) {
				const sets = [...m.sets].sort((a, b) => a.setIndex - b.setIndex);
				const s = sets[round];
				if (s) steps.push(stepFor(m, s));
			}
		}
	}

	return {
		steps,
		totalSets: steps.length,
		supersetGroups: seenGroups.size,
	};
}
