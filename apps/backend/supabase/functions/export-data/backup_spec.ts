// Pure data + small helpers for the export-data EF's `backup` format.
// Extracted so the table-spec list can be unit-tested without spinning
// up a Supabase stack or fetching a real download. The runtime fetch +
// zip pipeline lives in index.ts.

export interface BackupTableSpec {
	entry: string;
	table: string;
	filter: string;
	select: string;
	redact?: (row: Record<string, unknown>) => Record<string, unknown>;
}

/// Build the full table-spec list. Pure — only takes the caller's
/// user id. Mirrors the Go worker's `FetchExportPersonalDataTables`
/// shape so the EF rollback path is functionally equivalent. See
/// `apps/job_worker/internal/supabase.go` + audit/data-export-
/// completeness May 2026 High.
export function buildBackupSpecs(userId: string): BackupTableSpec[] {
	// index.ts interpolates `spec.filter` verbatim into the REST URL
	// (unlike `select`, which goes through encoding), so the value must
	// be encoded here. audit-findings 2026-05-30 Medium.
	const uid = encodeURIComponent(userId);
	const uidEq = `user_id=eq.${uid}`;
	return [
		{ entry: 'coach_messages.json', table: 'coach_messages', filter: uidEq, select: '*' },
		{ entry: 'notifications.json', table: 'notifications', filter: uidEq, select: '*' },
		{
			entry: 'training_plans.json',
			table: 'training_plans',
			filter: uidEq,
			select: '*,weeks:plan_weeks(*,workouts:plan_workouts(*))',
		},
		{
			entry: 'integrations.json',
			table: 'integrations',
			filter: uidEq,
			// access_token / refresh_token never ship — vault material.
			// `disconnected_at` + `disconnected_reason` added per
			// persona-hunt Round 3 finding Privacy #2 — migration
			// `20261004_001` introduced these columns; GDPR Art 15
			// requires the export to reflect them.
			select:
				'id,provider,external_id,scope,last_sync_at,sync_cursor,disconnected_at,disconnected_reason,created_at,updated_at',
		},
		{ entry: 'run_kudos.json', table: 'run_kudos', filter: uidEq, select: '*' },
		{
			entry: 'run_comments.json',
			table: 'run_comments',
			filter: `author_id=eq.${uid}`,
			select: '*',
		},
		{
			entry: 'run_photos.json',
			table: 'run_photos',
			filter: `owner_id=eq.${uid}`,
			select: '*',
		},
		{ entry: 'segment_efforts.json', table: 'segment_efforts', filter: uidEq, select: '*' },
		{ entry: 'gear.json', table: 'gear', filter: `owner_id=eq.${uid}`, select: '*' },
		{ entry: 'fitness_snapshots.json', table: 'fitness_snapshots', filter: uidEq, select: '*' },
		{ entry: 'personal_records.json', table: 'personal_records', filter: uidEq, select: '*' },
		{
			entry: 'device_tokens.json',
			table: 'device_tokens',
			filter: uidEq,
			select: '*',
			redact: (row) => ({ ...row, token: '<redacted>' }),
		},
		{ entry: 'live_run_pings.json', table: 'live_run_pings', filter: uidEq, select: '*' },
		{
			entry: 'following.json',
			table: 'user_follows',
			filter: `follower_id=eq.${uid}`,
			select: '*',
		},
		{
			entry: 'followers.json',
			table: 'user_follows',
			filter: `followee_id=eq.${uid}`,
			select: '*',
		},
		{ entry: 'event_attendees.json', table: 'event_attendees', filter: uidEq, select: '*' },
		{ entry: 'club_members.json', table: 'club_members', filter: uidEq, select: '*' },
		{ entry: 'saved_routes.json', table: 'saved_routes', filter: uidEq, select: '*' },
		{ entry: 'route_reviews.json', table: 'route_reviews', filter: uidEq, select: '*' },
		{ entry: 'race_pings.json', table: 'race_pings', filter: uidEq, select: '*' },
		// user_settings — the universal (per-user) prefs bag: privacy
		// zones, HR settings, date-of-birth, week-start, units, and
		// every other preference. The Go worker also surfaces this as
		// `profile.json`'s `settings_prefs` field, but the EF rollback
		// path has no profile.json, so without this spec entry the EF
		// export omitted the user's settings entirely — a persona
		// round-5 GDPR Art 20 gap. It's the subject's own data, so the
		// full prefs ship unredacted. persona round-5 privacy /
		// GDPR Art 20.
		{ entry: 'user_settings.json', table: 'user_settings', filter: uidEq, select: '*' },
		{ entry: 'user_device_settings.json', table: 'user_device_settings', filter: uidEq, select: '*' },
		{ entry: 'user_coach_usage.json', table: 'user_coach_usage', filter: uidEq, select: '*' },
		{
			entry: 'reports.json',
			table: 'reports',
			filter: `reporter_id=eq.${uid}`,
			select: '*',
		},
		// reports_against_me — Art 15(1)(c) recipient disclosure with
		// reporter anonymised (competing rights under Art 15(4)).
		{
			entry: 'reports_against_me.json',
			table: 'reports',
			filter: `target_kind=eq.user&target_id=eq.${uid}`,
			select: 'id,target_kind,target_id,reason,status,notes,created_at,resolved_at',
		},
		// direct_messages — private 1:1 conversations, both directions.
		// `body` is the subject's own correspondence and ships verbatim.
		// audit/data-export-completeness (2026-05-30) Critical.
		{
			entry: 'direct_messages_sent.json',
			table: 'direct_messages',
			filter: `sender_id=eq.${uid}`,
			select: '*',
		},
		{
			entry: 'direct_messages_received.json',
			table: 'direct_messages',
			filter: `recipient_id=eq.${uid}`,
			select: '*',
		},
		// coach_athletes — coaching relationships as coach + as athlete.
		// `invite_token` is a redeemable credential; the narrow select
		// omits it (same rationale as integrations' vault columns).
		// audit/data-export-completeness (2026-05-30) Critical.
		{
			entry: 'coaching_as_coach.json',
			table: 'coach_athletes',
			filter: `coach_id=eq.${uid}`,
			select: 'id,coach_id,athlete_id,status,note,created_at,accepted_at,ended_at',
		},
		{
			entry: 'coaching_as_athlete.json',
			table: 'coach_athletes',
			filter: `athlete_id=eq.${uid}`,
			select: 'id,coach_id,athlete_id,status,note,created_at,accepted_at,ended_at',
		},
		// event_results — own race finish records (time, rank, DNF/DNS,
		// age-grade). audit/data-export-completeness (2026-05-30) Critical.
		{ entry: 'event_results.json', table: 'event_results', filter: uidEq, select: '*' },
		// event_result_claims — the subject's own result claims (status +
		// who decided). audit-findings (2026-05-30) High.
		{
			entry: 'event_result_claims.json',
			table: 'event_result_claims',
			filter: `claimant_id=eq.${uid}`,
			select: '*',
		},
		// user_blocks — the subject's own block list. High.
		{
			entry: 'user_blocks.json',
			table: 'user_blocks',
			filter: `blocker_id=eq.${uid}`,
			select: '*',
		},
		// club_posts — club-feed posts the subject authored. High.
		{
			entry: 'club_posts.json',
			table: 'club_posts',
			filter: `author_id=eq.${uid}`,
			select: '*',
		},
		// event_exceptions — recurring-event instance cancellations the
		// subject made. High.
		{
			entry: 'event_exceptions.json',
			table: 'event_exceptions',
			filter: `cancelled_by=eq.${uid}`,
			select: '*',
		},
		// gym_workouts (+ sets via nested embed). Phase 4 multi-modal
		// strength log (migration 20261204_001). gym_sets has no user_id
		// of its own (it cascades from the parent workout), so the export
		// nests each workout's sets, mirroring the training_plans embed.
		// audit/data-export-completeness gym/nutrition gap.
		{
			entry: 'gym_workouts.json',
			table: 'gym_workouts',
			filter: uidEq,
			select: '*,sets:gym_sets(*)',
		},
		// gym_routines (+ exercises + their planned sets via nested embeds).
		// The gym-programming P1 reusable plan (migration 20270101_001).
		// Author-scoped; gym_routine_exercises / gym_routine_sets have no
		// user_id of their own (they cascade from the parent routine), so the
		// export nests them — mirroring the training_plans + gym_workouts
		// embeds. gym_programming.md § DSAR export.
		{
			entry: 'gym_routines.json',
			table: 'gym_routines',
			filter: `author_id=eq.${uid}`,
			select: '*,exercises:gym_routine_exercises(*,sets:gym_routine_sets(*))',
		},
		// food_log — Phase 4 nutrition diary (calories + macros per item,
		// migration 20261204_001). Owner-scoped Art 20 personal data.
		{ entry: 'food_log.json', table: 'food_log', filter: uidEq, select: '*' },
		// body_metrics — Phase 4 nutrition weight time-series (migration
		// 20261216_001). Special-category health data, owner-scoped, squarely
		// within Art 20. height_cm ships in the user_profiles export entry.
		{ entry: 'body_metrics.json', table: 'body_metrics', filter: uidEq, select: '*' },
		// instructor_payout_accounts — the host's Stripe Connect payout-account
		// metadata (club_events.md paid-registration rail). The subject's own
		// data under Art 15: their connected-account reference
		// (`stripe_connect_account_id`, an `acct_…` id — a reference, not a
		// secret key) + the status flags Stripe mirrors back. No Stripe secret
		// is stored on the row, so the select carries every column (`*`):
		// status flags + country + default_currency + onboarded_at are all the
		// subject's own data. Mirrors the Go worker's exportPersonalDataSpecs
		// entry (the live export path).
		{ entry: 'instructor_payout_accounts.json', table: 'instructor_payout_accounts', filter: uidEq, select: '*' },
		// safety_contacts — opt-in finish-alert relationships (migration
		// 20261218_001). The subject is on both legs: rows they own
		// (owner_id) and rows where they are the confirmed contact
		// (contact_user_id). `confirm_token` is a redeemable capability —
		// anyone holding it can confirm the contact via
		// confirm_safety_contact_by_token — so the narrow select omits it,
		// mirroring coach_athletes' invite_token exclusion.
		{
			entry: 'safety_contacts_owned.json',
			table: 'safety_contacts',
			filter: `owner_id=eq.${uid}`,
			select: 'id,owner_id,contact_user_id,contact_email,confirmed_at,created_at,updated_at',
		},
		{
			entry: 'safety_contacts_as_contact.json',
			table: 'safety_contacts',
			filter: `contact_user_id=eq.${uid}`,
			select: 'id,owner_id,contact_user_id,contact_email,confirmed_at,created_at,updated_at',
		},
		// session_plans (+ blocks + items via nested embeds). The yoga/pilates
		// session-planner P1 authored content (migration 20270103_001).
		// Author-scoped; session_plan_blocks / session_plan_items have no owner
		// column of their own (they cascade from the parent plan), so the export
		// nests them — mirroring the gym_routines + training_plans embeds. The
		// Go guard's user_id-keyed scan can't see author_id, so it is wired in
		// explicitly. Mirrors the Go worker's exportPersonalDataSpecs entry.
		{
			entry: 'session_plans.json',
			table: 'session_plans',
			filter: `author_id=eq.${uid}`,
			select: '*,blocks:session_plan_blocks(*),items:session_plan_items(*)',
		},
		// route_photos — the subject's own route-photo metadata (migration
		// 20270114_001). owner_id is the uploader. Image bytes live in Storage;
		// the metadata row is the subject's own Art 20 data. Keyed by owner_id.
		{
			entry: 'route_photos.json',
			table: 'route_photos',
			filter: `owner_id=eq.${uid}`,
			select: '*',
		},
		// event_orders — the subject's paid-registration ledger, both legs:
		// orders placed as buyer (buyer_user_id) and orders for their events as
		// host (host_user_id). The financial record of a transaction the subject
		// was party to is their own Art 15/20 data. The Stripe id columns are
		// references (not secret keys), so `*` leaks no credential.
		{
			entry: 'event_orders_as_buyer.json',
			table: 'event_orders',
			filter: `buyer_user_id=eq.${uid}`,
			select: '*',
		},
		{
			entry: 'event_orders_as_host.json',
			table: 'event_orders',
			filter: `host_user_id=eq.${uid}`,
			select: '*',
		},
		// event_pricing — the price sheets the subject set as host (migration
		// 20261229_001). event_pricing has no owner column; the host link is
		// event_id → events.host_user_id. The spec inner-joins the parent event
		// and filters on its host_user_id, so only the subject's own events'
		// pricing ships. The embedded events object projects only host_user_id
		// (the subject's own id), leaking no third-party event data.
		{
			entry: 'event_pricing_as_host.json',
			table: 'event_pricing',
			filter: `events.host_user_id=eq.${uid}`,
			select: '*,events!inner(host_user_id)',
		},
		// achievements — the subject's earned badges (PR / segment / streak /
		// distance / plan), tier, earned_at. Owner-scoped (user_id) Art 20 data.
		// Surfaced by the widened export-completeness guard (2026-06-20).
		{ entry: 'achievements.json', table: 'achievements', filter: uidEq, select: '*' },
		// challenge_participants — the subject's challenge enrolments.
		{ entry: 'challenge_participants.json', table: 'challenge_participants', filter: uidEq, select: '*' },
		// challenge_badges — the subject's durable challenge-completion records.
		{ entry: 'challenge_badges.json', table: 'challenge_badges', filter: uidEq, select: '*' },
		// public_recaps — the subject's published Year/Month-in-Running snapshots.
		{ entry: 'public_recaps.json', table: 'public_recaps', filter: uidEq, select: '*' },
	];
}

/// Aggregate raw `jobs.kind` strings into a count-by-kind summary —
/// the audit's preferred shape over the raw payload (which would
/// leak internal retry state).
export function summariseJobsByKind(
	rows: Array<{ kind: string }>,
): Array<{ kind: string; count: number }> {
	const counts: Record<string, number> = {};
	for (const r of rows) {
		counts[r.kind] = (counts[r.kind] ?? 0) + 1;
	}
	return Object.entries(counts).map(([kind, count]) => ({ kind, count }));
}
