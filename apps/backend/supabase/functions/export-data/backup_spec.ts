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
	const uidEq = `user_id=eq.${userId}`;
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
			select:
				'id,provider,external_id,scope,last_sync_at,sync_cursor,created_at,updated_at',
		},
		{ entry: 'run_kudos.json', table: 'run_kudos', filter: uidEq, select: '*' },
		{
			entry: 'run_comments.json',
			table: 'run_comments',
			filter: `author_id=eq.${userId}`,
			select: '*',
		},
		{
			entry: 'run_photos.json',
			table: 'run_photos',
			filter: `owner_id=eq.${userId}`,
			select: '*',
		},
		{ entry: 'segment_efforts.json', table: 'segment_efforts', filter: uidEq, select: '*' },
		{ entry: 'gear.json', table: 'gear', filter: `owner_id=eq.${userId}`, select: '*' },
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
			filter: `follower_id=eq.${userId}`,
			select: '*',
		},
		{
			entry: 'followers.json',
			table: 'user_follows',
			filter: `followee_id=eq.${userId}`,
			select: '*',
		},
		{ entry: 'event_attendees.json', table: 'event_attendees', filter: uidEq, select: '*' },
		{ entry: 'club_members.json', table: 'club_members', filter: uidEq, select: '*' },
		{ entry: 'saved_routes.json', table: 'saved_routes', filter: uidEq, select: '*' },
		{ entry: 'route_reviews.json', table: 'route_reviews', filter: uidEq, select: '*' },
		{ entry: 'race_pings.json', table: 'race_pings', filter: uidEq, select: '*' },
		{ entry: 'user_device_settings.json', table: 'user_device_settings', filter: uidEq, select: '*' },
		{ entry: 'user_coach_usage.json', table: 'user_coach_usage', filter: uidEq, select: '*' },
		{
			entry: 'reports.json',
			table: 'reports',
			filter: `reporter_id=eq.${userId}`,
			select: '*',
		},
		// reports_against_me — Art 15(1)(c) recipient disclosure with
		// reporter anonymised (competing rights under Art 15(4)).
		{
			entry: 'reports_against_me.json',
			table: 'reports',
			filter: `target_kind=eq.user&target_id=eq.${userId}`,
			select: 'id,target_kind,target_id,reason,status,notes,created_at,resolved_at',
		},
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
