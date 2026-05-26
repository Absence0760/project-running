// Shared Strava import logic — used by both `strava-import` (the
// OAuth-driven backfill EF) and `strava-webhook` (the per-activity
// push handler). Keeping these in one module ensures the two EFs
// agree byte-for-byte on the run-row shape, dedupe key, and metadata
// keys we write — which matters because dashboard queries read across
// both writers.
//
// Anything that touches `runs.metadata` keys here must be mirrored
// in `docs/metadata.md` (the single source of truth for which keys
// readers can rely on).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';

export type StravaTokens = {
	access_token: string;
	refresh_token: string;
	expires_at: number;
	athlete: { id: number };
	// Comma-separated list of scopes Strava actually granted. Differs
	// from the scope the client claimed when calling /oauth/authorize
	// — Strava's consent screen lets users untick individual scopes.
	// Only this value is authoritative; never trust the body-claimed
	// scope for the activity:read_all gate.
	scope?: string;
};

export type StravaActivity = {
	id: number;
	name: string;
	distance: number; // m
	moving_time: number; // s
	elapsed_time: number; // s
	total_elevation_gain: number; // m
	start_date: string; // ISO
	type: string; // "Run", "Walk", "Hike", "Ride", etc.
	sport_type?: string;
	average_heartrate?: number;
	has_heartrate?: boolean;
};

/// Refresh a Strava access token. Used both ad-hoc (from `sync`) and
/// proactively by the cron-driven `refresh-tokens` EF. Returns the new
/// access token on success, null on failure (caller decides whether
/// that's fatal — for `sync` it isn't, the stale token may still work).
export async function refreshStravaToken(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	refreshToken: string,
): Promise<string | null> {
	const resp = await fetch('https://www.strava.com/oauth/token', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({
			client_id: Deno.env.get('STRAVA_CLIENT_ID'),
			client_secret: Deno.env.get('STRAVA_CLIENT_SECRET'),
			refresh_token: refreshToken,
			grant_type: 'refresh_token',
		}),
	});
	if (!resp.ok) return null;
	const tokens = (await resp.json()) as StravaTokens;
	await supabase.rpc('set_integration_tokens', {
		p_user_id: userId,
		p_provider: 'strava',
		p_access_token: tokens.access_token,
		p_refresh_token: tokens.refresh_token,
		p_token_expiry: new Date(tokens.expires_at * 1000).toISOString(),
	});
	return tokens.access_token;
}

/// Fetch a single Strava activity by ID. Used by the webhook EF to
/// hydrate the activity object after Strava notifies us about a new
/// upload — the webhook payload only carries the activity id, not the
/// detail.
///
/// Three-state return so callers can distinguish:
///   - { status: 'ok', activity } — successful fetch
///   - { status: 'rate_limited' } — Strava returned 429 / 503; the
///     caller should propagate this so a webhook returns 500 (Strava
///     retries) rather than 200 (Strava drops the event).
///   - { status: 'not_found' } — anything else (404, auth fail, etc.).
export type StravaFetchResult =
	| { status: 'ok'; activity: StravaActivity }
	| { status: 'rate_limited' }
	| { status: 'not_found' };

export async function fetchStravaActivity(
	accessToken: string,
	activityId: number,
): Promise<StravaFetchResult> {
	const resp = await fetch(`https://www.strava.com/api/v3/activities/${activityId}`, {
		headers: { Authorization: `Bearer ${accessToken}` },
	});
	if (resp.status === 429 || resp.status === 503) {
		console.warn('strava activity fetch rate-limited / unavailable', {
			activityId,
			status: resp.status,
		});
		return { status: 'rate_limited' };
	}
	if (!resp.ok) return { status: 'not_found' };
	return { status: 'ok', activity: (await resp.json()) as StravaActivity };
}

/// Has this user already imported this Strava activity? Cheap dedupe
/// check via metadata.strava_id. Both EFs use this so a webhook fired
/// during a backfill doesn't double-insert.
export async function isAlreadyImported(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	stravaId: number,
): Promise<boolean> {
	const { count } = await supabase
		.from('runs')
		.select('id', { count: 'exact', head: true })
		.eq('user_id', userId)
		.eq('source', 'strava')
		.eq('metadata->>strava_id', String(stravaId));
	return (count ?? 0) > 0;
}

/// Insert a Strava activity as a `runs` row + (best-effort) upload its
/// gzipped GPS track to Storage. Caller is responsible for dedupe.
///
/// Note: `runs` has no `title` or `elevation_m` columns — both live on
/// `metadata` per docs/metadata.md (matches the apps/web/src/lib/data.ts
/// saveRun writer used by the Strava + Garmin ZIP importers).
export async function ingestActivity(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	accessToken: string,
	act: StravaActivity,
): Promise<void> {
	const sportLower = (act.sport_type ?? act.type ?? '').toLowerCase();
	const activityType = sportLower.includes('walk')
		? 'walk'
		: sportLower.includes('hike')
			? 'hike'
			: 'run';

	const metadata: Record<string, unknown> = {
		strava_id: act.id,
		activity_type: activityType,
		imported_from: 'strava',
		imported_at: new Date().toISOString(),
		strava_activity_type: act.type,
	};
	if (act.average_heartrate) metadata.avg_bpm = Math.round(act.average_heartrate);
	if (act.name) metadata.title = act.name;
	if (act.total_elevation_gain != null) metadata.elevation_m = Math.round(act.total_elevation_gain);

	const { data: inserted, error } = await supabase
		.from('runs')
		.insert({
			user_id: userId,
			started_at: act.start_date,
			distance_m: Math.round(act.distance),
			duration_s: act.moving_time || act.elapsed_time,
			source: 'strava',
			metadata,
		})
		.select('id')
		.single();

	if (error || !inserted) throw error ?? new Error('Insert failed');

	const runId = inserted.id as string;

	// Best-effort GPS stream fetch. Short / indoor activities have no
	// stream and Strava returns 404 — don't treat that as a failure.
	if (act.distance >= 200) {
		try {
			const streamResp = await fetch(
				`https://www.strava.com/api/v3/activities/${act.id}/streams?keys=latlng,altitude,time,heartrate&key_by_type=true`,
				{ headers: { Authorization: `Bearer ${accessToken}` } },
			);
			if (streamResp.ok) {
				const streams = await streamResp.json();
				const track = buildTrackFromStreams(streams, act.start_date);
				if (track.length >= 2) {
					await uploadTrack(supabase, userId, runId, track);
				}
			}
		} catch (_) {
			// Swallow — the row is still valid without a track.
		}
	}
}

export function buildTrackFromStreams(
	streams: Record<string, { data: unknown[] }>,
	startIso: string,
): Array<{ lat: number; lng: number; ele?: number; ts?: string; bpm?: number }> {
	const latlng = streams.latlng?.data as [number, number][] | undefined;
	if (!Array.isArray(latlng) || latlng.length === 0) return [];
	const altitude = streams.altitude?.data as number[] | undefined;
	const time = streams.time?.data as number[] | undefined;
	const hr = streams.heartrate?.data as number[] | undefined;
	const startMs = Date.parse(startIso);

	const out: Array<{ lat: number; lng: number; ele?: number; ts?: string; bpm?: number }> = [];
	for (let i = 0; i < latlng.length; i++) {
		const pair = latlng[i];
		if (!Array.isArray(pair) || pair.length < 2) continue;
		const [lat, lng] = pair;
		if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
		const point: { lat: number; lng: number; ele?: number; ts?: string; bpm?: number } = {
			lat,
			lng,
		};
		if (altitude?.[i] != null) point.ele = altitude[i];
		if (time?.[i] != null && Number.isFinite(startMs)) {
			point.ts = new Date(startMs + time[i] * 1000).toISOString();
		}
		if (hr?.[i] != null && hr[i] >= 30 && hr[i] <= 230) point.bpm = hr[i];
		out.push(point);
	}
	return out;
}

export async function uploadTrack(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	runId: string,
	track: unknown[],
): Promise<void> {
	const path = `${userId}/${runId}.json.gz`;
	const json = new TextEncoder().encode(JSON.stringify(track));
	const gzipped = await gzipBytes(json);
	const { error: upErr } = await supabase.storage
		.from('runs')
		.upload(path, new Blob([gzipped], { type: 'application/gzip' }), {
			contentType: 'application/gzip',
			upsert: true,
		});
	if (upErr) throw upErr;
	await supabase.from('runs').update({ track_url: path }).eq('id', runId);
}

export async function gzipBytes(data: Uint8Array): Promise<Uint8Array> {
	const cs = new (globalThis as any).CompressionStream('gzip');
	const stream = new Response(data).body!.pipeThrough(cs);
	const chunks: Uint8Array[] = [];
	const reader = stream.getReader();
	while (true) {
		const { done, value } = await reader.read();
		if (done) break;
		chunks.push(value as Uint8Array);
	}
	const total = chunks.reduce((a, c) => a + c.length, 0);
	const out = new Uint8Array(total);
	let offset = 0;
	for (const c of chunks) {
		out.set(c, offset);
		offset += c.length;
	}
	return out;
}
