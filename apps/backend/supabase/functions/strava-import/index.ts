import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// `strava-import` handles two modes, selected by the `action` field:
//
// - `connect` — first-time OAuth handshake. Exchanges the auth code
//   Strava handed the browser for access / refresh tokens and stores
//   them in `integrations`. Triggers an immediate `sync` so the user
//   sees data on first connect.
//
// - `sync` — pulls activities for an already-connected user. Fetches
//   `/api/v3/athlete/activities` paginated back `lookbackDays` days
//   (default 90), and for each running activity upserts a row into
//   `runs` with `source = 'strava'`, keyed by the Strava activity ID
//   (stored in `metadata.strava_id`). Skips activities already ingested
//   so repeat syncs are cheap.
//
// The GPS stream endpoint is called opportunistically — small runs
// (< 200 m) are saved as a scalar row without a track. For longer
// activities the stream is fetched, gzipped, uploaded to the `runs`
// Storage bucket, and the row's `track_url` is set.

type StravaTokens = {
	access_token: string;
	refresh_token: string;
	expires_at: number;
	athlete: { id: number };
};

type StravaActivity = {
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

serve(async (req: Request) => {
	if (req.method !== 'POST') {
		return new Response('Method not allowed', { status: 405 });
	}

	const authHeader = req.headers.get('Authorization');
	if (!authHeader) return new Response('Unauthorized', { status: 401 });

	const supabase = createClient(
		Deno.env.get('SUPABASE_URL')!,
		Deno.env.get('SUPABASE_ANON_KEY')!,
		{ global: { headers: { Authorization: authHeader } } },
	);

	const { data: userData } = await supabase.auth.getUser();
	const user = userData.user;
	if (!user) return new Response('Unauthorized', { status: 401 });

	const body = await req.json().catch(() => ({}));
	const action = body.action ?? (body.code ? 'connect' : 'sync');

	if (action === 'connect') {
		return handleConnect(supabase, user.id, body.code, body.scope);
	}
	if (action === 'sync') {
		return handleSync(supabase, user.id, body.lookbackDays ?? 90);
	}
	return new Response('Unknown action', { status: 400 });
});

async function handleConnect(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	code: string,
	scope: string,
): Promise<Response> {
	if (!code) return new Response('Missing code', { status: 400 });

	const tokenResponse = await fetch('https://www.strava.com/oauth/token', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({
			client_id: Deno.env.get('STRAVA_CLIENT_ID'),
			client_secret: Deno.env.get('STRAVA_CLIENT_SECRET'),
			code,
			grant_type: 'authorization_code',
		}),
	});

	if (!tokenResponse.ok) {
		const text = await tokenResponse.text();
		return new Response(`Strava token exchange failed: ${text}`, { status: 502 });
	}

	const tokens = (await tokenResponse.json()) as StravaTokens;

	const { error } = await supabase.from('integrations').upsert(
		{
			user_id: userId,
			provider: 'strava',
			access_token: tokens.access_token,
			refresh_token: tokens.refresh_token,
			token_expiry: new Date(tokens.expires_at * 1000).toISOString(),
			external_id: String(tokens.athlete.id),
			scope,
		},
		{ onConflict: 'user_id,provider' },
	);

	if (error) {
		return new Response(`Store tokens failed: ${error.message}`, { status: 500 });
	}

	// First-time connects always trigger a backfill so the user sees data
	// immediately. 90 days is a sensible default — Strava's athlete list
	// goes much further back but that's rarely what someone wants on day
	// one.
	const result = await backfill(supabase, userId, tokens.access_token, 90);
	return Response.json({ ...result, athlete_id: String(tokens.athlete.id) });
}

async function handleSync(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	lookbackDays: number,
): Promise<Response> {
	const { data: integration } = await supabase
		.from('integrations')
		.select('access_token, refresh_token, token_expiry')
		.eq('user_id', userId)
		.eq('provider', 'strava')
		.maybeSingle();

	if (!integration?.access_token) {
		return new Response('Strava not connected', { status: 400 });
	}

	let accessToken = integration.access_token as string;

	// Refresh on-demand if the stored token is within 5 minutes of expiry.
	// This path runs independently of the scheduled refresh job so an
	// ad-hoc sync after a long gap still works.
	if (integration.token_expiry) {
		const expiryMs = new Date(integration.token_expiry as string).getTime();
		if (Date.now() + 300_000 > expiryMs) {
			const refreshed = await refreshStravaToken(supabase, userId, integration.refresh_token as string);
			if (refreshed) accessToken = refreshed;
		}
	}

	const result = await backfill(supabase, userId, accessToken, lookbackDays);
	return Response.json(result);
}

async function refreshStravaToken(
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
	await supabase
		.from('integrations')
		.update({
			access_token: tokens.access_token,
			refresh_token: tokens.refresh_token,
			token_expiry: new Date(tokens.expires_at * 1000).toISOString(),
			updated_at: new Date().toISOString(),
		})
		.eq('user_id', userId)
		.eq('provider', 'strava');
	return tokens.access_token;
}

async function backfill(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	accessToken: string,
	lookbackDays: number,
): Promise<{ imported: number; skipped: number; failed: number }> {
	const afterEpoch = Math.floor((Date.now() - lookbackDays * 86400_000) / 1000);
	let page = 1;
	const pageSize = 50;
	let imported = 0;
	let skipped = 0;
	let failed = 0;

	// Pull existing Strava-sourced runs in one shot so we can dedupe
	// without hitting the DB per activity. Keyed by Strava activity ID
	// stored in metadata.
	const { data: existing } = await supabase
		.from('runs')
		.select('metadata')
		.eq('user_id', userId)
		.eq('source', 'strava');
	const seen = new Set<string>();
	for (const r of existing ?? []) {
		const sid = (r.metadata as Record<string, unknown> | null)?.strava_id;
		if (sid) seen.add(String(sid));
	}

	while (true) {
		const url = `https://www.strava.com/api/v3/athlete/activities?after=${afterEpoch}&per_page=${pageSize}&page=${page}`;
		const resp = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
		if (!resp.ok) {
			// Bail silently on the first failure rather than looping forever —
			// partial imports are still useful.
			break;
		}
		const activities = (await resp.json()) as StravaActivity[];
		if (!Array.isArray(activities) || activities.length === 0) break;

		for (const act of activities) {
			// Restrict to run-type activities. Strava's `sport_type` is the
			// preferred modern field; `type` is the legacy fallback.
			const kind = (act.sport_type ?? act.type ?? '').toLowerCase();
			if (!kind.includes('run') && !kind.includes('walk') && !kind.includes('hike')) continue;
			if (seen.has(String(act.id))) {
				skipped++;
				continue;
			}
			try {
				await ingestActivity(supabase, userId, accessToken, act);
				imported++;
			} catch (_) {
				failed++;
			}
		}

		if (activities.length < pageSize) break;
		page++;
		if (page > 20) break; // safety cap — 1000 activities per sync
	}

	await supabase
		.from('integrations')
		.update({ last_sync_at: new Date().toISOString() })
		.eq('user_id', userId)
		.eq('provider', 'strava');

	return { imported, skipped, failed };
}

async function ingestActivity(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	accessToken: string,
	act: StravaActivity,
): Promise<void> {
	// Start with scalar fields. The track is attached separately via
	// Storage upload; the DB row holds the URL not the payload.
	const activityType = (act.sport_type ?? act.type ?? 'Run').toLowerCase().includes('walk')
		? 'walk'
		: (act.sport_type ?? act.type ?? '').toLowerCase().includes('hike')
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

	// Insert the run first so we have its id for the Storage path.
	const { data: inserted, error } = await supabase
		.from('runs')
		.insert({
			user_id: userId,
			started_at: act.start_date,
			distance_m: Math.round(act.distance),
			duration_s: act.moving_time || act.elapsed_time,
			elevation_m: act.total_elevation_gain != null ? Math.round(act.total_elevation_gain) : null,
			source: 'strava',
			metadata,
			title: act.name,
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

function buildTrackFromStreams(
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

async function uploadTrack(
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

async function gzipBytes(data: Uint8Array): Promise<Uint8Array> {
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
