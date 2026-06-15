import { gzipSync } from 'zlib';

import { getAdminClient } from './local-supabase';

interface TrackPoint {
	lat: number;
	lng: number;
	ele?: number | null;
	t?: string | null;
	/// Per-point heart rate in BPM (matches `src/lib/types.ts`
	/// TrackPoint.bpm). Lets HR-zone e2e tests plant a track that
	/// the run-detail page reads to compute the zone breakdown.
	bpm?: number;
}

/**
 * Service-role helpers for actions only mobile / watch can do on the
 * canonical web stack. Web is the canonical feature surface (decisions
 * §24) but recording, live broadcasting, and a few HealthKit / Garmin
 * sync paths only exist on device — saga tests need them as setup
 * steps without spinning up a real recorder.
 *
 * Each helper bypasses RLS via the service-role client. Keep them
 * narrow — anything a real user could do via the web UI should go
 * through the UI in the saga, not here.
 *
 * Today: just `insertRun()`. Future helpers as sagas demand them:
 *   - `startLiveBroadcast(runId, points)` — insert live_run_pings
 *     so /live/[id] receives data without a real broadcaster.
 *   - `insertEvent(clubId, ...)` — bypass the create-event modal
 *     for sagas where the event isn't the test subject.
 *   - `insertClubMember(clubId, userId, role)` — pre-populate
 *     members for cluster-of-N tests where joining via UI per
 *     user is too slow.
 */

export async function insertRun(opts: {
	user_id: string;
	started_at?: string;
	duration_s: number;
	distance_m: number;
	source?: 'app' | 'strava' | 'parkrun' | 'healthkit';
	is_public?: boolean;
	/** Real `runs.activity_type` column (20261207_001). Defaults to 'run'. */
	activity_type?: 'run' | 'walk' | 'hike' | 'cycle' | 'stroller';
	is_dnf?: boolean;
	metadata?: Record<string, unknown>;
	/** Optional linked route (runs.route_id). The public_runs view only
	 *  surfaces it back to a viewer when the route is itself public. */
	route_id?: string;
	/** Optional GPS track. When supplied, gzipped JSON is uploaded to
	 *  the `runs` Storage bucket at `{user_id}/{run_id}.json.gz` and
	 *  the row's `track_url` column is set to that path. Mirrors what
	 *  the recorder's sync flow does. */
	track?: TrackPoint[];
	/** Optional indoor/treadmill HR series. Gzipped JSON is uploaded to
	 *  `{user_id}/{run_id}.hr.json.gz` and `hr_series_url` is set — the
	 *  trackless-run shape the HR-zone chart falls back to (decisions §116). */
	hrSeries?: { bpm: number; ts?: string }[];
}): Promise<string> {
	const admin = getAdminClient();
	const { data, error } = await admin
		.from('runs')
		.insert({
			user_id: opts.user_id,
			started_at: opts.started_at ?? new Date().toISOString(),
			duration_s: opts.duration_s,
			distance_m: opts.distance_m,
			source: opts.source ?? 'app',
			is_public: opts.is_public ?? false,
			activity_type: opts.activity_type ?? 'run',
			is_dnf: opts.is_dnf ?? false,
			route_id: opts.route_id ?? null,
			metadata: opts.metadata ?? {}
		})
		.select('id')
		.single();
	if (error || !data) {
		throw new Error(`simulate.insertRun failed: ${error?.message ?? 'no row returned'}`);
	}
	const runId = data.id as string;

	if (opts.track && opts.track.length > 0) {
		const path = `${opts.user_id}/${runId}.json.gz`;
		const json = JSON.stringify(opts.track);
		const gzipped = gzipSync(Buffer.from(json, 'utf-8'));
		const { error: upErr } = await admin.storage
			.from('runs')
			.upload(path, gzipped, {
				contentType: 'application/octet-stream',
				upsert: true
			});
		if (upErr) {
			throw new Error(`simulate.insertRun track upload failed: ${upErr.message}`);
		}
		const { error: updErr } = await admin
			.from('runs')
			.update({ track_url: path })
			.eq('id', runId);
		if (updErr) {
			throw new Error(`simulate.insertRun track_url set failed: ${updErr.message}`);
		}
	}

	if (opts.hrSeries && opts.hrSeries.length > 0) {
		const path = `${opts.user_id}/${runId}.hr.json.gz`;
		const gzipped = gzipSync(Buffer.from(JSON.stringify(opts.hrSeries), 'utf-8'));
		const { error: upErr } = await admin.storage
			.from('runs')
			.upload(path, gzipped, { contentType: 'application/octet-stream', upsert: true });
		if (upErr) {
			throw new Error(`simulate.insertRun hr-series upload failed: ${upErr.message}`);
		}
		const { error: updErr } = await admin
			.from('runs')
			.update({ hr_series_url: path })
			.eq('id', runId);
		if (updErr) {
			throw new Error(`simulate.insertRun hr_series_url set failed: ${updErr.message}`);
		}
	}

	return runId;
}

export async function deleteRun(runId: string): Promise<void> {
	const admin = getAdminClient();
	// Try to remove the gzipped track from Storage too, if any. List
	// the user folder by reading the row first.
	const { data: row } = await admin
		.from('runs')
		.select('track_url, hr_series_url')
		.eq('id', runId)
		.maybeSingle();
	const paths = [row?.track_url, row?.hr_series_url].filter(
		(p): p is string => !!p,
	);
	if (paths.length > 0) {
		await admin.storage.from('runs').remove(paths);
	}
	const { error } = await admin.from('runs').delete().eq('id', runId);
	if (error) {
		throw new Error(`simulate.deleteRun failed: ${error.message}`);
	}
}

/// Service-role upsert for `user_settings.prefs.<key>`. Used by tests
/// that need to plant a setting (e.g. privacy zones) without driving
/// through the canonical UI — appropriate when the UI requires
/// interactions that are hard to drive in Playwright (the privacy-zone
/// picker, for instance, takes a click on a MapLibre canvas).
export async function setUserSetting(
	userId: string,
	key: string,
	value: unknown
): Promise<void> {
	const admin = getAdminClient();
	const { data: existing } = await admin
		.from('user_settings')
		.select('prefs')
		.eq('user_id', userId)
		.maybeSingle();
	const prefs = (existing?.prefs as Record<string, unknown> | null) ?? {};
	prefs[key] = value;
	if (existing) {
		const { error } = await admin
			.from('user_settings')
			.update({ prefs, updated_at: new Date().toISOString() })
			.eq('user_id', userId);
		if (error) {
			throw new Error(`simulate.setUserSetting update failed: ${error.message}`);
		}
	} else {
		const { error } = await admin
			.from('user_settings')
			.insert({ user_id: userId, prefs });
		if (error) {
			throw new Error(`simulate.setUserSetting insert failed: ${error.message}`);
		}
	}
}

export async function deleteRoute(routeId: string): Promise<void> {
	const { error } = await getAdminClient().from('routes').delete().eq('id', routeId);
	if (error) {
		throw new Error(`simulate.deleteRoute failed: ${error.message}`);
	}
}

export async function insertRoute(opts: {
	user_id: string;
	name: string;
	waypoints: Array<{ lat: number; lng: number; elevation_m?: number | null }>;
	distance_m: number;
	is_public?: boolean;
	elevation_m?: number | null;
}): Promise<string> {
	// The routes_geom_trigger derives `geom` from `waypoints` on insert,
	// which the route_markers_position_trigger needs to compute each
	// marker's position_m along the line — so a route with >=2 waypoints
	// inserted here yields markers with real position_m, the input the
	// roadbook (and the spectator cut-off card) reads.
	const { data, error } = await getAdminClient()
		.from('routes')
		.insert({
			user_id: opts.user_id,
			name: opts.name,
			waypoints: opts.waypoints,
			distance_m: opts.distance_m,
			elevation_m: opts.elevation_m ?? null,
			is_public: opts.is_public ?? false
		})
		.select('id')
		.single();
	if (error || !data) {
		throw new Error(`simulate.insertRoute failed: ${error?.message ?? 'no row'}`);
	}
	return data.id as string;
}

export async function insertRouteMarker(opts: {
	route_id: string;
	user_id: string;
	kind: 'aid_station' | 'cutoff' | 'crew_access' | 'hazard' | 'note' | 'climb' | 'custom';
	label: string;
	lat: number;
	lng: number;
	meta?: Record<string, unknown>;
}): Promise<string> {
	const { data, error } = await getAdminClient()
		.from('route_markers')
		.insert({
			route_id: opts.route_id,
			user_id: opts.user_id,
			kind: opts.kind,
			label: opts.label,
			lat: opts.lat,
			lng: opts.lng,
			meta: opts.meta ?? {}
		})
		.select('id')
		.single();
	if (error || !data) {
		throw new Error(`simulate.insertRouteMarker failed: ${error?.message ?? 'no row'}`);
	}
	return data.id as string;
}

/// Clear the seed's now()-relative "Morning easy 8K" run (and any other
/// trailing-8-day runs) for `userId`, returning a callback that restores
/// them verbatim. Why: a freshly planted current-week goal would
/// otherwise read 32%, not the 0% baseline these tests assert — and the
/// /nutrition + dashboard-readiness specs still need the seed run, so it
/// must be put back (the 8-day window covers Monday- and Sunday-start
/// weeks per goals.ts periodStart).
export async function withCleanCurrentWeek(userId: string): Promise<() => Promise<void>> {
	const admin = getAdminClient();
	const since = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000).toISOString();
	const { data, error } = await admin
		.from('runs')
		.select('*')
		.eq('user_id', userId)
		.gte('started_at', since);
	if (error) {
		throw new Error(`simulate.withCleanCurrentWeek snapshot failed: ${error.message}`);
	}
	const snapshot = (data ?? []) as Record<string, unknown>[];
	if (snapshot.length > 0) {
		const { error: delErr } = await admin
			.from('runs')
			.delete()
			.eq('user_id', userId)
			.gte('started_at', since);
		if (delErr) {
			throw new Error(`simulate.withCleanCurrentWeek delete failed: ${delErr.message}`);
		}
	}
	return async () => {
		if (snapshot.length === 0) return;
		const { error: insErr } = await admin.from('runs').insert(snapshot);
		if (insErr) {
			throw new Error(`simulate.withCleanCurrentWeek restore failed: ${insErr.message}`);
		}
	};
}

export async function deletePlan(planId: string): Promise<void> {
	// plan_weeks → plan_workouts cascade via FK ON DELETE CASCADE; the
	// plans row delete sweeps everything beneath. Used by tests that
	// drove a plan create through the wizard but don't want to walk
	// the abandon → delete UI path just to clean up.
	const { error } = await getAdminClient().from('training_plans').delete().eq('id', planId);
	if (error) {
		throw new Error(`simulate.deletePlan failed: ${error.message}`);
	}
}

export async function deleteClub(clubId: string): Promise<void> {
	const { error } = await getAdminClient().from('clubs').delete().eq('id', clubId);
	if (error) {
		throw new Error(`simulate.deleteClub failed: ${error.message}`);
	}
}

export async function setPlanStatus(
	planId: string,
	status: 'active' | 'abandoned' | 'completed' | 'draft',
): Promise<void> {
	const { error } = await getAdminClient()
		.from('training_plans')
		.update({ status })
		.eq('id', planId);
	if (error) {
		throw new Error(`simulate.setPlanStatus failed: ${error.message}`);
	}
}

export async function insertEvent(opts: {
	club_id: string;
	author_id: string;
	title: string;
	starts_at?: string;
	duration_min?: number;
	description?: string;
	recurrence_freq?: 'weekly' | 'biweekly' | 'monthly' | null;
	recurrence_byday?: string[] | null;
	recurrence_until?: string | null;
	capacity?: number | null;
	distance_m?: number | null;
	pace_target_sec?: number | null;
	category?: 'run' | 'cycle' | 'class' | 'social';
	discipline?: string | null;
	gym_template?: { discipline: string | null; duration_min: number | null } | null;
}): Promise<string> {
	const { data, error } = await getAdminClient()
		.from('events')
		.insert({
			club_id: opts.club_id,
			author_id: opts.author_id,
			title: opts.title,
			category: opts.category ?? 'run',
			discipline: opts.discipline ?? null,
			starts_at:
				opts.starts_at ??
				new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString(),
			duration_min: opts.duration_min ?? 60,
			description: opts.description ?? null,
			recurrence_freq: opts.recurrence_freq ?? null,
			recurrence_byday: opts.recurrence_byday ?? null,
			recurrence_until: opts.recurrence_until ?? null,
			capacity: opts.capacity ?? null,
			distance_m: opts.distance_m ?? null,
			pace_target_sec: opts.pace_target_sec ?? null,
			gym_template: opts.gym_template ?? null
		})
		.select('id')
		.single();
	if (error || !data) {
		throw new Error(`simulate.insertEvent failed: ${error?.message ?? 'no row'}`);
	}
	return data.id as string;
}

export async function deleteEvent(eventId: string): Promise<void> {
	const { error } = await getAdminClient().from('events').delete().eq('id', eventId);
	if (error) {
		throw new Error(`simulate.deleteEvent failed: ${error.message}`);
	}
}

export async function insertKudos(runId: string, userId: string): Promise<void> {
	const { error } = await getAdminClient()
		.from('run_kudos')
		.insert({ run_id: runId, user_id: userId });
	if (error) {
		throw new Error(`simulate.insertKudos failed: ${error.message}`);
	}
}

export async function insertComment(opts: {
	run_id: string;
	author_id: string;
	body: string;
}): Promise<string> {
	const { data, error } = await getAdminClient()
		.from('run_comments')
		.insert({ run_id: opts.run_id, author_id: opts.author_id, body: opts.body })
		.select('id')
		.single();
	if (error || !data) {
		throw new Error(`simulate.insertComment failed: ${error?.message ?? 'no row'}`);
	}
	return data.id as string;
}

export async function setClubMemberStatus(
	clubId: string,
	userId: string,
	// Matches the club_members_status_check CHECK constraint
	// (migration 20260416_001): there is no 'banned' state — 'rejected'
	// is the terminal lockout status. Passing an unmodelled value would
	// violate the CHECK and the service-role insert would silently fail.
	status: 'active' | 'pending' | 'rejected',
): Promise<void> {
	const { error } = await getAdminClient()
		.from('club_members')
		.update({ status })
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) {
		throw new Error(`simulate.setClubMemberStatus failed: ${error.message}`);
	}
}

export async function setClubMemberRole(
	clubId: string,
	userId: string,
	role: 'owner' | 'admin' | 'event_organiser' | 'race_director' | 'member',
): Promise<void> {
	const { error } = await getAdminClient()
		.from('club_members')
		.update({ role })
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) {
		throw new Error(`simulate.setClubMemberRole failed: ${error.message}`);
	}
}

export async function insertLivePings(opts: {
	run_id: string;
	user_id: string;
	points: Array<{
		lat: number;
		lng: number;
		distance_m?: number;
		elapsed_s?: number;
		at?: string;
	}>;
}): Promise<void> {
	// Plant a sequence of live_run_pings rows for the spectator page to
	// hydrate from. The /live/[id] page calls fetchBacklog on mount and
	// renders the trace + status='live' as soon as any pings exist.
	// Inserts go through the service-role client to bypass RLS, but the
	// `live_run_pings_drop_in_zone` BEFORE-INSERT trigger still fires —
	// keep test points well clear of any seeded privacy zones (the seed
	// puts a 200 m zone around runner's home in Sydney CBD).
	const rows = opts.points.map((p, i) => ({
		run_id: opts.run_id,
		user_id: opts.user_id,
		lat: p.lat,
		lng: p.lng,
		distance_m: p.distance_m ?? null,
		elapsed_s: p.elapsed_s ?? null,
		at: p.at ?? new Date(Date.now() - (opts.points.length - i) * 1000).toISOString()
	}));
	const { error } = await getAdminClient().from('live_run_pings').insert(rows);
	if (error) {
		throw new Error(`simulate.insertLivePings failed: ${error.message}`);
	}
}

export async function insertRaceSession(opts: {
	event_id: string;
	instance_start: string;
	status: 'armed' | 'running' | 'finished' | 'cancelled';
	started_at?: string | null;
	finished_at?: string | null;
	started_by?: string | null;
	is_auto_approve?: boolean;
}): Promise<void> {
	const { error } = await getAdminClient()
		.from('race_sessions')
		.upsert(
			{
				event_id: opts.event_id,
				instance_start: opts.instance_start,
				status: opts.status,
				started_at: opts.started_at ?? null,
				finished_at: opts.finished_at ?? null,
				started_by: opts.started_by ?? null,
				is_auto_approve: opts.is_auto_approve ?? true
			},
			{ onConflict: 'event_id,instance_start' }
		);
	if (error) {
		throw new Error(`simulate.insertRaceSession failed: ${error.message}`);
	}
}

export async function insertRacePings(opts: {
	event_id: string;
	instance_start: string;
	runners: Array<{
		user_id: string;
		points: Array<{
			lat: number;
			lng: number;
			distance_m?: number;
			elapsed_s?: number;
			at?: string;
		}>;
	}>;
}): Promise<void> {
	// Plant a sequence of race_pings for each runner. Inserts go through
	// service-role to bypass the running-state RLS insert check, but the
	// race_pings_drop_in_zone BEFORE-INSERT trigger still fires — keep
	// test points clear of any seeded privacy zones (runner has a 200 m
	// zone around Melbourne CBD).
	const baseAt = Date.now();
	const rows: Array<Record<string, unknown>> = [];
	for (const r of opts.runners) {
		r.points.forEach((p, i) => {
			rows.push({
				event_id: opts.event_id,
				instance_start: opts.instance_start,
				user_id: r.user_id,
				at:
					p.at ??
					new Date(baseAt - (r.points.length - i) * 1000).toISOString(),
				lat: p.lat,
				lng: p.lng,
				distance_m: p.distance_m ?? null,
				elapsed_s: p.elapsed_s ?? null
			});
		});
	}
	if (rows.length === 0) return;
	const { error } = await getAdminClient().from('race_pings').insert(rows);
	if (error) {
		throw new Error(`simulate.insertRacePings failed: ${error.message}`);
	}
}

export async function clearNotifications(userId: string): Promise<void> {
	// Wipe the user's notifications. Tests that need a deterministic
	// starting state (bell-badge tests asserting exact counts, inbox
	// tests planting fresh items) call this in beforeEach. Real
	// behaviour: notifications accumulate from kudos / comment / follow
	// triggers, so cross-test leakage is the default unless cleared.
	const { error } = await getAdminClient()
		.from('notifications')
		.delete()
		.eq('user_id', userId);
	if (error) {
		throw new Error(`simulate.clearNotifications failed: ${error.message}`);
	}
}

export async function setNotificationsUnread(userId: string): Promise<void> {
	// Restore unread state across the user's notifications. Used as an
	// afterEach safety net by the inbox test so the bell-badge test
	// downstream still sees something to count.
	const { error } = await getAdminClient()
		.from('notifications')
		.update({ read_at: null })
		.eq('user_id', userId);
	if (error) {
		throw new Error(`simulate.setNotificationsUnread failed: ${error.message}`);
	}
}

export async function clearUserSettingKey(userId: string, key: string): Promise<void> {
	const admin = getAdminClient();
	const { data: existing } = await admin
		.from('user_settings')
		.select('prefs')
		.eq('user_id', userId)
		.maybeSingle();
	if (!existing) return;
	const prefs = (existing.prefs as Record<string, unknown> | null) ?? {};
	delete prefs[key];
	const { error } = await admin
		.from('user_settings')
		.update({ prefs, updated_at: new Date().toISOString() })
		.eq('user_id', userId);
	if (error) {
		throw new Error(`simulate.clearUserSettingKey failed: ${error.message}`);
	}
}

export async function insertCheckpoint(opts: {
	event_id: string;
	created_by: string;
	name: string;
	ordinal: number;
	position_m?: number | null;
	cutoff_elapsed_s?: number | null;
	requires_weigh_in?: boolean;
}): Promise<string> {
	const { data, error } = await getAdminClient()
		.from('event_checkpoints')
		.insert({
			event_id: opts.event_id,
			created_by: opts.created_by,
			name: opts.name,
			ordinal: opts.ordinal,
			position_m: opts.position_m ?? null,
			cutoff_elapsed_s: opts.cutoff_elapsed_s ?? null,
			requires_weigh_in: opts.requires_weigh_in ?? false
		})
		.select('id')
		.single();
	if (error || !data) {
		throw new Error(`simulate.insertCheckpoint failed: ${error?.message ?? 'no row'}`);
	}
	return data.id as string;
}

export async function insertCrossing(opts: {
	event_id: string;
	checkpoint_id: string;
	instance_start: string;
	user_id?: string | null;
	bib?: string | null;
	runner_name?: string | null;
	in_time?: string | null;
	out_time?: string | null;
}): Promise<void> {
	const { error } = await getAdminClient().from('checkpoint_crossings').insert({
		event_id: opts.event_id,
		checkpoint_id: opts.checkpoint_id,
		instance_start: opts.instance_start,
		user_id: opts.user_id ?? null,
		bib: opts.bib ?? null,
		runner_name: opts.runner_name ?? null,
		in_time: opts.in_time ?? null,
		out_time: opts.out_time ?? null
	});
	if (error) {
		throw new Error(`simulate.insertCrossing failed: ${error.message}`);
	}
}
