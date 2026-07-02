import type { SetAdherenceStatus } from './gym_adherence';

// Web-only; not a parity pair — the Dart side drives GymWorkoutRunner directly. Weights canonical kg.
export interface EnteredSet {
	reps: number | null;
	weightKg: number | null;
	rpe: number | null;
	durationS: number | null;
}

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

// Weights canonical kg.
export interface GymStepResult {
	exercise_key: string;
	set_index: number;
	status: SetAdherenceStatus;
	target_reps_min: number | null;
	target_reps_max: number | null;
	target_weight_kg: number | null;
	target_duration_s: number | null;
	actual_reps: number | null;
	actual_weight_kg: number | null;
	actual_duration_s: number | null;
}
