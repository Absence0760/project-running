import { gzipSync } from 'zlib';

import { getAdminClient } from './local-supabase';

interface TrackPoint {
	lat: number;
	lng: number;
	ele?: number | null;
	t?: string | null;
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
	metadata?: Record<string, unknown>;
	/** Optional GPS track. When supplied, gzipped JSON is uploaded to
	 *  the `runs` Storage bucket at `{user_id}/{run_id}.json.gz` and
	 *  the row's `track_url` column is set to that path. Mirrors what
	 *  the recorder's sync flow does. */
	track?: TrackPoint[];
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
			metadata: opts.metadata ?? { activity_type: 'run' }
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

	return runId;
}

export async function deleteRun(runId: string): Promise<void> {
	const admin = getAdminClient();
	// Try to remove the gzipped track from Storage too, if any. List
	// the user folder by reading the row first.
	const { data: row } = await admin
		.from('runs')
		.select('track_url')
		.eq('id', runId)
		.maybeSingle();
	if (row?.track_url) {
		await admin.storage.from('runs').remove([row.track_url as string]);
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
