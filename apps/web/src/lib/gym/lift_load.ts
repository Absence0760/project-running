// Bridges the gym data layer (`GymSetWithDate` rows) into the input the
// training-load model expects (`LiftForLoad`: one entry per session with
// its sets). Pure + unit-tested so the dashboard can feed real lifts into
// computeTrainingLoadSeries and have CTL/ATL/TSB reflect them, while the
// run-only curve stays recoverable (the model tags lift stress separately;
// see training_load.ts § "Separable provenance").

import type { LiftForLoad } from '$lib/training/training_load';

/// One flat set row joined to its workout start time — the shape
/// `fetchGymSetHistory` returns. Re-declared here (rather than importing
/// the data-layer type) so this stays a pure module with no Supabase
/// dependency and is `tsx --test`-runnable.
export interface SetWithWorkoutDate {
	workout_id: string;
	started_at: string;
	reps: number | null;
	weight_kg: number | null;
	rpe: number | null;
}

/// Group flat set-history rows into per-session `LiftForLoad` entries.
/// Sessions with no started_at (an RLS-stripped join) are dropped — a
/// lift with no date can't land on a calendar day, so it can't carry
/// stress. Order is not significant; computeTrainingLoadSeries buckets
/// by local day.
export function liftsFromSetHistory(
	history: SetWithWorkoutDate[],
): LiftForLoad[] {
	const byWorkout = new Map<string, LiftForLoad>();
	for (const s of history) {
		if (!s.workout_id || !s.started_at) continue;
		let lift = byWorkout.get(s.workout_id);
		if (!lift) {
			lift = { started_at: s.started_at, sets: [] };
			byWorkout.set(s.workout_id, lift);
		}
		lift.sets.push({ reps: s.reps, weight_kg: s.weight_kg, rpe: s.rpe });
	}
	return [...byWorkout.values()];
}
