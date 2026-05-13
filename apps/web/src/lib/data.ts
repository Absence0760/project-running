/**
 * Data access layer — all Supabase queries in one place.
 */
import { supabase } from './supabase';
import type {
	Run,
	Route,
	Integration,
	Club,
	ClubWithMeta,
	ClubMember,
	ClubRole,
	MembershipStatus,
	JoinPolicy,
	Event,
	EventWithMeta,
	EventAttendee,
	RsvpStatus,
	ClubPost,
	ClubPostWithAuthor,
	RecurrenceFreq,
	Weekday,
	TrainingPlan,
	PlanWeek,
	PlanWorkout,
	ActivePlanOverview,
	PlanStatus
} from './types';
import { parseRunSource } from './types';
import type { GeneratedPlan, GoalEvent } from './training';
import { auth } from './stores/auth.svelte';
import { nextInstanceAfter } from './recurrence';

// --- Runs ---

export interface FetchRunsOptions {
	/** Cap the number of rows returned. Pair with `offset` for paging. */
	limit?: number;
	/** Skip this many rows before the page (for paged loads). */
	offset?: number;
}

export async function fetchRuns(opts?: FetchRunsOptions): Promise<Run[]> {
	// Explicit user_id filter as defence in depth — RLS already scopes
	// runs to the caller, but every other personal-data list in this
	// file follows the same explicit-scope pattern. See audit
	// `/tmp/data-isolation-audit/client-realtime.md` M2.
	const userId = auth.user?.id;
	if (!userId) return [];
	let q = supabase
		.from('runs')
		.select('*')
		.eq('user_id', userId)
		.order('started_at', { ascending: false });
	if (opts?.limit != null) {
		const from = opts.offset ?? 0;
		const to = from + opts.limit - 1;
		q = q.range(from, to);
	}
	const { data, error } = await q;
	if (error || !data) return [];
	// Defensive narrow on read: the DB CHECK constraint stops bad
	// `source` values at write time, but historical rows imported before
	// the constraint or rows from a future client whose new value
	// hasn't propagated to this build need a fallback. parseRunSource
	// coerces unknowns to 'app'.
	return data.map((r: any) => ({
		...r,
		source: parseRunSource(r.source),
		track: null,
	}));
}

export async function fetchRunById(id: string): Promise<Run | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data } = await supabase
		.from('runs')
		.select('*')
		.eq('id', id)
		.eq('user_id', userId)
		.single();

	if (!data) return null;

	// Lazy-load the GPS track from Storage when the run has one.
	let track = null;
	if (data.track_url) {
		try {
			track = await fetchTrack(data.track_url);
		} catch (e) {
			console.warn('Failed to fetch track', e);
		}
	}
	return { ...data, source: parseRunSource(data.source), track };
}

/// Fetch every run by the signed-in user against `routeId`, ordered
/// by duration ascending so the caller can read off PB / rank without
/// re-sorting. Used by the Route History panel on `/runs/[id]`. The
/// returned rows are the column subset `route_history.ts` declares —
/// no track download.
export async function fetchRunsOnRoute(
	routeId: string,
): Promise<{ id: string; route_id: string | null; distance_m: number; duration_s: number; metadata: Record<string, unknown> | null }[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data, error } = await supabase
		.from('runs')
		.select('id, route_id, distance_m, duration_s, metadata')
		.eq('user_id', userId)
		.eq('route_id', routeId)
		.order('duration_s', { ascending: true });
	if (error || !data) return [];
	return data as never;
}

/**
 * Download a gzipped GPS track from the `runs` Storage bucket.
 * Throws if the path is invalid or the user can't read it.
 */
async function fetchTrack(path: string) {
	const { data, error } = await supabase.storage.from('runs').download(path);
	if (error || !data) throw error ?? new Error('No data');
	const buf = await data.arrayBuffer();
	const decompressed = await decompressGzip(buf);
	const json = new TextDecoder().decode(decompressed);
	return JSON.parse(json);
}

/// Public wrapper for list-page thumbnail fetches. Same pipeline as
/// the detail-page track loader but exposed so the runs list can lazy-
/// download track blobs as cards scroll into view. **Owner-only path** —
/// the per-user-folder Storage policy from 20260410_001 gates access to
/// `(storage.foldername(name))[1] = auth.uid()::text`. Non-owner viewers
/// must use [fetchClippedTrackForRun] instead, which routes through the
/// `clip-public-track` Edge Function so the privacy-zone clip happens
/// server-side and the unclipped blob never crosses the wire.
export async function fetchTrackByPath(path: string) {
	return fetchTrack(path);
}

/// Privacy-aware non-owner track fetcher. Calls the `clip-public-track`
/// Edge Function which downloads the gzipped track via service-role,
/// passes the points through `clip_track_for_user`, and returns the
/// clipped result. Use this on every non-owner surface where the old
/// pattern was "fetchTrackByPath then clipTrackForUser client-side" —
/// that pattern leaked the unclipped blob (audit/storage High,
/// closed by migration 20260619_001 dropping the public-runs Storage
/// policy).
export async function fetchClippedTrackForRun(runId: string) {
	const { data, error } = await supabase.functions.invoke('clip-public-track', {
		body: { run_id: runId },
	});
	if (error) throw error;
	const points = (data as { points?: unknown })?.points;
	if (!Array.isArray(points)) {
		throw new Error('clip-public-track returned malformed payload');
	}
	return points;
}

/// Server-side privacy-zone-clipped waypoints for a route owned by
/// someone other than the caller. Routes carry waypoints inline as a
/// jsonb column (no Storage indirection like runs), so this is a
/// straight RPC rather than an Edge Function. The SECURITY DEFINER
/// function checks visibility (owner / public / club member), then
/// returns either unclipped waypoints (owner) or clipped output
/// (non-owner). Anon callers (no JWT) only get public routes.
///
/// Use on every non-owner route render site — the bare `route.waypoints`
/// from a `routes` row is the unclipped polyline and must not reach
/// the renderer when the viewer != owner. Decisions §33.
export async function fetchClippedRouteForViewer(
	routeId: string,
): Promise<Array<{ lat: number; lng: number }>> {
	const { data, error } = await supabase.rpc('clip_route_for_viewer', {
		p_route_id: routeId,
	});
	if (error) {
		// Fail closed — returning the unclipped waypoints on RPC error
		// would defeat the helper's purpose. Render an empty polyline
		// rather than leak. Matches the clipTrackForUser shape.
		console.warn('clip_route_for_viewer failed; failing closed (empty route)', error);
		return [];
	}
	if (!Array.isArray(data)) return [];
	return data as Array<{ lat: number; lng: number }>;
}

export type RouteMatchCandidate = {
	id: string;
	name: string;
	distanceM: number;
	startOffsetM: number;
	endOffsetM: number;
};

/// Auto-link helper: given a recorded run's track, ask the DB which
/// of the user's saved routes it overlaps. Backed by the
/// routes_intersecting_track RPC (migration 20260610_001) which
/// uses the routes.geom GIST index to pre-filter candidates.
///
/// Caller decides the final ranking. The combination
/// (start_offset + end_offset < 2 * tolerance) AND
/// (|distance_m - track_length| / track_length < 0.20) is a strong
/// "definitely the same route" signal. A single low-offset candidate
/// with that distance match is auto-link-worthy; multiple candidates
/// or a length mismatch should defer to user confirmation.
export async function fetchRoutesIntersectingTrack(
	track: import('$lib/types').TrackPoint[],
	toleranceM = 100,
	maxResults = 10,
): Promise<RouteMatchCandidate[]> {
	const userId = auth.user?.id;
	if (!userId || track.length < 2) return [];
	const geojson = {
		type: 'LineString' as const,
		coordinates: track.map((p) => [p.lng, p.lat]),
	};
	const { data, error } = await supabase.rpc('routes_intersecting_track', {
		caller_user_id: userId,
		track_geojson: geojson,
		tolerance_m: toleranceM,
		max_results: maxResults,
	});
	if (error || !data) return [];
	return (data as Array<{
		id: string;
		name: string;
		distance_m: number;
		start_offset_m: number;
		end_offset_m: number;
	}>).map((r) => ({
		id: r.id,
		name: r.name,
		distanceM: Number(r.distance_m),
		startOffsetM: Number(r.start_offset_m),
		endOffsetM: Number(r.end_offset_m),
	}));
}

/// Persist runs.route_id. Used by the auto-link suggestion on
/// /runs/[id] and by any future "save as route" flow that wants
/// to back-link the run to its source.
export async function linkRunToRoute(runId: string, routeId: string): Promise<void> {
	await supabase.from('runs').update({ route_id: routeId }).eq('id', runId);
}

export type MatchStatus = 'pending' | 'matched' | 'failed' | 'skipped';

export type RunMatchInfo = {
	status: MatchStatus;
	algorithm: string | null;
	algorithmVersion: string | null;
	matchedAt: string | null;
	track: import('$lib/types').TrackPoint[] | null;
};

/// Fetch the run_matched_tracks row for a run + lazily download the
/// matched track when status='matched'. The owner-read RLS policy
/// gates this — non-owners get an empty result and the caller falls
/// back to the raw track. L4 per docs/conventions.md § Layered
/// resilience: the matched track is an enhancement on top of the
/// raw track that already renders; a failure here must NOT break
/// the run-detail page.
export async function fetchRunMatchedTrack(
	runId: string,
): Promise<RunMatchInfo | null> {
	const { data, error } = await supabase
		.from('run_matched_tracks')
		.select('status, matched_track_url, algorithm, algorithm_version, matched_at')
		.eq('run_id', runId)
		.maybeSingle();
	if (error || !data) return null;

	let track: import('$lib/types').TrackPoint[] | null = null;
	if (data.status === 'matched' && data.matched_track_url) {
		try {
			track = (await fetchTrack(data.matched_track_url)) as import('$lib/types').TrackPoint[];
		} catch (e) {
			console.warn('Failed to fetch matched track', e);
		}
	}
	return {
		status: data.status as MatchStatus,
		algorithm: data.algorithm,
		algorithmVersion: data.algorithm_version,
		matchedAt: data.matched_at,
		track,
	};
}

/// Force a fresh map-match for a run the caller owns. Resets
/// run_matched_tracks to pending and queues a `map_match` job. The
/// PostgREST RPC self-gates on auth.uid() = run.user_id; non-owner
/// calls get a 42501 error which we surface to the toast layer.
/// Idempotent against in-flight jobs (jobs_dedupe_map_match unique
/// index) — calling twice while a previous re-match is queued is a
/// no-op.
export async function enqueueRunRematch(runId: string): Promise<void> {
	const { error } = await supabase.rpc('enqueue_run_rematch', { p_run_id: runId });
	if (error) throw error;
}

/** Decompress a gzipped ArrayBuffer using the browser's DecompressionStream. */
async function decompressGzip(buf: ArrayBuffer): Promise<Uint8Array> {
	const ds = new (globalThis as any).DecompressionStream('gzip');
	const stream = new Response(buf).body!.pipeThrough(ds);
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

export async function fetchPublicRun(id: string): Promise<Run | null> {
	// Public reads go through the public_runs view (decisions §33,
	// migration 20260626_001) which strips external_id, redacts the
	// metadata bag's audit / sync / training-plan-linkage keys, and
	// nulls route_id / event_id when the joined target isn't public.
	// The view's where clause is `is_public = true` so the dropped
	// `.eq('is_public', true)` filter is redundant.
	//
	// Track is *not* fetched here: the audit (storage High) flagged that
	// loading raw bytes inline meant a future maintainer using `r.track`
	// for non-owners would bypass the privacy-zone clipping required by
	// decisions §33. RunShareView already branches on owner — owner takes
	// the direct Storage path via fetchTrack(); non-owner takes
	// fetchClippedTrackForRun(). This function only returns the row.
	const { data } = await supabase
		.from('public_runs')
		.select('*')
		.eq('id', id)
		.single();

	if (!data) return null;
	return { ...data, track: null } as Run;
}

export async function deleteRun(id: string): Promise<void> {
	// Best-effort sweep of attached Storage objects before the row delete:
	//   - the gzipped track file in the `runs` bucket
	//   - every photo blob in the `run-photos` bucket
	// The DB cascade deletes the `run_photos` rows when the run is gone,
	// but the bytes orphan in Storage and continue paying for storage
	// indefinitely. (Visibility is closed by the Storage SELECT policy
	// since the row-cascade kills the join target — but unreachable
	// orphan bytes still occupy the bucket.) Audit/storage Medium fix.
	const { data: run } = await supabase
		.from('runs')
		.select('track_url')
		.eq('id', id)
		.single();
	if (run?.track_url) {
		try {
			await supabase.storage.from('runs').remove([run.track_url]);
		} catch (e) {
			// Don't log the storage path — it embeds the user's auth
			// UUID and would land in Sentry breadcrumbs. The Sentry
			// hook redacts known signed-URL patterns but the row's
			// storage path doesn't match those. The run id is
			// sufficient to triangulate from server logs.
			console.warn('deleteRun: track storage removal failed (orphaned file)', { run_id: id, error: e });
		}
	}
	const { data: photos } = await supabase
		.from('run_photos')
		.select('storage_path')
		.eq('run_id', id);
	if (photos && photos.length > 0) {
		const paths = photos
			.map((p: { storage_path: string | null }) => p.storage_path)
			.filter((p: string | null): p is string => !!p);
		if (paths.length > 0) {
			try {
				await supabase.storage.from('run-photos').remove(paths);
			} catch (e) {
				console.warn('deleteRun: photo storage removal failed (orphaned files)', { run_id: id, count: paths.length, error: e });
			}
		}
	}
	const { error } = await supabase.from('runs').delete().eq('id', id);
	if (error) throw error;
}

/// Delete a batch of runs plus their Storage track files. One RLS-scoped
/// REST call per delete because Supabase's batch delete doesn't return
/// the pre-delete `track_url` we need to clean up Storage. Runs in
/// parallel via `Promise.allSettled` — individual failures don't stop
/// the rest. Returns the ids that failed so the caller can surface them.
export async function deleteRuns(ids: string[]): Promise<{ failed: string[] }> {
	if (ids.length === 0) return { failed: [] };
	const failed: string[] = [];
	const results = await Promise.allSettled(ids.map((id) => deleteRun(id)));
	for (let i = 0; i < results.length; i++) {
		if (results[i].status === 'rejected') failed.push(ids[i]);
	}
	return { failed };
}

/// Flip a route's visibility. Mirrors the Android
/// `ApiClient.setRoutePublic` signature — bidirectional (public ↔
/// private) rather than the one-way `makeRoutePublic` the old Share
/// flow assumed. RLS guards ownership; the caller should still gate
/// the UI so non-owners never see the control.
export async function setRoutePublic(id: string, isPublic: boolean): Promise<void> {
	const { error } = await supabase
		.from('routes')
		.update({ is_public: isPublic })
		.eq('id', id);
	if (error) throw error;
}

export async function makeRunPublic(id: string): Promise<void> {
	const { error } = await supabase
		.from('runs')
		.update({ is_public: true })
		.eq('id', id);
	if (error) throw error;
}

/// Upsert a fitness snapshot for the signed-in user. The dashboard
/// call path computes the snapshot on every open (cheap — pure math
/// over the run list the dashboard already fetched) and persists so
/// the trend chart has a history to draw. Returns the id of the
/// inserted row.
export async function insertFitnessSnapshot(input: {
	vdot: number | null;
	vo2Max: number | null;
	acuteLoad: number | null;
	chronicLoad: number | null;
	trainingStressBal: number | null;
	qualifyingRunCount: number;
}): Promise<void> {
	const { data: authUser } = await supabase.auth.getUser();
	const userId = authUser.user?.id;
	if (!userId) return;
	// Don't spam writes — only persist when the user has enough data
	// for the numbers to mean something. Anything less is just noise
	// on the trend chart.
	if (
		input.vdot == null &&
		input.chronicLoad == null &&
		input.qualifyingRunCount < 3
	) {
		return;
	}
	await supabase.from('fitness_snapshots').insert({
		user_id: userId,
		vdot: input.vdot,
		vo2_max: input.vo2Max,
		acute_load: input.acuteLoad,
		chronic_load: input.chronicLoad,
		training_stress_bal: input.trainingStressBal,
		qualifying_run_count: input.qualifyingRunCount,
		source: 'client',
	});
}

export interface FitnessSnapshotRow {
	computed_at: string;
	vdot: number | null;
	vo2_max: number | null;
	acute_load: number | null;
	chronic_load: number | null;
	training_stress_bal: number | null;
}

/// Fetch recent snapshots for the trend chart. Ordered oldest → newest
/// so a Svelte `{#each}` draws the chart left-to-right.
export async function fetchFitnessSnapshots(limit = 60): Promise<FitnessSnapshotRow[]> {
	const { data } = await supabase
		.from('fitness_snapshots')
		.select('computed_at, vdot, vo2_max, acute_load, chronic_load, training_stress_bal')
		.order('computed_at', { ascending: false })
		.limit(limit);
	const rows = (data as FitnessSnapshotRow[] | null) ?? [];
	return rows.slice().reverse();
}

/// Save a run's GPS track as a reusable saved route. Runs the track
/// through Douglas-Peucker to shed GPS jitter before persisting (same
/// 10 m epsilon the Android path uses), sums elevation gain, and
/// inserts a `routes` row for the current user. Throws if the run has
/// no track (manual-entry runs); the caller should gate the button.
///
/// Returns the new route id so the caller can navigate to it.
export async function saveRunAsRoute(
	runId: string,
	name: string,
	track: Array<{ lat: number; lng: number; ele?: number | null }>,
): Promise<{ id: string }> {
	const { simplifyTrack, computeElevationGain } = await import('./route_simplify');
	if (track.length < 2) throw new Error('Not enough GPS points to save a route');
	const simplified = simplifyTrack(track, 10);

	const waypoints = simplified.map((p) => ({
		lat: p.lat,
		lng: p.lng,
		...(p.ele != null ? { ele: p.ele } : {}),
	}));
	// Distance — sum of segment lengths. Haversine would be marginally
	// more accurate; equirectangular is more than close enough at
	// running scales and matches the Android save-as-route path.
	let distance = 0;
	for (let i = 1; i < simplified.length; i++) {
		const a = simplified[i - 1];
		const b = simplified[i];
		const dLat = ((b.lat - a.lat) * Math.PI) / 180;
		const dLng = ((b.lng - a.lng) * Math.PI) / 180;
		const midLat = ((a.lat + b.lat) / 2 * Math.PI) / 180;
		const x = dLng * Math.cos(midLat);
		const y = dLat;
		distance += Math.sqrt(x * x + y * y) * 6_371_000;
	}
	const elevation = computeElevationGain(simplified);

	const { data: authUser } = await supabase.auth.getUser();
	const userId = authUser.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const { data, error } = await supabase
		.from('routes')
		.insert({
			user_id: userId,
			name,
			waypoints,
			distance_m: distance,
			elevation_m: elevation,
			is_public: false,
		})
		.select('id')
		.single();
	if (error) throw error;

	// Back-link the run to its new route for convenience on the
	// run-detail page. Best-effort — the route insert is the important
	// bit. Swallow any RLS or FK miss silently.
	try {
		await supabase.from('runs').update({ route_id: data.id }).eq('id', runId);
	} catch (e) {
		console.warn('saveRunAsRoute: back-link update failed', e);
	}

	return { id: data.id };
}

/// Insert a manually-entered run. No GPS track, no track file —
/// `track_url` stays null and downstream readers (run detail map,
/// dashboards) already handle the "no track" path. `source` is always
/// `'app'` so the run picks up the "Recorded" label in the UI; the
/// `metadata.manual_entry = true` flag lets the detail page show
/// "Manual entry" instead of the map.
export async function createManualRun(input: {
	startedAt: string; // ISO UTC
	durationS: number;
	distanceM: number;
	activityType?: 'run' | 'walk' | 'hike' | 'cycle';
	notes?: string | null;
	routeId?: string | null;
}): Promise<{ id: string }> {
	const { data: authUser } = await supabase.auth.getUser();
	const userId = authUser.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const metadata: Record<string, unknown> = {
		manual_entry: true,
		activity_type: input.activityType ?? 'run',
	};
	if (input.notes && input.notes.trim()) metadata.notes = input.notes.trim();

	const { data, error } = await supabase
		.from('runs')
		.insert({
			user_id: userId,
			started_at: input.startedAt,
			duration_s: input.durationS,
			distance_m: input.distanceM,
			source: 'app',
			metadata,
			route_id: input.routeId ?? null,
		})
		.select('id')
		.single();
	if (error) throw error;
	return { id: data.id };
}

/// Insert a run from an importer (Strava zip, GPX bulk, etc). Uploads
/// an optional `track` to the Storage bucket and stores the path in
/// `track_url`. For callers without a GPS track, pass `track: undefined`
/// and the row is saved without one, same as a scalar row from parkrun.
export async function saveRun(input: {
	started_at: string;
	distance_m: number;
	duration_s: number;
	elevation_m: number | null;
	source: string;
	metadata: Record<string, unknown> | null;
	track?: Array<{ lat: number; lng: number; ele?: number; ts?: string; bpm?: number }>;
	title?: string | null;
}): Promise<{ id: string; trackUploaded: boolean; trackError?: string }> {
	const { data: authUser } = await supabase.auth.getUser();
	const userId = authUser.user?.id;
	if (!userId) throw new Error('Not authenticated');

	// elevation_m and title are not columns on `runs` (elevation_m lives on
	// `routes`; title has no DB column). Merge both into metadata so they
	// survive the round-trip. See docs/metadata.md for the registered keys.
	const mergedMetadata: Record<string, unknown> = { ...(input.metadata ?? {}) };
	if (input.title) mergedMetadata.title = input.title;
	if (input.elevation_m != null) mergedMetadata.elevation_m = input.elevation_m;
	const row: Record<string, unknown> = {
		user_id: userId,
		started_at: input.started_at,
		distance_m: input.distance_m,
		duration_s: input.duration_s,
		source: input.source,
		metadata: mergedMetadata,
	};

	const { data, error } = await supabase
		.from('runs')
		.insert(row)
		.select('id')
		.single();
	if (error) throw error;
	const runId = data.id as string;

	// Track upload runs as a separate transaction (no DB-level FK between
	// the row and the storage object). When it fails the scalar run row
	// is still valid — the readers (web, mobile) treat a null
	// `track_url` as "no track" and render fine. We surface the failure
	// to the caller so importers can report "X imported with tracks,
	// Y scalar-only" and interactive callers can show a toast +
	// retry button instead of silently shipping a GPS-less run.
	let trackUploaded = false;
	let trackError: string | undefined;
	if (input.track && input.track.length >= 2) {
		try {
			const path = `${userId}/${runId}.json.gz`;
			const encoded = new TextEncoder().encode(JSON.stringify(input.track));
			const gzipped = await gzipBytes(encoded);
			const { error: upErr } = await supabase.storage
				.from('runs')
				.upload(path, new Blob([gzipped as BlobPart], { type: 'application/gzip' }), {
					contentType: 'application/gzip',
					upsert: true,
				});
			if (upErr) {
				trackError = upErr.message;
			} else {
				const { error: linkErr } = await supabase
					.from('runs')
					.update({ track_url: path })
					.eq('id', runId);
				if (linkErr) {
					trackError = linkErr.message;
				} else {
					trackUploaded = true;
				}
			}
		} catch (e) {
			trackError = e instanceof Error ? e.message : String(e);
		}
	}

	return { id: runId, trackUploaded, trackError };
}

async function gzipBytes(data: Uint8Array): Promise<Uint8Array> {
	const cs = new (globalThis as any).CompressionStream('gzip');
	// TS 6 widened Uint8Array.buffer to ArrayBufferLike; Response()
	// wants BodyInit which excludes SharedArrayBuffer-backed views.
	// Cast is safe because data is always backed by a real ArrayBuffer.
	const stream = new Response(data as BodyInit).body!.pipeThrough(cs);
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

export async function updateRunMetadata(
	id: string,
	fields: { title?: string; notes?: string },
): Promise<void> {
	const { data: run } = await supabase
		.from('runs')
		.select('metadata')
		.eq('id', id)
		.single();
	if (!run) throw new Error('Run not found');
	const metadata = {
		...(run.metadata as Record<string, unknown> ?? {}),
		...fields,
		last_modified_at: new Date().toISOString(),
	};
	const { error } = await supabase
		.from('runs')
		.update({ metadata })
		.eq('id', id);
	if (error) throw error;
}

// --- Route reviews ---

export async function getRouteReviews(routeId: string, limit = 100) {
	const { data, error } = await supabase
		.from('route_reviews')
		.select('*')
		.eq('route_id', routeId)
		.order('created_at', { ascending: false })
		.limit(limit);
	if (error) throw error;
	return data ?? [];
}

export async function upsertRouteReview(review: {
	route_id: string;
	rating: number;
	comment?: string | null;
}): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase.from('route_reviews').upsert(
		{ ...review, user_id: userId },
		{ onConflict: 'route_id,user_id' },
	);
	if (error) throw error;
}

// --- Routes ---

export async function nearbyPublicRoutes(options: {
	lat: number;
	lng: number;
	radiusM?: number;
	limit?: number;
}): Promise<Route[]> {
	const { lat, lng, radiusM = 50000, limit = 50 } = options;
	const { data, error } = await supabase.rpc('nearby_routes', {
		lat,
		lng,
		radius_m: radiusM,
		max_results: limit,
	});
	if (error || !data) return [];
	return data as Route[];
}

export async function searchPublicRoutes(options?: {
	query?: string;
	minDistanceM?: number;
	maxDistanceM?: number;
	surface?: string;
	tags?: string[];
	featuredOnly?: boolean;
	sort?: 'newest' | 'popular' | 'featured';
	limit?: number;
	offset?: number;
}): Promise<Route[]> {
	const {
		query,
		minDistanceM,
		maxDistanceM,
		surface,
		tags,
		featuredOnly,
		sort = 'newest',
		limit = 50,
		offset = 0,
	} = options ?? {};

	const { data, error } = await supabase.rpc('search_public_routes', {
		p_query: query && query.trim() ? query.trim() : null,
		p_min_distance_m: minDistanceM ?? null,
		p_max_distance_m: maxDistanceM ?? null,
		p_surface: surface ?? null,
		p_tags: tags && tags.length > 0 ? tags : null,
		p_featured_only: featuredOnly ?? false,
		p_sort: sort,
		p_limit: limit,
		p_offset: offset,
	});
	if (error || !data) return [];
	return data as Route[];
}

/// The set of tags currently used across any public route, ordered by
/// most-used. Powers the filter chip row on /explore. Aggregation is
/// client-side because a single SELECT returns a small array per row
/// and the route count is modest; when the library grows past a few
/// thousand public routes, replace this with a DB-side materialised
/// view.
export async function fetchPopularRouteTags(limit = 20): Promise<string[]> {
	const { data } = await supabase
		.from('routes')
		.select('tags')
		.eq('is_public', true)
		.limit(500);
	if (!data) return [];
	const counts = new Map<string, number>();
	for (const row of data as { tags: string[] | null }[]) {
		for (const t of row.tags ?? []) {
			counts.set(t, (counts.get(t) ?? 0) + 1);
		}
	}
	return [...counts.entries()]
		.sort((a, b) => b[1] - a[1])
		.slice(0, limit)
		.map(([t]) => t);
}

export async function updateRouteTags(routeId: string, tags: string[]): Promise<void> {
	const { error } = await supabase
		.from('routes')
		.update({ tags, updated_at: new Date().toISOString() })
		.eq('id', routeId);
	if (error) throw error;
}

/// Toggle the star/favorite flag on a route. Starred routes are what
/// the watch fetches at run prep time — curating here surfaces the
/// runner's training rotation on a 1.4-inch picker that can't show
/// 30+ entries comfortably.
export async function setRouteStar(routeId: string, starred: boolean): Promise<void> {
	const { error } = await supabase
		.from('routes')
		.update({ is_starred: starred, updated_at: new Date().toISOString() })
		.eq('id', routeId);
	if (error) throw error;
}

export async function fetchRoutes(): Promise<Route[]> {
	const result = await fetchRoutesWithError();
	return result.routes;
}

/// Same as `fetchRoutes` but returns the error message alongside the
/// rows. Callers that want to surface a failure to the user (rather
/// than silently rendering an empty state — which is indistinguishable
/// from "user has no routes") use this variant.
///
/// "My routes" is the union of routes the user uploaded (`user_id = me`)
/// and routes they've bookmarked (`saved_routes.user_id = me`). Each is
/// fetched in parallel and merged with a Set on `id` so a user who saves
/// their own route doesn't see it twice.
export async function fetchRoutesWithError(): Promise<{ routes: Route[]; error: string | null }> {
	// Read the session via `getSession()` — synchronous-ish from local
	// storage, doesn't round-trip to /auth/v1/user, and works the
	// instant the supabase-js client has initialised. Falls back to
	// just running the query and letting RLS decide if no session is
	// found, since the user might be in the brief hydration window.
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;

	if (!userId) {
		return { routes: [], error: 'Not signed in — sign in to see your saved routes.' };
	}

	const [ownedRes, savedRes] = await Promise.all([
		supabase
			.from('routes')
			.select('*')
			.eq('user_id', userId)
			.order('created_at', { ascending: false }),
		supabase
			.from('saved_routes')
			.select('saved_at, route:routes(*)')
			.eq('user_id', userId)
			.order('saved_at', { ascending: false }),
	]);

	if (ownedRes.error) {
		console.error('fetchRoutes (owned) failed', ownedRes.error);
		return {
			routes: [],
			error: `${ownedRes.error.message}${ownedRes.error.code ? ` (${ownedRes.error.code})` : ''}`,
		};
	}

	const owned = (ownedRes.data ?? []) as Route[];
	const saved = ((savedRes.data ?? []) as unknown as { route: Route | null }[])
		.map(r => r.route)
		.filter((r): r is Route => r != null);

	const seen = new Set<string>();
	const merged: Route[] = [];
	for (const r of [...owned, ...saved]) {
		if (seen.has(r.id)) continue;
		seen.add(r.id);
		merged.push(r);
	}
	return { routes: merged, error: null };
}

/// Routes owned by a club (`routes.club_id = clubId`). Read-gated by
/// RLS to club members; admin-write-gated for transfers/edits. Used by
/// the club home Routes tab and by EventEditor's route picker.
export async function fetchClubRoutes(clubId: string): Promise<Route[]> {
	const { data, error } = await supabase
		.from('routes')
		.select('*')
		.eq('club_id', clubId)
		.order('created_at', { ascending: false });
	if (error) {
		console.error('fetchClubRoutes failed', error);
		return [];
	}
	return data ?? [];
}

/// Bookmark a public route. Inserts a `saved_routes` reference rather
/// than cloning the row — see decisions.md § 30.
export async function bookmarkRoute(routeId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from('saved_routes')
		.insert({ user_id: userId, route_id: routeId });
	// Treat duplicate (already saved) as a no-op.
	if (error && error.code !== '23505') throw error;
}

export async function unbookmarkRoute(routeId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from('saved_routes')
		.delete()
		.eq('user_id', userId)
		.eq('route_id', routeId);
	if (error) throw error;
}

/// Transfer a personal route into club ownership (admins only) — or
/// back out (`clubId = null`). Server-side RLS enforces that only
/// admins of the target club may set `club_id`.
export async function setRouteClubId(routeId: string, clubId: string | null): Promise<void> {
	const { error } = await supabase
		.from('routes')
		.update({ club_id: clubId, updated_at: new Date().toISOString() })
		.eq('id', routeId);
	if (error) throw error;
}

/// Read a route by id. Owners and active club members get the full
/// `routes` row directly (RLS allows it). Anon and non-owner /
/// non-club-member callers read the redacted metadata from the
/// `public_routes` view and assemble a `Route` with server-clipped
/// waypoints from `clip_route_for_viewer`. Non-owners never see
/// unclipped polyline / `geom` / `start_point` on the wire — closes
/// the audit/public-rows + audit/privacy-zones High finding.
export async function fetchRouteById(id: string): Promise<Route | null> {
	const ownerRead = await supabase
		.from('routes')
		.select('*')
		.eq('id', id)
		.maybeSingle();
	if (ownerRead.data) return ownerRead.data;

	const meta = await supabase
		.from('public_routes')
		.select('*')
		.eq('id', id)
		.maybeSingle();
	if (!meta.data) return null;

	const clipped = await fetchClippedRouteForViewer(id);
	// public_routes intentionally omits `waypoints`, `geom`, `start_point`,
	// and `is_starred`; pad them out so downstream consumers that read
	// these keys still get a defined shape (empty arrays / nulls).
	return {
		...meta.data,
		waypoints: clipped,
		is_starred: false,
	} as Route;
}

/// Public-share read path. Same redaction shape as `fetchRouteById`'s
/// non-owner branch — kept as a separate export so call sites that
/// only ever intend to read a public route stay explicit.
export async function fetchPublicRoute(id: string): Promise<Route | null> {
	const { data } = await supabase
		.from('public_routes')
		.select('*')
		.eq('id', id)
		.maybeSingle();
	if (!data) return null;
	const clipped = await fetchClippedRouteForViewer(id);
	return {
		...data,
		waypoints: clipped,
		is_starred: false,
	} as Route;
}

export async function saveRoute(route: {
	name: string;
	waypoints: { lat: number; lng: number }[];
	distance_m: number;
	elevation_m: number | null;
	surface: 'road' | 'trail' | 'mixed';
	is_public: boolean;
	club_id?: string | null;
}): Promise<Route> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const { data, error } = await supabase
		.from('routes')
		.insert({
			user_id: userId,
			name: route.name,
			waypoints: route.waypoints,
			distance_m: route.distance_m,
			elevation_m: route.elevation_m,
			surface: route.surface,
			is_public: route.is_public,
			club_id: route.club_id ?? null,
		})
		.select()
		.single();

	if (error) throw error;
	return data;
}

export async function deleteRoute(id: string): Promise<void> {
	const { error } = await supabase.from('routes').delete().eq('id', id);
	if (error) throw error;
}

// --- Dashboard stats ---

export async function fetchWeeklyMileage() {
	const { data: { user } } = await supabase.auth.getUser();
	if (!user) return [];
	const { data: runs } = await supabase
		.from('runs')
		.select('started_at, distance_m')
		.eq('user_id', user.id)
		.order('started_at', { ascending: true })
		.limit(2000);

	if (!runs || runs.length === 0) return [];

	// Group by ISO week. Keep distance in metres so render-time
	// formatting can honor the user's preferred unit.
	const weeks = new Map<string, number>();
	for (const run of runs) {
		const d = new Date(run.started_at);
		const weekStart = new Date(d);
		weekStart.setDate(d.getDate() - ((d.getDay() + 6) % 7)); // Monday-start, matches goals.ts
		const key = weekStart.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
		weeks.set(key, (weeks.get(key) ?? 0) + run.distance_m);
	}

	return Array.from(weeks.entries())
		.slice(-12)
		.map(([week, distance_m]) => ({ week, distance_m: Math.round(distance_m) }));
}

export async function fetchPersonalRecords() {
	// Read the trigger-maintained `personal_records` cache rather than
	// recomputing from `runs`. The cache is already user-scoped by RLS,
	// but we add an explicit `auth.user.id` filter as defence in depth
	// — every other personal-data query in this file does the same, and
	// silently relying on RLS for the canonical read path is fragile if
	// a future policy edit slips. See migration 20260508_001.
	const userId = auth.user?.id;
	if (!userId) return [];

	const { data } = await supabase
		.from('personal_records')
		.select('distance, best_time_s, achieved_at')
		.eq('user_id', userId);

	if (!data || data.length === 0) return [];

	const labels: Record<string, string> = {
		'5k': '5k',
		'10k': '10k',
		half_marathon: 'Half Marathon',
		marathon: 'Marathon',
	};
	const order: Record<string, number> = { '5k': 0, '10k': 1, half_marathon: 2, marathon: 3 };

	return data
		.slice()
		.sort((a, b) => (order[a.distance] ?? 99) - (order[b.distance] ?? 99))
		.map((r) => ({
			distance: labels[r.distance] ?? r.distance,
			time_s: r.best_time_s,
			date: r.achieved_at.slice(0, 10),
		}));
}

// --- Integrations ---

export async function fetchIntegrations(): Promise<Integration[]> {
	const userId = auth.user?.id;
	if (!userId) return [];

	const { data } = await supabase
		.from('integrations')
		.select('*')
		.eq('user_id', userId);

	return data ?? [];
}

export async function connectIntegration(provider: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const { error } = await supabase.from('integrations').upsert(
		{ user_id: userId, provider },
		{ onConflict: 'user_id,provider' }
	);
	if (error) throw error;
}

export async function disconnectIntegration(provider: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const { error } = await supabase
		.from('integrations')
		.delete()
		.eq('user_id', userId)
		.eq('provider', provider);
	if (error) throw error;
}

// --- Clubs ---

// Column-level grant lockdown: `invite_token` is revoked from anon +
// authenticated (migration 20260801_001 + 20260818_001 redo). Selecting
// `*` raises 42501. Every read enumerates these safe columns; admin
// reads of `invite_token` go through the SECURITY DEFINER RPC
// `get_club_invite_token`. The arch-guard test
// `tests-e2e/cross-cutting/select-star-discipline.spec.ts` greps to
// keep this in lockstep.
// `as const` on a single-line literal — supabase-js's `.select(<cols>)`
// type-level parser needs a string-literal type to infer the row shape,
// not the `string` widening that `'a' + 'b'` concatenation produces.
// Without `as const`, every `.from('clubs').select(CLUB_SELECT_COLS)`
// falls back to `GenericStringError` and downstream type assertions
// fail svelte-check.
const CLUB_SELECT_COLS =
	'id, owner_id, name, slug, description, avatar_url, location_label, is_public, join_policy, created_at, updated_at' as const;

// Column-level grant lockdown: `meet_lat` / `meet_lng` are revoked
// from anon + authenticated (migrations 20260723_001 + 20260806_001 +
// 20260818_001 redo). Selecting `*` raises 42501. Every read
// enumerates these safe columns; the two coords are write-only
// today (no UI consumer).
const EVENT_SELECT_COLS =
	'id, club_id, title, description, starts_at, duration_min, meet_label, route_id, distance_m, pace_target_sec, capacity, created_by, created_at, updated_at, recurrence_freq, recurrence_byday, recurrence_until, recurrence_count' as const;

function slugify(name: string): string {
	return name
		.toLowerCase()
		.trim()
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-|-$/g, '')
		.slice(0, 48);
}

/** Browse public clubs. Most recently created first. */
export async function browseClubs(search?: string): Promise<ClubWithMeta[]> {
	let query = supabase.from('clubs').select(CLUB_SELECT_COLS).eq('is_public', true);
	if (search && search.trim()) {
		const term = search.trim();
		query = query.or(`name.ilike.%${term}%,location_label.ilike.%${term}%`);
	}
	const { data } = await query.order('created_at', { ascending: false }).limit(60);
	if (!data) return [];
	return enrichClubs(data);
}

/** Clubs the current user belongs to (owner or member). */
export async function fetchMyClubs(): Promise<ClubWithMeta[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data } = await supabase
		.from('club_members')
		.select(`club_id, role, clubs!inner(${CLUB_SELECT_COLS})`)
		.eq('user_id', userId)
		.order('joined_at', { ascending: false });
	if (!data) return [];
	const clubs = data.map((row: any) => row.clubs).filter(Boolean);
	return enrichClubs(clubs);
}

export async function fetchClubBySlug(slug: string): Promise<ClubWithMeta | null> {
	const { data } = await supabase.from('clubs').select(CLUB_SELECT_COLS).eq('slug', slug).maybeSingle();
	if (!data) return null;
	const [enriched] = await enrichClubs([data]);
	if (!enriched) return null;
	if (enriched.viewer_role === 'owner' || enriched.viewer_role === 'admin') {
		const { data: token } = await supabase.rpc('get_club_invite_token', {
			target_club: enriched.id
		});
		return { ...enriched, invite_token: (token as string | null) ?? null };
	}
	return enriched;
}

/** Attach member_count + viewer_role + viewer_status to clubs in two queries. */
async function enrichClubs(clubs: Club[]): Promise<ClubWithMeta[]> {
	if (clubs.length === 0) return [];
	const ids = clubs.map((c) => c.id);
	const userId = auth.user?.id;

	const [countsRes, rolesRes] = await Promise.all([
		supabase
			.from('club_members')
			.select('club_id', { count: 'exact' })
			.in('club_id', ids)
			.eq('status', 'active'),
		userId
			? supabase
					.from('club_members')
					.select('club_id, role, status')
					.in('club_id', ids)
					.eq('user_id', userId)
			: Promise.resolve({ data: [] as { club_id: string; role: string; status: string }[] })
	]);

	const counts = new Map<string, number>();
	for (const row of (countsRes.data ?? []) as { club_id: string }[]) {
		counts.set(row.club_id, (counts.get(row.club_id) ?? 0) + 1);
	}
	const roles = new Map<string, ClubRole>();
	const statuses = new Map<string, MembershipStatus>();
	for (const row of (rolesRes.data ?? []) as { club_id: string; role: string; status: string }[]) {
		if (row.status === 'active') roles.set(row.club_id, row.role as ClubRole);
		statuses.set(row.club_id, row.status as MembershipStatus);
	}
	return clubs.map((c) => ({
		...c,
		join_policy: (c.join_policy ?? 'open') as JoinPolicy,
		member_count: counts.get(c.id) ?? 0,
		viewer_role: roles.get(c.id) ?? null,
		viewer_status: statuses.get(c.id) ?? null
	}));
}

export async function createClub(input: {
	name: string;
	description?: string;
	location_label?: string;
	is_public: boolean;
	join_policy: JoinPolicy;
}): Promise<Club & { invite_token: string | null }> {
	// invite_token is excluded from the base Club shape (column-grant
	// lockdown) but createClub knows the freshly-generated token —
	// decorate the return so callers can display the share link
	// immediately without a separate get_club_invite_token RPC.
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const baseSlug = slugify(input.name) || 'club';
	const inviteToken = input.join_policy === 'invite' ? genToken() : null;
	// Retry with a short random suffix up to 3 times if the slug is taken —
	// simpler than a SQL trigger and acceptable for the expected volume.
	for (let attempt = 0; attempt < 4; attempt++) {
		const candidate =
			attempt === 0 ? baseSlug : `${baseSlug}-${Math.random().toString(36).slice(2, 6)}`;
		const { data, error } = await supabase
			.from('clubs')
			.insert({
				owner_id: userId,
				name: input.name.trim(),
				slug: candidate,
				description: input.description?.trim() || null,
				location_label: input.location_label?.trim() || null,
				is_public: input.is_public,
				join_policy: input.join_policy,
				invite_token: inviteToken
			})
			.select(CLUB_SELECT_COLS)
			.single();
		if (!error && data) {
			return {
				...data,
				invite_token: inviteToken,
				join_policy: (data.join_policy ?? 'open') as JoinPolicy
			};
		}
		if (error && error.code !== '23505') throw error;
	}
	throw new Error(`Could not allocate a slug for "${input.name}" after 4 attempts`);
}

function genToken(): string {
	const bytes = new Uint8Array(16);
	crypto.getRandomValues(bytes);
	return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export async function regenerateInviteToken(clubId: string): Promise<string> {
	const token = genToken();
	const { error } = await supabase.from('clubs').update({ invite_token: token }).eq('id', clubId);
	if (error) throw error;
	return token;
}

export async function updateClub(
	id: string,
	patch: Partial<Pick<Club, 'name' | 'description' | 'location_label' | 'is_public' | 'avatar_url'>>
): Promise<void> {
	const { error } = await supabase.from('clubs').update(patch).eq('id', id);
	if (error) throw error;
}

export async function deleteClub(id: string): Promise<void> {
	const { error } = await supabase.from('clubs').delete().eq('id', id);
	if (error) throw error;
}

export async function joinClub(clubId: string, policy: JoinPolicy = 'open'): Promise<MembershipStatus> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const status: MembershipStatus = policy === 'request' ? 'pending' : 'active';
	const { error } = await supabase
		.from('club_members')
		.insert({ club_id: clubId, user_id: userId, role: 'member', status });
	if (error && error.code !== '23505') throw error;
	return status;
}

/** Redeem a shareable invite token. Returns the joined club id. */
export async function joinClubByToken(token: string): Promise<string> {
	const { data, error } = await supabase.rpc('join_club_by_token', { token });
	if (error) throw error;
	return data as string;
}

export async function fetchPendingRequests(clubId: string): Promise<(ClubMember & {
	display_name: string | null;
	avatar_url: string | null;
})[]> {
	const { data: rows } = await supabase
		.from('club_members')
		.select('*')
		.eq('club_id', clubId)
		.eq('status', 'pending')
		.order('joined_at', { ascending: true });
	if (!rows || rows.length === 0) return [];
	const userIds = (rows as ClubMember[]).map((r) => r.user_id);
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', userIds);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profiles ?? []) byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	return (rows as ClubMember[]).map((r) => ({
		...r,
		display_name: byId.get(r.user_id)?.display_name ?? null,
		avatar_url: byId.get(r.user_id)?.avatar_url ?? null
	}));
}

export async function approveMember(clubId: string, userId: string): Promise<void> {
	const { error } = await supabase
		.from('club_members')
		.update({ status: 'active' })
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw error;
}

export async function setMemberRole(
	clubId: string,
	userId: string,
	role: 'admin' | 'event_organiser' | 'race_director' | 'member'
): Promise<void> {
	const { error } = await supabase
		.from('club_members')
		.update({ role })
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw error;
}

export async function rejectMember(clubId: string, userId: string): Promise<void> {
	const { error } = await supabase
		.from('club_members')
		.delete()
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw error;
}

/// Admin-only: remove an active member from a club. Mechanically a
/// duplicate of rejectMember (both delete the row, both rely on the
/// `admins can manage members` RLS policy), but kept as a separate
/// export so the calling UI can speak in terms of intent — the
/// "kick a member" affordance lives next to the role selector on
/// the Members tab; the "reject a request" affordance lives on the
/// pending-requests admin panel. Either RLS check or the trigger
/// rejecting an owner-row delete will block a misuse.
export async function removeMember(clubId: string, userId: string): Promise<void> {
	const { error } = await supabase
		.from('club_members')
		.delete()
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw error;
}

export async function leaveClub(clubId: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from('club_members')
		.delete()
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw error;
}

export async function fetchClubMembers(clubId: string): Promise<(ClubMember & {
	display_name: string | null;
	avatar_url: string | null;
})[]> {
	const { data: members } = await supabase
		.from('club_members')
		.select('*')
		.eq('club_id', clubId)
		.order('joined_at', { ascending: true });
	if (!members) return [];
	const userIds = (members as ClubMember[]).map((m) => m.user_id);
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', userIds);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profiles ?? []) byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	return (members as ClubMember[]).map((m) => ({
		...m,
		display_name: byId.get(m.user_id)?.display_name ?? null,
		avatar_url: byId.get(m.user_id)?.avatar_url ?? null
	}));
}

// --- Events ---

/// The next event the signed-in user has RSVP'd `going` to within the
/// given window. Returns null when nothing matches — the dashboard
/// card hides itself.
///
/// Mirrors `SocialService.fetchNextRsvpedEvent` on Android so both
/// surfaces show the same card at the same moment in time.
export async function fetchNextRsvpedEvent(
	windowHours = 48,
): Promise<{
	event_id: string;
	instance_start: string;
	club_slug: string;
	title: string;
	meet_label: string | null;
} | null> {
	const { data: { user } } = await supabase.auth.getUser();
	if (!user) return null;
	const now = new Date();
	const horizon = new Date(now.getTime() + windowHours * 3600_000);
	const { data } = await supabase
		.from('event_attendees')
		.select(
			'event_id, instance_start, events(title, meet_label, clubs(slug))',
		)
		.eq('user_id', user.id)
		.eq('status', 'going')
		.gte('instance_start', now.toISOString())
		.lte('instance_start', horizon.toISOString())
		.order('instance_start', { ascending: true })
		.limit(1);
	const row = (data as Array<Record<string, unknown>> | null)?.[0];
	if (!row) return null;
	const ev = row.events as
		| { title: string; meet_label: string | null; clubs: { slug: string } }
		| null;
	if (!ev) return null;
	return {
		event_id: row.event_id as string,
		instance_start: row.instance_start as string,
		club_slug: ev.clubs.slug,
		title: ev.title,
		meet_label: ev.meet_label ?? null,
	};
}

export async function fetchUpcomingEvents(clubId: string): Promise<EventWithMeta[]> {
	// For recurring series, `starts_at` can be in the past even though the
	// next instance is in the future. Pull anything that's either (a) one-off
	// in the future OR (b) recurring with an until-date that's still ahead.
	// The client-side enrichment computes `next_instance_start` per event.
	// Cap at 200 — busy clubs accumulate event history but the upcoming-set
	// of interest is far smaller; the client filter discards the rest.
	const { data } = await supabase
		.from('events')
		.select(EVENT_SELECT_COLS)
		.eq('club_id', clubId)
		.order('starts_at', { ascending: true })
		.limit(200);
	const events = (data as Event[]) ?? [];
	const now = new Date();
	const enriched = await enrichEvents(events);
	return enriched
		.filter((e) => new Date(e.next_instance_start) >= now)
		.sort(
			(a, b) =>
				new Date(a.next_instance_start).getTime() - new Date(b.next_instance_start).getTime()
		);
}

export async function fetchPastEvents(clubId: string, limit = 12): Promise<EventWithMeta[]> {
	const nowIso = new Date().toISOString();
	const { data } = await supabase
		.from('events')
		.select(EVENT_SELECT_COLS)
		.eq('club_id', clubId)
		.lt('starts_at', nowIso)
		.order('starts_at', { ascending: false })
		.limit(limit);
	return enrichEvents((data as Event[]) ?? []);
}

export async function fetchEventById(id: string): Promise<EventWithMeta | null> {
	const { data } = await supabase.from('events').select(EVENT_SELECT_COLS).eq('id', id).maybeSingle();
	if (!data) return null;
	const [enriched] = await enrichEvents([data as Event]);
	return enriched ?? null;
}

async function enrichEvents(events: Event[]): Promise<EventWithMeta[]> {
	if (events.length === 0) return [];

	// Compute each event's next instance client-side so counts + RSVPs can be
	// scoped to that instance. One-off events use their starts_at verbatim.
	const nextMap = new Map<string, string>();
	for (const e of events) {
		const evt = normaliseEvent(e);
		const next = evt.recurrence_freq ? nextInstanceAfter(evt) ?? new Date(evt.starts_at) : new Date(evt.starts_at);
		nextMap.set(e.id, next.toISOString());
	}

	const ids = events.map((e) => e.id);
	const userId = auth.user?.id;

	// "Going" count on the next instance of each event.
	const countsPromise: Promise<Array<[string, number]>> = Promise.all(
		ids.map(
			(id) =>
				supabase
					.from('event_attendees')
					.select('event_id', { count: 'exact' })
					.eq('event_id', id)
					.eq('status', 'going')
					.eq('instance_start', nextMap.get(id) as string)
					.then((res) => [id, res.count ?? 0] as [string, number])
		)
	);
	const rsvpPromise: Promise<Array<[string, RsvpStatus | null]>> = userId
		? Promise.all(
				ids.map(
					(id) =>
						supabase
							.from('event_attendees')
							.select('status')
							.eq('event_id', id)
							.eq('user_id', userId)
							.eq('instance_start', nextMap.get(id) as string)
							.maybeSingle()
							.then(
								(res) => [id, (res.data?.status ?? null) as RsvpStatus | null] as [
									string,
									RsvpStatus | null
								]
						)
				)
		  )
		: Promise.resolve([] as Array<[string, RsvpStatus | null]>);

	const [countRows, rsvpRows] = await Promise.all([countsPromise, rsvpPromise]);
	const counts = new Map<string, number>(countRows);
	const rsvps = new Map<string, RsvpStatus | null>(rsvpRows);

	return events.map((e) => ({
		...normaliseEvent(e),
		attendee_count: counts.get(e.id) ?? 0,
		viewer_rsvp: rsvps.get(e.id) ?? null,
		next_instance_start: nextMap.get(e.id)!
	}));
}

/** Coerce server-side string[]/string into typed unions. */
function normaliseEvent(e: Event): Event {
	return {
		...e,
		recurrence_freq: (e.recurrence_freq ?? null) as RecurrenceFreq | null,
		recurrence_byday: (e.recurrence_byday ?? null) as Weekday[] | null
	};
}

export async function createEvent(input: {
	club_id: string;
	title: string;
	description?: string;
	starts_at: string; // ISO
	duration_min?: number;
	meet_label?: string;
	meet_lat?: number;
	meet_lng?: number;
	route_id?: string | null;
	distance_m?: number;
	pace_target_sec?: number;
	capacity?: number;
	recurrence_freq?: RecurrenceFreq | null;
	recurrence_byday?: Weekday[] | null;
	recurrence_until?: string | null;
	recurrence_count?: number | null;
}): Promise<Event> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('events')
		.insert({
			club_id: input.club_id,
			title: input.title.trim(),
			description: input.description?.trim() || null,
			starts_at: input.starts_at,
			duration_min: input.duration_min ?? null,
			meet_label: input.meet_label?.trim() || null,
			meet_lat: input.meet_lat ?? null,
			meet_lng: input.meet_lng ?? null,
			route_id: input.route_id ?? null,
			distance_m: input.distance_m ?? null,
			pace_target_sec: input.pace_target_sec ?? null,
			capacity: input.capacity ?? null,
			recurrence_freq: input.recurrence_freq ?? null,
			recurrence_byday: input.recurrence_byday ?? null,
			recurrence_until: input.recurrence_until ?? null,
			recurrence_count: input.recurrence_count ?? null,
			created_by: userId
		})
		.select(EVENT_SELECT_COLS)
		.single();
	if (error) throw error;
	return normaliseEvent(data as Event);
}

export async function deleteEvent(id: string): Promise<void> {
	const { error } = await supabase.from('events').delete().eq('id', id);
	if (error) throw error;
}

export async function rsvpEvent(
	eventId: string,
	status: RsvpStatus,
	instanceStart: string
): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from('event_attendees')
		.upsert(
			{ event_id: eventId, user_id: userId, status, instance_start: instanceStart },
			{ onConflict: 'event_id,user_id,instance_start' }
		);
	if (error) throw error;
}

export async function clearRsvp(eventId: string, instanceStart: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from('event_attendees')
		.delete()
		.eq('event_id', eventId)
		.eq('user_id', userId)
		.eq('instance_start', instanceStart);
	if (error) throw error;
}

export async function fetchEventAttendees(
	eventId: string,
	instanceStart: string
): Promise<(EventAttendee & {
	display_name: string | null;
	avatar_url: string | null;
})[]> {
	const { data: attendees } = await supabase
		.from('event_attendees')
		.select('*')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.order('joined_at', { ascending: true });
	if (!attendees) return [];
	const userIds = (attendees as EventAttendee[]).map((a) => a.user_id);
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', userIds);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profiles ?? []) byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	return (attendees as EventAttendee[]).map((a) => ({
		...a,
		display_name: byId.get(a.user_id)?.display_name ?? null,
		avatar_url: byId.get(a.user_id)?.avatar_url ?? null
	}));
}

// --- Event results (leaderboard) ---

export interface EventResultRow {
	user_id: string;
	run_id: string | null;
	duration_s: number;
	distance_m: number;
	rank: number | null;
	finisher_status: 'finished' | 'dnf' | 'dns';
	age_grade_pct: number | null;
	note: string | null;
	created_at: string;
	organiser_approved: boolean;
	// organiser_approved_by / organiser_approved_at are admin-side
	// columns; intentionally omitted from `fetchEventResults`'s public
	// read path. Add them back via a service-role-only fetcher if/when
	// an admin moderation UI needs them.
}

export interface EventResultWithUser extends EventResultRow {
	display_name: string | null;
	avatar_url: string | null;
}

export async function fetchEventResults(
	eventId: string,
	instanceStart: string
): Promise<EventResultWithUser[]> {
	// Don't request organiser_approved_by / organiser_approved_at on
	// the public read path — those are admin-operational fields with
	// no UI consumer here. The boolean `organiser_approved` is what
	// the leaderboard actually shows. Audit pass 3 caught the wider
	// projection leaking the approving admin's UUID to anon.
	//
	// Read from the redaction view rather than the base table —
	// `event_results_redacted` nulls `run_id` for non-owner rows so
	// the public leaderboard can't bridge to a participant's private
	// run via the linked run_id. (Migration 20260805_001.)
	const { data: results } = await supabase
		.from('event_results_redacted')
		.select(
			'user_id, run_id, duration_s, distance_m, rank, finisher_status, age_grade_pct, note, created_at, organiser_approved'
		)
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.order('rank', { ascending: true, nullsFirst: false })
		.order('created_at', { ascending: true });
	if (!results) return [];
	const rows = results as EventResultRow[];
	if (rows.length === 0) return [];
	const userIds = rows.map((r) => r.user_id);
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', userIds);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profiles ?? [])
		byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	return rows.map((r) => ({
		...r,
		display_name: byId.get(r.user_id)?.display_name ?? null,
		avatar_url: byId.get(r.user_id)?.avatar_url ?? null,
	}));
}

export async function submitEventResult(params: {
	eventId: string;
	instanceStart: string;
	durationS: number;
	distanceM: number;
	runId?: string | null;
	finisherStatus?: 'finished' | 'dnf' | 'dns';
	ageGradePct?: number | null;
	note?: string | null;
}): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase.from('event_results').upsert(
		{
			event_id: params.eventId,
			instance_start: params.instanceStart,
			user_id: userId,
			run_id: params.runId ?? null,
			duration_s: params.durationS,
			distance_m: params.distanceM,
			finisher_status: params.finisherStatus ?? 'finished',
			age_grade_pct: params.ageGradePct ?? null,
			note: params.note ?? null,
			updated_at: new Date().toISOString(),
		},
		{ onConflict: 'event_id,instance_start,user_id' }
	);
	if (error) throw error;
	// Best-effort back-link so the run-detail page can show "ran at {event}".
	if (params.runId) {
		await supabase
			.from('runs')
			.update({ event_id: params.eventId })
			.eq('id', params.runId)
			.eq('user_id', userId);
	}
}

export async function removeEventResult(
	eventId: string,
	instanceStart: string
): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from('event_results')
		.delete()
		.eq('event_id', eventId)
		.eq('user_id', userId)
		.eq('instance_start', instanceStart);
	if (error) throw error;
}

export interface RecentRunOption {
	id: string;
	started_at: string;
	duration_s: number;
	distance_m: number;
	activity_type: string;
}

export async function fetchRecentRunsForPicker(limit = 20): Promise<RecentRunOption[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data } = await supabase
		.from('runs')
		.select('id, started_at, duration_s, distance_m, metadata')
		.eq('user_id', userId)
		.order('started_at', { ascending: false })
		.limit(limit);
	if (!data) return [];
	return data.map((r) => ({
		id: r.id,
		started_at: r.started_at,
		duration_s: r.duration_s,
		distance_m: r.distance_m,
		activity_type:
			(r.metadata && typeof r.metadata === 'object' && 'activity_type' in r.metadata
				? ((r.metadata as Record<string, unknown>).activity_type as string)
				: null) ?? 'run',
	}));
}

// --- Race sessions (live race mode) ---

export interface RaceSessionRow {
	event_id: string;
	instance_start: string;
	status: 'armed' | 'running' | 'finished' | 'cancelled';
	started_at: string | null;
	started_by: string | null;
	finished_at: string | null;
	auto_approve: boolean;
	created_at: string;
	updated_at: string;
}

export async function fetchRaceSession(
	eventId: string,
	instanceStart: string
): Promise<RaceSessionRow | null> {
	// Read from the redaction view rather than the base table —
	// `race_sessions_redacted` masks `started_by` + `auto_approve`
	// for non-admin viewers (decisions per /audit/all 2026-05-07,
	// migration 20260813_001). Admin row-level mutations
	// (armRace / startRace / endRace) below keep writing the base
	// table so the columns reach Postgres unmasked.
	const { data } = await supabase
		.from('race_sessions_redacted')
		.select('*')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.maybeSingle();
	return (data as RaceSessionRow | null) ?? null;
}

export async function armRace(
	eventId: string,
	instanceStart: string,
	autoApprove: boolean
): Promise<RaceSessionRow> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('race_sessions')
		.upsert(
			{
				event_id: eventId,
				instance_start: instanceStart,
				status: 'armed',
				started_at: null,
				started_by: null,
				finished_at: null,
				auto_approve: autoApprove,
				updated_at: new Date().toISOString(),
			},
			{ onConflict: 'event_id,instance_start' }
		)
		.select()
		.single();
	if (error) throw error;
	return data as RaceSessionRow;
}

export async function startRace(
	eventId: string,
	instanceStart: string
): Promise<RaceSessionRow> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('race_sessions')
		.update({
			status: 'running',
			started_at: new Date().toISOString(),
			started_by: userId,
			updated_at: new Date().toISOString(),
		})
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.select()
		.single();
	if (error) throw error;
	return data as RaceSessionRow;
}

export async function endRace(
	eventId: string,
	instanceStart: string,
	status: 'finished' | 'cancelled' = 'finished'
): Promise<RaceSessionRow> {
	const { data, error } = await supabase
		.from('race_sessions')
		.update({
			status,
			finished_at: new Date().toISOString(),
			updated_at: new Date().toISOString(),
		})
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.select()
		.single();
	if (error) throw error;
	return data as RaceSessionRow;
}

export async function approveEventResult(
	eventId: string,
	instanceStart: string,
	userId: string,
	approve: boolean
): Promise<void> {
	const { error } = await supabase.rpc('approve_event_result', {
		p_event_id: eventId,
		p_instance_start: instanceStart,
		p_user_id: userId,
		p_approve: approve,
	});
	if (error) throw error;
}

export interface RacePingRow {
	id: number;
	event_id: string;
	instance_start: string;
	user_id: string;
	at: string;
	lat: number;
	lng: number;
	distance_m: number | null;
	elapsed_s: number | null;
	bpm: number | null;
}

/// Recent pings for a race instance, newest first. The spectator page
/// derives both the leaderboard (latest per user) and per-user trails
/// from this single fetch. Capped at `limit` rows; the index on
/// (event_id, instance_start, at desc) makes this cheap.
export async function fetchRecentRacePings(
	eventId: string,
	instanceStart: string,
	limit = 1000
): Promise<RacePingRow[]> {
	const { data } = await supabase
		.from('race_pings')
		.select('*')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.order('at', { ascending: false })
		.limit(limit);
	return (data as RacePingRow[]) ?? [];
}

/// Latest ping per runner, sorted by distance descending so the lead
/// runner is first. Convenience wrapper over `fetchRecentRacePings`.
export async function fetchLatestRacePings(
	eventId: string,
	instanceStart: string
): Promise<RacePingRow[]> {
	const pings = await fetchRecentRacePings(eventId, instanceStart, 500);
	const byUser = new Map<string, RacePingRow>();
	for (const p of pings) {
		if (!byUser.has(p.user_id)) byUser.set(p.user_id, p);
	}
	return [...byUser.values()].sort(
		(a, b) => (b.distance_m ?? 0) - (a.distance_m ?? 0)
	);
}

export async function postRacePing(params: {
	eventId: string;
	instanceStart: string;
	lat: number;
	lng: number;
	distanceM?: number;
	elapsedS?: number;
	bpm?: number;
}): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase.from('race_pings').insert({
		event_id: params.eventId,
		instance_start: params.instanceStart,
		user_id: userId,
		lat: params.lat,
		lng: params.lng,
		distance_m: params.distanceM ?? null,
		elapsed_s: params.elapsedS ?? null,
		bpm: params.bpm ?? null,
	});
	if (error) throw error;
}

// --- Club posts (owner updates) ---

export async function fetchClubPosts(
	clubId: string,
	limit = 20
): Promise<ClubPostWithAuthor[]> {
	// Top-level posts only; replies are loaded lazily per-post.
	const { data: posts } = await supabase
		.from('club_posts')
		.select('*')
		.eq('club_id', clubId)
		.is('parent_post_id', null)
		.order('created_at', { ascending: false })
		.limit(limit);
	if (!posts) return [];
	return enrichPosts(posts as ClubPost[]);
}

export async function fetchPostReplies(parentId: string, limit = 200): Promise<ClubPostWithAuthor[]> {
	const { data: posts } = await supabase
		.from('club_posts')
		.select('*')
		.eq('parent_post_id', parentId)
		.order('created_at', { ascending: true })
		.limit(limit);
	if (!posts) return [];
	return enrichPosts(posts as ClubPost[]);
}

async function enrichPosts(posts: ClubPost[]): Promise<ClubPostWithAuthor[]> {
	if (posts.length === 0) return [];
	const authorIds = Array.from(new Set(posts.map((p) => p.author_id)));
	const topLevelIds = posts.filter((p) => !p.parent_post_id).map((p) => p.id);

	const [profilesRes, repliesRes] = await Promise.all([
		supabase
			.from('user_profiles')
			.select('id, display_name, avatar_url')
			.in('id', authorIds),
		topLevelIds.length > 0
			? supabase
					.from('club_posts')
					.select('parent_post_id')
					.in('parent_post_id', topLevelIds)
					.limit(5000)
			: Promise.resolve({ data: [] as { parent_post_id: string }[] })
	]);

	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profilesRes.data ?? []) byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });

	const replyCounts = new Map<string, number>();
	for (const row of (repliesRes.data ?? []) as { parent_post_id: string }[]) {
		replyCounts.set(row.parent_post_id, (replyCounts.get(row.parent_post_id) ?? 0) + 1);
	}

	return posts.map((post) => ({
		...post,
		author_display_name: byId.get(post.author_id)?.display_name ?? null,
		author_avatar_url: byId.get(post.author_id)?.avatar_url ?? null,
		reply_count: replyCounts.get(post.id) ?? 0
	}));
}

export async function createClubPost(input: {
	club_id: string;
	body: string;
	event_id?: string | null;
	event_instance_start?: string | null;
	parent_post_id?: string | null;
}): Promise<ClubPost> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('club_posts')
		.insert({
			club_id: input.club_id,
			event_id: input.event_id ?? null,
			event_instance_start: input.event_instance_start ?? null,
			parent_post_id: input.parent_post_id ?? null,
			author_id: userId,
			body: input.body.trim()
		})
		.select()
		.single();
	if (error) throw error;
	return data as ClubPost;
}

export async function deleteClubPost(id: string): Promise<void> {
	const { error } = await supabase.from('club_posts').delete().eq('id', id);
	if (error) throw error;
}

// --- Training plans ---

export async function fetchMyPlans(limit = 100): Promise<TrainingPlan[]> {
	// Templates live in the same table; filter them out of the
	// user-facing plan list (decisions §35).
	const { data } = await supabase
		.from('training_plans')
		.select('*')
		.eq('is_template', false)
		.order('created_at', { ascending: false })
		.limit(limit);
	return (data ?? []) as TrainingPlan[];
}

/// Plan templates owned by `clubId`. Visible to club members; admins
/// can write. See decisions §35.
export async function fetchClubTemplates(clubId: string, limit = 100): Promise<TrainingPlan[]> {
	const { data, error } = await supabase
		.from('training_plans')
		.select('*')
		.eq('is_template', true)
		.eq('club_id', clubId)
		.order('created_at', { ascending: false })
		.limit(limit);
	if (error) {
		console.error('fetchClubTemplates failed', error);
		return [];
	}
	return (data ?? []) as TrainingPlan[];
}

/// Clone a template into a user-owned active plan, anchored at
/// new_start_date. Returns the new plan's id; caller should navigate
/// to /plans/{id}. The RPC enforces authorisation server-side.
export async function clonePlanTemplate(
	templateId: string,
	newStartDate: string
): Promise<string> {
	const { data, error } = await supabase.rpc('clone_plan_template', {
		template_id: templateId,
		new_start_date: newStartDate,
	});
	if (error) throw error;
	return data as string;
}

/// Toggle is_template on an existing plan (admin / coach action). When
/// flipping a club-owned plan to a template the caller must already
/// be a club admin via RLS.
export async function setPlanIsTemplate(
	planId: string,
	isTemplate: boolean,
	clubId: string | null = null
): Promise<void> {
	const patch: Record<string, unknown> = {
		is_template: isTemplate,
		updated_at: new Date().toISOString(),
	};
	// If we're flagging it as a template, drop active status so it
	// doesn't claim the per-user "one active plan" slot — the
	// training_plans_template_status CHECK forbids active+template.
	if (isTemplate) patch.status = 'completed';
	if (clubId !== null) patch.club_id = clubId;
	const { error } = await supabase.from('training_plans').update(patch).eq('id', planId);
	if (error) throw error;
}

/**
 * Clone a user's plan into a new club-owned template, leaving the
 * original plan untouched on the user's /plans list. Mirrors
 * `clone_plan_template` but in the publish direction: copy the plan
 * row + every plan_week + every plan_workout into a new
 * `is_template = true, club_id = X` sibling. Completion fields are
 * intentionally not copied — templates start fresh.
 */
export async function publishPlanAsTemplate(
	sourcePlanId: string,
	clubId: string
): Promise<string> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const source = await fetchPlan(sourcePlanId);
	if (!source.plan) throw new Error('Source plan not found');
	if (source.plan.user_id !== userId) {
		throw new Error('Only the plan owner can publish');
	}
	const src = source.plan;

	// vdot + current_5k_seconds are the publisher's private fitness
	// measurements — derived proxies for age, fitness, and recent 5 km
	// performance. They aren't template-design values; copying them
	// into a row that every club member can SELECT leaks personal
	// fitness data. Strip on publish; the cloning RPC also strips on
	// the read side as defence-in-depth (migration 20260721_001).
	const { data: tmpl, error: planErr } = await supabase
		.from('training_plans')
		.insert({
			user_id: userId,
			name: src.name,
			goal_event: src.goal_event,
			goal_distance_m: src.goal_distance_m,
			goal_time_seconds: src.goal_time_seconds,
			start_date: src.start_date,
			end_date: src.end_date,
			days_per_week: src.days_per_week,
			vdot: null,
			current_5k_seconds: null,
			status: 'completed',
			source: src.source ?? 'manual',
			notes: src.notes,
			rules: src.rules,
			is_template: true,
			club_id: clubId,
			parent_template_id: null,
		})
		.select('id')
		.single();
	if (planErr || !tmpl) throw planErr ?? new Error('Template insert failed');
	const newPlanId = tmpl.id as string;

	if (source.weeks.length === 0) return newPlanId;

	const weekRows = source.weeks.map((w) => ({
		plan_id: newPlanId,
		week_index: w.week_index,
		phase: w.phase,
		target_volume_m: w.target_volume_m,
		notes: w.notes,
	}));
	const { data: weekRes, error: weekErr } = await supabase
		.from('plan_weeks')
		.insert(weekRows)
		.select('id, week_index');
	if (weekErr || !weekRes) throw weekErr ?? new Error('Weeks insert failed');

	const byIdx = new Map<number, string>();
	for (const w of weekRes as { id: string; week_index: number }[]) {
		byIdx.set(w.week_index, w.id);
	}
	const oldToNew = new Map<string, string>();
	for (const old of source.weeks) {
		const newId = byIdx.get(old.week_index);
		if (newId) oldToNew.set(old.id, newId);
	}

	const workoutRows = source.workouts
		.map((w) => {
			const newWeekId = oldToNew.get(w.week_id);
			if (!newWeekId) return null;
			return {
				week_id: newWeekId,
				scheduled_date: w.scheduled_date,
				kind: w.kind,
				target_distance_m: w.target_distance_m,
				target_duration_seconds: w.target_duration_seconds,
				target_pace_sec_per_km: w.target_pace_sec_per_km,
				target_pace_end_sec_per_km: w.target_pace_end_sec_per_km,
				target_pace_tolerance_sec: w.target_pace_tolerance_sec,
				pace_zone: w.pace_zone,
				structure: w.structure,
				notes: w.notes,
			};
		})
		.filter((r): r is NonNullable<typeof r> => r != null);
	if (workoutRows.length > 0) {
		const { error: woErr } = await supabase.from('plan_workouts').insert(workoutRows);
		if (woErr) throw woErr;
	}

	return newPlanId;
}

export async function fetchPlan(id: string): Promise<{
	plan: TrainingPlan | null;
	weeks: PlanWeek[];
	workouts: PlanWorkout[];
}> {
	const [planRes, weeksRes] = await Promise.all([
		supabase.from('training_plans').select('*').eq('id', id).maybeSingle(),
		supabase
			.from('plan_weeks')
			.select('*')
			.eq('plan_id', id)
			.order('week_index', { ascending: true })
	]);
	const plan = (planRes.data ?? null) as TrainingPlan | null;
	const weeks = (weeksRes.data ?? []) as PlanWeek[];
	if (!plan || weeks.length === 0) {
		return { plan, weeks, workouts: [] };
	}
	const weekIds = weeks.map((w) => w.id);
	const { data: woData } = await supabase
		.from('plan_workouts')
		.select('*')
		.in('week_id', weekIds)
		.order('scheduled_date', { ascending: true });
	return {
		plan,
		weeks,
		workouts: (woData ?? []) as PlanWorkout[]
	};
}

export async function fetchWorkout(id: string): Promise<PlanWorkout | null> {
	const { data } = await supabase
		.from('plan_workouts')
		.select('*')
		.eq('id', id)
		.maybeSingle();
	return (data as PlanWorkout | null) ?? null;
}

export async function fetchActivePlanOverview(): Promise<ActivePlanOverview | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data: plan } = await supabase
		.from('training_plans')
		.select('*')
		.eq('user_id', userId)
		.eq('status', 'active')
		.maybeSingle();
	if (!plan) return null;
	const { weeks, workouts } = await fetchPlan(plan.id);
	// Local-tz today — `toISOString().slice(0,10)` returns the UTC date,
	// which rolls a calendar day early/late depending on the viewer's TZ.
	const { todayISO } = await import('./training');
	const today = todayISO();
	const todayWorkout = workouts.find((w) => w.scheduled_date === today) ?? null;
	const completed = workouts.filter(
		(w) => w.manually_completed === true || w.completed_run_id != null
	).length;
	const total = workouts.filter((w) => w.kind !== 'rest').length;
	const completionPct = total === 0 ? 0 : Math.round((completed / total) * 100);
	return {
		plan: plan as TrainingPlan,
		weeks: weeks ?? [],
		workouts: workouts ?? [],
		todayWorkout,
		completionPct
	};
}

/**
 * Persist a freshly generated plan — plan row, one row per week, and N
 * workouts per week. Runs four sequential inserts (plan → weeks → workouts
 * grouped by week); could be collapsed into a single RPC later but the
 * linear path is easier to reason about while the feature is new.
 */
export async function createTrainingPlan(input: {
	name: string;
	goalEvent: GoalEvent;
	goalDistanceM: number;
	goalTimeSec?: number | null;
	recent5kSec?: number | null;
	startDate: string; // ISO date
	daysPerWeek: number;
	notes?: string;
	generated: GeneratedPlan;
}): Promise<TrainingPlan> {
	// Read the id from the session directly rather than from the auth store.
	// The store's `user` object is populated by a background profile fetch
	// which races with "Create plan" — using the session avoids the
	// spurious "Not authenticated" when the session is valid but the profile
	// hasn't loaded.
	const { data: { session } } = await supabase.auth.getSession();
	const userId = session?.user?.id;
	if (!userId) throw new Error('Please sign in to create a plan.');

	// Pre-flight validation — every client-set invariant the DB enforces
	// echoed here so the user gets a readable error instead of a raw
	// PostgrestError 23xxx code.
	if (!input.name.trim()) throw new Error('Name is required.');
	if (!(input.goalDistanceM > 0)) throw new Error('Goal distance must be positive.');
	if (input.daysPerWeek < 3 || input.daysPerWeek > 7) {
		throw new Error('Days per week must be between 3 and 7.');
	}
	if (input.goalTimeSec != null && input.goalTimeSec <= 0) {
		throw new Error('Goal time must be positive.');
	}
	if (input.recent5kSec != null && input.recent5kSec <= 0) {
		throw new Error('Recent 5K time must be positive.');
	}
	if (!input.generated.weeks.length) {
		throw new Error('Generated plan has no weeks.');
	}
	// Defence in depth for the null-kind bug we fixed in training.ts —
	// if some future change lets a kindless workout escape the generator,
	// catch it here instead of losing the context in a server-side 23502.
	for (const w of input.generated.weeks) {
		for (const wo of w.workouts) {
			if (!wo.kind) {
				throw new Error(
					`Generator produced a workout with no kind (week ${w.week_index}, ${wo.scheduled_date}).`
				);
			}
		}
	}

	// Auto-complete any existing active plan so the partial unique index
	// (one-active-per-user) doesn't reject the insert.
	await supabase
		.from('training_plans')
		.update({ status: 'completed' })
		.eq('user_id', userId)
		.eq('status', 'active');

	const { data: plan, error: planErr } = await supabase
		.from('training_plans')
		.insert({
			user_id: userId,
			name: input.name.trim(),
			goal_event: input.goalEvent,
			goal_distance_m: input.goalDistanceM,
			goal_time_seconds: input.goalTimeSec ?? null,
			start_date: input.startDate,
			end_date: input.generated.endDate,
			days_per_week: input.daysPerWeek,
			vdot: input.generated.vdot ?? null,
			current_5k_seconds: input.recent5kSec ?? null,
			status: 'active' as PlanStatus,
			source: 'generated' as const,
			notes: input.notes?.trim() || null
		})
		.select()
		.single();
	if (planErr || !plan) throw planErr ?? new Error('Plan insert failed');

	const weekRows = input.generated.weeks.map((w) => ({
		plan_id: plan.id,
		week_index: w.week_index,
		phase: w.phase,
		target_volume_m: w.target_volume_m,
		notes: w.notes
	}));
	const { data: weekRes, error: weekErr } = await supabase
		.from('plan_weeks')
		.insert(weekRows)
		.select();
	if (weekErr || !weekRes) throw weekErr ?? new Error('Weeks insert failed');

	const byIndex = new Map<number, string>();
	for (const w of weekRes as { id: string; week_index: number }[]) {
		byIndex.set(w.week_index, w.id);
	}

	const workoutRows = input.generated.weeks.flatMap((w) =>
		w.workouts.map((wo) => ({
			week_id: byIndex.get(w.week_index)!,
			scheduled_date: wo.scheduled_date,
			kind: wo.kind,
			target_distance_m: wo.target_distance_m,
			target_duration_seconds: wo.target_duration_seconds,
			target_pace_sec_per_km: wo.target_pace_sec_per_km,
			target_pace_tolerance_sec: wo.target_pace_tolerance_sec,
			structure: wo.structure,
			notes: wo.notes
		}))
	);
	if (workoutRows.length > 0) {
		const { error: woErr } = await supabase.from('plan_workouts').insert(workoutRows);
		if (woErr) throw woErr;
	}

	return plan as TrainingPlan;
}

export async function updatePlanStatus(
	id: string,
	status: PlanStatus
): Promise<void> {
	const { error } = await supabase
		.from('training_plans')
		.update({ status })
		.eq('id', id);
	if (error) throw error;
}

export async function deletePlan(id: string): Promise<void> {
	const { error } = await supabase.from('training_plans').delete().eq('id', id);
	if (error) throw error;
}

export async function markWorkoutCompleted(
	workoutId: string,
	runId: string | null,
	options: { manual?: boolean } = {}
): Promise<void> {
	const manual = options.manual === true;
	const isCompleting = runId != null || manual;
	const { error } = await supabase
		.from('plan_workouts')
		.update({
			completed_run_id: runId,
			manually_completed: manual,
			completed_at: isCompleting ? new Date().toISOString() : null
		})
		.eq('id', workoutId);
	if (error) throw error;
}

/**
 * Best-effort auto-match: link `runId` to a plan workout scheduled for the
 * same calendar date whose target distance is within ±25% of the actual.
 * Returns the matched workout id, or null. Wrong matches are manually
 * clearable via `markWorkoutCompleted(id, null)`.
 */
export async function autoMatchRunToPlanWorkout(
	runId: string,
	runIsoDate: string,
	runDistanceM: number
): Promise<string | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	// Pre-fetch the user's plan + week ids and constrain the workout
	// query with `in('week_id', ...)`. RLS on `plan_workouts` already
	// chains through `plan_weeks → training_plans.user_id`, but an
	// explicit scope is defence in depth — without it, a future RLS
	// edit that breaks the chain would silently allow this function
	// to match a run to another user's workout. See audit
	// `/tmp/data-isolation-audit/client-realtime.md` H2.
	const { data: plans } = await supabase
		.from('training_plans')
		.select('id, plan_weeks(id)')
		.eq('user_id', userId);
	const weekIds = (plans ?? []).flatMap((p) =>
		((p as { plan_weeks: { id: string }[] }).plan_weeks ?? []).map((w) => w.id),
	);
	if (weekIds.length === 0) return null;

	const { data: candidates } = await supabase
		.from('plan_workouts')
		.select('id, target_distance_m, completed_run_id, week_id')
		.in('week_id', weekIds)
		.eq('scheduled_date', runIsoDate)
		.is('completed_run_id', null);
	if (!candidates || candidates.length === 0) return null;
	const withDistance = candidates
		.filter((c) => c.target_distance_m != null)
		.map((c) => ({
			id: c.id as string,
			target: c.target_distance_m as number,
			delta: Math.abs((c.target_distance_m as number) - runDistanceM)
		}))
		.filter(
			(c) =>
				c.delta / c.target <= 0.25 // within 25% of target distance
		)
		.sort((a, b) => a.delta - b.delta);
	if (withDistance.length === 0) return null;
	const match = withDistance[0];
	await markWorkoutCompleted(match.id, runId);
	return match.id;
}

/**
 * Patch a single plan workout — supports the inline editor. Only the
 * provided fields are updated; leave others out of the `patch` map to keep
 * them untouched.
 */
export async function updatePlanWorkout(
	id: string,
	patch: Partial<{
		kind: string;
		target_distance_m: number | null;
		target_duration_seconds: number | null;
		target_pace_sec_per_km: number | null;
		target_pace_end_sec_per_km: number | null;
		target_pace_tolerance_sec: number | null;
		pace_zone: string | null;
		notes: string | null;
		scheduled_date: string;
		structure: Record<string, unknown> | null;
	}>
): Promise<void> {
	const { error } = await supabase.from('plan_workouts').update(patch).eq('id', id);
	if (error) throw error;
}

export async function updatePlanWeek(
	id: string,
	patch: Partial<{ phase: string; target_volume_m: number | null; notes: string | null }>
): Promise<void> {
	const { error } = await supabase.from('plan_weeks').update(patch).eq('id', id);
	if (error) throw error;
}

export async function updatePlanMeta(
	id: string,
	patch: Partial<{
		name: string;
		notes: string | null;
		goal_time_seconds: number | null;
		days_per_week: number;
		rules: unknown[] | null;
	}>
): Promise<void> {
	const { error } = await supabase.from('training_plans').update(patch).eq('id', id);
	if (error) throw error;
}

// ─────────────────────── Following + activity feed (decisions §31) ───────────────────────

export interface PublicProfile {
	id: string;
	display_name: string | null;
	avatar_url: string | null;
}

export interface ProfileSummary extends PublicProfile {
	follower_count: number;
	following_count: number;
	viewer_follows: boolean;
}

/// Public-by-default user profile lookup. Returns null when the user
/// doesn't exist or RLS hides the row (shouldn't happen now that
/// user_profiles has a public-read policy, but a defensive null is
/// cheap insurance).
export async function fetchPublicProfile(userId: string): Promise<ProfileSummary | null> {
	const { data: sessionData } = await supabase.auth.getSession();
	const viewerId = sessionData.session?.user?.id;

	const [profileRes, followerRes, followingRes, viewerRes] = await Promise.all([
		supabase
			.from('user_profiles')
			.select('id, display_name, avatar_url')
			.eq('id', userId)
			.maybeSingle(),
		supabase
			.from('user_follows')
			.select('*', { count: 'exact', head: true })
			.eq('followee_id', userId),
		supabase
			.from('user_follows')
			.select('*', { count: 'exact', head: true })
			.eq('follower_id', userId),
		viewerId && viewerId !== userId
			? supabase
					.from('user_follows')
					.select('follower_id')
					.eq('follower_id', viewerId)
					.eq('followee_id', userId)
					.maybeSingle()
			: Promise.resolve({ data: null }),
	]);

	if (!profileRes.data) return null;

	return {
		id: profileRes.data.id,
		display_name: profileRes.data.display_name,
		avatar_url: profileRes.data.avatar_url,
		follower_count: followerRes.count ?? 0,
		following_count: followingRes.count ?? 0,
		viewer_follows: viewerRes.data != null,
	};
}

export async function followUser(targetUserId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	if (userId === targetUserId) throw new Error("Can't follow yourself");
	const { error } = await supabase
		.from('user_follows')
		.insert({ follower_id: userId, followee_id: targetUserId });
	// Treat duplicate (already following) as a no-op.
	if (error && error.code !== '23505') throw error;
}

export async function unfollowUser(targetUserId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from('user_follows')
		.delete()
		.eq('follower_id', userId)
		.eq('followee_id', targetUserId);
	if (error) throw error;
}

/// People who follow `userId`, paginated client-side after fetch.
export async function fetchFollowers(userId: string, limit = 50): Promise<PublicProfile[]> {
	const { data: edges } = await supabase
		.from('user_follows')
		.select('follower_id, followed_at')
		.eq('followee_id', userId)
		.order('followed_at', { ascending: false })
		.limit(limit);
	const ids = (edges ?? []).map((e) => e.follower_id as string);
	if (ids.length === 0) return [];
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', ids);
	const byId = new Map<string, PublicProfile>();
	for (const p of profiles ?? []) byId.set(p.id, p);
	// Preserve the followed_at ordering.
	return ids.map((id) => byId.get(id)).filter((p): p is PublicProfile => p != null);
}

/// People `userId` follows, ordered by most-recently followed.
export async function fetchFollowing(userId: string, limit = 50): Promise<PublicProfile[]> {
	const { data: edges } = await supabase
		.from('user_follows')
		.select('followee_id, followed_at')
		.eq('follower_id', userId)
		.order('followed_at', { ascending: false })
		.limit(limit);
	const ids = (edges ?? []).map((e) => e.followee_id as string);
	if (ids.length === 0) return [];
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', ids);
	const byId = new Map<string, PublicProfile>();
	for (const p of profiles ?? []) byId.set(p.id, p);
	return ids.map((id) => byId.get(id)).filter((p): p is PublicProfile => p != null);
}

export interface FeedEntry extends Run {
	author: PublicProfile;
}

/// Activity feed: recent public runs from people the caller follows.
/// Cursor is the started_at + id of the last entry on the previous page;
/// pass null for the first page.
export const FEED_WINDOW_DAYS = 14;

export async function fetchFollowingFeed(opts?: {
	limit?: number;
	cursor?: { started_at: string; id: string } | null;
	/** Restrict to a single followee. Pass `null` / omit for "everyone you follow". */
	authorId?: string | null;
	/** Restrict by `metadata->>activity_type`. Pass 'all' / omit for any activity. */
	activityType?: string | null;
}): Promise<FeedEntry[]> {
	const limit = opts?.limit ?? 20;
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) return [];

	// Resolve the followed set once; the runs query will filter on it.
	const { data: edges } = await supabase
		.from('user_follows')
		.select('followee_id')
		.eq('follower_id', userId);
	const followeeIds = (edges ?? []).map((e) => e.followee_id as string);
	if (followeeIds.length === 0) return [];

	// Author filter narrows the followee set to a single person; we
	// validate it's actually someone the viewer follows so the UI
	// can't enumerate strangers' activity by editing the URL.
	const wantedAuthor = opts?.authorId ?? null;
	const filteredAuthors = wantedAuthor
		? followeeIds.filter((id) => id === wantedAuthor)
		: followeeIds;
	if (filteredAuthors.length === 0) return [];

	const cutoff = new Date(Date.now() - FEED_WINDOW_DAYS * 24 * 60 * 60 * 1000).toISOString();
	// Feed reads go through the public_runs view (decisions §33,
	// migration 20260626_001) — the view filters on is_public and
	// applies the column / metadata-key redaction so feed entries
	// don't leak third-party ids or sync-state internals.
	let q = supabase
		.from('public_runs')
		.select('*')
		.in('user_id', filteredAuthors)
		.gte('started_at', cutoff)
		.order('started_at', { ascending: false })
		.order('id', { ascending: false })
		.limit(limit);
	if (opts?.activityType && opts.activityType !== 'all') {
		// jsonb metadata key — Supabase exposes the `->>` operator via
		// the column-name string syntax. Matches '{activity_type:run}'.
		q = q.eq('metadata->>activity_type', opts.activityType);
	}
	if (opts?.cursor) {
		// Stable cursor pagination on (started_at, id) — strictly less than
		// the cursor row to skip what we've already seen.
		q = q.or(
			`started_at.lt.${opts.cursor.started_at},and(started_at.eq.${opts.cursor.started_at},id.lt.${opts.cursor.id})`
		);
	}
	const { data: runs } = await q;
	if (!runs || runs.length === 0) return [];

	const authorIds = Array.from(new Set(runs.map((r) => r.user_id)));
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', authorIds);
	const byId = new Map<string, PublicProfile>();
	for (const p of profiles ?? []) byId.set(p.id, p);

	return runs.map((r) => ({
		...(r as Run),
		author: byId.get(r.user_id) ?? { id: r.user_id, display_name: null, avatar_url: null },
	}));
}

/// Server-side privacy-zone clipping (decisions §33). Pass the run /
/// route owner's `user_id` and a points array; receive the clipped
/// middle. Zones never come down the wire — the RPC reads them
/// internally with security-definer privileges. The RPC is a no-op
/// (returns the input) when the owner has no zones configured.
///
/// **Fails closed:** on RPC error or unexpected response shape this
/// returns `[]` rather than the unclipped input. The previous
/// behaviour (return `points` on error) is the leak this helper exists
/// to prevent — a transient DB blip that bypassed clipping was a
/// privacy regression. Callers should guard owner views *before*
/// calling so an outage doesn't blank the owner's own map; this
/// function only ever speaks for non-owner viewers.
export async function clipTrackForUser(
	targetUserId: string,
	points: { lat: number; lng: number; ele?: number; t?: number }[]
): Promise<{ lat: number; lng: number; ele?: number; t?: number }[]> {
	if (points.length === 0) return points;
	const { data, error } = await supabase.rpc('clip_track_for_user', {
		target_user_id: targetUserId,
		points,
	});
	if (error) {
		console.warn('clip_track_for_user failed; failing closed (empty track)', error);
		return [];
	}
	if (!Array.isArray(data)) return [];
	return data as typeof points;
}

/// Recent public runs from a single user — used by the profile page.
/// Reads through the public_runs view (decisions §33, migration
/// 20260626_001) so the redaction applies on the wire even when the
/// caller is signed in.
export async function fetchPublicRunsByUser(userId: string, limit = 20): Promise<Run[]> {
	const { data } = await supabase
		.from('public_runs')
		.select('*')
		.eq('user_id', userId)
		.order('started_at', { ascending: false })
		.limit(limit);
	return (data ?? []) as Run[];
}

// ─────────────────────── Kudos + comments on runs (decisions §32) ───────────────────────

export interface RunKudosSummary {
	count: number;
	viewer_has_kudos: boolean;
}

export interface RunCommentWithAuthor {
	id: string;
	run_id: string;
	author_id: string;
	parent_comment_id: string | null;
	body: string;
	created_at: string;
	updated_at: string;
	author: PublicProfile;
}

/// Batch kudos + comment counts for a list of runs — used on the
/// feed where mounting a full RunSocial per card would be wasteful.
/// Returns a map keyed by run id.
export async function fetchEngagementSummaries(
	runIds: string[]
): Promise<Map<string, { kudos_count: number; viewer_has_kudos: boolean; comment_count: number }>> {
	const out = new Map<string, { kudos_count: number; viewer_has_kudos: boolean; comment_count: number }>();
	if (runIds.length === 0) return out;

	const { data: sessionData } = await supabase.auth.getSession();
	const viewerId = sessionData.session?.user?.id;

	const [kudosRows, viewerKudos, commentRows] = await Promise.all([
		supabase.from('run_kudos').select('run_id').in('run_id', runIds),
		viewerId
			? supabase
					.from('run_kudos')
					.select('run_id')
					.eq('user_id', viewerId)
					.in('run_id', runIds)
			: Promise.resolve({ data: [] as { run_id: string }[] }),
		supabase.from('run_comments').select('run_id').in('run_id', runIds),
	]);

	for (const id of runIds) out.set(id, { kudos_count: 0, viewer_has_kudos: false, comment_count: 0 });
	for (const row of kudosRows.data ?? []) {
		const e = out.get(row.run_id as string);
		if (e) e.kudos_count++;
	}
	for (const row of (viewerKudos.data ?? []) as { run_id: string }[]) {
		const e = out.get(row.run_id);
		if (e) e.viewer_has_kudos = true;
	}
	for (const row of commentRows.data ?? []) {
		const e = out.get(row.run_id as string);
		if (e) e.comment_count++;
	}
	return out;
}

/// Returns kudos count for a run + whether the current viewer has
/// given kudos. Two parallel queries — count is server-side, viewer
/// flag is one indexed lookup.
export async function fetchKudosForRun(runId: string): Promise<RunKudosSummary> {
	const { data: sessionData } = await supabase.auth.getSession();
	const viewerId = sessionData.session?.user?.id;

	const [countRes, viewerRes] = await Promise.all([
		supabase
			.from('run_kudos')
			.select('*', { count: 'exact', head: true })
			.eq('run_id', runId),
		viewerId
			? supabase
					.from('run_kudos')
					.select('user_id')
					.eq('run_id', runId)
					.eq('user_id', viewerId)
					.maybeSingle()
			: Promise.resolve({ data: null }),
	]);

	return {
		count: countRes.count ?? 0,
		viewer_has_kudos: viewerRes.data != null,
	};
}

export async function giveKudos(runId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from('run_kudos')
		.insert({ user_id: userId, run_id: runId });
	// Treat duplicate as no-op.
	if (error && error.code !== '23505') throw error;
}

export async function rescindKudos(runId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from('run_kudos')
		.delete()
		.eq('run_id', runId)
		.eq('user_id', userId);
	if (error) throw error;
}

/// Comments on a run, sorted oldest-first. Author profiles are joined
/// in a second round trip so PostgREST doesn't need an embedded select.
export async function fetchRunComments(runId: string, limit = 200): Promise<RunCommentWithAuthor[]> {
	const { data: rows, error } = await supabase
		.from('run_comments')
		.select('*')
		.eq('run_id', runId)
		.order('created_at', { ascending: true })
		.limit(limit);
	if (error) {
		console.error('fetchRunComments failed', error);
		return [];
	}
	if (!rows || rows.length === 0) return [];

	const authorIds = Array.from(new Set(rows.map((r) => r.author_id)));
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', authorIds);
	const byId = new Map<string, PublicProfile>();
	for (const p of profiles ?? []) byId.set(p.id, p);

	return rows.map((r) => ({
		...r,
		author: byId.get(r.author_id) ?? { id: r.author_id, display_name: null, avatar_url: null },
	}));
}

export async function postRunComment(input: {
	run_id: string;
	body: string;
	parent_comment_id?: string | null;
}): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase.from('run_comments').insert({
		run_id: input.run_id,
		author_id: userId,
		body: input.body,
		parent_comment_id: input.parent_comment_id ?? null,
	});
	if (error) throw error;
}

export async function deleteRunComment(commentId: string): Promise<void> {
	const { error } = await supabase.from('run_comments').delete().eq('id', commentId);
	if (error) throw error;
}

// --- Run photos (decisions §36) ---

export interface RunPhoto {
	id: string;
	run_id: string;
	owner_id: string;
	storage_path: string;
	/// Server-generated 512w thumbnail path, populated by the
	/// photo_process job (apps/job_worker handler_photo_process.go).
	/// Null while the job is still queued OR when the original is
	/// already small enough that resizing would just inflate the
	/// stored bytes. Gallery callers should prefer `thumbUrl` when
	/// present and fall back to `url`.
	thumb_512_path: string | null;
	caption: string | null;
	position_idx: number;
	created_at: string;
	url: string;
	thumbUrl: string | null;
}

const PHOTO_MIME_TO_EXT: Record<string, string> = {
	'image/jpeg': 'jpg',
	'image/png': 'png',
	'image/webp': 'webp',
	'image/heic': 'heic',
	'image/heif': 'heif',
};

const PHOTO_MAX_BYTES = 10 * 1024 * 1024; // 10 MB

// `run-photos` is a private bucket (migration 20260712_001 — closed the
// public-CDN bypass on the visibility gate). Signed URLs carry their own
// TTL; an hour is comfortable for a gallery render and short enough that
// a run flipped from public → private won't keep serving stale bytes
// long after the visibility change.
const PHOTO_SIGNED_URL_TTL_S = 60 * 60;

async function signRunPhotoPaths(paths: string[]): Promise<Record<string, string>> {
	if (paths.length === 0) return {};
	const { data, error } = await supabase.storage
		.from('run-photos')
		.createSignedUrls(paths, PHOTO_SIGNED_URL_TTL_S);
	if (error || !data) {
		console.error('signRunPhotoPaths failed', error);
		return {};
	}
	const out: Record<string, string> = {};
	for (const row of data) {
		if (row.path && row.signedUrl) out[row.path] = row.signedUrl;
	}
	return out;
}

export async function fetchRunPhotos(runId: string, limit = 50): Promise<RunPhoto[]> {
	const { data, error } = await supabase
		.from('run_photos')
		.select('*')
		.eq('run_id', runId)
		.order('position_idx', { ascending: true })
		.order('created_at', { ascending: true })
		.limit(limit);
	if (error) {
		console.error('fetchRunPhotos failed', error);
		return [];
	}
	const rows = data ?? [];
	// Sign both the original and any present thumbnail in one batch
	// — Storage's createSignedUrls handles missing paths gracefully
	// (returns an empty array entry) so the dedupe + fallback are
	// safe even on fresh uploads where the worker hasn't filled in
	// thumb_512_path yet.
	const paths: string[] = [];
	for (const r of rows) {
		paths.push(r.storage_path);
		if (r.thumb_512_path) paths.push(r.thumb_512_path);
	}
	const signed = await signRunPhotoPaths(paths);
	return rows.map((r) => ({
		...r,
		url: signed[r.storage_path] ?? '',
		thumbUrl: r.thumb_512_path ? (signed[r.thumb_512_path] ?? null) : null,
	}));
}

export async function addRunPhoto(input: {
	run_id: string;
	file: File;
	caption?: string | null;
}): Promise<RunPhoto> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const ext = PHOTO_MIME_TO_EXT[input.file.type];
	if (!ext) throw new Error('Unsupported image type — JPEG, PNG, WebP, or HEIC only');
	if (input.file.size > PHOTO_MAX_BYTES) throw new Error('Image too large (10 MB max)');

	const photoId = crypto.randomUUID();
	const storagePath = `${userId}/${photoId}.${ext}`;

	const { error: upErr } = await supabase.storage
		.from('run-photos')
		.upload(storagePath, input.file, {
			contentType: input.file.type,
			upsert: false,
		});
	if (upErr) throw upErr;

	const { data: posData } = await supabase
		.from('run_photos')
		.select('position_idx')
		.eq('run_id', input.run_id)
		.order('position_idx', { ascending: false })
		.limit(1)
		.maybeSingle();
	const nextIdx = (posData?.position_idx ?? -1) + 1;

	const { data, error } = await supabase
		.from('run_photos')
		.insert({
			id: photoId,
			run_id: input.run_id,
			owner_id: userId,
			storage_path: storagePath,
			caption: input.caption?.trim() || null,
			position_idx: nextIdx,
		})
		.select('*')
		.single();
	if (error || !data) {
		// Best-effort cleanup of the uploaded blob if metadata insert fails.
		await supabase.storage.from('run-photos').remove([storagePath]);
		throw error ?? new Error('Insert failed');
	}
	const { data: signed } = await supabase.storage
		.from('run-photos')
		.createSignedUrl(storagePath, PHOTO_SIGNED_URL_TTL_S);
	return {
		...data,
		url: signed?.signedUrl ?? '',
	};
}

export async function deleteRunPhoto(photoId: string): Promise<void> {
	const { data: row, error: fetchErr } = await supabase
		.from('run_photos')
		.select('storage_path')
		.eq('id', photoId)
		.maybeSingle();
	if (fetchErr) throw fetchErr;

	const { error } = await supabase.from('run_photos').delete().eq('id', photoId);
	if (error) throw error;

	if (row?.storage_path) {
		// Best-effort — RLS allows the photo owner to remove their own bytes.
		// If the run owner (not photo owner) deleted the row, the bytes
		// will be orphaned in Storage but invisible to the UI.
		await supabase.storage.from('run-photos').remove([row.storage_path]);
	}
}

export async function updateRunPhotoCaption(
	photoId: string,
	caption: string | null,
): Promise<void> {
	const trimmed = caption?.trim() || null;
	const { error } = await supabase
		.from('run_photos')
		.update({ caption: trimmed })
		.eq('id', photoId);
	if (error) throw error;
}

// --- Gear tracking (decisions backlog item #7) ---

export type GearKind = 'shoe' | 'bike';

export interface Gear {
	id: string;
	owner_id: string;
	kind: GearKind;
	name: string;
	brand: string | null;
	model: string | null;
	purchased_at: string | null;
	retired_at: string | null;
	target_distance_m: number | null;
	notes: string | null;
	created_at: string;
	updated_at: string;
}

export interface GearWithDistance extends Gear {
	total_distance_m: number;
	run_count: number;
}

/// Fetch every gear item the signed-in user owns, with the rolled-up
/// total distance from `gear_with_distance`. Default order: active
/// (retired_at IS NULL) first, then newest. Settings UI renders sub-
/// tabs (shoes / bikes) on top of this single fetch.
export async function fetchMyGear(): Promise<GearWithDistance[]> {
	const { data, error } = await supabase
		.from('gear_with_distance')
		.select('*')
		.order('retired_at', { ascending: true, nullsFirst: true })
		.order('created_at', { ascending: false });
	if (error) {
		console.error('fetchMyGear failed', error);
		return [];
	}
	return ((data ?? []) as GearWithDistance[]).map((g) => ({
		...g,
		// Postgres bigint comes through as a string in some PostgREST
		// configurations; coerce defensively so the UI math is never
		// surprised by 'NaN km'.
		total_distance_m: Number(g.total_distance_m ?? 0),
		target_distance_m:
			g.target_distance_m == null ? null : Number(g.target_distance_m),
	}));
}

export async function createGear(input: {
	kind: GearKind;
	name: string;
	brand?: string | null;
	model?: string | null;
	purchased_at?: string | null;
	target_distance_m?: number | null;
	notes?: string | null;
}): Promise<Gear> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from('gear')
		.insert({
			owner_id: userId,
			kind: input.kind,
			name: input.name,
			brand: input.brand ?? null,
			model: input.model ?? null,
			purchased_at: input.purchased_at ?? null,
			target_distance_m: input.target_distance_m ?? null,
			notes: input.notes ?? null,
		})
		.select('*')
		.single();
	if (error || !data) throw error ?? new Error('createGear failed');
	return data as Gear;
}

export async function updateGear(
	id: string,
	patch: Partial<Pick<Gear,
		'name' | 'brand' | 'model' | 'purchased_at' | 'retired_at' |
		'target_distance_m' | 'notes'
	>>,
): Promise<void> {
	const { error } = await supabase.from('gear').update(patch).eq('id', id);
	if (error) throw error;
}

/// Stamp retired_at to today and clear nothing else — the row stays
/// around for historical mileage roll-ups on past runs that reference
/// it. Use [deleteGear] to actually remove (cascades to run_gear).
export async function retireGear(id: string): Promise<void> {
	const today = new Date().toISOString().slice(0, 10);
	await updateGear(id, { retired_at: today });
}

/// Un-retire — restore an actively-tracked piece of gear without
/// touching anything else. Useful when a runner pulled an old pair
/// out of retirement for slow / treadmill runs.
export async function unretireGear(id: string): Promise<void> {
	await updateGear(id, { retired_at: null });
}

export async function deleteGear(id: string): Promise<void> {
	const { error } = await supabase.from('gear').delete().eq('id', id);
	if (error) throw error;
}

/// Replace the full gear set assigned to a run. Empty array clears
/// the assignment. Idempotent — re-running with the same set is a
/// no-op once the round trip completes. RLS gates both the insert
/// and the delete to the run's owner.
export async function setRunGear(runId: string, gearIds: string[]): Promise<void> {
	// Delete-then-insert is the simple shape; the join table has no
	// natural-key churn to make a smarter diff worthwhile. Wrap in
	// best-effort error surfacing for the toast layer.
	const del = await supabase.from('run_gear').delete().eq('run_id', runId);
	if (del.error) throw del.error;
	if (gearIds.length === 0) return;
	const rows = gearIds.map((gear_id) => ({ run_id: runId, gear_id }));
	const ins = await supabase.from('run_gear').insert(rows);
	if (ins.error) throw ins.error;
}

/// Fetch the gear assigned to a single run. Used on the run-detail
/// page to render the chip row. RLS gates this to runs the viewer
/// can see (owner OR public run); non-visible runs return [].
export async function fetchRunGear(runId: string): Promise<Gear[]> {
	const { data, error } = await supabase
		.from('run_gear')
		.select('gear:gear_id(*)')
		.eq('run_id', runId);
	if (error || !data) {
		console.error('fetchRunGear failed', error);
		return [];
	}
	return (data as unknown as Array<{ gear: Gear | null }>)
		.map((r) => r.gear)
		.filter((g): g is Gear => g != null);
}

// --- Segments + leaderboards (decisions §37) ---

export interface Segment {
	id: string;
	route_id: string;
	name: string;
	start_distance_m: number;
	end_distance_m: number;
	length_m: number | null;
	created_by: string | null;
	created_at: string;
}

export interface SegmentEffort {
	id: string;
	segment_id: string;
	run_id: string;
	user_id: string;
	time_seconds: number;
	started_at: string;
	created_at: string;
}

export interface SegmentLeaderboardEntry {
	effort: SegmentEffort;
	athlete: PublicProfile;
	rank: number;
}

export interface SegmentEffortWithSegment {
	effort: SegmentEffort;
	segment: Segment;
	rank: number;
}

export async function fetchSegmentsForRoute(routeId: string, limit = 100): Promise<Segment[]> {
	const { data, error } = await supabase
		.from('segments')
		.select('*')
		.eq('route_id', routeId)
		.order('start_distance_m', { ascending: true })
		.limit(limit);
	if (error) {
		console.error('fetchSegmentsForRoute failed', error);
		return [];
	}
	return (data ?? []) as Segment[];
}

export async function createSegment(input: {
	route_id: string;
	name: string;
	start_distance_m: number;
	end_distance_m: number;
}): Promise<Segment> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from('segments')
		.insert({
			route_id: input.route_id,
			name: input.name.trim(),
			start_distance_m: input.start_distance_m,
			end_distance_m: input.end_distance_m,
			created_by: userId,
		})
		.select('*')
		.single();
	if (error || !data) throw error ?? new Error('Insert failed');
	return data as Segment;
}

export async function deleteSegment(segmentId: string): Promise<void> {
	const { error } = await supabase.from('segments').delete().eq('id', segmentId);
	if (error) throw error;
}

/**
 * Leaderboard for a segment — efforts ascending by time, joined to
 * the author profile so the UI can render avatars + names. Ranks are
 * 1-based and dense (ties share a rank).
 */
export async function fetchSegmentLeaderboard(
	segmentId: string,
	limit = 50,
): Promise<SegmentLeaderboardEntry[]> {
	const { data: efforts, error } = await supabase
		.from('segment_efforts')
		.select('*')
		.eq('segment_id', segmentId)
		.order('time_seconds', { ascending: true })
		.limit(limit);
	if (error || !efforts || efforts.length === 0) return [];

	const userIds = Array.from(new Set(efforts.map((e) => e.user_id)));
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', userIds);
	const byId = new Map<string, PublicProfile>();
	for (const p of profiles ?? []) byId.set(p.id, p);

	const out: SegmentLeaderboardEntry[] = [];
	let lastTime = -1;
	let lastRank = 0;
	for (let i = 0; i < efforts.length; i++) {
		const e = efforts[i] as SegmentEffort;
		const rank = e.time_seconds === lastTime ? lastRank : i + 1;
		lastTime = e.time_seconds;
		lastRank = rank;
		out.push({
			effort: e,
			athlete: byId.get(e.user_id) ?? { id: e.user_id, display_name: null, avatar_url: null },
			rank,
		});
	}
	return out;
}

/**
 * All segment efforts attached to a single run, joined to the parent
 * segment so the run-detail page can render "Climb of doom — 4:21,
 * #3 of 17". Rank is computed via a count query against the
 * leaderboard.
 */
export async function fetchEffortsForRun(runId: string): Promise<SegmentEffortWithSegment[]> {
	const { data: efforts, error } = await supabase
		.from('segment_efforts')
		.select('*')
		.eq('run_id', runId);
	if (error || !efforts || efforts.length === 0) return [];

	const segmentIds = Array.from(new Set(efforts.map((e) => e.segment_id)));
	const { data: segments } = await supabase
		.from('segments')
		.select('*')
		.in('id', segmentIds);
	const bySeg = new Map<string, Segment>();
	for (const s of segments ?? []) bySeg.set(s.id, s as Segment);

	// Rank query — one count per segment+effort. Cheap because the
	// segment_efforts(segment_id, time_seconds) index covers it.
	const out: SegmentEffortWithSegment[] = [];
	for (const e of efforts as SegmentEffort[]) {
		const segment = bySeg.get(e.segment_id);
		if (!segment) continue;
		const { count } = await supabase
			.from('segment_efforts')
			.select('*', { count: 'exact', head: true })
			.eq('segment_id', e.segment_id)
			.lt('time_seconds', e.time_seconds);
		out.push({
			effort: e,
			segment,
			rank: (count ?? 0) + 1,
		});
	}
	return out;
}

/**
 * Client-side auto-effort generation for a run (decisions §37).
 *
 * Called from the run detail page on mount. Walks each route segment
 * over the run's track and inserts any new efforts. Existing efforts
 * are protected by the unique(segment_id, run_id) index — a duplicate
 * insert returns 23505 and we treat it as a no-op.
 *
 * Returns the count of new efforts written.
 */
export async function computeSegmentEffortsForRun(input: {
	run_id: string;
	user_id: string;
	route_id: string;
	track: { lat: number; lng: number; ts?: string }[];
}): Promise<number> {
	if (!input.track || input.track.length < 2) return 0;
	const userId = auth.user?.id;
	if (!userId || userId !== input.user_id) return 0;

	const segments = await fetchSegmentsForRoute(input.route_id);
	if (segments.length === 0) return 0;

	const { computeEffortFromTrack } = await import('./segments');

	let written = 0;
	for (const seg of segments) {
		const eff = computeEffortFromTrack(input.track as any, {
			start_distance_m: Number(seg.start_distance_m),
			end_distance_m: Number(seg.end_distance_m),
		});
		if (!eff) continue;
		const { error } = await supabase.from('segment_efforts').insert({
			segment_id: seg.id,
			run_id: input.run_id,
			user_id: userId,
			time_seconds: eff.time_seconds,
			started_at: eff.started_at,
		});
		if (!error) written++;
		else if (error.code !== '23505') {
			console.warn('segment effort insert failed', seg.id, error);
		}
	}
	return written;
}

// --- Notifications (decisions §38) ---

export type NotificationKind = 'kudos' | 'comment' | 'comment_reply' | 'follow';

export interface NotificationRow {
	id: string;
	user_id: string;
	actor_id: string | null;
	kind: NotificationKind;
	run_id: string | null;
	comment_id: string | null;
	read_at: string | null;
	created_at: string;
}

export interface NotificationView {
	row: NotificationRow;
	actor: PublicProfile | null;
	run_distance_m: number | null;
	run_started_at: string | null;
	comment_excerpt: string | null;
}

/**
 * Last `limit` notifications for the current user, joined to actor
 * profiles + small run/comment metadata so the UI can render
 * "Alice commented on your 8 km run" without follow-up queries.
 */
export async function fetchNotifications(limit = 50): Promise<NotificationView[]> {
	const { data: rows, error } = await supabase
		.from('notifications')
		.select('*')
		.order('created_at', { ascending: false })
		.limit(limit);
	if (error || !rows || rows.length === 0) {
		if (error) console.error('fetchNotifications failed', error);
		return [];
	}

	const actorIds = Array.from(new Set(rows.map((r) => r.actor_id).filter((x): x is string => !!x)));
	const runIds = Array.from(new Set(rows.map((r) => r.run_id).filter((x): x is string => !!x)));
	const commentIds = Array.from(new Set(rows.map((r) => r.comment_id).filter((x): x is string => !!x)));

	const [profiles, runs, comments] = await Promise.all([
		actorIds.length > 0
			? supabase.from('user_profiles').select('id, display_name, avatar_url').in('id', actorIds)
			: Promise.resolve({ data: [] as PublicProfile[] }),
		runIds.length > 0
			? supabase.from('runs').select('id, distance_m, started_at').in('id', runIds)
			: Promise.resolve({ data: [] as { id: string; distance_m: number; started_at: string }[] }),
		commentIds.length > 0
			? supabase.from('run_comments').select('id, body').in('id', commentIds)
			: Promise.resolve({ data: [] as { id: string; body: string }[] }),
	]);

	const profileBy = new Map<string, PublicProfile>();
	for (const p of (profiles.data ?? []) as PublicProfile[]) profileBy.set(p.id, p);
	const runBy = new Map<string, { distance_m: number; started_at: string }>();
	for (const r of (runs.data ?? []) as { id: string; distance_m: number; started_at: string }[]) {
		runBy.set(r.id, { distance_m: r.distance_m, started_at: r.started_at });
	}
	const commentBy = new Map<string, string>();
	for (const c of (comments.data ?? []) as { id: string; body: string }[]) {
		commentBy.set(c.id, c.body);
	}

	return rows.map((row) => {
		const r = row as NotificationRow;
		const run = r.run_id ? runBy.get(r.run_id) ?? null : null;
		const body = r.comment_id ? commentBy.get(r.comment_id) ?? null : null;
		return {
			row: r,
			actor: r.actor_id ? profileBy.get(r.actor_id) ?? null : null,
			run_distance_m: run?.distance_m ?? null,
			run_started_at: run?.started_at ?? null,
			comment_excerpt: body ? (body.length > 120 ? body.slice(0, 117) + '…' : body) : null,
		};
	});
}

export async function fetchUnreadNotificationCount(): Promise<number> {
	const { count, error } = await supabase
		.from('notifications')
		.select('*', { count: 'exact', head: true })
		.is('read_at', null);
	if (error) {
		console.error('fetchUnreadNotificationCount failed', error);
		return 0;
	}
	return count ?? 0;
}

export async function markNotificationRead(id: string): Promise<void> {
	const { error } = await supabase
		.from('notifications')
		.update({ read_at: new Date().toISOString() })
		.eq('id', id)
		.is('read_at', null);
	if (error) throw error;
}

export async function markAllNotificationsRead(): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) return;
	const { error } = await supabase
		.from('notifications')
		.update({ read_at: new Date().toISOString() })
		.eq('user_id', userId)
		.is('read_at', null);
	if (error) throw error;
}

export async function deleteNotification(id: string): Promise<void> {
	const { error } = await supabase.from('notifications').delete().eq('id', id);
	if (error) throw error;
}
