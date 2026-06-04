// Central registry for the database name-classes the web client touches:
// table / view names, Storage bucket ids, and `runs.metadata` jsonb keys.
// The same bare strings used to be scattered across data access, importers,
// the coach context builder and route pages; a typo on a read or a write
// failed silently and a future rename was a cross-file grep-and-pray.
//
// Routing every call site through these constants makes a rename a one-line
// edit, and lets the architecture guard in `schema.test.ts` fail the build
// on a stray bare `.from('runs')`. See reviews/audit-db-optimization.md § F11.
// The metadata-key registry of record (shapes, writers, readers, public
// safety) stays docs/backend/metadata.md — this is only the name list.

/// Postgres tables + views reached via `supabase.from(...)`. The activity-core
/// surface (runs + the gym / nutrition / unified-timeline tables) is routed
/// today; the F11 rollout extends outward from here as other call sites move.
export const TABLES = {
	runs: 'runs',
	gym_workouts: 'gym_workouts',
	gym_sets: 'gym_sets',
	food_log: 'food_log',
	activities: 'activities',
} as const;

/// Supabase Storage buckets reached via `supabase.storage.from(...)`.
export const BUCKETS = {
	runs: 'runs',
} as const;

/// Keys on the schema-less `runs.metadata` jsonb bag that the web client
/// reads or writes. Codegen cannot see inside jsonb, so this is the only
/// compile-time coupling between the writer and reader sides. Every key here
/// is documented in docs/backend/metadata.md — keep the two in lockstep.
export const METADATA_KEYS = {
	activity_type: 'activity_type',
	avg_bpm: 'avg_bpm',
	max_bpm: 'max_bpm',
	cadence_spm: 'cadence_spm',
	laps: 'laps',
	indoor: 'indoor',
	sub_sport: 'sub_sport',
	running_dynamics: 'running_dynamics',
	garmin_id: 'garmin_id',
	imported_from: 'imported_from',
	imported_at: 'imported_at',
	source_file: 'source_file',
	strava_id: 'strava_id',
	strava_activity_type: 'strava_activity_type',
	manual_entry: 'manual_entry',
	notes: 'notes',
	title: 'title',
	is_dnf: 'is_dnf',
	plan_workout_id: 'plan_workout_id',
	workout_step_results: 'workout_step_results',
	workout_adherence: 'workout_adherence',
	steps: 'steps',
	age_grade: 'age_grade',
	elevation_m: 'elevation_m',
} as const;
