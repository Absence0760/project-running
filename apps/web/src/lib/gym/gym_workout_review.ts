// Rebuilds the planned-vs-actual review of a logged gym session from the
// `gym_workouts.metadata` execution trio the guided runner persisted
// (`routine_id` / `gym_step_results` / `gym_adherence` — metadata.md).
//
// Pure — no Svelte / Supabase dependencies, so it runs under `npx tsx --test`.
// Web-only: the mobile detail screen renders its sets from `LocalGymStore`
// rather than re-deriving the review, so there is no Dart twin.
//
// This is a REPLAY, not a recomputation: `computeRoutineAdherence` already ran
// at session time and its verdict is what the row records. Re-grading here off
// the stored targets would let a later change to the scoring rules silently
// restate a finished session's result.

import type { RoutineAdherence, RoutineVerdict, SetAdherence } from './gym_adherence';
import type { GymStepResult } from './gym_session_types';

export interface GymWorkoutReview {
	adherence: RoutineAdherence;
	stepResults: GymStepResult[];
}

const VERDICTS: readonly string[] = ['completed', 'partial', 'abandoned'];

/// Null whenever the trio is absent or unrecognisable, so the caller self-hides
/// the panel rather than rendering a half-read row.
export function reviewFromMetadata(metadata: unknown): GymWorkoutReview | null {
	if (!metadata || typeof metadata !== 'object') return null;
	const verdict = (metadata as Record<string, unknown>)['gym_adherence'];
	const raw = (metadata as Record<string, unknown>)['gym_step_results'];
	if (typeof verdict !== 'string' || !VERDICTS.includes(verdict)) return null;
	if (!Array.isArray(raw) || raw.length === 0) return null;

	const stepResults = raw as GymStepResult[];
	const sets: SetAdherence[] = stepResults.map((s) => ({
		exerciseKey: s.exercise_key,
		// Pre-§304 rows carry no step_index because set_index WAS the match
		// identity they were written under — replaying them with it is the
		// key they actually used, not a guess.
		stepIndex: s.step_index ?? s.set_index,
		setIndex: s.set_index,
		status: s.status,
		repsDelta: s.reps_delta ?? null,
		weightDeltaKg: s.weight_delta_kg ?? null,
	}));

	const planned = stepResults.filter((s) => s.status !== 'extra');
	const plannedCount = planned.length;
	const completedCount = planned.filter((s) => s.status === 'hit').length;

	return {
		adherence: {
			sets,
			plannedCount,
			completedCount,
			adherencePct: plannedCount === 0 ? 0 : completedCount / plannedCount,
			verdict: verdict as RoutineVerdict,
		},
		stepResults,
	};
}

/// Stable `{#each}` key for one persisted step-result row.
///
/// `set_index` restarts per block, so one exercise programmed into two blocks
/// yields the same `(exercise_key, set_index, status)` triple twice — Svelte
/// throws `each_key_duplicate` and wedges the whole review. `step_index` is
/// the expanded-step ordinal that decisions §304 introduced precisely because
/// it is unique across blocks. Pre-§304 rows fall back to `set_index`, the
/// identity they were actually written under, matching `reviewFromMetadata`.
export function reviewRowKey(
	s: Pick<GymStepResult, 'exercise_key' | 'set_index' | 'step_index' | 'status'>,
): string {
	return `${s.exercise_key}:${s.step_index ?? s.set_index}:${s.status}`;
}
