import type { SetAdherenceStatus } from './gym_adherence';

// Web-only; not a parity pair — the Dart side drives GymWorkoutRunner directly. Weights canonical kg.
export interface EnteredSet {
	reps: number | null;
	weightKg: number | null;
	rpe: number | null;
	durationS: number | null;
	distanceM: number | null;
}

/// What the runner recorded for one expanded step. Lives here rather than in
/// GymSessionRunner.svelte because the draft snapshot shapes it too.
export type StepOutcome = { kind: 'logged'; entered: EnteredSet } | { kind: 'skipped' };

// P4 "next target" hint shown on the workout review (gym_programming.md). Weights
// canonical kg. Built by the page from nextPrescription + the routine's
// per-exercise progression scheme; the review only renders it.
export interface NextTargetHint {
	exerciseKey: string;
	exerciseName: string;
	suggestedWeightKg: number | null;
	suggestedRepsMin: number | null;
	suggestedRepsMax: number | null;
	/// Heaviest weighted set this exercise logged this session, for the +/- delta.
	currentTopKg: number | null;
	/// Reps at the heaviest logged set this session, for a rep-climb hint.
	currentTopReps: number | null;
	reason: 'increase_weight' | 'increase_reps' | 'hold' | 'establish_baseline' | 'deload';
}

// One persisted `gym_workouts.metadata.gym_step_results` row (metadata.md).
// Weights canonical kg.
export interface GymStepResult {
	exercise_key: string;
	/// Ordinal position in the expanded step list — the planned↔actual match
	/// identity (gym_adherence.refKey). Optional only because rows persisted
	/// before decisions §304 keyed on `set_index` and carry no `step_index`;
	/// jsonb history is immutable, so a reader has to cope with both.
	step_index?: number;
	set_index: number;
	status: SetAdherenceStatus;
	reps_delta: number | null;
	weight_delta_kg: number | null;
	target_reps_min: number | null;
	target_reps_max: number | null;
	target_weight_kg: number | null;
	target_duration_s: number | null;
	target_distance_m: number | null;
	actual_reps: number | null;
	actual_weight_kg: number | null;
	actual_duration_s: number | null;
	actual_distance_m: number | null;
}
