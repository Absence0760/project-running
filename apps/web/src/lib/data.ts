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
	return data.map((r: any) => ({ ...r, track: null }));
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
	return { ...data, track };
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
/// download track blobs as cards scroll into view.
export async function fetchTrackByPath(path: string) {
	return fetchTrack(path);
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
	const { data } = await supabase
		.from('runs')
		.select('*')
		.eq('id', id)
		.eq('is_public', true)
		.single();

	if (!data) return null;

	let track = null;
	if (data.track_url) {
		try {
			track = await fetchTrack(data.track_url);
		} catch (e) {
			console.warn('Failed to fetch public run track', e);
		}
	}
	return { ...data, track };
}

export async function deleteRun(id: string): Promise<void> {
	// Delete the track file from Storage first (best-effort).
	const { data: run } = await supabase
		.from('runs')
		.select('track_url')
		.eq('id', id)
		.single();
	if (run?.track_url) {
		try {
			await supabase.storage.from('runs').remove([run.track_url]);
		} catch (e) {
			console.warn('deleteRun: track storage removal failed (orphaned file)', run.track_url, e);
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
}): Promise<{ id: string }> {
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

	if (input.track && input.track.length >= 2) {
		try {
			const path = `${userId}/${runId}.json.gz`;
			const encoded = new TextEncoder().encode(JSON.stringify(input.track));
			const gzipped = await gzipBytes(encoded);
			const { error: upErr } = await supabase.storage
				.from('runs')
				.upload(path, new Blob([gzipped], { type: 'application/gzip' }), {
					contentType: 'application/gzip',
					upsert: true,
				});
			if (!upErr) {
				await supabase.from('runs').update({ track_url: path }).eq('id', runId);
			}
		} catch (_) {
			// Track upload is best-effort — the scalar row is still valid.
		}
	}

	return { id: runId };
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

export async function getRouteReviews(routeId: string) {
	const { data, error } = await supabase
		.from('route_reviews')
		.select('*')
		.eq('route_id', routeId)
		.order('created_at', { ascending: false });
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

export async function fetchRouteById(id: string): Promise<Route | null> {
	const { data } = await supabase
		.from('routes')
		.select('*')
		.eq('id', id)
		.single();

	if (data) return data;
	return null;
}

export async function fetchPublicRoute(id: string): Promise<Route | null> {
	const { data } = await supabase
		.from('routes')
		.select('*')
		.eq('id', id)
		.eq('is_public', true)
		.single();

	return data;
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
	let query = supabase.from('clubs').select('*').eq('is_public', true);
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
		.select('club_id, role, clubs!inner(*)')
		.eq('user_id', userId)
		.order('joined_at', { ascending: false });
	if (!data) return [];
	const clubs = data.map((row: any) => row.clubs).filter(Boolean);
	return enrichClubs(clubs);
}

export async function fetchClubBySlug(slug: string): Promise<ClubWithMeta | null> {
	const { data } = await supabase.from('clubs').select('*').eq('slug', slug).maybeSingle();
	if (!data) return null;
	const [enriched] = await enrichClubs([data]);
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
}): Promise<Club> {
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
			.select()
			.single();
		if (!error && data) {
			return { ...data, join_policy: (data.join_policy ?? 'open') as JoinPolicy };
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
	const { data } = await supabase
		.from('events')
		.select('*')
		.eq('club_id', clubId)
		.order('starts_at', { ascending: true });
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
		.select('*')
		.eq('club_id', clubId)
		.lt('starts_at', nowIso)
		.order('starts_at', { ascending: false })
		.limit(limit);
	return enrichEvents((data as Event[]) ?? []);
}

export async function fetchEventById(id: string): Promise<EventWithMeta | null> {
	const { data } = await supabase.from('events').select('*').eq('id', id).maybeSingle();
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
		.select()
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
	organiser_approved_by: string | null;
	organiser_approved_at: string | null;
}

export interface EventResultWithUser extends EventResultRow {
	display_name: string | null;
	avatar_url: string | null;
}

export async function fetchEventResults(
	eventId: string,
	instanceStart: string
): Promise<EventResultWithUser[]> {
	const { data: results } = await supabase
		.from('event_results')
		.select(
			'user_id, run_id, duration_s, distance_m, rank, finisher_status, age_grade_pct, note, created_at, organiser_approved, organiser_approved_by, organiser_approved_at'
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
	const { data } = await supabase
		.from('race_sessions')
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

export async function fetchPostReplies(parentId: string): Promise<ClubPostWithAuthor[]> {
	const { data: posts } = await supabase
		.from('club_posts')
		.select('*')
		.eq('parent_post_id', parentId)
		.order('created_at', { ascending: true });
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

export async function fetchMyPlans(): Promise<TrainingPlan[]> {
	// Templates live in the same table; filter them out of the
	// user-facing plan list (decisions §35).
	const { data } = await supabase
		.from('training_plans')
		.select('*')
		.eq('is_template', false)
		.order('created_at', { ascending: false });
	return ((data ?? []) as TrainingPlan[]) ?? [];
}

/// Plan templates owned by `clubId`. Visible to club members; admins
/// can write. See decisions §35.
export async function fetchClubTemplates(clubId: string): Promise<TrainingPlan[]> {
	const { data, error } = await supabase
		.from('training_plans')
		.select('*')
		.eq('is_template', true)
		.eq('club_id', clubId)
		.order('created_at', { ascending: false });
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
			vdot: src.vdot,
			current_5k_seconds: src.current_5k_seconds,
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
	const weeks = ((weeksRes.data ?? []) as PlanWeek[]) ?? [];
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
		workouts: ((woData ?? []) as PlanWorkout[]) ?? []
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
export async function fetchFollowingFeed(opts?: {
	limit?: number;
	cursor?: { started_at: string; id: string } | null;
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

	let q = supabase
		.from('runs')
		.select('*')
		.in('user_id', followeeIds)
		.eq('is_public', true)
		.order('started_at', { ascending: false })
		.order('id', { ascending: false })
		.limit(limit);
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
/// internally with security-definer privileges. Returns the input
/// unchanged when the owner has no zones configured.
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
		console.warn('clip_track_for_user failed; falling back to unclipped track', error);
		return points;
	}
	return (data ?? points) as typeof points;
}

/// Recent public runs from a single user — used by the profile page.
export async function fetchPublicRunsByUser(userId: string, limit = 20): Promise<Run[]> {
	const { data } = await supabase
		.from('runs')
		.select('*')
		.eq('user_id', userId)
		.eq('is_public', true)
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
export async function fetchRunComments(runId: string): Promise<RunCommentWithAuthor[]> {
	const { data: rows, error } = await supabase
		.from('run_comments')
		.select('*')
		.eq('run_id', runId)
		.order('created_at', { ascending: true });
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
	caption: string | null;
	position_idx: number;
	created_at: string;
	url: string;
}

const PHOTO_MIME_TO_EXT: Record<string, string> = {
	'image/jpeg': 'jpg',
	'image/png': 'png',
	'image/webp': 'webp',
	'image/heic': 'heic',
	'image/heif': 'heif',
};

const PHOTO_MAX_BYTES = 10 * 1024 * 1024; // 10 MB

export async function fetchRunPhotos(runId: string): Promise<RunPhoto[]> {
	const { data, error } = await supabase
		.from('run_photos')
		.select('*')
		.eq('run_id', runId)
		.order('position_idx', { ascending: true })
		.order('created_at', { ascending: true });
	if (error) {
		console.error('fetchRunPhotos failed', error);
		return [];
	}
	return (data ?? []).map((r) => ({
		...r,
		url: supabase.storage.from('run-photos').getPublicUrl(r.storage_path).data.publicUrl,
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
	return {
		...data,
		url: supabase.storage.from('run-photos').getPublicUrl(storagePath).data.publicUrl,
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

export async function fetchSegmentsForRoute(routeId: string): Promise<Segment[]> {
	const { data, error } = await supabase
		.from('segments')
		.select('*')
		.eq('route_id', routeId)
		.order('start_distance_m', { ascending: true });
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
