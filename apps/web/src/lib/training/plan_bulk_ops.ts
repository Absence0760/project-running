/**
 * Pure helpers behind the plan-editor bulk operations on /plans/[id]:
 * shifting the whole plan forward/back by N days, and turning a week
 * into a recovery (step-back) week. The page does the Supabase
 * orchestration (one update per affected row); these pure functions
 * compute the new field values so they can be unit-tested in isolation.
 */

/// A recovery week drops volume + intensity to ~60% of the planned load.
export const RECOVERY_SCALE = 0.6;

/// Shift an ISO `YYYY-MM-DD` date by `days` (may be negative). UTC math
/// so it never drifts across a local-midnight / DST boundary.
export function shiftIsoDate(iso: string, days: number): string {
	const [y, m, d] = iso.split('-').map((n) => parseInt(n, 10));
	const t = Date.UTC(y, m - 1, d) + days * 86_400_000;
	const out = new Date(t);
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${out.getUTCFullYear()}-${pad(out.getUTCMonth() + 1)}-${pad(out.getUTCDate())}`;
}

/// Kinds that carry quality intensity — converted to `recovery` when a
/// week is marked as a down week. Easy / long / walk-run keep their kind
/// (just scaled); rest + race are left untouched entirely.
const QUALITY_KINDS = new Set(['tempo', 'interval', 'marathon_pace']);

export interface RecoveryWorkoutPatch {
	kind?: string;
	target_distance_m?: number | null;
	target_pace_sec_per_km?: number | null;
}

/// Compute the patch to apply to one workout when its week is marked as
/// recovery. Returns null for workouts that shouldn't change (`rest`,
/// `race`). Quality kinds become `recovery` with their strict pace
/// target cleared; distances scale to RECOVERY_SCALE.
export function recoveryWorkoutPatch(w: {
	kind: string;
	target_distance_m: number | null;
}): RecoveryWorkoutPatch | null {
	if (w.kind === 'rest' || w.kind === 'race') return null;
	const patch: RecoveryWorkoutPatch = {};
	if (QUALITY_KINDS.has(w.kind)) {
		patch.kind = 'recovery';
		patch.target_pace_sec_per_km = null; // recovery = comfortable, no strict target
	}
	if (w.target_distance_m != null) {
		patch.target_distance_m = Math.round(w.target_distance_m * RECOVERY_SCALE);
	}
	// Nothing to change (e.g. an easy run with no distance set) → skip.
	return Object.keys(patch).length > 0 ? patch : null;
}

/// New target volume for a week marked as recovery.
export function recoveryWeekVolume(targetVolumeM: number | null): number | null {
	if (targetVolumeM == null) return null;
	return Math.round(targetVolumeM * RECOVERY_SCALE);
}
