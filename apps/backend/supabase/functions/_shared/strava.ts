// Shared Strava import logic — used by both `strava-import` (the
// OAuth-driven backfill EF) and `strava-webhook` (the per-activity
// push handler). Keeping these in one module ensures the two EFs
// agree byte-for-byte on the run-row shape, dedupe key, and metadata
// keys we write — which matters because dashboard queries read across
// both writers.
//
// Anything that touches `runs.metadata` keys here must be mirrored
// in `docs/backend/metadata.md` (the single source of truth for which keys
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
	// audit/strava May 2026 High #3 — CAS write so a concurrent
	// refresh (cron + on-demand + webhook race) doesn't overwrite
	// the winner's new vault row with a stale-old refresh token.
	// We pass the refresh token the caller read pre-Strava-call as
	// the "expected" value. If the row was rotated between read +
	// write, the RPC returns false and we silently treat that as
	// "another caller already won — the new token is in vault";
	// return the caller's freshly-fetched access token regardless
	// since Strava already issued it (the old one is invalidated
	// either way).
	const { data: applied } = await supabase.rpc('set_integration_tokens_cas', {
		p_user_id: userId,
		p_provider: 'strava',
		p_expected_refresh_token: refreshToken,
		p_access_token: tokens.access_token,
		p_refresh_token: tokens.refresh_token,
		p_token_expiry: new Date(tokens.expires_at * 1000).toISOString(),
	});
	if (applied === false) {
		// Race lost — log so the metric counter can pick this up,
		// but the caller's fresh access token is still usable for the
		// remainder of this turn since Strava just issued it.
		console.warn('refreshStravaToken: CAS race lost — another caller already rotated', { userId });
	}
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

/// Allowlist of Strava sport_type / type strings that map to a runs row.
/// The /sport_type/ field is the new model (Run, TrailRun, VirtualRun,
/// Walk, Hike); /type/ is the legacy fallback. Both can carry the same
/// substring patterns. Anything not matching this allowlist is rejected
/// upstream (callers should pre-filter via this list); ingestActivity
/// also re-validates as a defence-in-depth so a future code path that
/// reaches this function with a Swim / Ride / Ski payload can't end up
/// in the user's weekly mileage with activity_type='run'. Persona-hunt
/// finding Pro #3.
export const STRAVA_RUN_SPORT_PATTERNS = ['run', 'walk', 'hike'] as const;

/// True when the Strava sport_type / type field maps to a runs-table row.
export function isStravaRunFamily(sport: string | null | undefined): boolean {
	const s = (sport ?? '').toLowerCase();
	return STRAVA_RUN_SPORT_PATTERNS.some((p) => s.includes(p));
}

/// Insert a Strava activity as a `runs` row + (best-effort) upload its
/// gzipped GPS track to Storage. Caller is responsible for dedupe.
///
/// Note: `runs` has no `title` or `elevation_m` columns — both live on
/// `metadata` per docs/backend/metadata.md (matches the apps/web/src/lib/data.ts
/// saveRun writer used by the Strava + Garmin ZIP importers).
export async function ingestActivity(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	accessToken: string,
	act: StravaActivity,
	// Honour the user's privacy_default for imported runs (persona #27).
	// The caller resolves the pref once and passes it; defaults to private
	// (fail-closed) so a caller that doesn't pass it — e.g. the deprecated
	// strava-webhook rollback path — never publishes.
	isPublic = false,
): Promise<void> {
	// Reject non-run-family payloads ahead of the insert. The webhook +
	// backfill paths pre-filter, but a future caller that doesn't (or
	// a Strava-side reclassification arriving mid-flight) must not
	// silently ship swim / ride / ski load into weekly mileage with
	// activity_type='run'. Persona-hunt finding Pro #3.
	const sport = act.sport_type ?? act.type ?? '';
	if (!isStravaRunFamily(sport)) {
		throw new Error(
			`ingestActivity rejected non-run-family sport: ${sport || '<empty>'} ` +
				`(activity ${act.id}). Callers must pre-filter to run / walk / hike.`,
		);
	}
	const sportLower = sport.toLowerCase();
	const activityType = sportLower.includes('walk')
		? 'walk'
		: sportLower.includes('hike')
			? 'hike'
			: 'run';

	// Stringify the Strava id so `metadata.strava_id` is the same
	// type in JSON regardless of writer (EF / Go / mobile ZIP). PG's
	// `->>` coerces numbers to canonical strings on read, but
	// downstream pure-TS readers compare against typeof === 'string'.
	// /audit/strava L3.
	const stravaId = String(act.id);
	const metadata: Record<string, unknown> = {
		strava_id: stravaId,
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
			// activity_type is a real column now (F3 / 20261207_001), no
			// longer a metadata key. is_dnf defaults to false at the DB.
			activity_type: activityType,
			is_public: isPublic,
			// `external_id = 'strava:<id>'` is the cross-source dedupe key
			// — same shape mobile ZIP writes. A future unique constraint
			// on `(user_id, external_id) WHERE external_id IS NOT NULL`
			// would catch the OAuth-then-ZIP double-import path that
			// today only `metadata.strava_id` checks against. /audit/strava M3.
			external_id: `strava:${stravaId}`,
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
					// Embedded best efforts: a fast 5k/10k inside a long run
					// misses every whole-run canonical bracket, so without these
					// keys it never reaches `personal_records` (the 20260529000002
					// trigger reads them). Computed here — the one place the Strava
					// stream is materialised — so both `strava-import` and
					// `strava-webhook` get it off a single fetch. Skipped silently
					// (no metadata write) when the track is too short to cover any
					// canonical distance.
					const bests = computeEmbeddedBests(track);
					if (Object.keys(bests).length > 0) {
						await supabase
							.from('runs')
							.update({ metadata: { ...metadata, ...bests } })
							.eq('id', runId);
					}
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

	// audit/strava May 2026 High #4 — bounds-check every sample.
	// Keep in lockstep with apps/job_worker/internal/handler_strava
	// _event.go BuildTrackFromStreams: any drift between the EF and
	// Go path causes the same activity to render differently
	// depending on which transport ingested it.
	const out: Array<{ lat: number; lng: number; ele?: number; ts?: string; bpm?: number }> = [];
	let lastTs = -1;
	for (let i = 0; i < latlng.length; i++) {
		const pair = latlng[i];
		if (!Array.isArray(pair) || pair.length < 2) continue;
		const [lat, lng] = pair;
		if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
		if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
		const point: { lat: number; lng: number; ele?: number; ts?: string; bpm?: number } = {
			lat,
			lng,
		};
		if (altitude?.[i] != null) {
			const ele = altitude[i];
			if (Number.isFinite(ele) && ele >= -500 && ele <= 9000) point.ele = ele;
		}
		if (time?.[i] != null && Number.isFinite(startMs)) {
			const ts = startMs + time[i] * 1000;
			// Reject a sample whose ms-since-epoch goes backwards
			// more than 1s from the prior accepted sample. Tolerate
			// 1s wobble for upstream clock jitter.
			if (lastTs >= 0 && ts < lastTs - 1000) continue;
			lastTs = ts;
			point.ts = new Date(ts).toISOString();
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

// ---------------------------------------------------------------------------
// Cross-provider near-duplicate detection.
//
// The per-provider dedupe keys (`metadata.strava_id`, `external_id`) only
// catch a re-import of the SAME provider. A single physical activity that
// reaches us under two providers — a Garmin watch that auto-uploads to
// Strava, then the same run imported from a Garmin bulk-export ZIP — lands
// as two rows with different provider ids, so neither key sees the other.
// Two recordings of one effort start within seconds and cover ~the same
// distance; two genuinely distinct runs can't start within a few minutes of
// each other (you can't record two tracks at once). We gate on BOTH axes so
// a warm-up + race of similar distance but well-separated starts is never
// suppressed. Keep this in lockstep with the web twin in
// `apps/web/src/lib/integrations/garmin_dedupe.ts`.
// ---------------------------------------------------------------------------

/// A run's identity for cross-provider matching: start instant (epoch ms)
/// and total distance (metres).
export interface RunIdentity {
	startedAtMs: number;
	distanceM: number;
}

/// Max start-time gap (seconds) for two rows to be the same effort. A few
/// minutes absorbs the offset between a watch's and a service's start stamp.
export const CROSS_PROVIDER_START_TOLERANCE_S = 180;
/// Max relative distance difference for two rows to be the same effort. GPS
/// / algorithm differences between providers move total distance a percent
/// or two; 5 % matches the same run across providers without merging two
/// different-length efforts.
export const CROSS_PROVIDER_DISTANCE_FRACTION = 0.05;

/// True when `candidate` is a near-duplicate of any row in `existing` —
/// start within the tolerance AND distance within the fraction. Callers
/// skip the import when this returns true so a run already present under
/// ANY source isn't re-inserted.
export function isCrossProviderDuplicate(
	candidate: RunIdentity,
	existing: readonly RunIdentity[],
): boolean {
	if (!Number.isFinite(candidate.startedAtMs)) return false;
	for (const row of existing) {
		if (!Number.isFinite(row.startedAtMs) || !Number.isFinite(row.distanceM)) continue;
		const dtS = Math.abs(candidate.startedAtMs - row.startedAtMs) / 1000;
		if (dtS > CROSS_PROVIDER_START_TOLERANCE_S) continue;
		const larger = Math.max(Math.abs(candidate.distanceM), Math.abs(row.distanceM));
		const diff = Math.abs(candidate.distanceM - row.distanceM);
		if (larger === 0 || diff <= larger * CROSS_PROVIDER_DISTANCE_FRACTION) return true;
	}
	return false;
}

/// A raw `{ started_at, distance_m }` row as PostgREST returns it.
export interface RawRunRow {
	started_at: string | null;
	distance_m: number | null;
}

/// Page size + safety ceiling for `collectRunIdentities`.
export const RUN_IDENTITY_PAGE_SIZE = 1000;
export const RUN_IDENTITY_SAFETY_MAX = 50_000;

/// Pull every existing run's start + distance identity across ALL sources by
/// paging `fetchPage` in `RUN_IDENTITY_PAGE_SIZE` chunks — PostgREST caps an
/// unbounded SELECT at 1000 rows, so a pro with 1000+ runs would otherwise
/// compare against an arbitrary slice and re-import duplicates anyway, the
/// exact failure the cross-provider guard exists to close. Keep in lockstep
/// with the web twin in `apps/web/src/lib/integrations/garmin_dedupe.ts`.
export async function collectRunIdentities(
	fetchPage: (from: number, to: number) => PromiseLike<RawRunRow[] | null>,
	pageSize: number = RUN_IDENTITY_PAGE_SIZE,
	safetyMax: number = RUN_IDENTITY_SAFETY_MAX,
): Promise<RunIdentity[]> {
	const out: RunIdentity[] = [];
	for (let from = 0; from < safetyMax; from += pageSize) {
		const data = await fetchPage(from, from + pageSize - 1);
		if (!data) break;
		for (const r of data) {
			const ms = Date.parse(r.started_at ?? '');
			if (!Number.isFinite(ms)) continue;
			out.push({ startedAtMs: ms, distanceM: Number(r.distance_m ?? 0) });
		}
		if (data.length < pageSize) break;
	}
	return out;
}

// ---------------------------------------------------------------------------
// Embedded best efforts.
//
// The whole-run distance of a long run misses every canonical PR bracket, so
// a sub-20 5k inside a 30 km long run never reaches `personal_records`. The
// 20260529000002 migration teaches the PR trigger to read
// `metadata.fastest_{5k,10k,half_marathon,marathon}_s`; the live recorder
// writes them (embedded_bests.dart) but no importer did. Keep the algorithm
// in lockstep with `fastestWindowOf` in
// `apps/mobile_android/lib/run_stats.dart` + `enrichMetadataWithEmbeddedBests`
// in `apps/mobile_android/lib/embedded_bests.dart` so an imported run's best
// matches what a live recording of the same effort would write.
// ---------------------------------------------------------------------------

/// Canonical distances (metres) → metadata key. Matches the bracket
/// midpoints the SQL trigger searches (±2 % wide, so 5000 m exactly).
export const EMBEDDED_BEST_DISTANCES: ReadonlyArray<readonly [string, number]> = [
	['fastest_5k_s', 5000],
	['fastest_10k_s', 10000],
	['fastest_half_marathon_s', 21097.5],
	['fastest_marathon_s', 42195],
];

interface EmbeddedTrackPoint {
	lat: number;
	lng: number;
	ts?: string;
}

function embeddedHaversineM(lat1: number, lng1: number, lat2: number, lng2: number): number {
	const r = 6371000;
	const toRad = Math.PI / 180;
	const dLat = (lat2 - lat1) * toRad;
	const dLng = (lng2 - lng1) * toRad;
	const s1 = Math.sin(dLat / 2);
	const s2 = Math.sin(dLng / 2);
	const a = s1 * s1 + Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) * s2 * s2;
	return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function pointMs(p: EmbeddedTrackPoint): number | null {
	if (typeof p.ts !== 'string') return null;
	const ms = Date.parse(p.ts);
	return Number.isFinite(ms) ? ms : null;
}

/// Fastest continuous `windowMetres` (whole seconds) anywhere in the track,
/// or null when the track has < 2 points, is shorter than the window, or has
/// no timestamped window. Sliding-window with linear interpolation at the
/// exact distance boundary — the port of Dart's `fastestWindowOf`.
export function fastestWindowSeconds(
	track: readonly EmbeddedTrackPoint[],
	windowMetres: number,
): number | null {
	const n = track.length;
	if (n < 2 || windowMetres <= 0) return null;

	const cum = new Array<number>(n).fill(0);
	for (let i = 1; i < n; i++) {
		cum[i] = cum[i - 1] +
			embeddedHaversineM(track[i - 1].lat, track[i - 1].lng, track[i].lat, track[i].lng);
	}
	if (cum[n - 1] < windowMetres) return null;

	let best: number | null = null;
	let i = 0;
	for (let j = 1; j < n; j++) {
		while (i + 1 < j && cum[j] - cum[i + 1] >= windowMetres) i++;
		if (cum[j] - cum[i] < windowMetres) continue;

		const ti = pointMs(track[i]);
		const tj = pointMs(track[j]);
		if (ti == null || tj == null) continue;

		const segDist = cum[i + 1] - cum[i];
		let startMs: number;
		if (segDist <= 0) {
			startMs = ti;
		} else {
			const ti1 = pointMs(track[i + 1]);
			if (ti1 == null) {
				startMs = ti;
			} else {
				const targetCum = cum[j] - windowMetres;
				const fraction = Math.min(1, Math.max(0, (targetCum - cum[i]) / segDist));
				startMs = ti + Math.round((ti1 - ti) * fraction);
			}
		}

		const windowMs = tj - startMs;
		if (windowMs <= 0) continue;
		if (best == null || windowMs < best) best = windowMs;
	}
	return best == null ? null : Math.round(best / 1000);
}

/// Embedded best-effort seconds for every canonical distance the track is
/// long enough to cover. Returns `{}` (no fake bests) when the track has < 3
/// points or covers no canonical distance; callers merge the result into
/// `metadata` and skip the write when empty.
export function computeEmbeddedBests(
	track: readonly EmbeddedTrackPoint[],
): Record<string, number> {
	const out: Record<string, number> = {};
	if (!Array.isArray(track) || track.length < 3) return out;
	for (const [key, dist] of EMBEDDED_BEST_DISTANCES) {
		const secs = fastestWindowSeconds(track, dist);
		if (secs != null && secs > 0) out[key] = secs;
	}
	return out;
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
