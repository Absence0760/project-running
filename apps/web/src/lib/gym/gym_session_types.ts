import type { SetAdherenceStatus } from './gym_adherence';

// Web-only; not a parity pair — the Dart side drives GymWorkoutRunner directly. Weights canonical kg.
export interface EnteredSet {
	reps: number | null;
	weightKg: number | null;
	rpe: number | null;
	durationS: number | null;
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
