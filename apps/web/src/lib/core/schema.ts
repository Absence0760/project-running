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

/// Postgres base tables reached via `supabase.from(...)`. The activity-core
/// surface (runs + the gym / nutrition / unified-timeline tables) was routed
/// first; the F11 rollout extends outward as call sites move. A name only
/// belongs here once EVERY bare `.from('<name>')` for it has been repointed —
/// `core/schema.test.ts` fails the build on a stray literal, so a half-done
/// table breaks CI.
///
/// VIEWS (`public_runs`, `public_routes`, `*_redacted`, `*_with_distance`)
/// stay bare on purpose: they are distinct DB objects unaffected by a base-
/// table rename, and routing them here would couple two unrelated names.
///
/// Still bare (call sites spill into route pages / components owned by other
/// surfaces, so converting them risks clobbering concurrent work — tracked as
/// the remaining F11 web tail): user_profiles, clubs, events, routes,
/// saved_routes, training_plans, plan_weeks, plan_workouts, coach_messages,
/// user_follows, user_settings, user_device_settings.
export const TABLES = {
	runs: 'runs',
	gym_workouts: 'gym_workouts',
	gym_sets: 'gym_sets',
	gym_routines: 'gym_routines',
	gym_routine_exercises: 'gym_routine_exercises',
	gym_routine_sets: 'gym_routine_sets',
	food_log: 'food_log',
	body_metrics: 'body_metrics',
	activities: 'activities',
	club_members: 'club_members',
	club_posts: 'club_posts',
	event_attendees: 'event_attendees',
	event_results: 'event_results',
	route_reviews: 'route_reviews',
	route_photos: 'route_photos',
	route_markers: 'route_markers',
	run_kudos: 'run_kudos',
	run_comments: 'run_comments',
	run_photos: 'run_photos',
	run_gear: 'run_gear',
	notifications: 'notifications',
	direct_messages: 'direct_messages',
	coach_athletes: 'coach_athletes',
	integrations: 'integrations',
	segments: 'segments',
	segment_efforts: 'segment_efforts',
	gear: 'gear',
	fitness_snapshots: 'fitness_snapshots',
	personal_records: 'personal_records',
	user_blocks: 'user_blocks',
	safety_contacts: 'safety_contacts',
} as const;

/// Supabase Storage buckets reached via `supabase.storage.from(...)`.
export const BUCKETS = {
	runs: 'runs',
	run_photos: 'run-photos',
	route_photos: 'route-photos',
} as const;

/// Keys on the schema-less `runs.metadata` jsonb bag that the web client
/// reads or writes. Codegen cannot see inside jsonb, so this is the only
/// compile-time coupling between the writer and reader sides. Every key here
/// is documented in docs/backend/metadata.md — keep the two in lockstep.
export const METADATA_KEYS = {
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
	plan_workout_id: 'plan_workout_id',
	workout_step_results: 'workout_step_results',
	workout_adherence: 'workout_adherence',
	steps: 'steps',
	age_grade: 'age_grade',
	elevation_m: 'elevation_m',
} as const;
