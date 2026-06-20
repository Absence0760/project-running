// Package schema is the worker's single registry of the Supabase
// vocabulary the Go code talks to over PostgREST + Storage REST:
// table names, Storage bucket names, the `runs.metadata` jsonb keys,
// and the `user_settings.prefs` keys.
//
// Before this package every `/rest/v1/<table>` path, every
// `/storage/v1/object/<bucket>/` path, and every `metadata["<key>"]`
// access spelled its table / bucket / key as a bare string literal,
// scattered across supabase.go, livehub/, dataexport/, and premium/.
// A typo ("run_photo" for "run_photos") would compile and only fail at
// runtime against a 404; a renamed table meant grepping for a string.
// Routing them through these constants makes the set of tables the
// worker touches enumerable (the data-export coverage guard in
// supabase package depends on it) and a rename a one-line edit.
//
// These names mirror the Postgres schema in
// apps/backend/supabase/migrations and the registries in
// docs/backend/{metadata,settings}.md. Keep them in lockstep — a
// constant here that drifts from the DB is the same latent 404 the
// bare literals were.
package schema

// Table is a PostgREST table name — the `<table>` in `/rest/v1/<table>`.
const (
	TableRuns                  = "runs"
	TableRunMatchedTracks      = "run_matched_tracks"
	TableRunPhotos             = "run_photos"
	TableRunGear               = "run_gear"
	TableGear                  = "gear"
	TableRoutes                = "routes"
	TableRouteReviews          = "route_reviews"
	TableRouteMarkers          = "route_markers"
	TableSavedRoutes           = "saved_routes"
	TableIntegrations          = "integrations"
	TableWebhookEvents         = "webhook_events"
	TableJobs                  = "jobs"
	TableUserProfiles          = "user_profiles"
	TableUserSettings          = "user_settings"
	TableUserDeviceSettings    = "user_device_settings"
	TableUserCoachUsage        = "user_coach_usage"
	TableUserFollows           = "user_follows"
	TableUserBlocks            = "user_blocks"
	TableNotifications         = "notifications"
	TableLifecycleEmailLog     = "lifecycle_email_log"
	TableCoachMessages         = "coach_messages"
	TableCoachAthletes         = "coach_athletes"
	TableTrainingPlans         = "training_plans"
	TableRunKudos              = "run_kudos"
	TableRunComments           = "run_comments"
	TableSegmentEfforts        = "segment_efforts"
	TableFitnessSnapshots      = "fitness_snapshots"
	TablePersonalRecords       = "personal_records"
	TableDeviceTokens          = "device_tokens"
	TableLiveRunPings          = "live_run_pings"
	TableRacePings             = "race_pings"
	TableEventAttendees        = "event_attendees"
	TableEventResults          = "event_results"
	TableEventResultClaims     = "event_result_claims"
	TableCheckpointCrossings   = "checkpoint_crossings"
	TableEventExceptions       = "event_exceptions"
	TableClubMembers           = "club_members"
	TableClubPosts             = "club_posts"
	TableReports               = "reports"
	TableDirectMessages        = "direct_messages"
	TableGymWorkouts           = "gym_workouts"
	TableGymRoutines           = "gym_routines"
	TableFoodLog               = "food_log"
	TableBodyMetrics           = "body_metrics"
	TableSafetyContacts        = "safety_contacts"
	TableSessionPlans          = "session_plans"
	TableRoutePhotos           = "route_photos"
	TableEventOrders           = "event_orders"
	TableEventPricing          = "event_pricing"
	TableAchievements          = "achievements"
	TableChallengeParticipants = "challenge_participants"
	TableChallengeBadges       = "challenge_badges"
	TablePublicRecaps          = "public_recaps"
	// TableEmailSuppressions is the hard-block list (bounce / complaint /
	// explicit unsubscribe) the weekly-digest builder + handler MUST consult
	// before any send. Migration 20270108_001. Fail-closed RLS — worker-only.
	TableEmailSuppressions = "email_suppressions"
	// TableInstructorPayoutAccounts holds the host's Stripe Connect payout-account
	// metadata (status flags + the acct_ reference — no secret keys). User-scoped
	// personal data under GDPR Art 15; exported by the DSAR spec.
	TableInstructorPayoutAccounts = "instructor_payout_accounts"
)

// Bucket is a Supabase Storage bucket name — the `<bucket>` in
// `/storage/v1/object/<bucket>/`. Distinct from the like-named tables
// (`run_photos` the table vs `run-photos` the bucket).
const (
	BucketRuns      = "runs"
	BucketRunPhotos = "run-photos"
)

// MetadataKey is a key inside the `runs.metadata` jsonb bag. The bag
// has no schema codegen, so docs/backend/metadata.md + this block are
// the only thing keeping cross-platform writers and readers in sync.
//
// activity_type and is_dnf used to live here; F3 (migration
// 20261207_001) promoted both to real `runs` columns, so they are now
// plain column-name strings in select lists and row maps, not bag keys.
const (
	MetaTitle              = "title"
	MetaAvgBPM             = "avg_bpm"
	MetaSteps              = "steps"
	MetaElevationM         = "elevation_m"
	MetaStravaID           = "strava_id"
	MetaStravaActivityType = "strava_activity_type"
	MetaImportedFrom       = "imported_from"
	MetaImportedAt         = "imported_at"
)

// PrefsKey is a key inside the `user_settings.prefs` jsonb bag — the
// per-user preferences registry documented in docs/backend/settings.md.
const (
	PrefsPrivacyZones = "privacy_zones"
	// PrefsEmailWeeklyDigest is the opt-IN consent for the weekly engagement
	// digest (default 'off', migration 20270108_001). Marketing/promotional
	// mail — NEVER folded into email_notifications (you can't infer marketing
	// consent from a transactional-email setting). Only the literal 'on'
	// opts a recipient in; anything else (absent, 'off', non-string) is a skip.
	PrefsEmailWeeklyDigest = "email_weekly_digest"
)
