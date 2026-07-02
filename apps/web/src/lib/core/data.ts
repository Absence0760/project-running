/**
 * Data access layer — all Supabase queries in one place.
 */
import { supabase } from './supabase';
import { TABLES, BUCKETS, METADATA_KEYS } from './schema';
import { loadSettings, effective } from '../settings/settings';
import { privacyDefaultToIsPublic } from '../social/run_visibility';
import { bandsToRanges, type DistanceBandKey } from '../routes/distance_bands';
import { assemblePublicRoute } from '../routes/public_route_assembly';
import { stripExifFromFile } from '../util/exif_strip';
import { entriesFromTemplate } from '../nutrition/meal_template';
import { logInputFromRecipe } from '../nutrition/recipe';
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
	EventAttendance,
	RsvpStatus,
	ClubPost,
	ClubPostWithAuthor,
	RecurrenceFreq,
	EventCategory,
	EventPricing,
	EventOrder,
	Weekday,
	TrainingPlan,
	PlanWeek,
	PlanWorkout,
	ActivePlanOverview,
	PlanStatus,
	NotificationKind,
	GymSetType,
	GymExerciseModality,
	GymProgressionScheme,
	Exercise,
	ExerciseCategory,
	RouteMarker,
	RouteMarkerKind,
	Achievement,
	Challenge,
	ChallengeMetric,
	ChallengeScope,
	ChallengeWithMeta,
	ChallengeLeaderboardRow,
	ActivityType,
	Fundraiser,
	FundraiserStatus,
	FundraiserFeedEntry,
	FundraiserTotals,
	RaceListing,
	RaceProvider,
	RouteCondition,
	RouteConditionKind,
	RouteConditionSeverity
} from '../types';
export type { NotificationKind };
import { parseRunSource, parseRouteSurface, type RunSource } from '../types';
import {
	filterRelinkCandidates,
	DEFAULT_RELINK_WINDOW_DAYS,
	type RelinkCandidateRun
} from '../training/relink_candidates';
import type { GeneratedPlan, GoalEvent } from '../training/training';
import { auth } from '../stores/auth.svelte';
import { compareLeaderboard } from '../runs/race_leaderboard';
import type { RecapPeriodKind } from '../types';
import { normaliseExerciseName } from '../gym/gym_prs';
import type { YearInRunningRecap } from '../runs/recap';
import type {
	CoachAthleteStatus,
	SessionPlan,
	SessionPlanBlock,
	SessionPlanItem,
	SessionPlanWithItems,
	SessionItemKind,
	ReportTargetKind
} from '../types';
// Re-export the session-plan domain shapes so consumers can import them from the
// data-layer facade alongside fetchSessionPlan* (which returns SessionPlanWithItems)
// and the SessionPlan*Input types defined below.
export type { SessionPlan, SessionPlanBlock, SessionPlanItem, SessionPlanWithItems } from '../types';
// ReportTargetKind lives in types.ts alongside the other CHECK-paired narrow
// unions (so the CHECK<->union guard can read it from one file); re-exported
// here so the report surfaces keep importing it from the data-layer facade.
export type { ReportTargetKind } from '../types';
import { nextInstanceAfter } from '../social/recurrence';
import {
	parseGymTemplate,
	type EventGymTemplate
} from '../social/event_gym_template';
import { rateLimitErrorMessage } from '../util/rate_limit_errors';
import type { ParsedResultRow } from '../runs/event_results_csv';
import { applyRunMetadataPatch, normalisePlanWorkoutNotes } from './data_normalise';
import { bucketWeeklyMileage } from './weekly_mileage';
import { chunk, mergeFeedPages, FEED_FOLLOWEE_CHUNK } from '../social/feed_merge';
import {
	assignCompetitionRanks,
	type SegmentAgeBand,
	type SegmentGenderFilter,
} from '../segments/segments';

// --- Runs ---

export interface FetchRunsOptions {
	/** Cap the number of rows returned. Pair with `offset` for paging. */
	limit?: number;
	/** Skip this many rows before the page (for paged loads). */
	offset?: number;
	/**
	 * Re-throw a hard fetch error instead of degrading to `[]`. Default off:
	 * most callers want a resilient empty list. The personal heatmap opts in
	 * so it can tell "fetch failed" (retryable error) apart from "no runs yet"
	 * (empty state) — returning `[]` on a 500 would tell an active runner
	 * they've never run anywhere.
	 */
	throwOnError?: boolean;
}

export async function fetchRuns(opts?: FetchRunsOptions): Promise<Run[]> {
	// Explicit user_id filter as defence in depth — RLS already scopes
	// runs to the caller, but every other personal-data list in this
	// file follows the same explicit-scope pattern. See audit
	// `/tmp/data-isolation-audit/client-realtime.md` M2.
	const userId = auth.user?.id;
	if (!userId) return [];
	const build = () =>
		supabase
			.from(TABLES.runs)
			.select('*')
			.eq('user_id', userId)
			.order('started_at', { ascending: false });

	let rows: any[];
	if (opts?.limit != null) {
		const from = opts.offset ?? 0;
		const { data, error } = await build().range(from, from + opts.limit - 1);
		if (error || !data) {
			if (opts?.throwOnError && error) throw error;
			return [];
		}
		rows = data;
	} else {
		// No explicit limit means "every run". PostgREST caps an unbounded
		// SELECT at 1000 rows, which silently dropped the oldest activities
		// of a high-volume history (a 1,500-run Strava migrant lost ~500)
		// across recap / heatmap / dashboard / account / runs. Page through
		// instead so nothing is truncated; the safety ceiling logs rather
		// than dropping silently. Theme C (strava-migration / pro).
		const PAGE = 1000;
		const SAFETY_MAX = 50_000;
		rows = [];
		for (let from = 0; from < SAFETY_MAX; from += PAGE) {
			const { data, error } = await build().range(from, from + PAGE - 1);
			if (error || !data) {
				if (opts?.throwOnError && error) throw error;
				break;
			}
			rows.push(...data);
			if (data.length < PAGE) break;
		}
		if (rows.length >= SAFETY_MAX) {
			console.warn(`fetchRuns reached the ${SAFETY_MAX}-row ceiling; older runs may be omitted`);
		}
	}
	// Defensive narrow on read: the DB CHECK constraint stops bad
	// `source` values at write time, but historical rows imported before
	// the constraint or rows from a future client whose new value
	// hasn't propagated to this build need a fallback. parseRunSource
	// coerces unknowns to 'app'.
	return rows.map((r: any) => ({
		...r,
		source: parseRunSource(r.source),
		track: null,
	}));
}

/// Runs for the signed-in user that surface a hard fetch failure instead of
/// degrading to `[]`. `fetchRuns` returns an empty list on a network / DB
/// error, which is indistinguishable from a brand-new account with zero runs
/// — so the /runs + /history surfaces showed the "log your first run"
/// onboarding card (with no retry) on a transient failure. This sibling
/// distinguishes the two: `error` is non-null only on a real failure; a
/// genuinely-empty result is `{ runs: [], error: null }`. Mirrors the
/// `fetchFoodLogWithError` convention. A signed-out caller is empty, not an
/// error (nothing to load yet).
export async function fetchRunsWithError(
	opts?: FetchRunsOptions,
): Promise<{ runs: Run[]; error: string | null }> {
	try {
		const runs = await fetchRuns({ ...opts, throwOnError: true });
		return { runs, error: null };
	} catch (e) {
		return { runs: [], error: (e as Error)?.message ?? 'Failed to load runs' };
	}
}

/// Supplementary counts for the Year-in-Running recap that can't be
/// derived from `Run` rows alone (see `recap.ts#RecapExtras`): photos
/// attached to the year's runs, and personal records achieved during the
/// year. Both are scoped to the signed-in user (RLS + an explicit filter,
/// matching every other personal-data read here). Year bounds are UTC;
/// the recap aggregate itself buckets runs by local year, so a run within
/// a few hours of the boundary can disagree — acceptable for headline
/// counts on a wrap-up card.
export async function fetchRecapExtras(
	year: number,
): Promise<{ photoCount: number; personalRecordCount: number }> {
	const userId = auth.user?.id;
	if (!userId) return { photoCount: 0, personalRecordCount: 0 };
	const start = `${year}-01-01T00:00:00Z`;
	const end = `${year + 1}-01-01T00:00:00Z`;

	const [photos, prs] = await Promise.all([
		supabase
			.from(TABLES.run_photos)
			.select('id, runs!inner(started_at)', { count: 'exact', head: true })
			.eq('owner_id', userId)
			.gte('runs.started_at', start)
			.lt('runs.started_at', end),
		supabase
			.from(TABLES.personal_records)
			.select('user_id', { count: 'exact', head: true })
			.eq('user_id', userId)
			.gte('achieved_at', start)
			.lt('achieved_at', end),
	]);

	return {
		photoCount: photos.error ? 0 : photos.count ?? 0,
		personalRecordCount: prs.error ? 0 : prs.count ?? 0,
	};
}

/// Publish (or re-publish) a recap as a public, OG-unfurlable snapshot and
/// return its share id (the uuid in the /recap/share/[id] link). Owner-only:
/// RLS rejects writes for any other user. The snapshot is FROZEN aggregate
/// data only (totals / badges / monthly strip) — no GPS, no per-run rows.
/// Upserts on (user_id, period_kind, period_key) so re-publishing the same
/// period refreshes the same link instead of minting a new one. Returns null
/// when signed-out or the write fails (the caller surfaces the failure).
export async function publishRecap(
	periodKind: RecapPeriodKind,
	periodKey: string,
	snapshot: YearInRunningRecap,
): Promise<string | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data, error } = await supabase
		.from(TABLES.public_recaps)
		.upsert(
			{
				user_id: userId,
				period_kind: periodKind,
				period_key: periodKey,
				snapshot: snapshot as unknown as Record<string, unknown>,
			},
			{ onConflict: 'user_id,period_kind,period_key' },
		)
		.select('id')
		.single();
	if (error || !data) {
		console.warn('publishRecap failed', error);
		return null;
	}
	return data.id;
}

/// Fetch a published recap snapshot by its share id. Anon-readable via the
/// public_recap_by_id RPC (the id is the capability token; the bare table is
/// not enumerable — migration 20270305_001). Used by the public share page;
/// returns null when the id doesn't resolve (never published, or revoked).
export async function fetchPublicRecap(
	id: string,
): Promise<{ periodKind: RecapPeriodKind; periodKey: string; snapshot: YearInRunningRecap } | null> {
	const { data, error } = await supabase
		.rpc('public_recap_by_id', { p_id: id })
		.maybeSingle();
	const row = data as {
		period_kind?: string | null;
		period_key?: string | null;
		snapshot?: unknown;
	} | null;
	if (error || !row?.period_kind || !row.period_key) return null;
	return {
		periodKind: row.period_kind as RecapPeriodKind,
		periodKey: row.period_key,
		snapshot: row.snapshot as unknown as YearInRunningRecap,
	};
}

export async function fetchRunById(id: string): Promise<Run | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data } = await supabase
		.from(TABLES.runs)
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
): Promise<{ id: string; route_id: string | null; distance_m: number; duration_s: number; activity_type: string | null }[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data, error } = await supabase
		.from(TABLES.runs)
		.select('id, route_id, distance_m, duration_s, activity_type')
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
	const { data, error } = await supabase.storage.from(BUCKETS.runs).download(path);
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

/// Owner-only fetch of the indoor/treadmill HR sidecar
/// (`{user_id}/{run_id}.hr.json.gz`, decisions §116). Same Storage pipeline as
/// the track. Returns the `{ bpm, ts? }` series; used by the run-detail HR-zone
/// breakdown when the GPS track carries no per-point bpm. The sidecar holds no
/// location, so unlike the track there is no non-owner / clipped variant — it
/// is never exposed off the owner's own run detail.
export async function fetchHrSeries(
	path: string,
): Promise<Array<{ bpm: number; ts?: string }>> {
	const series = await fetchTrack(path);
	if (!Array.isArray(series)) return [];
	return series.filter(
		(s): s is { bpm: number; ts?: string } =>
			!!s && typeof s.bpm === 'number',
	);
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
	await supabase.from(TABLES.runs).update({ route_id: routeId }).eq('id', runId);
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
/// back to the raw track. L4 per docs/architecture/conventions.md § Layered
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
		.from(TABLES.runs)
		.select('track_url, hr_series_url')
		.eq('id', id)
		.single();
	// Both Storage sidecars (GPS track + indoor HR series) are removed
	// alongside the row so the bucket doesn't accumulate orphans.
	const orphanPaths = [run?.track_url, run?.hr_series_url].filter(
		(p): p is string => !!p,
	);
	if (orphanPaths.length > 0) {
		try {
			await supabase.storage.from(BUCKETS.runs).remove(orphanPaths);
		} catch (e) {
			// Don't log the storage path — it embeds the user's auth
			// UUID and would land in Sentry breadcrumbs. The Sentry
			// hook redacts known signed-URL patterns but the row's
			// storage path doesn't match those. The run id is
			// sufficient to triangulate from server logs.
			console.warn('deleteRun: storage removal failed (orphaned file)', { run_id: id, error: e });
		}
	}
	const { data: photos } = await supabase
		.from(TABLES.run_photos)
		.select('storage_path, thumb_512_path')
		.eq('run_id', id);
	if (photos && photos.length > 0) {
		// Sweep both the original upload AND the worker-generated 512-wide
		// thumbnail. Until the audit/storage pass landed, `deleteRun` only
		// removed `storage_path`; the row cascade-deleted (so the Storage
		// SELECT policy hides the bytes via the run_photos join) but the
		// thumbnail blob persisted in the bucket indefinitely, paying for
		// storage cost and leaving a latent privacy footprint. Both paths
		// are best-effort — the row delete is more important than the
		// file cleanup.
		const paths = photos
			.flatMap((p: { storage_path: string | null; thumb_512_path: string | null }) => [
				p.storage_path,
				p.thumb_512_path,
			])
			.filter((p: string | null): p is string => !!p);
		if (paths.length > 0) {
			try {
				await supabase.storage.from(BUCKETS.run_photos).remove(paths);
			} catch (e) {
				console.warn('deleteRun: photo storage removal failed (orphaned files)', { run_id: id, count: paths.length, error: e });
			}
		}
	}
	const { error } = await supabase.from(TABLES.runs).delete().eq('id', id);
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
		.from(TABLES.runs)
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
	await supabase.from(TABLES.fitness_snapshots).insert({
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
		.from(TABLES.fitness_snapshots)
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
	const { summarizeRouteFromTrack } = await import('../routes/route_simplify');
	if (track.length < 2) throw new Error('Not enough GPS points to save a route');
	const { waypoints, distance_m, elevation_m } = summarizeRouteFromTrack(track, 10);

	const { data: authUser } = await supabase.auth.getUser();
	const userId = authUser.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const { data, error } = await supabase
		.from('routes')
		.insert({
			user_id: userId,
			// Defence in depth — the call site already trims, but a
			// future non-prompt caller (bulk run→route conversion, an
			// automation) shouldn't be able to write whitespace.
			name: name.trim(),
			waypoints,
			distance_m,
			elevation_m,
			is_public: false,
		})
		.select('id')
		.single();
	if (error) throw error;

	// Back-link the run to its new route for convenience on the
	// run-detail page. Best-effort — the route insert is the important
	// bit. Swallow any RLS or FK miss silently.
	try {
		await supabase.from(TABLES.runs).update({ route_id: data.id }).eq('id', runId);
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
/// Map the user's `privacy_default` preference to the `runs.is_public`
/// boolean for a newly-created run. Only `public` yields a public run;
/// `followers` and `private` stay private (runs have no followers-only
/// visibility tier — see docs/backend/settings.md). Mirrors mobile
/// `Preferences.newRunsArePublic`. Web previously ignored this entirely
/// (runs always landed at the `is_public default false`), so a runner who
/// chose `public` still got private runs from web saves + imports
/// (comeback persona #27). Fail-closed: any settings-read failure → private.
async function defaultRunIsPublic(userId: string): Promise<boolean> {
	try {
		const settings = await loadSettings(userId);
		return privacyDefaultToIsPublic(effective<string>(settings, 'privacy_default', 'followers'));
	} catch {
		return false;
	}
}

export async function createManualRun(input: {
	startedAt: string; // ISO UTC
	durationS: number;
	distanceM: number;
	activityType?: 'run' | 'walk' | 'hike' | 'cycle' | 'stroller';
	notes?: string | null;
	routeId?: string | null;
	/// Per-run visibility override. When omitted, falls back to the user's
	/// `privacy_default` preference (`public` → public, else private).
	isPublic?: boolean;
}): Promise<{ id: string }> {
	const { data: authUser } = await supabase.auth.getUser();
	const userId = authUser.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const isPublic = input.isPublic ?? (await defaultRunIsPublic(userId));

	const metadata: Record<string, unknown> = {
		[METADATA_KEYS.manual_entry]: true,
	};
	if (input.notes && input.notes.trim()) metadata[METADATA_KEYS.notes] = input.notes.trim();

	const { data, error } = await supabase
		.from(TABLES.runs)
		.insert({
			user_id: userId,
			started_at: input.startedAt,
			duration_s: input.durationS,
			distance_m: input.distanceM,
			source: 'app',
			activity_type: input.activityType ?? 'run',
			metadata,
			route_id: input.routeId ?? null,
			is_public: isPublic,
		})
		.select('id')
		.single();
	if (error) throw error;
	const runId = data.id as string;

	try {
		const runDate = input.startedAt.slice(0, 10);
		await autoMatchRunToPlanWorkout(runId, runDate, input.distanceM);
	} catch (e) {
		console.warn('autoMatchRunToPlanWorkout failed', e);
	}

	return { id: runId };
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
	/// Real `runs.activity_type` column (20261207_001). Defaults to 'run'.
	activity_type?: 'run' | 'walk' | 'hike' | 'cycle' | 'stroller';
	metadata: Record<string, unknown> | null;
	track?: Array<{ lat: number; lng: number; ele?: number; ts?: string; bpm?: number }>;
	/// Per-point HR for a trackless (indoor / treadmill) run. Uploaded as the
	/// `{user_id}/{run_id}.hr.json.gz` sidecar only when `track` carries no bpm,
	/// so the run-detail HR-zone chart has a series without faking coordinates
	/// (decisions §116). Ignored when the track already has per-point bpm.
	hrSeries?: Array<{ bpm: number; ts?: string }>;
	title?: string | null;
	/// Cross-source dedupe key (e.g. `strava:1234567`, `csv:<iso>-<dist>-<dur>`).
	/// Saved into runs.external_id so a subsequent import of the same
	/// activity by any path can detect + skip. /audit/strava M3.
	external_id?: string | null;
	/// Per-run visibility override. When omitted, falls back to the user's
	/// `privacy_default` preference. Importers omit it so a bulk import
	/// honours the runner's default visibility.
	isPublic?: boolean;
}): Promise<{ id: string; trackUploaded: boolean; trackError?: string }> {
	const { data: authUser } = await supabase.auth.getUser();
	const userId = authUser.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const isPublic = input.isPublic ?? (await defaultRunIsPublic(userId));

	// elevation_m and title are not columns on `runs` (elevation_m lives on
	// `routes`; title has no DB column). Merge both into metadata so they
	// survive the round-trip. See docs/backend/metadata.md for the registered keys.
	const mergedMetadata: Record<string, unknown> = { ...(input.metadata ?? {}) };
	if (input.title) mergedMetadata[METADATA_KEYS.title] = input.title;
	if (input.elevation_m != null) mergedMetadata[METADATA_KEYS.elevation_m] = input.elevation_m;
	const row: Record<string, unknown> = {
		user_id: userId,
		started_at: input.started_at,
		distance_m: input.distance_m,
		duration_s: input.duration_s,
		source: input.source,
		activity_type: input.activity_type ?? 'run',
		metadata: mergedMetadata,
		is_public: isPublic,
	};
	if (input.external_id) row.external_id = input.external_id;

	const { data, error } = await supabase
		.from(TABLES.runs)
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
				.from(TABLES.runs)
				.upload(path, new Blob([gzipped as BlobPart], { type: 'application/gzip' }), {
					contentType: 'application/gzip',
					upsert: true,
				});
			if (upErr) {
				trackError = upErr.message;
			} else {
				const { error: linkErr } = await supabase
					.from(TABLES.runs)
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

	// HR sidecar for a trackless run (indoor / treadmill). Only when the track
	// carries no per-point bpm — an outdoor run's HR already rides on the track
	// points, so a sidecar would be redundant. Failure is non-fatal (same
	// contract as the track upload): the row's scalar avg_bpm still renders.
	const trackHasBpm = !!input.track?.some((p) => p.bpm != null);
	if (trackHasBpm && input.hrSeries && input.hrSeries.length > 0) {
		// Mixed run (GPS records + fix-less HR records, e.g. a treadmill warm-up
		// stretch). The track's per-point bpm drives the zone chart, so the
		// fix-less hrSeries is intentionally dropped — but surface it so the
		// partial-coverage case isn't silently invisible. (decisions §116)
		console.warn(
			`saveRun: ${input.hrSeries.length} fix-less HR samples dropped — track already carries per-point bpm`,
		);
	}
	if (!trackHasBpm && input.hrSeries && input.hrSeries.length >= 1) {
		try {
			const path = `${userId}/${runId}.hr.json.gz`;
			const encoded = new TextEncoder().encode(JSON.stringify(input.hrSeries));
			const gzipped = await gzipBytes(encoded);
			const { error: upErr } = await supabase.storage
				.from(TABLES.runs)
				.upload(path, new Blob([gzipped as BlobPart], { type: 'application/gzip' }), {
					contentType: 'application/gzip',
					upsert: true,
				});
			if (upErr) {
				console.warn('hr-series sidecar upload failed', upErr.message);
			} else {
				// Mirror the track-upload error handling: a PostgREST error here is
				// a resolved { error }, not a throw, so the outer catch can't see
				// it — check it explicitly or the sidecar orphans silently.
				const { error: linkErr } = await supabase
					.from(TABLES.runs)
					.update({ hr_series_url: path })
					.eq('id', runId);
				if (linkErr) {
					console.warn('hr-series sidecar row-link failed', linkErr.message);
				}
			}
		} catch (e) {
			console.warn('hr-series sidecar upload failed', e);
		}
	}

	try {
		const runDate = input.started_at.slice(0, 10);
		await autoMatchRunToPlanWorkout(runId, runDate, input.distance_m);
	} catch (e) {
		console.warn('autoMatchRunToPlanWorkout failed', e);
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
		.from(TABLES.runs)
		.select('metadata')
		.eq('id', id)
		.single();
	if (!run) throw new Error('Run not found');
	// Trim + drop empty-after-trim keys so clearing a field via the
	// edit dialog actually removes the key from the metadata bag
	// instead of leaving `notes: ""` behind. Mobile's run-detail
	// edit dialog applies the same normalisation. Logic lives in
	// data_normalise.ts so the contract can be unit-tested.
	const next = applyRunMetadataPatch(
		run.metadata as Record<string, unknown> | null | undefined,
		fields,
		new Date().toISOString(),
	);
	const { error } = await supabase
		.from(TABLES.runs)
		.update({ metadata: next })
		.eq('id', id);
	if (error) throw error;
}

// --- Route reviews ---

export async function getRouteReviews(routeId: string, limit = 100) {
	const { data, error } = await supabase
		.from(TABLES.route_reviews)
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
	const { error } = await supabase.from(TABLES.route_reviews).upsert(
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
		// Treat empty-string surface the same as null (no filter) —
		// matches mobile's `ApiClient.searchPublicRoutes`, which gates
		// on `surface.isNotEmpty`. Previously web passed `''` straight
		// through to the RPC, where `surface = ''` matches no rows
		// and the user saw an empty result list rather than the full
		// catalogue.
		p_surface: surface && surface.length > 0 ? surface : null,
		p_tags: tags && tags.length > 0 ? tags : null,
		p_featured_only: featuredOnly ?? false,
		p_sort: sort,
		p_limit: limit,
		p_offset: offset,
	});
	// Throw on error rather than collapsing to []: the sole caller
	// (RouteExplorer) needs to tell a genuine load failure apart from a
	// legitimately empty result so it can show a retry affordance instead
	// of a misleading "no matches" empty state.
	if (error) throw error;
	return (data ?? []) as Route[];
}

/// The set of tags currently used across any public route, ordered by
/// most-used. Powers the filter chip row on /explore.
///
/// Goes through the `popular_route_tags` RPC (migration 20260502_001;
/// rewritten in 20260703_001 to read from the `public_routes` view).
/// The RPC aggregates server-side with `count(*)` + `order by count desc,
/// tag asc`, so the result is stable, cap-free, and matches mobile's
/// `ApiClient.fetchPopularRouteTags` byte-for-byte.
///
/// The previous client-side aggregation was capped at 500 rows (a
/// known limitation noted in the original comment); past that the
/// chip row would silently mis-represent the popular-tag tail.
export async function fetchPopularRouteTags(limit = 20): Promise<string[]> {
	const { data } = await supabase.rpc('popular_route_tags', {
		tag_limit: limit,
	});
	if (!Array.isArray(data)) return [];
	return (data as Array<{ tag: string }>).map((r) => r.tag);
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

	const [ownedRes, savedIdsRes] = await Promise.all([
		supabase
			.from('routes')
			.select('*')
			.eq('user_id', userId)
			.order('created_at', { ascending: false }),
		supabase
			.from('saved_routes')
			.select('route_id, saved_at')
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

	// Saved routes can't be embedded as `route:routes(*)` off saved_routes:
	// the base `routes` SELECT RLS only exposes the caller's own + club
	// routes, so a bookmarked route owned by ANOTHER user (the dominant
	// case — you save other people's routes from Explore) joins to null and
	// silently vanishes from My routes. Read the saved bodies by id from the
	// `public_routes` view (which exposes every public route's metadata,
	// the same privacy-preserving path Explore uses — waypoints stay behind
	// clip_route_for_viewer) AND the base table (for own / club-visible
	// saved routes), then union, preferring the fuller base-table row.
	const savedIds = ((savedIdsRes.data ?? []) as { route_id: string }[]).map(
		(r) => r.route_id,
	);
	let saved: Route[] = [];
	if (savedIds.length > 0) {
		const [savedBaseRes, savedPublicRes] = await Promise.all([
			supabase.from('routes').select('*').in('id', savedIds),
			supabase.from('public_routes').select('*').in('id', savedIds),
		]);
		const byId = new Map<string, Route>();
		for (const r of [
			...((savedBaseRes.data ?? []) as Route[]),
			...((savedPublicRes.data ?? []) as unknown as Route[]),
		]) {
			if (!byId.has(r.id)) byId.set(r.id, r);
		}
		// Preserve the saved_at-desc order the id list already carries.
		saved = savedIds
			.map((id) => byId.get(id))
			.filter((r): r is Route => r != null);
	}

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
	if (ownerRead.data) {
		// `shadow_hidden` is a server-/trigger-owned moderation column
		// (migration 20270218_001) the client has no business reading; the
		// `public_routes` view already projects it away, so strip it from the
		// base-table owner read too. `surface` is narrowed through the same
		// defensive parse `fetchRunById` uses for `source`, so a value outside
		// the RouteSurface union can't leak past the read boundary.
		const { shadow_hidden, ...rest } = ownerRead.data as typeof ownerRead.data & {
			shadow_hidden?: boolean;
		};
		void shadow_hidden;
		return { ...rest, surface: parseRouteSurface(rest.surface) } as Route;
	}

	// The metadata read and the server-clip RPC both key only on `id`, so
	// fire them concurrently instead of serialising two round trips.
	const assembled = await assemblePublicRoute(
		async () =>
			(await supabase.from('public_routes').select('*').eq('id', id).maybeSingle()).data,
		() => fetchClippedRouteForViewer(id),
	);
	if (!assembled) return null;

	// public_routes intentionally omits `waypoints`, `geom`, `start_point`,
	// and `is_starred`; pad them out so downstream consumers that read
	// these keys still get a defined shape (empty arrays / nulls).
	return {
		...assembled.meta,
		waypoints: assembled.clipped,
		is_starred: false,
	} as Route;
}

/// Public-share read path. Same redaction shape as `fetchRouteById`'s
/// non-owner branch — kept as a separate export so call sites that
/// only ever intend to read a public route stay explicit.
export async function fetchPublicRoute(id: string): Promise<Route | null> {
	// Both reads key only on `id`; run them concurrently so the anon
	// share / OG-image path pays one round trip's latency, not two.
	const assembled = await assemblePublicRoute(
		async () =>
			(await supabase.from('public_routes').select('*').eq('id', id).maybeSingle()).data,
		() => fetchClippedRouteForViewer(id),
	);
	if (!assembled) return null;
	return {
		...assembled.meta,
		waypoints: assembled.clipped,
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
	description?: string | null;
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
			description: route.description?.trim() || null,
		})
		.select()
		.single();

	if (error) {
		// Surface the create_route rate-limit P0001 (migration
		// 20260907_001 — 30 routes / hour per user, generous enough for
		// bulk Strava / Garmin imports) as a friendlier "wait N minutes"
		// message instead of the raw postgres exception.
		const friendly = rateLimitErrorMessage(error);
		if (friendly) throw new Error(friendly);
		throw error;
	}
	return data;
}

export async function deleteRoute(id: string): Promise<void> {
	const { data: photos } = await supabase
		.from(TABLES.route_photos)
		.select('storage_path, thumb_512_path')
		.eq('route_id', id);
	if (photos && photos.length > 0) {
		// Sweep route-photo blobs before the row delete. The FK cascade
		// removes the route_photos rows (so the Storage SELECT join hides
		// the bytes), but the blobs would otherwise orphan in the bucket —
		// the same gap deleteRun closes for run photos. Best-effort.
		const paths = photos
			.flatMap((p: { storage_path: string | null; thumb_512_path: string | null }) => [
				p.storage_path,
				p.thumb_512_path,
			])
			.filter((p: string | null): p is string => !!p);
		if (paths.length > 0) {
			try {
				await supabase.storage.from(BUCKETS.route_photos).remove(paths);
			} catch (e) {
				console.warn('deleteRoute: photo storage removal failed (orphaned files)', { route_id: id, count: paths.length, error: e });
			}
		}
	}
	const { error } = await supabase.from('routes').delete().eq('id', id);
	if (error) throw error;
}

// --- Dashboard stats ---

export async function fetchWeeklyMileage(
	locale?: string,
	weekStartDay: 'monday' | 'sunday' = 'monday',
) {
	const { data: { user } } = await supabase.auth.getUser();
	if (!user) return [];
	// Only the last ~12 weeks are charted, so window the query by date
	// rather than `.limit(2000)` ascending — that cap returned a >2000-run
	// user's OLDEST 2000 runs, so the chart showed ancient weeks. A 14-week
	// window (12 + a 2-week buffer for partial edges) is bounded and recent.
	const windowStart = new Date();
	windowStart.setDate(windowStart.getDate() - 14 * 7);
	const { data: runs } = await supabase
		.from(TABLES.runs)
		.select('started_at, distance_m')
		.eq('user_id', user.id)
		.gte('started_at', windowStart.toISOString())
		.order('started_at', { ascending: true });

	if (!runs || runs.length === 0) return [];
	return bucketWeeklyMileage(runs, 12, locale, weekStartDay);
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
		.from(TABLES.personal_records)
		.select('distance, best_time_s, achieved_at')
		.eq('user_id', userId);

	if (!data || data.length === 0) return [];

	const labels: Record<string, string> = {
		'1_mile': 'Mile',
		'5k': '5k',
		'10k': '10k',
		half_marathon: 'Half Marathon',
		marathon: 'Marathon',
	};
	const order: Record<string, number> = {
		'1_mile': 0,
		'5k': 1,
		'10k': 2,
		half_marathon: 3,
		marathon: 4,
	};

	return data
		.slice()
		.sort((a, b) => (order[a.distance] ?? 99) - (order[b.distance] ?? 99))
		.map((r) => ({
			key: r.distance as string,
			distance: labels[r.distance] ?? r.distance,
			time_s: r.best_time_s,
			date: r.achieved_at.slice(0, 10),
		}));
}

// --- Integrations ---

export async function fetchIntegrations(): Promise<Integration[]> {
	const userId = auth.user?.id;
	if (!userId) return [];

	// Filter out rows with `disconnected_at is not null` — those are
	// integrations the user disconnected (or whose grant Strava
	// revoked). The integrations row stays around for the audit
	// trail + so the UI can show "Reconnect Strava", but the
	// connected-integration list shown on /settings/integrations
	// should treat them as gone. /audit/strava High #1 + H2.
	const { data } = await supabase
		.from(TABLES.integrations)
		.select('*')
		.eq('user_id', userId)
		.is('disconnected_at', null);

	return data ?? [];
}

export async function connectIntegration(provider: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const { error } = await supabase.from(TABLES.integrations).upsert(
		{ user_id: userId, provider },
		{ onConflict: 'user_id,provider' }
	);
	if (error) throw error;
}

export async function disconnectIntegration(provider: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	// audit/strava May 2026 High #1 — Strava goes through the EF
	// so the access token gets revoked at Strava's end + vault rows
	// get wiped + `disconnected_at` is stamped. Pre-fix the path was
	// a bare DELETE on the integrations row which left vault material
	// orphaned + the Strava-side connection live indefinitely.
	if (provider === 'strava') {
		const { error: fnError } = await supabase.functions.invoke('strava-import', {
			body: { action: 'disconnect' },
		});
		if (fnError) throw fnError;
		return;
	}

	const { error } = await supabase
		.from(TABLES.integrations)
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
	'id, owner_id, name, slug, description, avatar_url, location_label, is_public, is_verified, join_policy, member_count, requires_activity_waiver, website_url, instagram_url, strava_url, facebook_url, shadow_hidden, created_at, updated_at' as const;

// Column-level grant lockdown: `meet_lat` / `meet_lng` are revoked
// from anon + authenticated (migrations 20260723_001 + 20260806_001 +
// 20260818_001 redo). Selecting `*` raises 42501. Every read
// enumerates these safe columns; the two coords are write-only
// today (no UI consumer).
const EVENT_SELECT_COLS =
	'id, club_id, title, description, starts_at, timezone, duration_min, meet_label, route_id, distance_m, pace_target_sec, capacity, author_id, created_at, updated_at, recurrence_freq, recurrence_byday, recurrence_until, recurrence_count, category, discipline, gym_template, session_plan_id, is_public' as const;

function slugify(name: string): string {
	return name
		.toLowerCase()
		.trim()
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-|-$/g, '')
		.slice(0, 48);
}

/** Browse public clubs. Most recently created first. */
export async function browseClubsWithError(
	search?: string
): Promise<{ clubs: ClubWithMeta[]; error: string | null }> {
	let query = supabase.from('clubs').select(CLUB_SELECT_COLS).eq('is_public', true);
	if (search && search.trim()) {
		const term = search.trim();
		query = query.or(`name.ilike.%${term}%,location_label.ilike.%${term}%`);
	}
	const { data, error } = await query.order('created_at', { ascending: false }).limit(60);
	if (error) return { clubs: [], error: error.message };
	return { clubs: data ? await enrichClubs(data) : [], error: null };
}

export async function browseClubs(search?: string): Promise<ClubWithMeta[]> {
	return (await browseClubsWithError(search)).clubs;
}

/// Region-aware club search. Tries to geocode the query first
/// (so "Virginia" → centroid + ~470km radius → ST_DWithin against
/// `clubs.location_point`); falls back to the same ILIKE-on-name /
/// label path `browseClubs` uses when geocoding doesn't resolve
/// (short query, MapTiler offline, no key, etc.). See
/// [migration 20260905_001] for the RPC.
export async function searchClubsWithError(
	query: string
): Promise<{ clubs: ClubWithMeta[]; error: string | null }> {
	const term = query.trim();
	if (!term) return browseClubsWithError();

	// Geocode in the background while we kick off the RPC. The RPC's
	// text-only path doesn't need the geocode, so we can race the two
	// only if we accept "geographic matches appear on the second
	// render" — for now, await geocoding first so the first render
	// has both branches. Geocoding usually settles in <300ms.
	const { geocodePlace } = await import('../routes/geocoding');
	const place = await geocodePlace(term);

	const { data, error } = await supabase.rpc('search_clubs', {
		p_query: term,
		p_center_lng: place?.center.lng ?? undefined,
		p_center_lat: place?.center.lat ?? undefined,
		p_radius_m: place?.radiusM ?? undefined,
		p_limit: 60,
	});
	if (error) {
		console.warn('search_clubs RPC failed, falling back to ILIKE-only', error);
		return browseClubsWithError(term);
	}
	// The RPC returns `setof clubs` — strip the columns the client
	// shape doesn't include (location_point, invite_token).
	const rows = ((data ?? []) as Record<string, unknown>[]).map((r) => ({
		id: r.id as string,
		owner_id: r.owner_id as string,
		name: r.name as string,
		slug: r.slug as string,
		description: (r.description ?? null) as string | null,
		avatar_url: (r.avatar_url ?? null) as string | null,
		location_label: (r.location_label ?? null) as string | null,
		is_public: r.is_public as boolean,
		is_verified: (r.is_verified as boolean | undefined) ?? false,
		join_policy: (r.join_policy ?? 'open') as JoinPolicy,
		member_count: (r.member_count ?? 0) as number,
		requires_activity_waiver: (r.requires_activity_waiver as boolean | undefined) ?? false,
		website_url: (r.website_url ?? null) as string | null,
		instagram_url: (r.instagram_url ?? null) as string | null,
		strava_url: (r.strava_url ?? null) as string | null,
		facebook_url: (r.facebook_url ?? null) as string | null,
		shadow_hidden: (r.shadow_hidden as boolean | undefined) ?? false,
		created_at: r.created_at as string,
		updated_at: r.updated_at as string,
	}));
	return { clubs: await enrichClubs(rows), error: null };
}

export async function searchClubs(query: string): Promise<ClubWithMeta[]> {
	return (await searchClubsWithError(query)).clubs;
}

export type EventWeekday = 'MO' | 'TU' | 'WE' | 'TH' | 'FR' | 'SA' | 'SU';

export interface PublicEventFilters {
	query?: string;
	category?: 'run' | 'cycle' | 'class' | 'social';
	cadence?: 'one_off' | 'weekly' | 'biweekly' | 'monthly';
	byday?: EventWeekday;
	paid?: 'free' | 'paid';
	/// Local time-of-day bucket — resolved against each event's timezone
	/// (UTC fallback for legacy rows). morning 05–11, afternoon 12–16, evening 17–04.
	time?: 'morning' | 'afternoon' | 'evening';
	/// "Near me / near a place" centroid. Filters by the CLUB's geocoded
	/// location_point (never the event's revoked precise meet point), so clubs
	/// without a geocoded point are excluded when this is set. See migration
	/// 20270112_001 + decisions §147.
	center?: { lng: number; lat: number };
	/// Radius in metres around `center`. Defaults to 50km server-side.
	radiusM?: number;
	limit?: number;
}

/// A discoverable public-club event (the `search_public_events` row shape:
/// event + its club's name/slug + cheapest price, if any). Distinct from
/// EventWithMeta — this is the cross-club discovery projection, not a
/// club-scoped detail row.
export interface PublicEventResult {
	id: string;
	club_id: string;
	club_name: string;
	club_slug: string;
	title: string;
	category: string;
	discipline: string | null;
	starts_at: string;
	timezone: string | null;
	duration_min: number | null;
	recurrence_freq: string | null;
	recurrence_byday: string[] | null;
	capacity: number | null;
	price_cents: number | null;
	currency: string | null;
	/// Metres from the search center to the event's club, when a `center` was
	/// supplied — else null. Derived from the already-public club point, so
	/// surfacing it as a "2.3 km away" label leaks nothing.
	distance_m: number | null;
}

/// Cross-club activity discovery (migration 20270110_001). Searches PUBLIC
/// clubs' events across the typed-events model by category / discipline /
/// cadence / weekday / paid-or-free. Backs the /social Discover tab.
export async function searchPublicEvents(
	f: PublicEventFilters = {}
): Promise<PublicEventResult[]> {
	const { data, error } = await supabase.rpc('search_public_events', {
		p_query: f.query?.trim() || undefined,
		p_category: f.category ?? undefined,
		p_cadence: f.cadence ?? undefined,
		p_byday: f.byday ?? undefined,
		p_paid: f.paid ?? undefined,
		p_time: f.time ?? undefined,
		p_center_lng: f.center?.lng ?? undefined,
		p_center_lat: f.center?.lat ?? undefined,
		p_radius_m: f.radiusM ?? undefined,
		p_limit: f.limit ?? 60,
	});
	if (error) {
		throw error;
	}
	return (data ?? []) as PublicEventResult[];
}

// ── Race calendar + results import (race_calendar.md, migration 20270214_001) ──

export type RaceDistanceBand = '5k' | '10k' | 'half' | 'marathon' | 'ultra';

export interface RaceListingFilters {
	query?: string;
	distance?: RaceDistanceBand;
	from?: string; // ISO date
	to?: string; // ISO date
	center?: { lng: number; lat: number };
	radiusM?: number;
	limit?: number;
}

/// A discoverable race calendar entry (the search_race_listings projection:
/// listing cols + distance_m_away when a center was supplied).
export interface RaceListingResult {
	id: string;
	provider: string;
	provider_race_id: string | null;
	name: string;
	race_date: string;
	distance_m: number | null;
	location_label: string | null;
	entry_url: string | null;
	results_url: string | null;
	is_verified: boolean;
	distance_m_away: number | null;
}

/// Race discovery (security invoker, public clubs/listings). Mirrors
/// searchPublicEvents — proximity by the listing's geocoded location_point.
export async function searchRaceListings(
	f: RaceListingFilters = {}
): Promise<RaceListingResult[]> {
	const { data, error } = await supabase.rpc('search_race_listings', {
		p_query: f.query?.trim() || undefined,
		p_distance: f.distance ?? undefined,
		p_from: f.from ?? undefined,
		p_to: f.to ?? undefined,
		p_center_lng: f.center?.lng ?? undefined,
		p_center_lat: f.center?.lat ?? undefined,
		p_radius_m: f.radiusM ?? undefined,
		p_limit: f.limit ?? 60
	});
	if (error) throw error;
	return (data ?? []) as RaceListingResult[];
}

export interface RaceListingInput {
	provider?: RaceProvider; // defaults to 'manual'
	name: string;
	race_date: string;
	distance_m?: number | null;
	location_label?: string | null;
	entry_url?: string | null;
	results_url?: string | null;
}

/// Submit a crowd-sourced race listing. is_verified is forced false by the DB
/// trigger; submitted_by is stamped to the caller (RLS requires the match).
export async function submitRaceListing(input: RaceListingInput): Promise<RaceListing> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from('race_listings')
		.insert({
			provider: input.provider ?? 'manual',
			name: input.name.trim(),
			race_date: input.race_date,
			distance_m: input.distance_m ?? null,
			location_label: input.location_label?.trim() || null,
			entry_url: input.entry_url?.trim() || null,
			results_url: input.results_url?.trim() || null,
			submitted_by: userId
		})
		.select('*')
		.single();
	if (error) throw error;
	return data as RaceListing;
}

/// Edit one's own unverified listing (RLS locks verified ones).
export async function updateRaceListing(
	id: string,
	patch: Partial<RaceListingInput>
): Promise<void> {
	const fields: Record<string, unknown> = {};
	if (patch.name != null) fields.name = patch.name.trim();
	if (patch.race_date != null) fields.race_date = patch.race_date;
	if (patch.distance_m !== undefined) fields.distance_m = patch.distance_m;
	if (patch.location_label !== undefined)
		fields.location_label = patch.location_label?.trim() || null;
	if (patch.entry_url !== undefined) fields.entry_url = patch.entry_url?.trim() || null;
	if (patch.results_url !== undefined) fields.results_url = patch.results_url?.trim() || null;
	const { error } = await supabase.from('race_listings').update(fields).eq('id', id);
	if (error) throw error;
}

export interface ImportRaceResultInput {
	provider: 'runsignup' | 'ultrasignup' | 'chronotrack' | 'paste';
	listingId: string;
	runSignUpUserId?: string;
	ultraSignUpAthleteId?: string;
	/// ChronoTrack: filter the event's results to one bib.
	bib?: string;
	/// When set, enrich THIS existing run in place (the auto-match seam) instead
	/// of inserting a new race run.
	matchRunId?: string;
	/// paste-mode single result.
	result?: {
		bib?: string;
		chip_time?: string;
		gun_time?: string;
		overall_place?: number;
		age_group_place?: number;
		age_group?: string;
	};
}

export interface ImportRaceResultOutcome {
	imported: number;
	skipped: number;
	enriched: number;
}

/// Invoke race-results-import. Throws `RUNSIGNUP_UNAVAILABLE` /
/// `ULTRASIGNUP_UNAVAILABLE` / `CHRONOTRACK_UNAVAILABLE` when the chosen
/// provider key is unconfigured server-side (503), so the UI can show the
/// explainer rather than a generic failure.
export async function importRaceResult(
	input: ImportRaceResultInput
): Promise<ImportRaceResultOutcome> {
	const { data, error } = await supabase.functions.invoke('race-results-import', {
		body: {
			provider: input.provider,
			listingId: input.listingId,
			runSignUpUserId: input.runSignUpUserId,
			ultraSignUpAthleteId: input.ultraSignUpAthleteId,
			bib: input.bib,
			matchRunId: input.matchRunId,
			result: input.result
		}
	});
	if (error) {
		if (await isProviderNotConfigured(error)) {
			throw new Error(
				input.provider === 'ultrasignup'
					? 'ULTRASIGNUP_UNAVAILABLE'
					: input.provider === 'chronotrack'
						? 'CHRONOTRACK_UNAVAILABLE'
						: 'RUNSIGNUP_UNAVAILABLE'
			);
		}
		throw error;
	}
	return data as ImportRaceResultOutcome;
}

/// Probe whether the RunSignUp leg is configured server-side. Returns false
/// (unavailable) on a 503 provider_not_configured, true otherwise. Used to
/// disable the RunSignUp card with an explainer.
export async function isRunSignUpConfigured(): Promise<boolean> {
	const { error } = await supabase.functions.invoke('race-listings-sync', { body: {} });
	if (!error) return true;
	return !(await isProviderNotConfigured(error));
}

/// Probe whether the UltraSignup leg is configured server-side. Same fail-closed
/// shape as isRunSignUpConfigured, gating the independent UltraSignup key.
export async function isUltraSignUpConfigured(): Promise<boolean> {
	const { error } = await supabase.functions.invoke('race-listings-sync', {
		body: { provider: 'ultrasignup' }
	});
	if (!error) return true;
	return !(await isProviderNotConfigured(error));
}

/// Probe whether the ChronoTrack leg is configured server-side. Returns false
/// on a 503 provider_not_configured, true otherwise — drives the disabled
/// ChronoTrack card + explainer. Uses the race-results-import probe mode (no
/// listing needed), mirroring the RunSignUp probe shape.
export async function isChronoTrackConfigured(): Promise<boolean> {
	const { error } = await supabase.functions.invoke('race-results-import', {
		body: { provider: 'chronotrack', probe: true }
	});
	if (!error) return true;
	return !(await isProviderNotConfigured(error));
}

async function isProviderNotConfigured(error: unknown): Promise<boolean> {
	const ctx = (error as { context?: Response })?.context;
	if (ctx && typeof ctx.status === 'number' && ctx.status > 0) {
		if (ctx.status === 503) {
			try {
				const body = await ctx.clone().json();
				return (body as { error?: string })?.error === 'provider_not_configured';
			} catch {
				return true;
			}
		}
		// The probe never confirmed the provider is live: a 429 (the EF's own
		// per-user rate limit — several probes per page/test exceed the free
		// tier) or a 5xx didn't reach (or get past) the credential gate. Honour
		// the fail-closed default and report unavailable rather than offer an
		// action that will 503/429. A readable client error (other 4xx) means
		// the function DID run past the gate, so the provider is configured.
		if (ctx.status === 429 || ctx.status >= 500) return true;
		return false;
	}
	const msg = (error as { message?: string })?.message ?? '';
	if (msg.includes('provider_not_configured') || msg.includes('503')) return true;
	// No readable HTTP status — a FunctionsFetchError (network / CORS) or a
	// status-0 opaque response. supabase-js surfaces the gated 503 this way
	// when the cross-origin error response isn't readable by the browser, so
	// the probe could not CONFIRM the provider is live. Honour the feature's
	// fail-closed default (the missing-credential rule) and report unavailable
	// rather than fail open and offer an action that 503s.
	return true;
}

/// The matched-race view for a run: the run's owner-only race metadata + its
/// linked listing (when any). Owner-scoped — reads the base runs row.
export interface RaceResultForRun {
	race_listing: RaceListing | null;
	race_name: string | null;
	bib: string | null;
	chip_time: string | null;
	gun_time: string | null;
	overall_place: number | null;
	age_group_place: number | null;
	age_group: string | null;
}

export async function fetchRaceResultForRun(runId: string): Promise<RaceResultForRun | null> {
	const { data, error } = await supabase
		.from(TABLES.runs)
		.select('metadata, race_listing_id')
		.eq('id', runId)
		.maybeSingle();
	if (error || !data) return null;
	const meta = (data.metadata as Record<string, unknown> | null) ?? {};
	let listing: RaceListing | null = null;
	if (data.race_listing_id) {
		const { data: l } = await supabase
			.from('race_listings')
			.select('*')
			.eq('id', data.race_listing_id as string)
			.maybeSingle();
		listing = (l as RaceListing) ?? null;
	}
	return {
		race_listing: listing,
		race_name: (meta.race_name as string) ?? null,
		bib: (meta.bib as string) ?? null,
		chip_time: (meta.chip_time as string) ?? null,
		gun_time: (meta.gun_time as string) ?? null,
		overall_place: (meta.overall_place as number) ?? null,
		age_group_place: (meta.age_group_place as number) ?? null,
		age_group: (meta.age_group as string) ?? null
	};
}

/// The auto-match seam: given a run's id, return same-day nearby race listings
/// to offer "Is this your race?". Reads the run's date + start point, then asks
/// search_race_listings for that day's listings near the start; scoring is the
/// pure raceMatchScore (integrations/race_match.ts), applied by the caller.
export async function findRaceMatchCandidates(runId: string): Promise<RaceListingResult[]> {
	const { data: run, error } = await supabase
		.from(TABLES.runs)
		.select('started_at, track_url')
		.eq('id', runId)
		.maybeSingle();
	if (error || !run?.started_at) return [];
	const day = (run.started_at as string).slice(0, 10);
	// The run's GPS start point isn't a column; the caller passes the recorded
	// start latlng into raceMatchScore. Here we window on the date and let the
	// caller filter by proximity + distance band. A same-day window keeps the
	// candidate set tiny.
	try {
		return await searchRaceListings({ from: day, to: day, limit: 20 });
	} catch {
		return [];
	}
}

/** Clubs the current user belongs to (owner or member). */
export async function fetchMyClubsWithError(): Promise<{
	clubs: ClubWithMeta[];
	error: string | null;
}> {
	// Fall back to the session when the JS auth store hasn't hydrated yet —
	// on a fresh page load (bookmark, refresh, hard nav to /plans/new) the
	// store's user can still be null while a valid session sits in storage.
	// Without this, the first caller in a page's onMount silently gets [].
	let userId = auth.user?.id;
	if (!userId) {
		const { data: { session } } = await supabase.auth.getSession();
		userId = session?.user?.id;
	}
	if (!userId) return { clubs: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.club_members)
		.select(`club_id, role, clubs!inner(${CLUB_SELECT_COLS})`)
		.eq('user_id', userId)
		.order('joined_at', { ascending: false });
	if (error) return { clubs: [], error: error.message };
	const clubs = (data ?? []).map((row: any) => row.clubs).filter(Boolean);
	return { clubs: await enrichClubs(clubs), error: null };
}

export async function fetchMyClubs(): Promise<ClubWithMeta[]> {
	return (await fetchMyClubsWithError()).clubs;
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
			.from(TABLES.club_members)
			.select('club_id', { count: 'exact' })
			.in('club_id', ids)
			.eq('status', 'active'),
		userId
			? supabase
					.from(TABLES.club_members)
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
	/// Optional WKT-style geography point (`SRID=4326;POINT(lng lat)`).
	/// ClubEditor geocodes `location_label` via MapTiler and passes
	/// this so the new row is immediately searchable by region (see
	/// `searchClubs` + migration 20260905_001). Callers that lack a
	/// geocoded point pass `undefined` and the column stays NULL —
	/// the club is still findable via the ILIKE branch of search_clubs.
	location_point_wkt?: string;
	is_public: boolean;
	join_policy: JoinPolicy;
	requires_activity_waiver?: boolean;
	website_url?: string | null;
	instagram_url?: string | null;
	strava_url?: string | null;
	facebook_url?: string | null;
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
				location_point: input.location_point_wkt ?? null,
				is_public: input.is_public,
				join_policy: input.join_policy,
				requires_activity_waiver: input.requires_activity_waiver ?? false,
				website_url: normaliseClubLink(input.website_url),
				instagram_url: normaliseClubLink(input.instagram_url),
				strava_url: normaliseClubLink(input.strava_url),
				facebook_url: normaliseClubLink(input.facebook_url),
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
		// 23505 is the slug-uniqueness conflict — retry with a suffix.
		// Anything else (including the create_club rate-limit P0001 from
		// migration 20260907_001) bubbles. The rate-limit branch is
		// converted to a friendlier 'wait N minutes' message rather than
		// the raw `rate limit exceeded for create_club, retry in Ns`.
		if (error && error.code !== '23505') {
			const friendly = rateLimitErrorMessage(error);
			if (friendly) throw new Error(friendly);
			throw error;
		}
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
	patch: Partial<
		Pick<
			Club,
			| 'name'
			| 'description'
			| 'location_label'
			| 'is_public'
			| 'avatar_url'
			| 'website_url'
			| 'instagram_url'
			| 'strava_url'
			| 'facebook_url'
		>
	>
): Promise<void> {
	// Fail closed on a non-http(s) link so a javascript:/data: URL never
	// reaches the row (the DB CHECK is the backstop; this keeps the error
	// friendly + client-side). Empty string clears the link.
	const clean = { ...patch };
	for (const k of ['website_url', 'instagram_url', 'strava_url', 'facebook_url'] as const) {
		if (k in clean) clean[k] = normaliseClubLink(clean[k]);
	}
	const { error } = await supabase.from('clubs').update(clean).eq('id', id);
	if (error) throw error;
}

/// Trim a club link, returning null for empty / non-http(s) input so a
/// `javascript:`/`data:` URL can't be stored (XSS). The DB CHECK is the
/// authoritative backstop; this is the friendly client-side gate.
export function normaliseClubLink(raw: string | null | undefined): string | null {
	const v = (raw ?? '').trim();
	if (!v) return null;
	return /^https?:\/\//i.test(v) ? v : null;
}

export async function deleteClub(id: string): Promise<void> {
	const { error } = await supabase.from('clubs').delete().eq('id', id);
	if (error) throw error;
}

export async function joinClub(
	clubId: string,
	policy: JoinPolicy = 'open',
	ackWaiver = false,
): Promise<MembershipStatus> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const status: MembershipStatus = policy === 'request' ? 'pending' : 'active';
	const { error } = await supabase.from(TABLES.club_members).insert({
		club_id: clubId,
		user_id: userId,
		role: 'member',
		status,
		// Records the activity-risk acknowledgement when the club requires it
		// (persona #45); null when the club doesn't require a waiver.
		activity_waiver_ack_at: ackWaiver ? new Date().toISOString() : null,
	});
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
		.from(TABLES.club_members)
		.select('club_id, user_id, role, status, joined_at')
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
		.from(TABLES.club_members)
		.update({ status: 'active' })
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw error;
}

export async function bulkApproveMembers(clubId: string, userIds: string[]): Promise<void> {
	if (userIds.length === 0) return;
	const { error } = await supabase
		.from(TABLES.club_members)
		.update({ status: 'active' })
		.eq('club_id', clubId)
		.eq('status', 'pending')
		.in('user_id', userIds);
	if (error) throw error;
}

export async function setMemberRole(
	clubId: string,
	userId: string,
	role: 'admin' | 'event_organiser' | 'race_director' | 'member'
): Promise<void> {
	const { error } = await supabase
		.from(TABLES.club_members)
		.update({ role })
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw error;
}

export async function rejectMember(clubId: string, userId: string): Promise<void> {
	const { error } = await supabase
		.from(TABLES.club_members)
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
		.from(TABLES.club_members)
		.delete()
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw error;
}

export async function leaveClub(clubId: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.club_members)
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
		.from(TABLES.club_members)
		// Enumerate columns rather than `*`: on a public club anyone can
		// read this list, and `activity_waiver_ack_at` (when a member
		// signed the liability waiver) is the member's own business, not
		// public roster data.
		.select('club_id, user_id, role, status, joined_at')
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
		.from(TABLES.event_attendees)
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
	const nextStarts = ids.map((id) => nextMap.get(id)!);
	const userId = auth.user?.id;

	// The going-count is scoped to each event's NEXT instance and computed
	// server-side: the event_next_instance_going_counts RPC pairs each event id
	// with its next-instance timestamp (by ordinality) and returns one integer
	// per event. The prior client-side approach fetched EVERY all-time
	// status='going' row for the listed events with no limit and tallied the
	// matching instance locally — tens of thousands of rows on the wire to
	// produce N integers. The viewer's RSVPs are a single bounded per-user
	// fetch, so those still come back as rows and are matched to the next
	// instance client-side.
	const countsPromise = supabase.rpc(
		// Not yet in database.types.ts (orchestrator regenerates on landing the
		// 20270122_001 migration); the RPC name is cast until then.
		'event_next_instance_going_counts' as never,
		{ p_event_ids: ids, p_next_starts: nextStarts } as never
	);
	const rsvpPromise = userId
		? supabase
				.from(TABLES.event_attendees)
				.select('event_id, status, instance_start')
				.in('event_id', ids)
				.eq('user_id', userId)
		: Promise.resolve({ data: [] as { event_id: string; status: string; instance_start: string }[] });

	const [countRes, rsvpRes] = await Promise.all([countsPromise, rsvpPromise]);

	// Compare instants, not raw strings: nextMap holds toISOString() ('…Z')
	// while Postgres returns timestamptz as '…+00:00', so a string `===`
	// never matches and every RSVP would be dropped (regression from the
	// client-side debatch in 7e386e57 — the prior per-event `.eq()` compared
	// timestamptz server-side).
	const sameInstant = (a: string, b: string | undefined): boolean =>
		b != null && new Date(a).getTime() === new Date(b).getTime();
	const counts = new Map<string, number>();
	for (const row of (countRes.data ?? []) as { event_id: string; going_count: number }[]) {
		counts.set(row.event_id, Number(row.going_count));
	}
	const rsvps = new Map<string, RsvpStatus | null>();
	for (const row of (rsvpRes.data ?? []) as { event_id: string; status: string; instance_start: string }[]) {
		if (sameInstant(row.instance_start, nextMap.get(row.event_id))) {
			rsvps.set(row.event_id, (row.status ?? null) as RsvpStatus | null);
		}
	}

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
		recurrence_byday: (e.recurrence_byday ?? null) as Weekday[] | null,
		// Legacy rows predate the category column; treat them as athletic runs.
		category: (e.category ?? 'run') as EventCategory,
		// Raw jsonb on the row -> the typed seam shape (null for empty/malformed).
		gym_template: parseGymTemplate(e.gym_template as unknown)
	};
}

/// The caller's IANA timezone (e.g. 'America/New_York'), or null if the
/// runtime can't resolve one — events anchor to this so discovery can filter
/// by local time-of-day.
function localTimezone(): string | null {
	try {
		return Intl.DateTimeFormat().resolvedOptions().timeZone || null;
	} catch {
		return null;
	}
}

export async function createEvent(input: {
	club_id: string;
	title: string;
	category: EventCategory;
	discipline?: string | null;
	// The class -> gym seam hint. Only persisted for category === 'class';
	// null (no template) for every other category.
	gym_template?: EventGymTemplate | null;
	description?: string;
	starts_at: string; // ISO
	timezone?: string | null; // IANA; defaults to the organiser's browser tz
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
	// When false, the event is members-only: hidden from non-members + discovery.
	// Defaults to public. Only meaningful in a public club (a private club's
	// events are already members-only via the club gate).
	is_public?: boolean;
}): Promise<Event> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('events')
		.insert({
			club_id: input.club_id,
			title: input.title.trim(),
			category: input.category,
			is_public: input.is_public ?? true,
			discipline: input.discipline?.trim() || null,
			gym_template: input.category === 'class' ? (input.gym_template ?? null) : null,
			description: input.description?.trim() || null,
			starts_at: input.starts_at,
			// Anchor the event to the organiser's local timezone so discovery's
			// time-of-day filter resolves "7pm" as local, not the UTC instant.
			timezone: input.timezone ?? localTimezone(),
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
			author_id: userId
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

export interface EventException {
	event_id: string;
	instance_start: string;
	cancelled_by: string | null;
	reason: string | null;
	cancelled_at: string;
}

export async function fetchEventExceptions(eventId: string): Promise<EventException[]> {
	const { data } = await supabase
		.from('event_exceptions')
		.select('event_id, instance_start, cancelled_by, reason, cancelled_at')
		.eq('event_id', eventId);
	return (data as EventException[] | null) ?? [];
}

/// Event meetup coordinates, gated to active club members by the
/// `get_event_meet_point` SECURITY DEFINER RPC. `meet_lat` / `meet_lng`
/// are column-revoked from every client role (precise meeting points
/// leak organiser home addresses — migrations 20260723_001 /
/// 20260806_001), so a direct column select can't reach them. Returns
/// null for non-members and events without a meet point set.
/// Persona-hunt social-group #10.
export async function fetchEventMeetPoint(
	eventId: string
): Promise<{ lat: number; lng: number } | null> {
	const { data, error } = await supabase.rpc('get_event_meet_point', {
		p_event_id: eventId
	});
	if (error || !data || data.length === 0) return null;
	const row = data[0];
	if (typeof row.meet_lat !== 'number' || typeof row.meet_lng !== 'number') return null;
	return { lat: row.meet_lat, lng: row.meet_lng };
}

// ─────────────────────── Paid registration (club_events.md slice P1) ───────────────────────

/// Boolean-only view of the signed-in host's Stripe payout capability.
/// The raw `stripe_connect_account_id` is column-revoked from clients
/// (migration 20261229_001) — this reads the surfacing columns + the
/// `host_can_take_payment` RPC for the capability flags. Returns null
/// when the host has never started onboarding.
export interface PayoutAccountStatus {
	charges_enabled: boolean;
	payouts_enabled: boolean;
	details_submitted: boolean;
	country: string | null;
	default_currency: string | null;
}

export async function fetchPayoutAccount(): Promise<PayoutAccountStatus | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	// The own-row SELECT policy lets a host read their own account row;
	// `stripe_connect_account_id` is revoked at the column level, so we
	// never project it. The capability booleans live on the row directly.
	const { data, error } = await supabase
		.from('instructor_payout_accounts')
		.select('charges_enabled, payouts_enabled, details_submitted, country, default_currency')
		.eq('user_id', userId)
		.maybeSingle();
	if (error || !data) return null;
	return {
		charges_enabled: Boolean(data.charges_enabled),
		payouts_enabled: Boolean(data.payouts_enabled),
		details_submitted: Boolean(data.details_submitted),
		country: (data.country as string | null) ?? null,
		default_currency: (data.default_currency as string | null) ?? null
	};
}

/// Start (or resume) Stripe Connect onboarding for the signed-in host.
/// Invokes the events-connect-onboard Edge Function, which creates/reuses
/// an Express account and returns a hosted Account Link URL. The caller
/// redirects the browser there.
export async function startConnectOnboarding(): Promise<{ url: string }> {
	const { data, error } = await supabase.functions.invoke('events-connect-onboard', {
		body: {}
	});
	if (error) throw error;
	const url = (data as { url?: string } | null)?.url;
	if (!url) throw new Error('No onboarding URL returned');
	return { url };
}

/// Effective pricing for an event instance. Per-instance override wins
/// over the series default (instance_start IS NULL). Readable with the
/// event per RLS.
export async function fetchEventPricing(
	eventId: string,
	instanceStart?: string | null
): Promise<EventPricing | null> {
	const { data, error } = await supabase
		.from('event_pricing')
		.select('*')
		.eq('event_id', eventId);
	if (error || !data || data.length === 0) return null;
	const rows = data as EventPricing[];
	if (instanceStart) {
		const override = rows.find((r) => r.instance_start === instanceStart);
		if (override) return override;
	}
	return rows.find((r) => r.instance_start == null) ?? null;
}

/// Persist series-level (or per-instance) pricing for an event. Kept
/// separate from createEvent so the price write goes through its own
/// charges_enabled-gated RLS surface — folding it into the events insert
/// would couple two RLS surfaces (club_events.md, the race/results
/// precedent). The DB trigger rejects the write if the host lacks a
/// charges-enabled payout account, so a stale UI can't slip a price past.
export async function setEventPricing(
	eventId: string,
	input: {
		price_cents: number;
		currency: string;
		refund_policy: EventPricing['refund_policy'];
		sales_close_offset_minutes: number;
		platform_fee_bps?: number;
		instance_start?: string | null;
	}
): Promise<void> {
	const { error } = await supabase.from('event_pricing').upsert(
		{
			event_id: eventId,
			instance_start: input.instance_start ?? null,
			price_cents: input.price_cents,
			currency: input.currency,
			modality: 'in_person',
			refund_policy: input.refund_policy,
			sales_close_offset_minutes: input.sales_close_offset_minutes,
			platform_fee_bps: input.platform_fee_bps ?? 0
		},
		{ onConflict: input.instance_start ? 'event_id,instance_start' : 'event_id' }
	);
	if (error) throw error;
}

/// Begin a Stripe Checkout for a paid registration. The events-checkout
/// Edge Function validates the sales window + capacity, holds a soft
/// reservation (a pending order), and returns a hosted destination-charge
/// Checkout URL. The caller redirects the browser there.
export async function startEventCheckout(
	eventId: string,
	instanceStart: string
): Promise<{ url: string }> {
	const { data, error } = await supabase.functions.invoke('events-checkout', {
		body: { event_id: eventId, instance_start: instanceStart }
	});
	if (error) throw error;
	const url = (data as { url?: string } | null)?.url;
	if (!url) throw new Error('No checkout URL returned');
	return { url };
}

/// The signed-in buyer's most recent order for an event instance, used
/// by the post-checkout success poll (?paid=1). Buyer-reads-own RLS scopes
/// this to the caller's own orders.
export async function fetchMyOrder(
	eventId: string,
	instanceStart: string
): Promise<EventOrder | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data, error } = await supabase
		.from('event_orders')
		.select('*')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.eq('buyer_user_id', userId)
		.order('created_at', { ascending: false })
		.limit(1);
	if (error || !data || data.length === 0) return null;
	return data[0] as EventOrder;
}

/// Buyer self-cancel of their OWN paid/pending registration for an event
/// instance (club_events.md slice P2). Calls the events-cancel Edge
/// Function, which initiates the Stripe refund (paid order, refund-eligible
/// per the event's refund_policy) or expires the soft reservation (pending
/// order). The stripe-events webhook — still the sole writer of
/// event_orders.status — performs the actual status transition + seat
/// release when Stripe delivers the resulting event, so this returns the
/// initiated `action` and the caller polls/refreshes for the terminal state.
export async function cancelEventOrder(
	eventId: string,
	instanceStart: string
): Promise<{ action: string }> {
	const { data, error } = await supabase.functions.invoke('events-cancel', {
		body: { event_id: eventId, instance_start: instanceStart }
	});
	if (error) {
		// A non-2xx (e.g. 409 policy_no_refund, 503 stripe_not_configured)
		// arrives as a FunctionsHttpError carrying the Response in `context`.
		// Re-throw an Error whose message is the EF's machine `error` code so
		// the caller can map it to a localized string.
		const code = await edgeFunctionErrorCode(error);
		throw new Error(code ?? (error instanceof Error ? error.message : 'cancel_failed'));
	}
	const action = (data as { action?: string } | null)?.action;
	if (!action) throw new Error('cancel_failed');
	return { action };
}

/// Pull the machine `error` code out of a supabase-js FunctionsHttpError —
/// its `context` is the raw Response, whose JSON body carries our
/// `{ error: '<code>' }` envelope. Null when the body can't be read.
async function edgeFunctionErrorCode(error: unknown): Promise<string | null> {
	const ctx = (error as { context?: Response })?.context;
	if (!ctx || typeof ctx.clone !== 'function') return null;
	try {
		const body = await ctx.clone().json();
		const code = (body as { error?: string })?.error;
		return typeof code === 'string' ? code : null;
	} catch {
		return null;
	}
}

/// Cancel a single occurrence of a recurring event (the rest of the series
/// is untouched). Organiser-only via RLS; the fan-out trigger notifies every
/// going / maybe / waitlisted attendee of this instance.
export async function cancelEventInstance(
	eventId: string,
	instanceStart: string,
	reason: string | null
): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	// Idempotent: two organisers cancelling the same occurrence (or a
	// double-click) must not surface a raw 23505 on the (event_id,
	// instance_start) PK. First cancellation wins — ignore the duplicate.
	const { error } = await supabase.from('event_exceptions').upsert(
		{
			event_id: eventId,
			instance_start: instanceStart,
			cancelled_by: userId,
			reason: reason?.trim() || null
		},
		{ onConflict: 'event_id,instance_start', ignoreDuplicates: true }
	);
	if (error) throw error;
}

export async function reinstateEventInstance(
	eventId: string,
	instanceStart: string
): Promise<void> {
	const { error } = await supabase
		.from('event_exceptions')
		.delete()
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart);
	if (error) throw error;
}

/// Upsert the caller's RSVP and return the *effective* status. When the
/// requested status is 'going' but the event is at capacity, the
/// enforce_event_capacity trigger (migration 20261018_001) demotes the row to
/// 'waitlisted', so the persisted status can differ from what was requested —
/// we read it back via the upsert's returning row so the UI can show the
/// waitlist state without a second fetch.
export async function rsvpEvent(
	eventId: string,
	status: RsvpStatus,
	instanceStart: string
): Promise<RsvpStatus> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from(TABLES.event_attendees)
		.upsert(
			{ event_id: eventId, user_id: userId, status, instance_start: instanceStart },
			{ onConflict: 'event_id,user_id,instance_start' }
		)
		.select('status')
		.single();
	if (error) throw error;
	return (data?.status as RsvpStatus | undefined) ?? status;
}

export async function clearRsvp(eventId: string, instanceStart: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.event_attendees)
		.delete()
		.eq('event_id', eventId)
		.eq('user_id', userId)
		.eq('instance_start', instanceStart);
	if (error) throw error;
}

// Host-only: mark whether an attendee actually showed up. Orthogonal to the
// attendee's RSVP status — routes through the mark_attendance SECURITY DEFINER
// RPC (instructor_business.md M6) which enforces organiser-only writes and
// touches only the attendance column. Pass null to clear a prior mark.
export async function markAttendance(
	eventId: string,
	userId: string,
	instanceStart: string,
	attendance: EventAttendance | null
): Promise<void> {
	const { error } = await supabase.rpc('mark_attendance', {
		p_event_id: eventId,
		p_user_id: userId,
		p_instance_start: instanceStart,
		p_attendance: attendance
	});
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
		.from(TABLES.event_attendees)
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
	id: string;
	// Null for bib-only finishers imported from a chip-timing CSV
	// (persona #43) — those rows carry `bib` + `finisher_name` instead.
	user_id: string | null;
	bib: string | null;
	finisher_name: string | null;
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
			'id, user_id, bib, finisher_name, run_id, duration_s, distance_m, rank, finisher_status, age_grade_pct, note, created_at, organiser_approved'
		)
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.order('rank', { ascending: true, nullsFirst: false })
		.order('created_at', { ascending: true });
	if (!results) return [];
	const rows = results as EventResultRow[];
	if (rows.length === 0) return [];
	const userIds = rows.map((r) => r.user_id).filter((id): id is string => id !== null);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	if (userIds.length > 0) {
		const { data: profiles } = await supabase
			.from('user_profiles')
			.select('id, display_name, avatar_url')
			.in('id', userIds);
		for (const p of profiles ?? [])
			byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	}
	return rows.map((r) => ({
		...r,
		// Bib-only imported finishers have no profile — fall back to the
		// name printed on the results sheet.
		display_name: r.user_id ? (byId.get(r.user_id)?.display_name ?? null) : r.finisher_name,
		avatar_url: r.user_id ? (byId.get(r.user_id)?.avatar_url ?? null) : null,
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
	const noteTrimmed = params.note?.trim();
	const { error } = await supabase.from(TABLES.event_results).upsert(
		{
			event_id: params.eventId,
			instance_start: params.instanceStart,
			user_id: userId,
			run_id: params.runId ?? null,
			duration_s: params.durationS,
			distance_m: params.distanceM,
			finisher_status: params.finisherStatus ?? 'finished',
			age_grade_pct: params.ageGradePct ?? null,
			// Trim + collapse empty-after-trim to null so a whitespace
			// note from the result-submit dialog doesn't survive to the
			// DB. Mobile's `SocialService.submitEventResult` applies the
			// same normalisation.
			note: noteTrimmed && noteTrimmed.length > 0 ? noteTrimmed : null,
			updated_at: new Date().toISOString(),
		},
		{ onConflict: 'event_id,instance_start,user_id' }
	);
	if (error) throw error;
	// Best-effort back-link so the run-detail page can show "ran at {event}".
	if (params.runId) {
		await supabase
			.from(TABLES.runs)
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
		.from(TABLES.event_results)
		.delete()
		.eq('event_id', eventId)
		.eq('user_id', userId)
		.eq('instance_start', instanceStart);
	if (error) throw error;
}

// Organiser bulk-import of chip-timing results (persona #43). Rows are
// bib-only finishers (no account) keyed on bib; the upsert arbiter is the
// `(event_id, instance_start, bib)` unique constraint so re-importing a
// corrected sheet updates in place rather than duplicating. RLS gates the
// write to the event's organiser via `event_results_insert_organiser`.
//
// `user_id` is deliberately NOT in the payload: on a fresh bib it defaults
// to NULL (account-less), and on a re-import of a bib that a runner has
// since claimed (persona #43 claim flow → user_id set by an organiser
// approval) the column is left untouched so a corrected re-upload can't
// silently revert the result to account-less and wipe the claim.
export async function bulkImportEventResults(params: {
	eventId: string;
	instanceStart: string;
	rows: ParsedResultRow[];
}): Promise<void> {
	if (params.rows.length === 0) return;
	const payload = params.rows.map((r) => ({
		event_id: params.eventId,
		instance_start: params.instanceStart,
		bib: r.bib,
		finisher_name: r.finisherName,
		duration_s: r.durationS,
		distance_m: r.distanceM,
		finisher_status: r.finisherStatus,
		updated_at: new Date().toISOString(),
	}));
	const { error } = await supabase
		.from(TABLES.event_results)
		.upsert(payload, { onConflict: 'event_id,instance_start,bib' });
	if (error) throw error;
}

export interface EventResultClaim {
	id: string;
	result_id: string;
	claimant_id: string;
	status: 'pending' | 'approved' | 'rejected';
	created_at: string;
}

export interface EventResultClaimWithUser extends EventResultClaim {
	claimant_name: string | null;
	// The bib + finisher_name of the result being claimed, for the
	// organiser's approval queue ("Bob claims bib 102 — Alice Anon").
	bib: string | null;
	finisher_name: string | null;
}

// A logged-in runner claims a bib-only imported result (persona #43).
// Organiser-approve trust model — the row stays bib-only until an organiser
// approves via approveEventResultClaim. Returns the created/re-opened claim.
export async function requestEventResultClaim(resultId: string): Promise<void> {
	const { error } = await supabase.rpc('claim_event_result', { p_result_id: resultId });
	if (error) throw error;
}

// The current user's claims for a given (event, instance), keyed by
// result_id so the leaderboard can show a "claim pending" state on the row
// the viewer claimed. Reads through the RLS SELECT policy (claimant sees own).
export async function fetchMyEventResultClaims(
	eventId: string,
	instanceStart: string
): Promise<Map<string, EventResultClaim['status']>> {
	const userId = auth.user?.id;
	if (!userId) return new Map();
	const { data } = await supabase
		.from('event_result_claims')
		.select('result_id, status, event_results!inner(event_id, instance_start)')
		.eq('claimant_id', userId)
		.eq('event_results.event_id', eventId)
		.eq('event_results.instance_start', instanceStart);
	const map = new Map<string, EventResultClaim['status']>();
	for (const r of (data ?? []) as Array<{ result_id: string; status: EventResultClaim['status'] }>)
		map.set(r.result_id, r.status);
	return map;
}

// Pending claims an organiser needs to adjudicate for a given (event,
// instance). RLS gates this to organisers of the parent event.
export async function fetchPendingEventResultClaims(
	eventId: string,
	instanceStart: string
): Promise<EventResultClaimWithUser[]> {
	const { data } = await supabase
		.from('event_result_claims')
		.select(
			'id, result_id, claimant_id, status, created_at, event_results!inner(event_id, instance_start, bib, finisher_name)'
		)
		.eq('status', 'pending')
		.eq('event_results.event_id', eventId)
		.eq('event_results.instance_start', instanceStart)
		.order('created_at', { ascending: true });
	const rows = (data ?? []) as Array<{
		id: string;
		result_id: string;
		claimant_id: string;
		status: EventResultClaim['status'];
		created_at: string;
		// PostgREST returns the embedded relationship as an array.
		event_results: Array<{ bib: string | null; finisher_name: string | null }>;
	}>;
	if (rows.length === 0) return [];
	const claimantIds = [...new Set(rows.map((r) => r.claimant_id))];
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name')
		.in('id', claimantIds);
	const byId = new Map<string, string | null>();
	for (const p of profiles ?? []) byId.set(p.id, p.display_name);
	return rows.map((r) => ({
		id: r.id,
		result_id: r.result_id,
		claimant_id: r.claimant_id,
		status: r.status,
		created_at: r.created_at,
		claimant_name: byId.get(r.claimant_id) ?? null,
		bib: r.event_results[0]?.bib ?? null,
		finisher_name: r.event_results[0]?.finisher_name ?? null
	}));
}

// Organiser approves or rejects a claim. Approving attaches the claimant's
// account to the result row and auto-rejects competing claims (server-side).
export async function decideEventResultClaim(claimId: string, approve: boolean): Promise<void> {
	const { error } = await supabase.rpc('decide_event_result_claim', {
		p_claim_id: claimId,
		p_approve: approve
	});
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
		.from(TABLES.runs)
		.select('id, started_at, duration_s, distance_m, activity_type')
		.eq('user_id', userId)
		.order('started_at', { ascending: false })
		.limit(limit);
	if (!data) return [];
	return data.map((r) => ({
		id: r.id,
		started_at: r.started_at,
		duration_s: r.duration_s,
		distance_m: r.distance_m,
		activity_type: r.activity_type ?? 'run',
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
	is_auto_approve: boolean;
	created_at: string;
	updated_at: string;
}

export async function fetchRaceSession(
	eventId: string,
	instanceStart: string
): Promise<RaceSessionRow | null> {
	// Read from the redaction view rather than the base table —
	// `race_sessions_redacted` masks `started_by` + `is_auto_approve`
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
				is_auto_approve: autoApprove,
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
	// The `race_sessions_status_temporal_invariant` CHECK constraint
	// (migration `20260529000003`) requires `finished_at IS NULL`
	// when `status='cancelled'` and `finished_at IS NOT NULL` when
	// `status='finished'`. Stamping finished_at on a cancel write
	// violates the constraint — the UPDATE errors with
	// check_violation, the page's `raceSession` state never updates,
	// and the Arm-race button never re-appears. The
	// `event-race-control.spec.ts:170` Cancel-from-armed test timed
	// out on every CI run for this reason. Only stamp finished_at
	// when transitioning to `finished`.
	const patch: Record<string, unknown> = {
		status,
		updated_at: new Date().toISOString(),
	};
	if (status === 'finished') {
		patch.finished_at = new Date().toISOString();
	}
	const { data, error } = await supabase
		.from('race_sessions')
		.update(patch)
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

// Approve / unverify a single result by its row id. The `approve_event_result`
// RPC keys on (event, instance, user_id) so it can only touch account-linked
// rows — a bib-only imported finisher has user_id = NULL and is unreachable
// through it. This path goes straight at the row, gated by the
// `event_results_update_self_or_director` RLS policy (a race_director of the
// event's club may update any of its result rows). Audit columns are written
// client-side from the signed-in director to mirror what the RPC's auth.uid()
// would set.
export async function approveEventResultById(
	resultId: string,
	approve: boolean
): Promise<void> {
	const directorId = auth.user?.id;
	if (!directorId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.event_results)
		.update({
			organiser_approved: approve,
			organiser_approved_by: directorId,
			organiser_approved_at: new Date().toISOString(),
			updated_at: new Date().toISOString(),
		})
		.eq('id', resultId)
		// This path is for bib-only (unmatched) results; matched-user rows
		// approve via approve_event_result. Constrain to null-user rows so a
		// stray caller can't reach a matched runner's result through here
		// (the director RLS policy already bounds it to their own events).
		.is('user_id', null);
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
	coarse: boolean;
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

/// Latest ping per runner for the live leaderboard, ordered furthest-
/// first with a deterministic tie-break (see `compareLeaderboard`).
///
/// Backed by the `latest_race_pings` RPC (DISTINCT ON (user_id)) rather
/// than a flat newest-N fetch: a flat cap is spent on the high-cadence
/// front-of-pack pings, so a slow back-of-pack runner whose newest ping
/// has aged past the window would silently drop off the board. The RPC
/// returns exactly one row per runner, so every runner who has pinged
/// is always represented regardless of total ping volume. It is
/// SECURITY INVOKER, so the same race_pings RLS that gated the bare-
/// table read still applies.
export async function fetchLatestRacePings(
	eventId: string,
	instanceStart: string
): Promise<RacePingRow[]> {
	const { data } = await supabase.rpc('latest_race_pings', {
		p_event_id: eventId,
		p_instance_start: instanceStart
	});
	const rows = (data as RacePingRow[]) ?? [];
	return rows.sort(compareLeaderboard);
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
		.from(TABLES.club_posts)
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
		.from(TABLES.club_posts)
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
					.from(TABLES.club_posts)
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
		.from(TABLES.club_posts)
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
	const { error } = await supabase.from(TABLES.club_posts).delete().eq('id', id);
	if (error) throw error;
}

// --- Training plans ---

/// Same as `fetchMyPlans` but surfaces the error alongside the rows, so
/// a caller can show a "couldn't load — retry" state instead of an empty
/// list that's indistinguishable from "user has no plans". Mirrors the
/// `fetchRoutesWithError` convention.
export async function fetchMyPlansWithError(
	limit = 100
): Promise<{ plans: TrainingPlan[]; error: string | null }> {
	// Templates live in the same table; filter them out of the
	// user-facing plan list (decisions §35).
	const { data, error } = await supabase
		.from('training_plans')
		.select('*')
		.eq('is_template', false)
		.order('created_at', { ascending: false })
		.limit(limit);
	return { plans: (data ?? []) as TrainingPlan[], error: error?.message ?? null };
}

export async function fetchMyPlans(limit = 100): Promise<TrainingPlan[]> {
	return (await fetchMyPlansWithError(limit)).plans;
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

export type PublicPlanLibraryEntry = TrainingPlan & {
	author_handle: string | null;
};

/// Browse the public plan library — published plans any user can clone
/// (migration 20270126_001). Optional case-insensitive name search.
/// Each entry carries the author's public display name (handle) joined
/// from user_profiles; no other author data is exposed. Mirrors mobile
/// `TrainingService.fetchPublicPlanLibrary`.
export async function fetchPublicPlanLibrary(
	query = '',
	limit = 100
): Promise<{ plans: PublicPlanLibraryEntry[]; error: string | null }> {
	let q = supabase
		.from('training_plans')
		.select('*')
		.eq('is_public_template', true)
		.order('created_at', { ascending: false })
		.limit(limit);
	const trimmed = query.trim();
	if (trimmed) q = q.ilike('name', `%${trimmed}%`);
	const { data, error } = await q;
	if (error) return { plans: [], error: error.message };
	const rows = (data ?? []) as TrainingPlan[];
	const authorIds = [...new Set(rows.map((r) => r.user_id))];
	const byId = new Map<string, string | null>();
	if (authorIds.length > 0) {
		const { data: profiles } = await supabase
			.from('user_profiles')
			.select('id, display_name')
			.in('id', authorIds);
		for (const p of profiles ?? []) byId.set(p.id, p.display_name);
	}
	return {
		plans: rows.map((r) => ({ ...r, author_handle: byId.get(r.user_id) ?? null })),
		error: null,
	};
}

/// Clone a public-library plan into a user-owned active plan, anchored
/// at new_start_date. Returns the new plan's id. The clone_public_plan
/// RPC authorises on public visibility server-side and strips the
/// publisher's private fitness data.
export async function clonePublicPlan(
	templateId: string,
	newStartDate: string
): Promise<string> {
	const { data, error } = await supabase.rpc('clone_public_plan', {
		template_id: templateId,
		new_start_date: newStartDate,
	});
	if (error) throw error;
	return data as string;
}

/// Publish one of the viewer's plans to the public library: copy the
/// plan row + every plan_week + plan_workout into a new
/// `is_public_template = true` sibling, leaving the original plan
/// untouched on the user's list (mirrors `publishPlanAsTemplate`, in the
/// public direction). Publisher fitness data (vdot/current_5k_seconds)
/// is stripped so it can't leak to cloners. Returns the new template id.
export async function publishPlanToLibrary(sourcePlanId: string): Promise<string> {
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
			vdot: null,
			current_5k_seconds: null,
			status: 'completed',
			notes: src.notes,
			is_template: true,
			is_public_template: true,
			club_id: null,
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
				target_pace_tolerance_sec: w.target_pace_tolerance_sec,
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

/// Unpublish a public-library template the viewer owns — deletes the
/// published copy (weeks + workouts cascade). Owner-only via RLS.
export async function unpublishFromLibrary(templateId: string): Promise<void> {
	const { error } = await supabase
		.from('training_plans')
		.delete()
		.eq('id', templateId)
		.eq('is_public_template', true);
	if (error) throw error;
}

/// The viewer's own published public-library plans (so the plan-detail
/// page can show whether a plan is already published and offer Unpublish).
export async function fetchMyPublishedPlans(): Promise<TrainingPlan[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data, error } = await supabase
		.from('training_plans')
		.select('*')
		.eq('is_public_template', true)
		.eq('user_id', userId)
		.order('created_at', { ascending: false });
	if (error) {
		console.error('fetchMyPublishedPlans failed', error);
		return [];
	}
	return (data ?? []) as TrainingPlan[];
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
	error: string | null;
}> {
	const [planRes, weeksRes] = await Promise.all([
		supabase.from('training_plans').select('*').eq('id', id).maybeSingle(),
		supabase
			.from('plan_weeks')
			.select('*')
			.eq('plan_id', id)
			.order('week_index', { ascending: true })
	]);
	// Surface a query error so the detail page can show a "couldn't load —
	// retry" state instead of the not-found page (a real error otherwise
	// reads as a missing plan when the rows just come back null).
	const error = planRes.error?.message ?? weeksRes.error?.message ?? null;
	const plan = (planRes.data ?? null) as TrainingPlan | null;
	const weeks = (weeksRes.data ?? []) as PlanWeek[];
	if (!plan || weeks.length === 0) {
		return { plan, weeks, workouts: [], error };
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
		workouts: (woData ?? []) as PlanWorkout[],
		error
	};
}

export async function fetchWorkout(
	id: string
): Promise<{ workout: PlanWorkout | null; error: string | null }> {
	// Thread the query error so the detail page can show a "couldn't load —
	// retry" state instead of the not-found page (a transient error otherwise
	// reads as a deleted workout when the row just comes back null), mirroring
	// fetchPlan above.
	const { data, error } = await supabase
		.from('plan_workouts')
		.select('*')
		.eq('id', id)
		.maybeSingle();
	return { workout: (data as PlanWorkout | null) ?? null, error: error?.message ?? null };
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
	const { todayISO, isWorkoutSkipped } = await import('../training/training');
	const today = todayISO();
	const todayWorkout = workouts.find((w) => w.scheduled_date === today) ?? null;
	const completed = workouts.filter(
		(w) => w.manually_completed === true || w.completed_run_id != null
	).length;
	// Skipped workouts are off the books — neither done nor an outstanding
	// to-do — so they leave the progress denominator entirely.
	const total = workouts.filter((w) => w.kind !== 'rest' && !isWorkoutSkipped(w)).length;
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
			completed_at: isCompleting ? new Date().toISOString() : null,
			// Completing clears any prior skip — the two states are mutually
			// exclusive. Un-completing (runId null + manual false) leaves the
			// skip flag untouched so it isn't a back-door un-skip.
			...(isCompleting ? { skipped_at: null } : {})
		})
		.eq('id', workoutId);
	if (error) throw error;
}

/**
 * Toggle a planned workout's intentionally-skipped state. Marking it
 * skipped stamps `skipped_at` and clears any completion (a row is never
 * both skipped and done); un-skipping clears `skipped_at`. Distinct from
 * `markWorkoutCompleted(id, null)` — that path is "didn't do it / undo a
 * tick", this one is "deliberately dropping this session".
 */
export async function markWorkoutSkipped(
	workoutId: string,
	skipped: boolean
): Promise<void> {
	const { error } = await supabase
		.from('plan_workouts')
		.update(
			skipped
				? {
						skipped_at: new Date().toISOString(),
						completed_run_id: null,
						manually_completed: false,
						completed_at: null
					}
				: { skipped_at: null }
		)
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

export type { RelinkCandidateRun } from '../training/relink_candidates';

/**
 * Candidate runs the owner can re-link to a planned workout.
 *
 * Owner-scoped (RLS + an explicit `user_id` filter), within ±7 days of
 * the workout's `scheduled_date`, and — crucially — EXCLUDING any run
 * already linked (`completed_run_id`) to a *different* plan workout, so
 * re-linking can't double-count a single run across two workouts in
 * `plan_progress`. The workout's own current run stays in the list so
 * the current pick is visible. Newest-first.
 */
export async function fetchRelinkCandidateRuns(
	workout: PlanWorkout
): Promise<RelinkCandidateRun[]> {
	const userId = auth.user?.id;
	if (!userId) return [];

	// The set of run ids already linked anywhere in this owner's plans.
	// Scope through the owner's plan_weeks (RLS chains the same way, but
	// the explicit scope is defence in depth — see autoMatchRunToPlan-
	// Workout). A run linked to ANOTHER workout must not be offered.
	const { data: plans } = await supabase
		.from('training_plans')
		.select('id, plan_weeks(id)')
		.eq('user_id', userId);
	const weekIds = (plans ?? []).flatMap((p) =>
		((p as { plan_weeks: { id: string }[] }).plan_weeks ?? []).map((w) => w.id)
	);
	const linkedRunIds: string[] = [];
	if (weekIds.length > 0) {
		const { data: linkedRows } = await supabase
			.from('plan_workouts')
			.select('completed_run_id')
			.in('week_id', weekIds)
			.not('completed_run_id', 'is', null);
		for (const row of linkedRows ?? []) {
			const id = (row as { completed_run_id: string | null }).completed_run_id;
			if (id) linkedRunIds.push(id);
		}
	}

	// Owner's runs, explicitly scoped (RLS + user_id), scalars only — bounded
	// to a date window around the workout instead of the whole run history.
	// filterRelinkCandidates keeps only runs within ±DEFAULT_RELINK_WINDOW_DAYS
	// calendar days of scheduled_date (plus the current pick regardless), so a
	// generous ±(window+2)-day UTC pre-filter — wide enough to cover ±window
	// LOCAL calendar days across any timezone — returns a handful of rows
	// instead of every run a heavy-history user ever logged. The current
	// completed_run_id is OR-ed in so a re-link pick outside the window still
	// surfaces (filterRelinkCandidates always keeps it). Backed by the
	// (user_id, started_at desc) index.
	const currentRunId = workout.completed_run_id ?? null;
	const schedMs = Date.parse(`${workout.scheduled_date}T00:00:00Z`);
	const bufferMs = (DEFAULT_RELINK_WINDOW_DAYS + 2) * 86_400_000;
	const loIso = new Date(schedMs - bufferMs).toISOString();
	const hiIso = new Date(schedMs + bufferMs).toISOString();
	let runQuery = supabase
		.from(TABLES.runs)
		.select('id, started_at, distance_m, duration_s')
		.eq('user_id', userId);
	runQuery = currentRunId
		? runQuery.or(
				`and(started_at.gte.${loIso},started_at.lte.${hiIso}),id.eq.${currentRunId}`
			)
		: runQuery.gte('started_at', loIso).lte('started_at', hiIso);
	const { data: runRows } = await runQuery.order('started_at', { ascending: false });

	const runs: RelinkCandidateRun[] = (runRows ?? []).map((r) => ({
		id: (r as { id: string }).id,
		started_at: (r as { started_at: string }).started_at,
		distance_m: (r as { distance_m: number }).distance_m,
		duration_s: (r as { duration_s: number }).duration_s
	}));

	return filterRelinkCandidates({
		runs,
		linkedRunIds,
		currentRunId,
		scheduledDate: workout.scheduled_date
	});
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
	// Normalise the `notes` patch the same way `createTrainingPlan`
	// does on insert — trim + collapse empty-after-trim to null.
	// Mobile's `TrainingService.updateWorkout` applies the same
	// normalisation so the two clients write identical rows. Logic
	// lives in data_normalise.ts so the contract can be unit-tested.
	const normalisedPatch: typeof patch = { ...patch };
	if ('notes' in normalisedPatch) {
		normalisedPatch.notes = normalisePlanWorkoutNotes(normalisedPatch.notes);
	}
	const { error } = await supabase
		.from('plan_workouts')
		.update(normalisedPatch)
		.eq('id', id);
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
		start_date: string;
		end_date: string;
	}>
): Promise<void> {
	const { error } = await supabase.from('training_plans').update(patch).eq('id', id);
	if (error) throw error;
}

/// Duplicate the plan week at `weekIndex`, inserting the copy right after
/// it. Every later week shifts up one index (+7 days), the copy lands 7
/// days after its source, and the plan end_date extends a week. Atomic
/// server-side because the (plan_id, week_index) unique constraint makes
/// a client-side multi-update unsafe — see the duplicate_plan_week RPC.
/// Returns the new week's id.
export async function duplicatePlanWeek(planId: string, weekIndex: number): Promise<string> {
	const { data, error } = await supabase.rpc('duplicate_plan_week', {
		p_plan_id: planId,
		p_week_index: weekIndex
	});
	if (error) throw error;
	return data as string;
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
export async function fetchPublicProfile(
	userId: string
): Promise<{ profile: ProfileSummary | null; error: string | null }> {
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

	// Surface a query error so the profile page can show a "couldn't load —
	// retry" state instead of the not-found page (a real error otherwise
	// reads as a missing user when the row just comes back null).
	const error = (profileRes as { error?: { message?: string } | null }).error?.message ?? null;
	if (!profileRes.data) return { profile: null, error };

	return {
		profile: {
			id: profileRes.data.id,
			display_name: profileRes.data.display_name,
			avatar_url: profileRes.data.avatar_url,
			follower_count: followerRes.count ?? 0,
			following_count: followingRes.count ?? 0,
			viewer_follows: viewerRes.data != null,
		},
		error: null
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

/// Block `targetUserId` — see migration 20261012_001_user_blocks.sql.
/// `block_user` is SECURITY DEFINER and also drains existing follow
/// rows in either direction, so a viewer-initiated block subsumes
/// unfollow on both sides. Re-calling with a new reason updates the
/// reason in place (the RPC upserts on conflict).
export async function blockUser(targetUserId: string, reason?: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	if (userId === targetUserId) throw new Error("Can't block yourself");
	const { error } = await supabase.rpc('block_user', {
		p_target: targetUserId,
		p_reason: reason ?? null,
	});
	if (error) throw error;
}

export async function unblockUser(targetUserId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase.rpc('unblock_user', { p_target: targetUserId });
	if (error) throw error;
}

/// Returns true when the viewer has blocked `targetUserId`. Reads
/// `user_blocks` directly — RLS already gates the read to rows where
/// the viewer is the blocker, so no SECURITY DEFINER needed.
export async function isBlockedByViewer(targetUserId: string): Promise<boolean> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) return false;
	const { data } = await supabase
		.from(TABLES.user_blocks)
		.select('blocker_id')
		.eq('blocker_id', userId)
		.eq('blocked_id', targetUserId)
		.maybeSingle();
	return data != null;
}

export interface PeopleSuggestion extends PublicProfile {
	public_runs_count: number;
	shared_clubs: number;
	viewer_follows: boolean;
}

/// Free-text people search for /social People tab. Used to do a
/// direct ILIKE against `user_profiles`; now routes through the
/// `search_user_profiles` SECURITY DEFINER RPC so it can filter by
/// the `discoverable_in_search` opt-out pref (persona-hunt Round 3
/// finding Woman #2 — a runner who's been stalked needs a way to
/// remove themselves from name search; user_settings has owner-only
/// RLS so the join can't run client-side).
///
/// Excludes self, hydrates viewer→target follow edges + per-result
/// public-runs count so the row's Follow toggle starts in the right
/// state. Results are ranked by `public_runs_count` descending so a
/// bot mass-creating dummy accounts can't push real runners off the
/// top — anti-spam phase 1 of 3 in `docs/architecture/decisions.md § search ranking`.
///
/// `limit` caps the returned list. We fetch `limit * 3` candidates
/// from the RPC (capped server-side at 200) so the rank step has more
/// to chew on; with > N exact-name hits, the cap still defines the
/// visible page and the user can refine the query.
export async function searchPeople(q: string, limit = 20): Promise<PeopleSuggestion[]> {
	const term = q.trim();
	if (term.length < 1) return [];
	const { data: sessionData } = await supabase.auth.getSession();
	const viewerId = sessionData.session?.user?.id ?? null;
	const candidateLimit = Math.min(limit * 3, 120);
	const { data: profiles, error } = await supabase.rpc('search_user_profiles', {
		p_query: term,
		p_limit: candidateLimit,
	});
	if (error || !profiles) return [];
	const ids = (profiles as Array<{ id: string }>)
		.map((p) => p.id)
		.filter((id) => id !== viewerId);
	if (ids.length === 0) return [];
	const hydrated = await hydratePeopleSuggestions(ids, viewerId);
	// Reputation-weighted sort lives in `search_ranking.ts` so the
	// comparator can be unit-tested without booting Supabase. Accounts
	// with 0 public runs aren't hidden (a friend you search for by
	// exact name may not have posted any runs yet), they just rank
	// last within the result set.
	const { comparePeopleRank } = await import('../social/search_ranking');
	return hydrated.sort(comparePeopleRank).slice(0, limit);
}

/// Suggested people for the Social People tab: members of the viewer's
/// clubs they don't already follow, plus self-exclusion. Ordered by
/// shared-club count desc, then by display_name. Single round-trip via
/// client-composed queries (no SECURITY DEFINER RPC — every table read
/// is covered by existing RLS).
export async function fetchSuggestedPeople(limit = 12): Promise<PeopleSuggestion[]> {
	const { data: sessionData } = await supabase.auth.getSession();
	const viewerId = sessionData.session?.user?.id ?? null;
	if (!viewerId) return [];

	const { data: myMemberRows } = await supabase
		.from(TABLES.club_members)
		.select('club_id')
		.eq('user_id', viewerId)
		.eq('status', 'active');
	const myClubIds = (myMemberRows ?? []).map((r) => r.club_id as string);
	if (myClubIds.length === 0) return [];

	const { data: coMemberRows } = await supabase
		.from(TABLES.club_members)
		.select('user_id, club_id')
		.in('club_id', myClubIds)
		.eq('status', 'active')
		.neq('user_id', viewerId);
	if (!coMemberRows || coMemberRows.length === 0) return [];

	const shared = new Map<string, number>();
	for (const row of coMemberRows) {
		const uid = row.user_id as string;
		shared.set(uid, (shared.get(uid) ?? 0) + 1);
	}

	const { data: followedRows } = await supabase
		.from('user_follows')
		.select('followee_id')
		.eq('follower_id', viewerId)
		.in('followee_id', [...shared.keys()]);
	for (const r of followedRows ?? []) {
		shared.delete(r.followee_id as string);
	}
	if (shared.size === 0) return [];

	const ids = [...shared.keys()];
	const hydrated = await hydratePeopleSuggestions(ids, viewerId);
	// Rank by shared-club count desc, then display_name.
	return hydrated
		.map((p) => ({ ...p, shared_clubs: shared.get(p.id) ?? 0 }))
		.sort((a, b) => {
			if (b.shared_clubs !== a.shared_clubs) return b.shared_clubs - a.shared_clubs;
			return (a.display_name ?? '').localeCompare(b.display_name ?? '');
		})
		.slice(0, limit);
}

/// The subset of `candidateIds` the viewer has NOT blocked. One batched read
/// of user_blocks — the owner-read RLS policy scopes it to the viewer's own
/// blocks, so this enforces the viewer→target direction that the client is
/// authorised to read (the same direction `isBlockedByViewer` reads). The
/// symmetric target→viewer direction is gated server-side on the content
/// surfaces via `is_blocked_either_way`; a fully-symmetric discovery filter
/// would need a set-returning definer RPC (follow-up). On a read error we
/// keep all candidates rather than empty the list — the read failing is
/// independent of the profile fetch, and blanking discovery on a transient
/// blocks error would be a worse regression than the rare leak.
async function filterOutBlocked(viewerId: string, candidateIds: string[]): Promise<string[]> {
	if (candidateIds.length === 0) return candidateIds;
	const { data, error } = await supabase
		.from(TABLES.user_blocks)
		.select('blocked_id')
		.eq('blocker_id', viewerId)
		.in('blocked_id', candidateIds);
	if (error) return candidateIds;
	const blocked = new Set((data ?? []).map((r) => r.blocked_id as string));
	return candidateIds.filter((id) => !blocked.has(id));
}

async function hydratePeopleSuggestions(
	ids: string[],
	viewerId: string | null
): Promise<PeopleSuggestion[]> {
	if (ids.length === 0) return [];
	// Never surface a blocked account in People search / "Suggested for you".
	// Every other social surface (kudos, comments, follows, leaderboards,
	// profile) gates on the block predicate; discovery must too, or a runner
	// who blocked a harasser keeps seeing them by name + avatar. Both search
	// and suggestions funnel through this single hydrate step, so the filter
	// lives here (matches the "keep block additions in one place" note on the
	// user_blocks migration).
	const visibleIds = viewerId ? await filterOutBlocked(viewerId, ids) : ids;
	if (visibleIds.length === 0) return [];
	const [profilesRes, countsRes, followsRes] = await Promise.all([
		supabase
			.from('user_profiles')
			.select('id, display_name, avatar_url')
			.in('id', visibleIds),
		// Public-run counts via a SECURITY DEFINER GROUP BY RPC — one small row
		// per candidate, not one row per public run (which also can't be read
		// off the base runs table by a non-owner since 20260701_001 dropped the
		// public-anyone SELECT policy, so the old client tally returned ~0 for
		// everyone but the viewer). See public_run_counts (migration 20270118_001).
		supabase.rpc('public_run_counts', { p_user_ids: visibleIds }),
		viewerId
			? supabase
					.from('user_follows')
					.select('followee_id')
					.eq('follower_id', viewerId)
					.in('followee_id', visibleIds)
			: Promise.resolve({ data: [] as { followee_id: string }[] } as { data: { followee_id: string }[] }),
	]);
	const counts = new Map<string, number>();
	for (const row of (countsRes.data ?? []) as {
		user_id: string;
		public_run_count: number;
	}[]) {
		counts.set(row.user_id, Number(row.public_run_count) || 0);
	}
	const follows = new Set<string>(
		((followsRes.data ?? []) as { followee_id: string }[]).map((r) => r.followee_id)
	);
	return (profilesRes.data ?? []).map((p) => ({
		id: p.id as string,
		display_name: (p.display_name as string) ?? null,
		avatar_url: (p.avatar_url as string) ?? null,
		public_runs_count: counts.get(p.id as string) ?? 0,
		shared_clubs: 0,
		viewer_follows: follows.has(p.id as string),
	}));
}

/// People who follow `userId`, paginated client-side after fetch.
/// Default page size for the follower / following lists. The /u/[id]
/// tabs request one page at a time and load more on demand, so a user
/// with hundreds of followers is fully reachable rather than truncated.
export const FOLLOW_PAGE_SIZE = 50;

export async function fetchFollowers(
	userId: string,
	opts?: { limit?: number; offset?: number }
): Promise<PublicProfile[]> {
	const limit = opts?.limit ?? FOLLOW_PAGE_SIZE;
	const offset = opts?.offset ?? 0;
	const { data: edges } = await supabase
		.from('user_follows')
		.select('follower_id, followed_at')
		.eq('followee_id', userId)
		.order('followed_at', { ascending: false })
		// Secondary key so offset pages are stable when two follows share a
		// followed_at timestamp — without it a row on a page boundary can be
		// duplicated or skipped on load-more.
		.order('follower_id', { ascending: true })
		.range(offset, offset + limit - 1);
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
export async function fetchFollowing(
	userId: string,
	opts?: { limit?: number; offset?: number }
): Promise<PublicProfile[]> {
	const limit = opts?.limit ?? FOLLOW_PAGE_SIZE;
	const offset = opts?.offset ?? 0;
	const { data: edges } = await supabase
		.from('user_follows')
		.select('followee_id, followed_at')
		.eq('follower_id', userId)
		.order('followed_at', { ascending: false })
		// Secondary key so offset pages are stable when two follows share a
		// followed_at timestamp (see fetchFollowers).
		.order('followee_id', { ascending: true })
		.range(offset, offset + limit - 1);
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

/// Resolve the viewer's followed-author id set for a feed query: the ids the
/// caller follows, narrowed to a single author when `authorId` is supplied
/// (validated against the follow set so the URL can't enumerate strangers).
/// Returns [] when not signed in, the viewer follows nobody, or the requested
/// author isn't followed — every caller treats an empty set as "show nothing".
/// Resolved ONCE by `fetchFollowingActivityFeed` and threaded into both the
/// runs + lifts branches so a default feed page issues one user_follows read,
/// not two, and the two branches can't derive a divergent followee set.
async function resolveFollowedAuthorIds(authorId?: string | null): Promise<string[]> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) return [];
	const { data: edges } = await supabase
		.from('user_follows')
		.select('followee_id')
		.eq('follower_id', userId);
	const followeeIds = (edges ?? []).map((e) => e.followee_id as string);
	if (followeeIds.length === 0) return [];
	const wantedAuthor = authorId ?? null;
	return wantedAuthor ? followeeIds.filter((id) => id === wantedAuthor) : followeeIds;
}

export async function fetchFollowingFeed(
	opts?: {
		limit?: number;
		cursor?: { started_at: string; id: string } | null;
		/** Restrict to a single followee. Pass `null` / omit for "everyone you follow". */
		authorId?: string | null;
		/** Restrict by `runs.activity_type`. Pass 'all' / omit for any activity. */
		activityType?: string | null;
	},
	/** Pre-resolved followee set (from `resolveFollowedAuthorIds`); when the
	 * cross-modal orchestrator threads it in, this skips the redundant
	 * getSession + user_follows round-trip. Standalone callers omit it. */
	preresolvedAuthors?: string[]
): Promise<FeedEntry[]> {
	const limit = opts?.limit ?? 20;
	const filteredAuthors =
		preresolvedAuthors ?? (await resolveFollowedAuthorIds(opts?.authorId));
	if (filteredAuthors.length === 0) return [];

	const cutoff = new Date(Date.now() - FEED_WINDOW_DAYS * 24 * 60 * 60 * 1000).toISOString();
	// Feed reads go through the public_runs view (decisions §33,
	// migration 20260626_001) — the view filters on is_public and
	// applies the column / metadata-key redaction so feed entries
	// don't leak third-party ids or sync-state internals.
	//
	// The followee set is chunked: PostgREST serialises `.in()` into the
	// URL, so a viewer following many hundreds of people overflows the
	// gateway's request-line limit and the query silently returns null.
	// Each chunk applies the same cursor + ordering + limit; the global
	// top-`limit` is a subset of the union of per-chunk results, which
	// mergeFeedPages collapses back down.
	const queryChunk = async (ids: string[]) => {
		let q = supabase
			.from('public_runs')
			.select('*')
			.in('user_id', ids)
			.gte('started_at', cutoff)
			.order('started_at', { ascending: false })
			.order('id', { ascending: false })
			.limit(limit);
		if (opts?.activityType && opts.activityType !== 'all') {
			q = q.eq('activity_type', opts.activityType);
		}
		if (opts?.cursor) {
			// Stable cursor pagination on (started_at, id) — strictly less than
			// the cursor row to skip what we've already seen.
			q = q.or(
				`started_at.lt.${opts.cursor.started_at},and(started_at.eq.${opts.cursor.started_at},id.lt.${opts.cursor.id})`
			);
		}
		// Surface the error: a swallowed `{ data: null }` (5xx, RLS, gateway
		// in-clause overflow) is indistinguishable from a genuinely empty
		// feed, so the caller's try/catch could never show the load-failed
		// toast — a silent blank feed. Throw so SocialFeed / the profile feed
		// render the error state instead.
		const { data, error } = await q;
		if (error) throw error;
		return (data ?? []) as Run[];
	};

	const pages = await Promise.all(chunk(filteredAuthors, FEED_FOLLOWEE_CHUNK).map(queryChunk));
	const runs = mergeFeedPages(pages, limit);
	if (runs.length === 0) return [];

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

/// A public gym workout surfaced in the activity feed. Carries only the
/// non-sensitive headline a "lift card" renders — title, set count, total
/// working volume in canonical kg, started_at — plus the author. No notes,
/// no RPE, no per-set detail leak into the feed; the share page is the place
/// for full detail.
export interface LiftFeedEntry {
	kind: 'lift';
	id: string;
	user_id: string;
	started_at: string;
	title: string | null;
	set_count: number;
	volume_kg: number;
	author: PublicProfile;
}

/// A run feed entry tagged with its kind so the feed can render a run card vs
/// a lift card off a single discriminated union.
export type RunFeedEntry = FeedEntry & { kind: 'run' };

/// The cross-modal activity feed entry — a run or a public lift.
export type ActivityFeedEntry = RunFeedEntry | LiftFeedEntry;

/// Cross-modal following feed (multi_modal.md § Social feed): recent public
/// runs AND public gym workouts from people the caller follows, merged into
/// one reverse-chronological window.
///
/// Runs go through the redacted `public_runs` view (decisions §33) — they are
/// deliberately invisible through the `activities` view to non-owners, so the
/// feed reads them on the same path `fetchFollowingFeed` does. Lifts read
/// `gym_workouts` directly: that table's "owner or public read" RLS already
/// scopes a non-owner to public rows, and the feed projects only the
/// headline columns (title / set_count / volume_kg) — never notes or per-set
/// data. `set_count` + `volume_kg` are the trigger-maintained derived columns
/// (migration 20261214_001), so a lift card is a flat per-branch read.
///
/// `activityType`: 'all' (default) merges both; 'lift' / 'gym' returns lifts
/// only; any run activity_type ('run' / 'walk' / 'cycle' / 'hike') returns
/// runs only.
export async function fetchFollowingActivityFeed(opts?: {
	limit?: number;
	cursor?: { started_at: string; id: string } | null;
	authorId?: string | null;
	activityType?: string | null;
}): Promise<ActivityFeedEntry[]> {
	const limit = opts?.limit ?? 20;
	const activityType = opts?.activityType ?? 'all';
	const wantsLifts = activityType === 'all' || activityType === 'lift' || activityType === 'gym';
	const wantsRuns = activityType !== 'lift' && activityType !== 'gym';

	// Resolve the followee set ONCE and thread it into both branches so the
	// default ('all') feed issues a single user_follows read instead of two,
	// and the runs + lifts branches can't derive a divergent followee set.
	const authors = await resolveFollowedAuthorIds(opts?.authorId);
	if (authors.length === 0) return [];

	const runsPromise: Promise<RunFeedEntry[]> = wantsRuns
		? fetchFollowingFeed(opts, authors).then((rows) =>
				rows.map((r) => ({ ...r, kind: 'run' as const }))
			)
		: Promise.resolve([]);

	const liftsPromise: Promise<LiftFeedEntry[]> = wantsLifts
		? fetchFollowingLifts(opts, authors)
		: Promise.resolve([]);

	const [runs, lifts] = await Promise.all([runsPromise, liftsPromise]);
	return mergeFeedPages<ActivityFeedEntry>([runs, lifts], limit);
}

async function fetchFollowingLifts(
	opts?: {
		limit?: number;
		cursor?: { started_at: string; id: string } | null;
		authorId?: string | null;
	},
	preresolvedAuthors?: string[]
): Promise<LiftFeedEntry[]> {
	const limit = opts?.limit ?? 20;
	const filteredAuthors =
		preresolvedAuthors ?? (await resolveFollowedAuthorIds(opts?.authorId));
	if (filteredAuthors.length === 0) return [];

	const cutoff = new Date(Date.now() - FEED_WINDOW_DAYS * 24 * 60 * 60 * 1000).toISOString();
	const queryChunk = async (ids: string[]) => {
		let q = supabase
			.from(TABLES.gym_workouts)
			.select('id, user_id, started_at, title, set_count, volume_kg')
			.eq('is_public', true)
			.in('user_id', ids)
			.gte('started_at', cutoff)
			.order('started_at', { ascending: false })
			.order('id', { ascending: false })
			.limit(limit);
		if (opts?.cursor) {
			q = q.or(
				`started_at.lt.${opts.cursor.started_at},and(started_at.eq.${opts.cursor.started_at},id.lt.${opts.cursor.id})`
			);
		}
		// Surface the error rather than coercing a failed read to an empty
		// page — see the matching note in fetchFollowingFeed's queryChunk.
		const { data, error } = await q;
		if (error) throw error;
		return (data ?? []) as {
			id: string;
			user_id: string;
			started_at: string;
			title: string | null;
			set_count: number | null;
			volume_kg: number | null;
		}[];
	};

	const pages = await Promise.all(chunk(filteredAuthors, FEED_FOLLOWEE_CHUNK).map(queryChunk));
	const workouts = mergeFeedPages(pages, limit);
	if (workouts.length === 0) return [];

	const authorIds = Array.from(new Set(workouts.map((w) => w.user_id)));
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', authorIds);
	const byId = new Map<string, PublicProfile>();
	for (const p of profiles ?? []) byId.set(p.id, p);

	return workouts.map((w) => ({
		kind: 'lift' as const,
		id: w.id,
		user_id: w.user_id,
		started_at: w.started_at,
		title: w.title,
		set_count: w.set_count ?? 0,
		volume_kg: w.volume_kg ?? 0,
		author: byId.get(w.user_id) ?? { id: w.user_id, display_name: null, avatar_url: null },
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

	// Counts come from a server-side GROUP BY (run_engagement_counts) so the
	// wire payload is one small row per run, not every kudos + comment row on
	// the page (a popular share used to ship hundreds of rows to compute one
	// integer). viewer_has_kudos stays a narrow per-run .in() lookup.
	const [counts, viewerKudos] = await Promise.all([
		supabase.rpc('run_engagement_counts', { p_run_ids: runIds }),
		viewerId
			? supabase
					.from(TABLES.run_kudos)
					.select('run_id')
					.eq('user_id', viewerId)
					.in('run_id', runIds)
			: Promise.resolve({ data: [] as { run_id: string }[] }),
	]);

	for (const id of runIds) out.set(id, { kudos_count: 0, viewer_has_kudos: false, comment_count: 0 });
	for (const row of (counts.data ?? []) as {
		run_id: string;
		kudos_count: number;
		comment_count: number;
	}[]) {
		const e = out.get(row.run_id);
		if (e) {
			e.kudos_count = Number(row.kudos_count) || 0;
			e.comment_count = Number(row.comment_count) || 0;
		}
	}
	for (const row of (viewerKudos.data ?? []) as { run_id: string }[]) {
		const e = out.get(row.run_id);
		if (e) e.viewer_has_kudos = true;
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
			.from(TABLES.run_kudos)
			.select('*', { count: 'exact', head: true })
			.eq('run_id', runId),
		viewerId
			? supabase
					.from(TABLES.run_kudos)
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

/// Returns `true` when a NEW kudos row was inserted, `false` when the
/// viewer already had kudos (a 23505 no-op). The caller drives the
/// optimistic `+1` only on a real change — a stale local
/// `viewer_has_kudos: false` (kudos already given from another tab /
/// session) must not bump the count, or the displayed total drifts
/// above the server's.
export async function giveKudos(runId: string): Promise<boolean> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from(TABLES.run_kudos)
		.insert({ user_id: userId, run_id: runId });
	if (error) {
		if (error.code === '23505') return false;
		throw error;
	}
	return true;
}

/// Returns `true` when a kudos row was actually deleted, `false` when
/// there was nothing to remove (already rescinded). Mirror of
/// `giveKudos` — the caller applies the optimistic `-1` only on a real
/// delete so a stale local flag can't push the count below the server's.
export async function rescindKudos(runId: string): Promise<boolean> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.run_kudos)
		.delete()
		.eq('run_id', runId)
		.eq('user_id', userId)
		.select('user_id');
	if (error) throw error;
	return (data ?? []).length > 0;
}

/// Comments on a run, sorted oldest-first. Author profiles are joined
/// in a second round trip so PostgREST doesn't need an embedded select.
export async function fetchRunComments(runId: string, limit = 200): Promise<RunCommentWithAuthor[]> {
	const { data: rows, error } = await supabase
		.from(TABLES.run_comments)
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
	const { error } = await supabase.from(TABLES.run_comments).insert({
		run_id: input.run_id,
		author_id: userId,
		body: input.body,
		parent_comment_id: input.parent_comment_id ?? null,
	});
	if (error) throw error;
}

export async function deleteRunComment(commentId: string): Promise<void> {
	const { error } = await supabase.from(TABLES.run_comments).delete().eq('id', commentId);
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
	/// Set when the photo is tagged to an event gallery (#49).
	event_id: string | null;
	event_instance_start: string | null;
	url: string;
	thumbUrl: string | null;
}

/// A photo in an event gallery — a `RunPhoto` plus the uploader's
/// display name so the gallery can attribute each shot. (#49)
///
/// `run_id` is deliberately omitted: an event gallery is visible to
/// anyone who can see the event (even when the underlying run is
/// private), so surfacing the run's UUID would bridge a public event to
/// a private run's id. The gallery never needs it.
export interface EventPhoto extends Omit<RunPhoto, 'run_id'> {
	uploader_name: string | null;
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
// TTL that the Storage layer honours independently of the SELECT policy,
// so a URL minted while a run was public stays valid for its whole TTL
// even after the run flips to private. 15 min keeps that revocation gap
// short while still comfortably outlasting a gallery render (re-signing
// happens on the next fetch, not per render).
const PHOTO_SIGNED_URL_TTL_S = 15 * 60;

async function signRunPhotoPaths(paths: string[]): Promise<Record<string, string>> {
	if (paths.length === 0) return {};
	const { data, error } = await supabase.storage
		.from(BUCKETS.run_photos)
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
		.from(TABLES.run_photos)
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

/// Event gallery (#49): every photo tagged to this event instance,
/// across all attendees' runs. RLS lets anyone who can see the event
/// read these even when the underlying run is private. Uploader names
/// are fetched in a second batched query (the `run_photos` → `runs` →
/// `user_profiles` join isn't expressible through PostgREST resource
/// embedding because the run may be invisible to the viewer).
export async function fetchEventPhotos(
	eventId: string,
	instanceStart: string,
	limit = 100,
): Promise<EventPhoto[]> {
	const { data, error } = await supabase
		.from(TABLES.run_photos)
		// Enumerate columns — `run_id` is NOT selected so a private run's
		// UUID can't leak to an event viewer who can't see that run.
		.select('id, owner_id, storage_path, thumb_512_path, caption, position_idx, created_at, event_id, event_instance_start')
		.eq('event_id', eventId)
		.eq('event_instance_start', instanceStart)
		.order('created_at', { ascending: true })
		.limit(limit);
	if (error) {
		console.error('fetchEventPhotos failed', error);
		return [];
	}
	const rows = data ?? [];
	if (rows.length === 0) return [];
	const paths: string[] = [];
	for (const r of rows) {
		paths.push(r.storage_path);
		if (r.thumb_512_path) paths.push(r.thumb_512_path);
	}
	const ownerIds = [...new Set(rows.map((r) => r.owner_id))];
	const [signed, profiles] = await Promise.all([
		signRunPhotoPaths(paths),
		supabase.from('user_profiles').select('id, display_name').in('id', ownerIds),
	]);
	const nameById = new Map<string, string | null>(
		(profiles.data ?? []).map((p) => [p.id as string, (p.display_name as string | null) ?? null]),
	);
	return rows.map((r) => ({
		...r,
		url: signed[r.storage_path] ?? '',
		thumbUrl: r.thumb_512_path ? (signed[r.thumb_512_path] ?? null) : null,
		uploader_name: nameById.get(r.owner_id) ?? null,
	}));
}

export async function addRunPhoto(input: {
	run_id: string;
	file: File;
	caption?: string | null;
	/// When set, the photo joins the event's gallery (#49). The DB
	/// INSERT policy requires the uploader can see the event.
	event_id?: string | null;
	event_instance_start?: string | null;
}): Promise<RunPhoto> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const ext = PHOTO_MIME_TO_EXT[input.file.type];
	if (!ext) throw new Error('Unsupported image type — JPEG, PNG, WebP, or HEIC only');
	if (input.file.size > PHOTO_MAX_BYTES) throw new Error('Image too large (10 MB max)');

	// Strip EXIF/XMP (incl. GPS) client-side before upload so a geotagged
	// original never sits readable in the bucket ahead of the server worker's
	// async strip. Mirrors mobile's pre-upload strip (persona woman/family #52).
	const file = await stripExifFromFile(input.file);

	const photoId = crypto.randomUUID();
	const storagePath = `${userId}/${photoId}.${ext}`;

	const { error: upErr } = await supabase.storage
		.from(BUCKETS.run_photos)
		.upload(storagePath, file, {
			contentType: file.type,
			upsert: false,
		});
	if (upErr) throw upErr;

	const { data: posData } = await supabase
		.from(TABLES.run_photos)
		.select('position_idx')
		.eq('run_id', input.run_id)
		.order('position_idx', { ascending: false })
		.limit(1)
		.maybeSingle();
	const nextIdx = (posData?.position_idx ?? -1) + 1;

	const { data, error } = await supabase
		.from(TABLES.run_photos)
		.insert({
			id: photoId,
			run_id: input.run_id,
			owner_id: userId,
			storage_path: storagePath,
			caption: input.caption?.trim() || null,
			position_idx: nextIdx,
			event_id: input.event_id ?? null,
			event_instance_start: input.event_instance_start ?? null,
		})
		.select('*')
		.single();
	if (error || !data) {
		// Best-effort cleanup of the uploaded blob if metadata insert fails.
		await supabase.storage.from(BUCKETS.run_photos).remove([storagePath]);
		throw error ?? new Error('Insert failed');
	}
	const { data: signed } = await supabase.storage
		.from(BUCKETS.run_photos)
		.createSignedUrl(storagePath, PHOTO_SIGNED_URL_TTL_S);
	return {
		...data,
		url: signed?.signedUrl ?? '',
	};
}

export async function deleteRunPhoto(photoId: string): Promise<void> {
	const { data: row, error: fetchErr } = await supabase
		.from(TABLES.run_photos)
		.select('storage_path, thumb_512_path')
		.eq('id', photoId)
		.maybeSingle();
	if (fetchErr) throw fetchErr;

	const { error } = await supabase.from(TABLES.run_photos).delete().eq('id', photoId);
	if (error) throw error;

	// Sweep both the original upload AND the worker-generated 512-wide
	// thumbnail. Best-effort — RLS allows the photo owner to remove their
	// own bytes. If the run owner (not photo owner) deleted the row, the
	// bytes will be orphaned in Storage but invisible to the UI.
	const paths = [row?.storage_path, row?.thumb_512_path].filter(
		(p: string | null | undefined): p is string => !!p,
	);
	if (paths.length > 0) {
		await supabase.storage.from(BUCKETS.run_photos).remove(paths);
	}
}

// ─────────────────────────────── Avatars ───────────────────────────────
// Profile-picture upload into the PUBLIC `avatars` bucket (migration
// 20260927_001). Unlike run/route photos, avatars are public profile data —
// they render on the logged-out /u/[id] profile as a bare <img src> — so the
// bucket is public and avatar_url holds a plain public URL.

const AVATAR_MIME_TO_EXT: Record<string, string> = {
	'image/jpeg': 'jpg',
	'image/png': 'png',
	'image/webp': 'webp',
};
// Matches the `avatars` bucket file_size_limit (2 MB, migration 20260927_001);
// reject client-side so the user gets a friendly message instead of a 413.
const AVATAR_MAX_BYTES = 2 * 1024 * 1024;

// Every per-user avatar object lives at a stable path keyed by extension, so
// the full set a user could own is enumerable for cleanup without a folder
// `list` (which the public bucket's RLS doesn't grant authenticated callers).
const avatarPathsFor = (userId: string): string[] =>
	Object.values(AVATAR_MIME_TO_EXT).map((e) => `${userId}/avatar.${e}`);

/// Upload a profile avatar and point `user_profiles.avatar_url` at it.
/// EXIF/GPS is stripped client-side first — the bucket is public and has no
/// server-side strip worker, so this is the only strip. We remove-then-insert
/// at the stable `{uid}/avatar.{ext}` path rather than upsert: the avatars
/// bucket grants owner INSERT + DELETE but not the upsert WITH-CHECK path, so a
/// plain INSERT onto a freshly-cleared path is the only write that passes RLS.
/// A `?v=` cache-bust keeps an <img> off the previous picture (the query still
/// satisfies the avatar_url `^https?://` CHECK). Returns the new public URL,
/// already written to the profile row.
export async function uploadAvatar(file: File): Promise<string> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const ext = AVATAR_MIME_TO_EXT[file.type];
	if (!ext) throw new Error('Unsupported image type — JPEG, PNG, or WebP only');
	if (file.size > AVATAR_MAX_BYTES) throw new Error('Image too large (2 MB max)');

	const clean = await stripExifFromFile(file);
	const storagePath = `${userId}/avatar.${ext}`;

	// Clear any existing avatar (this ext and the others) so the upload is a
	// clean INSERT, not an upsert. remove() on a missing path is a no-op.
	await supabase.storage.from(BUCKETS.avatars).remove(avatarPathsFor(userId));

	const { error: upErr } = await supabase.storage
		.from(BUCKETS.avatars)
		.upload(storagePath, clean, { contentType: clean.type, upsert: false });
	if (upErr) throw upErr;

	const { data: pub } = supabase.storage.from(BUCKETS.avatars).getPublicUrl(storagePath);
	const url = `${pub.publicUrl}?v=${Date.now()}`;

	const { error: profErr } = await supabase
		.from('user_profiles')
		.update({ avatar_url: url })
		.eq('id', userId);
	if (profErr) {
		// Roll back the blob so a failed profile write doesn't leave an
		// orphaned avatar the UI never references.
		await supabase.storage.from(BUCKETS.avatars).remove([storagePath]);
		throw profErr;
	}
	return url;
}

/// Remove the user's avatar — drops every stored object for them and clears
/// `user_profiles.avatar_url` to null (renderers fall back to initials).
export async function removeAvatar(): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	await supabase.storage.from(BUCKETS.avatars).remove(avatarPathsFor(userId));
	const { error } = await supabase
		.from('user_profiles')
		.update({ avatar_url: null })
		.eq('id', userId);
	if (error) throw error;
}

export async function updateRunPhotoCaption(
	photoId: string,
	caption: string | null,
): Promise<void> {
	const trimmed = caption?.trim() || null;
	const { error } = await supabase
		.from(TABLES.run_photos)
		.update({ caption: trimmed })
		.eq('id', photoId);
	if (error) throw error;
}

// --- Route photos (backlog C1) ---
//
// The run_photos capability applied to routes. Metadata in `route_photos`;
// bytes in the private `route-photos` bucket at `{owner_id}/{photo_id}.{ext}`.
// The Storage SELECT policy joins through `route_photos` →
// `private.is_route_visible_to(route_id, auth.uid())`, so a route flipping
// from public to private propagates within the signed-URL TTL. Owner gates
// upload + caption + delete.

export interface RoutePhoto {
	id: string;
	route_id: string;
	owner_id: string;
	storage_path: string;
	thumb_512_path: string | null;
	caption: string | null;
	position_idx: number;
	created_at: string;
	url: string;
	thumbUrl: string | null;
}

async function signRoutePhotoPaths(paths: string[]): Promise<Record<string, string>> {
	if (paths.length === 0) return {};
	const { data, error } = await supabase.storage
		.from(BUCKETS.route_photos)
		.createSignedUrls(paths, PHOTO_SIGNED_URL_TTL_S);
	if (error || !data) {
		console.error('signRoutePhotoPaths failed', error);
		return {};
	}
	const out: Record<string, string> = {};
	for (const row of data) {
		if (row.path && row.signedUrl) out[row.path] = row.signedUrl;
	}
	return out;
}

export async function fetchRoutePhotos(routeId: string, limit = 50): Promise<RoutePhoto[]> {
	const { data, error } = await supabase
		.from(TABLES.route_photos)
		.select('*')
		.eq('route_id', routeId)
		.order('position_idx', { ascending: true })
		.order('created_at', { ascending: true })
		.limit(limit);
	if (error) {
		console.error('fetchRoutePhotos failed', error);
		return [];
	}
	const rows = data ?? [];
	const paths: string[] = [];
	for (const r of rows) {
		paths.push(r.storage_path);
		if (r.thumb_512_path) paths.push(r.thumb_512_path);
	}
	const signed = await signRoutePhotoPaths(paths);
	return rows.map((r) => ({
		...r,
		url: signed[r.storage_path] ?? '',
		thumbUrl: r.thumb_512_path ? (signed[r.thumb_512_path] ?? null) : null,
	}));
}

export async function addRoutePhoto(input: {
	route_id: string;
	file: File;
	caption?: string | null;
}): Promise<RoutePhoto> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const ext = PHOTO_MIME_TO_EXT[input.file.type];
	if (!ext) throw new Error('Unsupported image type — JPEG, PNG, WebP, or HEIC only');
	if (input.file.size > PHOTO_MAX_BYTES) throw new Error('Image too large (10 MB max)');

	const file = await stripExifFromFile(input.file);

	const photoId = crypto.randomUUID();
	const storagePath = `${userId}/${photoId}.${ext}`;

	const { error: upErr } = await supabase.storage
		.from(BUCKETS.route_photos)
		.upload(storagePath, file, {
			contentType: file.type,
			upsert: false,
		});
	if (upErr) throw upErr;

	const { data: posData } = await supabase
		.from(TABLES.route_photos)
		.select('position_idx')
		.eq('route_id', input.route_id)
		.order('position_idx', { ascending: false })
		.limit(1)
		.maybeSingle();
	const nextIdx = (posData?.position_idx ?? -1) + 1;

	const { data, error } = await supabase
		.from(TABLES.route_photos)
		.insert({
			id: photoId,
			route_id: input.route_id,
			owner_id: userId,
			storage_path: storagePath,
			caption: input.caption?.trim() || null,
			position_idx: nextIdx,
		})
		.select('*')
		.single();
	if (error || !data) {
		await supabase.storage.from(BUCKETS.route_photos).remove([storagePath]);
		throw error ?? new Error('Insert failed');
	}
	const { data: signed } = await supabase.storage
		.from(BUCKETS.route_photos)
		.createSignedUrl(storagePath, PHOTO_SIGNED_URL_TTL_S);
	return {
		...data,
		url: signed?.signedUrl ?? '',
		thumbUrl: null,
	};
}

export async function deleteRoutePhoto(photoId: string): Promise<void> {
	const { data: row, error: fetchErr } = await supabase
		.from(TABLES.route_photos)
		.select('storage_path, thumb_512_path')
		.eq('id', photoId)
		.maybeSingle();
	if (fetchErr) throw fetchErr;

	const { error } = await supabase.from(TABLES.route_photos).delete().eq('id', photoId);
	if (error) throw error;

	const paths = [row?.storage_path, row?.thumb_512_path].filter(
		(p: string | null | undefined): p is string => !!p,
	);
	if (paths.length > 0) {
		await supabase.storage.from(BUCKETS.route_photos).remove(paths);
	}
}

export async function updateRoutePhotoCaption(
	photoId: string,
	caption: string | null,
): Promise<void> {
	const trimmed = caption?.trim() || null;
	const { error } = await supabase
		.from(TABLES.route_photos)
		.update({ caption: trimmed })
		.eq('id', photoId);
	if (error) throw error;
}

// --- Club photos (gallery; migration 20270301_001) ---
// Mirrors the route-photo path but keyed on club membership: any active
// member may upload; a photo's owner OR a club admin may delete (moderation).

export interface ClubPhoto {
	id: string;
	club_id: string;
	owner_id: string;
	storage_path: string;
	thumb_512_path: string | null;
	caption: string | null;
	position_idx: number;
	created_at: string;
	url: string;
	thumbUrl: string | null;
}

async function signClubPhotoPaths(paths: string[]): Promise<Record<string, string>> {
	if (paths.length === 0) return {};
	const { data, error } = await supabase.storage
		.from(BUCKETS.club_photos)
		.createSignedUrls(paths, PHOTO_SIGNED_URL_TTL_S);
	if (error || !data) {
		console.error('signClubPhotoPaths failed', error);
		return {};
	}
	const out: Record<string, string> = {};
	for (const row of data) {
		if (row.path && row.signedUrl) out[row.path] = row.signedUrl;
	}
	return out;
}

export async function fetchClubPhotos(clubId: string, limit = 50): Promise<ClubPhoto[]> {
	const { data, error } = await supabase
		.from(TABLES.club_photos)
		.select('*')
		.eq('club_id', clubId)
		.order('position_idx', { ascending: true })
		.order('created_at', { ascending: true })
		.limit(limit);
	if (error) {
		console.error('fetchClubPhotos failed', error);
		return [];
	}
	const rows = data ?? [];
	const paths: string[] = [];
	for (const r of rows) {
		paths.push(r.storage_path);
		if (r.thumb_512_path) paths.push(r.thumb_512_path);
	}
	const signed = await signClubPhotoPaths(paths);
	return rows.map((r) => ({
		...r,
		url: signed[r.storage_path] ?? '',
		thumbUrl: r.thumb_512_path ? (signed[r.thumb_512_path] ?? null) : null,
	}));
}

export async function addClubPhoto(input: {
	club_id: string;
	file: File;
	caption?: string | null;
}): Promise<ClubPhoto> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const ext = PHOTO_MIME_TO_EXT[input.file.type];
	if (!ext) throw new Error('Unsupported image type — JPEG, PNG, WebP, or HEIC only');
	if (input.file.size > PHOTO_MAX_BYTES) throw new Error('Image too large (10 MB max)');

	const file = await stripExifFromFile(input.file);

	const photoId = crypto.randomUUID();
	const storagePath = `${userId}/${photoId}.${ext}`;

	const { error: upErr } = await supabase.storage
		.from(BUCKETS.club_photos)
		.upload(storagePath, file, {
			contentType: file.type,
			upsert: false,
		});
	if (upErr) throw upErr;

	const { data: posData } = await supabase
		.from(TABLES.club_photos)
		.select('position_idx')
		.eq('club_id', input.club_id)
		.order('position_idx', { ascending: false })
		.limit(1)
		.maybeSingle();
	const nextIdx = (posData?.position_idx ?? -1) + 1;

	const { data, error } = await supabase
		.from(TABLES.club_photos)
		.insert({
			id: photoId,
			club_id: input.club_id,
			owner_id: userId,
			storage_path: storagePath,
			caption: input.caption?.trim() || null,
			position_idx: nextIdx,
		})
		.select('*')
		.single();
	if (error || !data) {
		await supabase.storage.from(BUCKETS.club_photos).remove([storagePath]);
		throw error ?? new Error('Insert failed');
	}
	const { data: signed } = await supabase.storage
		.from(BUCKETS.club_photos)
		.createSignedUrl(storagePath, PHOTO_SIGNED_URL_TTL_S);
	return {
		...data,
		url: signed?.signedUrl ?? '',
		thumbUrl: null,
	};
}

export async function deleteClubPhoto(photoId: string): Promise<void> {
	const { data: row, error: fetchErr } = await supabase
		.from(TABLES.club_photos)
		.select('storage_path, thumb_512_path')
		.eq('id', photoId)
		.maybeSingle();
	if (fetchErr) throw fetchErr;

	const { error } = await supabase.from(TABLES.club_photos).delete().eq('id', photoId);
	if (error) throw error;

	const paths = [row?.storage_path, row?.thumb_512_path].filter(
		(p: string | null | undefined): p is string => !!p,
	);
	if (paths.length > 0) {
		await supabase.storage.from(BUCKETS.club_photos).remove(paths);
	}
}

export async function updateClubPhotoCaption(
	photoId: string,
	caption: string | null,
): Promise<void> {
	const trimmed = caption?.trim() || null;
	const { error } = await supabase
		.from(TABLES.club_photos)
		.update({ caption: trimmed })
		.eq('id', photoId);
	if (error) throw error;
}

// --- Route course markers (migration 20270129_001) ---

function asRouteMarker(row: Record<string, unknown>): RouteMarker {
	return {
		...row,
		meta: (row.meta as Record<string, unknown>) ?? {}
	} as RouteMarker;
}

/// Course markers for a route, ordered by distance along the line. Reads
/// through `route_markers_for_viewer`, which gates visibility (owner /
/// public / club member) AND redacts any marker inside the owner's privacy
/// zones for a non-owner — the marker analogue of `clip_route_for_viewer`.
/// Fails closed (empty list) on error so a redaction failure never leaks.
export async function fetchRouteMarkers(routeId: string): Promise<RouteMarker[]> {
	const { data, error } = await supabase.rpc('route_markers_for_viewer', {
		p_route_id: routeId
	});
	if (error) {
		console.warn('route_markers_for_viewer failed; failing closed (no markers)', error);
		return [];
	}
	return ((data ?? []) as Record<string, unknown>[]).map(asRouteMarker);
}

export async function addRouteMarker(input: {
	route_id: string;
	kind: RouteMarkerKind;
	label: string;
	lat: number;
	lng: number;
	meta?: Record<string, unknown>;
}): Promise<RouteMarker> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const { data, error } = await supabase
		.from(TABLES.route_markers)
		.insert({
			route_id: input.route_id,
			user_id: userId,
			kind: input.kind,
			label: input.label.trim(),
			lat: input.lat,
			lng: input.lng,
			meta: input.meta ?? {}
		})
		.select('*')
		.single();
	if (error || !data) throw error ?? new Error('Insert failed');
	return asRouteMarker(data);
}

export async function updateRouteMarker(
	id: string,
	patch: { kind?: RouteMarkerKind; label?: string; lat?: number; lng?: number; meta?: Record<string, unknown> }
): Promise<void> {
	const update: Record<string, unknown> = {};
	if (patch.kind !== undefined) update.kind = patch.kind;
	if (patch.label !== undefined) update.label = patch.label.trim();
	if (patch.lat !== undefined) update.lat = patch.lat;
	if (patch.lng !== undefined) update.lng = patch.lng;
	if (patch.meta !== undefined) update.meta = patch.meta;
	if (Object.keys(update).length === 0) return;

	const { error } = await supabase.from(TABLES.route_markers).update(update).eq('id', id);
	if (error) throw error;
}

export async function deleteRouteMarker(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.route_markers).delete().eq('id', id);
	if (error) throw error;
}

// --- Route condition reports (migration 20270215_001) ---

function asRouteCondition(row: Record<string, unknown>): RouteCondition {
	return {
		...row,
		condition: row.condition as RouteConditionKind,
		severity: row.severity as RouteConditionSeverity
	} as RouteCondition;
}

/// Condition reports for a route, newest first. Reads through
/// `route_conditions_for_viewer`, which gates visibility (owner / public /
/// club member) AND nulls the anchor of any report inside the owner's privacy
/// zones for a non-owner — the condition analogue of `route_markers_for_viewer`.
/// Fails closed (empty list) on error so a redaction failure never leaks.
export async function fetchRouteConditions(routeId: string): Promise<RouteCondition[]> {
	const { data, error } = await supabase.rpc('route_conditions_for_viewer', {
		p_route_id: routeId
	});
	if (error) {
		console.warn('route_conditions_for_viewer failed; failing closed (no conditions)', error);
		return [];
	}
	return ((data ?? []) as Record<string, unknown>[]).map(asRouteCondition);
}

export async function addRouteCondition(input: {
	route_id: string;
	condition: RouteConditionKind;
	severity: RouteConditionSeverity;
	note?: string | null;
	lat?: number | null;
	lng?: number | null;
}): Promise<RouteCondition> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const note = input.note?.trim();
	const { data, error } = await supabase
		.from(TABLES.route_conditions)
		.insert({
			route_id: input.route_id,
			user_id: userId,
			condition: input.condition,
			severity: input.severity,
			note: note && note.length > 0 ? note : null,
			lat: input.lat ?? null,
			lng: input.lng ?? null
		})
		.select('*')
		.single();
	if (error || !data) throw error ?? new Error('Insert failed');
	return asRouteCondition(data);
}

export async function deleteRouteCondition(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.route_conditions).delete().eq('id', id);
	if (error) throw error;
}

// --- Heatmap / popular-route discovery (decisions backlog item #4) ---

export interface HeatmapPoint {
	lng: number;
	lat: number;
}

/// Fetch densified sample points from public routes intersecting the
/// given bounding box. Backed by the `heatmap_points_in_bbox` PostGIS
/// RPC (migration 20260828_001), which itself caps the response at
/// `max_points` to keep the wire size bounded — a continent-wide pan
/// returns the same 5k points as a city pan, just spread thinner.
/// Empty array on RPC error so the caller's map layer just stays
/// blank rather than throwing.
export async function fetchHeatmapPoints(bbox: {
	minLng: number;
	minLat: number;
	maxLng: number;
	maxLat: number;
	maxPoints?: number;
}): Promise<HeatmapPoint[]> {
	const { data, error } = await supabase.rpc('heatmap_points_in_bbox', {
		p_min_lng: bbox.minLng,
		p_min_lat: bbox.minLat,
		p_max_lng: bbox.maxLng,
		p_max_lat: bbox.maxLat,
		p_max_points: bbox.maxPoints ?? 5000,
	});
	if (error || !data) {
		console.warn('fetchHeatmapPoints failed', error);
		return [];
	}
	return (data as { lng: number; lat: number }[]).map((r) => ({
		lng: r.lng,
		lat: r.lat,
	}));
}

/// Public clubs with a `location_point` inside the viewport bbox.
/// Backed by the SECURITY DEFINER RPC `clubs_in_bbox` (migration
/// 20260911_001). Used by the /routes?tab=heatmap discoverable-
/// pins layer so club locations show alongside the density
/// heatmap. The RPC is `is_public = true` gated server-side; this
/// caller does NOT see private clubs even if the row is in range.
export interface ClubPin {
	id: string;
	name: string;
	slug: string | null;
	avatar_url: string | null;
	location_label: string | null;
	member_count: number;
	lng: number;
	lat: number;
}

export async function fetchClubsInBbox(bbox: {
	minLng: number;
	minLat: number;
	maxLng: number;
	maxLat: number;
	limit?: number;
}): Promise<ClubPin[]> {
	const { data, error } = await supabase.rpc('clubs_in_bbox', {
		p_min_lng: bbox.minLng,
		p_min_lat: bbox.minLat,
		p_max_lng: bbox.maxLng,
		p_max_lat: bbox.maxLat,
		p_limit: bbox.limit ?? 100,
	});
	if (error || !data) {
		console.warn('fetchClubsInBbox failed', error);
		return [];
	}
	return data as ClubPin[];
}

/// Discoverable public routes inside the viewport bbox. The lens is
/// chosen by `filter`:
///   • 'popular'     (default) — featured OR run_count > 0.
///   • 'featured'    — admin-curated only.
///   • 'friends'     — public routes created by users you follow.
///   • 'hidden_gems' — un-run public routes past a >=1km sanity floor.
/// Returns the start_point for each route so the map can drop a pin
/// there. Mirrors the `p_filter` branch in
/// 20261113_001_discoverable_routes_filter.sql — keep the union in
/// lockstep with the RPC's CASE arms.
export type DiscoverFilter = 'popular' | 'featured' | 'friends' | 'hidden_gems';

export interface DiscoverableRoutePin {
	id: string;
	name: string;
	slug: string | null;
	is_featured: boolean;
	distance_m: number;
	elevation_m: number | null;
	surface: string;
	run_count: number;
	lng: number;
	lat: number;
}

export async function fetchDiscoverableRoutesInBbox(bbox: {
	minLng: number;
	minLat: number;
	maxLng: number;
	maxLat: number;
	limit?: number;
	filter?: DiscoverFilter;
	/// Selected race-distance bands. Empty / omitted = no distance
	/// filter. Ranges are resolved via `bandsToRanges` so the band
	/// numbers stay owned by `distance_bands.ts`.
	bands?: DistanceBandKey[];
}): Promise<DiscoverableRoutePin[]> {
	const ranges = bandsToRanges(bbox.bands ?? []);
	const { data, error } = await supabase.rpc('discoverable_routes_in_bbox', {
		p_min_lng: bbox.minLng,
		p_min_lat: bbox.minLat,
		p_max_lng: bbox.maxLng,
		p_max_lat: bbox.maxLat,
		p_limit: bbox.limit ?? 100,
		p_filter: bbox.filter ?? 'popular',
		p_dist_min: ranges.min ?? undefined,
		// Postgres accepts NULL elements (open-ended ultra bound); the
		// generated arg type is number[], so cast past the null.
		p_dist_max: (ranges.max ?? undefined) as number[] | undefined,
	});
	if (error || !data) {
		console.warn('fetchDiscoverableRoutesInBbox failed', error);
		return [];
	}
	return data as DiscoverableRoutePin[];
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
	is_default: boolean;
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
		.from(TABLES.gear)
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
	const { error } = await supabase.from(TABLES.gear).update(patch).eq('id', id);
	if (error) throw error;
}

/// Mark this gear as the user's current default for its kind. Unsets
/// any sibling (same owner + same kind) first so the partial-unique
/// constraint `(owner_id, kind) where is_default and not retired`
/// never trips. Pass null to clear the default for this kind entirely.
export async function setDefaultGear(
	gearId: string | null,
	kind: GearKind,
): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error: clearErr } = await supabase
		.from(TABLES.gear)
		.update({ is_default: false })
		.eq('owner_id', userId)
		.eq('kind', kind)
		.eq('is_default', true);
	if (clearErr) throw clearErr;
	if (gearId !== null) {
		const { error: setErr } = await supabase
			.from(TABLES.gear)
			.update({ is_default: true })
			.eq('id', gearId);
		if (setErr) throw setErr;
	}
}

/// Stamp retired_at to today and clear nothing else — the row stays
/// around for historical mileage roll-ups on past runs that reference
/// it. Use [deleteGear] to actually remove (cascades to run_gear).
export async function retireGear(id: string): Promise<void> {
	// Local-tz today — `toISOString().slice(0,10)` returns the UTC date, which
	// rolls a calendar day early/late depending on the runner's TZ (same fix as
	// the active-plan overview above).
	const { todayISO } = await import('../training/training');
	await updateGear(id, { retired_at: todayISO() });
}

/// Un-retire — restore an actively-tracked piece of gear without
/// touching anything else. Useful when a runner pulled an old pair
/// out of retirement for slow / treadmill runs.
export async function unretireGear(id: string): Promise<void> {
	await updateGear(id, { retired_at: null });
}

export async function deleteGear(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.gear).delete().eq('id', id);
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
	const del = await supabase.from(TABLES.run_gear).delete().eq('run_id', runId);
	if (del.error) throw del.error;
	if (gearIds.length === 0) return;
	const rows = gearIds.map((gear_id) => ({ run_id: runId, gear_id }));
	const ins = await supabase.from(TABLES.run_gear).insert(rows);
	if (ins.error) throw ins.error;
}

/// Fetch the gear assigned to a single run. Used on the run-detail page AND
/// the PUBLIC share page (non-owner / anon viewer) to render the chip row.
///
/// Goes through the `public_run_gear` SECURITY DEFINER RPC
/// (migration 20261126_001) rather than a `run_gear` → `gear` table join. The
/// `gear` SELECT policy is owner-only, so a join returns NULL gear rows for any
/// non-owner — the chip used to render for the owner only. The RPC gates on
/// `is_run_visible_to` and projects ONLY the public columns (id / kind / name /
/// brand / model); owner-private inventory metadata (notes / purchased_at /
/// retired_at / target_distance_m) is never selected, so exposing gear on a
/// public run stays leak-free.
export async function fetchRunGear(runId: string): Promise<Gear[]> {
	const { data, error } = await supabase.rpc('public_run_gear', { p_run_id: runId });
	if (error || !data) {
		console.error('fetchRunGear failed', error);
		return [];
	}
	return data as Gear[];
}

// --- Gear wear-pattern logging (roadmap §7) ---

export type GearWearArea = 'outsole' | 'midsole' | 'upper' | 'other';

export interface GearWearLog {
	id: string;
	gear_id: string;
	owner_id: string;
	logged_on: string;
	area: GearWearArea | null;
	note: string;
	created_at: string;
	updated_at: string;
}

/// Fetch a gear item's wear log, newest observation first. Owner-scoped by
/// RLS — a non-owner read returns nothing, never another user's notes.
export async function fetchGearWearLogs(gearId: string): Promise<GearWearLog[]> {
	const { data, error } = await supabase
		.from(TABLES.gear_wear_logs)
		.select('*')
		.eq('gear_id', gearId)
		.order('logged_on', { ascending: false })
		.order('created_at', { ascending: false });
	if (error) {
		console.error('fetchGearWearLogs failed', error);
		return [];
	}
	return (data ?? []) as GearWearLog[];
}

export async function addGearWearLog(input: {
	gearId: string;
	note: string;
	area?: GearWearArea | null;
	loggedOn?: string | null;
}): Promise<GearWearLog> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.gear_wear_logs)
		.insert({
			gear_id: input.gearId,
			owner_id: userId,
			note: input.note,
			area: input.area ?? null,
			// Let the column default (current_date) win when no date is supplied.
			...(input.loggedOn ? { logged_on: input.loggedOn } : {}),
		})
		.select('*')
		.single();
	if (error || !data) throw error ?? new Error('addGearWearLog failed');
	return data as GearWearLog;
}

export async function deleteGearWearLog(id: string): Promise<void> {
	const { error } = await supabase
		.from(TABLES.gear_wear_logs)
		.delete()
		.eq('id', id);
	if (error) throw error;
}

// --- Gear rotations (roadmap §7 — named multi-pair grouping) ---

export interface GearRotation {
	id: string;
	owner_id: string;
	name: string;
	created_at: string;
	updated_at: string;
}

/// A rotation plus the ids of the gear it contains. The membership ids
/// are fetched alongside so the settings UI can group the gear list by
/// rotation and pre-check the assignment toggles without a second round
/// trip per rotation.
export interface GearRotationWithMembers extends GearRotation {
	gear_ids: string[];
}

/// Fetch every rotation the signed-in user owns, each with its member
/// gear ids. Two owner-scoped reads (rotations + the membership join)
/// stitched client-side — both are tiny (a runner has a handful of
/// rotations), and RLS scopes each to the owner.
export async function fetchMyGearRotations(): Promise<GearRotationWithMembers[]> {
	const { data: rotations, error: rotErr } = await supabase
		.from(TABLES.gear_rotations)
		.select('*')
		.order('name', { ascending: true });
	if (rotErr) {
		console.error('fetchMyGearRotations failed', rotErr);
		return [];
	}
	const { data: members, error: memErr } = await supabase
		.from(TABLES.gear_rotation_members)
		.select('rotation_id, gear_id');
	if (memErr) {
		console.error('fetchMyGearRotations members failed', memErr);
		return [];
	}
	const byRotation = new Map<string, string[]>();
	for (const m of (members ?? []) as { rotation_id: string; gear_id: string }[]) {
		const list = byRotation.get(m.rotation_id) ?? [];
		list.push(m.gear_id);
		byRotation.set(m.rotation_id, list);
	}
	return ((rotations ?? []) as GearRotation[]).map((r) => ({
		...r,
		gear_ids: byRotation.get(r.id) ?? [],
	}));
}

export async function createGearRotation(name: string): Promise<GearRotation> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.gear_rotations)
		.insert({ owner_id: userId, name })
		.select('*')
		.single();
	if (error || !data) throw error ?? new Error('createGearRotation failed');
	return data as GearRotation;
}

export async function renameGearRotation(id: string, name: string): Promise<void> {
	const { error } = await supabase
		.from(TABLES.gear_rotations)
		.update({ name })
		.eq('id', id);
	if (error) throw error;
}

/// Delete a rotation. Membership rows cascade away via the FK; the gear
/// itself is untouched (a rotation is just a grouping).
export async function deleteGearRotation(id: string): Promise<void> {
	const { error } = await supabase
		.from(TABLES.gear_rotations)
		.delete()
		.eq('id', id);
	if (error) throw error;
}

/// Replace the full gear set assigned to a rotation. Delete-then-insert,
/// mirroring [setRunGear] — the join has no natural-key churn worth a
/// smarter diff. RLS gates both halves to the rotation + gear owner.
export async function setGearRotationMembers(
	rotationId: string,
	gearIds: string[],
): Promise<void> {
	const del = await supabase
		.from(TABLES.gear_rotation_members)
		.delete()
		.eq('rotation_id', rotationId);
	if (del.error) throw del.error;
	if (gearIds.length === 0) return;
	const rows = gearIds.map((gear_id) => ({ rotation_id: rotationId, gear_id }));
	const ins = await supabase.from(TABLES.gear_rotation_members).insert(rows);
	if (ins.error) throw ins.error;
}

// --- Safety contacts (decisions §131) ---

export interface SafetyContact {
	id: string;
	contact_email: string;
	contact_user_id: string | null;
	confirmed_at: string | null;
	created_at: string;
}

export interface PendingSafetyRequest {
	id: string;
	owner_name: string;
	created_at: string;
}

/// The owner's own safety-contact list (RLS scopes to owner_id = me).
export async function fetchMySafetyContacts(): Promise<SafetyContact[]> {
	const { data, error } = await supabase
		.from(TABLES.safety_contacts)
		.select('id, contact_email, contact_user_id, confirmed_at, created_at')
		.order('created_at', { ascending: false });
	if (error) {
		console.error('fetchMySafetyContacts failed', error);
		return [];
	}
	return (data ?? []) as SafetyContact[];
}

/// Add a safety contact by email. The address is stored as-is; a confirm
/// email is sent by the AFTER INSERT trigger. confirmed_at / contact_user_id
/// are forced null server-side (the contact must opt in), so we never set
/// them here. Throws on RLS / unique / format failure for the caller to
/// surface.
export async function addSafetyContact(email: string): Promise<SafetyContact> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.safety_contacts)
		.insert({ owner_id: userId, contact_email: email })
		.select('id, contact_email, contact_user_id, confirmed_at, created_at')
		.single();
	if (error || !data) throw error ?? new Error('addSafetyContact failed');
	return data as SafetyContact;
}

/// Remove a safety contact the owner added (RLS gates to owner_id = me).
export async function removeSafetyContact(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.safety_contacts).delete().eq('id', id);
	if (error) throw error;
}

/// Pending requests where the signed-in user is the named contact (matched
/// by their account email via a SECURITY DEFINER RPC — the pending row isn't
/// directly readable until they link by confirming).
export async function fetchPendingSafetyRequests(): Promise<PendingSafetyRequest[]> {
	const { data, error } = await supabase.rpc('my_pending_safety_requests');
	if (error || !data) {
		if (error) console.error('fetchPendingSafetyRequests failed', error);
		return [];
	}
	return data as PendingSafetyRequest[];
}

/// Confirm a pending request addressed to my account email (links my
/// account). Returns whether a row was confirmed.
export async function confirmSafetyRequest(id: string): Promise<boolean> {
	const { data, error } = await supabase.rpc('confirm_safety_contact', { p_id: id });
	if (error) throw error;
	return data === true;
}

/// Decline a pending request / withdraw from a confirmed one.
export async function declineSafetyRequest(id: string): Promise<boolean> {
	const { data, error } = await supabase.rpc('decline_safety_contact', { p_id: id });
	if (error) throw error;
	return data === true;
}

/// Unauthenticated email-link confirm for an external contact. The token is
/// the capability; the anon Supabase client may call it.
export async function confirmSafetyContactByToken(token: string): Promise<boolean> {
	const { data, error } = await supabase.rpc('confirm_safety_contact_by_token', { p_token: token });
	if (error) throw error;
	return data === true;
}

// --- Segments + leaderboards (decisions §37) ---

export interface Segment {
	id: string;
	route_id: string;
	name: string;
	start_distance_m: number;
	end_distance_m: number;
	length_m: number | null;
	author_id: string | null;
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
		.from(TABLES.segments)
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
		.from(TABLES.segments)
		.insert({
			route_id: input.route_id,
			name: input.name.trim(),
			start_distance_m: input.start_distance_m,
			end_distance_m: input.end_distance_m,
			author_id: userId,
		})
		.select('*')
		.single();
	if (error || !data) throw error ?? new Error('Insert failed');
	return data as Segment;
}

export async function deleteSegment(segmentId: string): Promise<void> {
	const { error } = await supabase.from(TABLES.segments).delete().eq('id', segmentId);
	if (error) throw error;
}

// SEGMENT_AGE_BANDS, SegmentAgeBand, and SegmentGenderFilter live in
// `./segments` (pure module, importable by unit tests without pulling
// in the SvelteKit-only supabase client). Re-exported here so existing
// callers don't break.
export { SEGMENT_AGE_BANDS, type SegmentAgeBand, type SegmentGenderFilter } from '../segments/segments';

/**
 * Tiered leaderboard for a segment. Calls the `segment_leaderboard_tiered` RPC
 * which joins user_profiles server-side and applies gender / age-band
 * filters. Pass `null` for "all" on a filter. Ranks are computed
 * client-side from the returned order (1-based standard competition —
 * ties share a rank; next distinct time skips ordinal positions).
 */
export async function fetchSegmentLeaderboardTiered(
	segmentId: string,
	filter: {
		gender?: SegmentGenderFilter | null;
		ageBand?: SegmentAgeBand | null;
		clubId?: string | null;
	} = {},
	limit = 50,
): Promise<SegmentLeaderboardEntry[]> {
	const { data, error } = await supabase.rpc('segment_leaderboard_tiered', {
		p_segment_id: segmentId,
		p_gender: filter.gender ?? null,
		p_age_band: filter.ageBand ?? null,
		p_limit: limit,
		p_club_id: filter.clubId ?? null,
	});
	if (error || !data) {
		console.warn('fetchSegmentLeaderboardTiered failed', error);
		return [];
	}
	const rows = data as Array<{
		effort_id: string;
		user_id: string;
		run_id: string;
		time_seconds: number;
		started_at: string;
		display_name: string | null;
		avatar_url: string | null;
		gender: string | null;
		age: number | null;
	}>;
	return assignCompetitionRanks(rows).map(({ row, rank }) => ({
		effort: {
			id: row.effort_id,
			segment_id: segmentId,
			run_id: row.run_id,
			user_id: row.user_id,
			time_seconds: row.time_seconds,
			started_at: row.started_at,
			created_at: row.started_at,
		} as SegmentEffort,
		athlete: { id: row.user_id, display_name: row.display_name, avatar_url: row.avatar_url },
		rank,
	}));
}

/**
 * All segment efforts attached to a single run, joined to the parent
 * segment so the run-detail page can render "Climb of doom — 4:21,
 * #3 of 17". Rank is computed via a count query against the
 * leaderboard.
 */
export async function fetchEffortsForRun(runId: string): Promise<SegmentEffortWithSegment[]> {
	const { data: efforts, error } = await supabase
		.from(TABLES.segment_efforts)
		.select('*')
		.eq('run_id', runId);
	if (error || !efforts || efforts.length === 0) return [];

	const segmentIds = Array.from(new Set(efforts.map((e) => e.segment_id)));
	const { data: segments } = await supabase
		.from(TABLES.segments)
		.select('*')
		.in('id', segmentIds);
	const bySeg = new Map<string, Segment>();
	for (const s of segments ?? []) bySeg.set(s.id, s as Segment);

	// Rank every effort in ONE round-trip via segment_effort_ranks (migration
	// 20261223_001) instead of a serial count-per-effort loop — a run over a
	// 30-segment route used to fire 30 sequential queries before the panel
	// rendered. The RPC is SECURITY INVOKER so RLS gates the comparison set
	// identically to the old client count; rank = 1 + strictly-faster visible
	// efforts. On RPC failure ranks fall back to null so the panel still shows
	// the efforts (degraded, not blank).
	const { data: rankRows, error: rankErr } = await supabase.rpc('segment_effort_ranks', {
		p_run_id: runId,
	});
	if (rankErr) console.error('segment_effort_ranks failed', rankErr);
	const rankByEffort = new Map<string, number>();
	for (const r of (rankRows ?? []) as { effort_id: string; rank: number }[]) {
		rankByEffort.set(r.effort_id, r.rank);
	}

	const out: SegmentEffortWithSegment[] = [];
	for (const e of efforts as SegmentEffort[]) {
		const segment = bySeg.get(e.segment_id);
		if (!segment) continue;
		out.push({
			effort: e,
			segment,
			rank: rankByEffort.get(e.id) ?? 1,
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

	const { buildSegmentEffortRows } = await import('../segments/auto_segment_effort');
	const rows = buildSegmentEffortRows(segments, input.track as import('$lib/types').TrackPoint[], {
		run_id: input.run_id,
		user_id: userId,
	});
	if (rows.length === 0) return 0;

	// One batched upsert instead of an insert-per-segment loop — a run over a
	// 30-segment route used to fire 30 serial round-trips on the run-detail
	// view. `ignoreDuplicates` (ON CONFLICT DO NOTHING on unique(segment_id,
	// run_id)) keeps the prior per-row 23505 idempotency: re-viewing a run
	// re-inserts nothing and the RETURNING set counts only newly-written rows.
	const { data: inserted, error } = await supabase
		.from(TABLES.segment_efforts)
		.upsert(rows, { onConflict: 'segment_id,run_id', ignoreDuplicates: true })
		.select('id');
	if (error) {
		console.warn('segment effort batch upsert failed', input.run_id, error);
		return 0;
	}
	return inserted?.length ?? 0;
}

// --- Notifications (decisions §38) ---

export interface NotificationRow {
	id: string;
	user_id: string;
	actor_id: string | null;
	kind: NotificationKind;
	run_id: string | null;
	comment_id: string | null;
	event_id: string | null;
	plan_id: string | null;
	club_id: string | null;
	achievement_id: string | null;
	challenge_id: string | null;
	read_at: string | null;
	created_at: string;
}

export interface NotificationView {
	row: NotificationRow;
	actor: PublicProfile | null;
	run_distance_m: number | null;
	run_started_at: string | null;
	comment_excerpt: string | null;
	event_title: string | null;
	event_club_slug: string | null;
	club_name: string | null;
	club_slug: string | null;
}

/**
 * Last `limit` notifications for the current user, joined to actor
 * profiles + small run/comment metadata so the UI can render
 * "Alice commented on your 8 km run" without follow-up queries.
 */
export async function fetchNotifications(limit = 50): Promise<NotificationView[]> {
	const { data: rows, error } = await supabase
		.from(TABLES.notifications)
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
	const eventIds = Array.from(new Set(rows.map((r) => (r as { event_id?: string | null }).event_id).filter((x): x is string => !!x)));
	const clubIds = Array.from(new Set(rows.map((r) => (r as { club_id?: string | null }).club_id).filter((x): x is string => !!x)));

	const [profiles, runs, publicRuns, comments, events, clubs] = await Promise.all([
		actorIds.length > 0
			? supabase.from('user_profiles').select('id, display_name, avatar_url').in('id', actorIds)
			: Promise.resolve({ data: [] as PublicProfile[] }),
		// Two run reads: `runs` resolves the recipient's OWN runs
		// (kudos / comment / reply notifications, where the recipient is
		// the owner and the run may be private), and `public_runs`
		// resolves runs owned by someone else (run_completed, where the
		// recipient is a follower — the bare `runs` table has owner-only
		// SELECT since migration 20260701_001 so a follower read returns
		// nothing). Merged below; either source filling the distance.
		runIds.length > 0
			? supabase.from(TABLES.runs).select('id, distance_m, started_at').in('id', runIds)
			: Promise.resolve({ data: [] as { id: string; distance_m: number; started_at: string }[] }),
		runIds.length > 0
			? supabase.from('public_runs').select('id, distance_m, started_at').in('id', runIds)
			: Promise.resolve({ data: [] as { id: string; distance_m: number; started_at: string }[] }),
		commentIds.length > 0
			? supabase.from(TABLES.run_comments).select('id, body').in('id', commentIds)
			: Promise.resolve({ data: [] as { id: string; body: string }[] }),
		eventIds.length > 0
			? supabase.from('events').select('id, title, club_id, clubs(slug)').in('id', eventIds)
			: Promise.resolve({ data: [] as { id: string; title: string; clubs: { slug: string } | { slug: string }[] | null }[] }),
		clubIds.length > 0
			? supabase.from('clubs').select('id, name, slug').in('id', clubIds)
			: Promise.resolve({ data: [] as { id: string; name: string; slug: string }[] }),
	]);

	const profileBy = new Map<string, PublicProfile>();
	for (const p of (profiles.data ?? []) as PublicProfile[]) profileBy.set(p.id, p);
	const runBy = new Map<string, { distance_m: number; started_at: string }>();
	for (const r of (publicRuns.data ?? []) as { id: string; distance_m: number; started_at: string }[]) {
		runBy.set(r.id, { distance_m: r.distance_m, started_at: r.started_at });
	}
	// Owner-read overlays public — both carry the same columns; this just
	// fills any private run the public view omits.
	for (const r of (runs.data ?? []) as { id: string; distance_m: number; started_at: string }[]) {
		runBy.set(r.id, { distance_m: r.distance_m, started_at: r.started_at });
	}
	const commentBy = new Map<string, string>();
	for (const c of (comments.data ?? []) as { id: string; body: string }[]) {
		commentBy.set(c.id, c.body);
	}
	const eventBy = new Map<string, { title: string; club_slug: string | null }>();
	for (const e of (events.data ?? []) as { id: string; title: string; clubs: { slug: string } | { slug: string }[] | null }[]) {
		const club = Array.isArray(e.clubs) ? e.clubs[0] ?? null : e.clubs;
		eventBy.set(e.id, { title: e.title, club_slug: club?.slug ?? null });
	}
	const clubBy = new Map<string, { name: string; slug: string }>();
	for (const c of (clubs.data ?? []) as { id: string; name: string; slug: string }[]) {
		clubBy.set(c.id, { name: c.name, slug: c.slug });
	}

	return rows.map((row) => {
		const r = row as NotificationRow;
		const run = r.run_id ? runBy.get(r.run_id) ?? null : null;
		const body = r.comment_id ? commentBy.get(r.comment_id) ?? null : null;
		const ev = r.event_id ? eventBy.get(r.event_id) ?? null : null;
		const club = r.club_id ? clubBy.get(r.club_id) ?? null : null;
		return {
			row: r,
			actor: r.actor_id ? profileBy.get(r.actor_id) ?? null : null,
			run_distance_m: run?.distance_m ?? null,
			run_started_at: run?.started_at ?? null,
			comment_excerpt: body ? (body.length > 120 ? body.slice(0, 117) + '…' : body) : null,
			event_title: ev?.title ?? null,
			event_club_slug: ev?.club_slug ?? null,
			club_name: club?.name ?? null,
			club_slug: club?.slug ?? null,
		};
	});
}

export async function fetchUnreadNotificationCount(): Promise<number> {
	const { count, error } = await supabase
		.from(TABLES.notifications)
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
		.from(TABLES.notifications)
		.update({ read_at: new Date().toISOString() })
		.eq('id', id)
		.is('read_at', null);
	if (error) throw error;
}

export async function markAllNotificationsRead(): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) return;
	const { error } = await supabase
		.from(TABLES.notifications)
		.update({ read_at: new Date().toISOString() })
		.eq('user_id', userId)
		.is('read_at', null);
	if (error) throw error;
}

export async function deleteNotification(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.notifications).delete().eq('id', id);
	if (error) throw error;
}

// ─────────────────────── User reports ───────────────────────
//
// Submit a report against a user / club / route. The server-side
// `submit_report` SECURITY DEFINER RPC validates the target exists,
// rejects self-reports, rate-limits at 10/hour, and raises 23505 if
// the same reporter already has a pending report against the same
// target. See migration 20260908_001.

export type ReportReason =
	| 'spam'
	| 'harassment'
	| 'inappropriate'
	| 'impersonation'
	| 'other';

export async function submitReport(input: {
	targetKind: ReportTargetKind;
	targetId: string;
	reason: ReportReason;
	notes?: string;
}): Promise<string> {
	const { data, error } = await supabase.rpc('submit_report', {
		p_target_kind: input.targetKind,
		p_target_id: input.targetId,
		p_reason: input.reason,
		p_notes: input.notes?.trim() || null,
	});
	if (error) {
		// Normalise the load-bearing failure modes into caller-
		// friendly messages. The PostgREST envelope surfaces the
		// SQLSTATE / hint exactly as raised in the migration; we
		// don't lean on the raw text because that string can change.
		if (error.code === '23505') {
			throw new Error('You already have a pending report against this content.');
		}
		// The `create_report` bucket goes through the same
		// enforce_create_rate_limit trigger as create_club + create_route,
		// so the shared helper recognises the message + emits a
		// consistent "filing reports too quickly — please wait N minutes"
		// rather than this function carrying its own copy of the
		// translation rule.
		const friendly = rateLimitErrorMessage(error);
		if (friendly) throw new Error(friendly);
		throw error;
	}
	return data as string;
}

// ─────────────────────── Direct messages (#55) ───────────────────────

export interface DirectMessage {
	id: string;
	sender_id: string;
	recipient_id: string;
	body: string;
	created_at: string;
	read_at: string | null;
}

export interface DmThread {
	partnerId: string;
	partnerName: string | null;
	partnerAvatar: string | null;
	lastBody: string;
	lastAt: string;
	lastFromMe: boolean;
	unread: number;
}

/// Conversation list: the latest message per partner + an unread count.
/// Aggregated server-side by the dm_threads() RPC (DISTINCT ON partner +
/// unread COUNT over the viewer's ENTIRE message set) — one preview row per
/// conversation instead of pulling the newest 500 full message bodies and
/// folding them in JS (which over-fetched AND silently dropped older partners
/// once a heavy inbox's newest 500 messages spanned fewer conversations than
/// it had). Partner name/avatar stays a single .in() profile lookup.
export async function fetchDmThreads(): Promise<DmThread[]> {
	const me = auth.user?.id;
	if (!me) return [];
	const { data, error } = await supabase.rpc('dm_threads');
	if (error || !data) return [];
	const threads: DmThread[] = (data as {
		partner_id: string;
		last_body: string;
		last_at: string;
		last_from_me: boolean;
		unread: number;
	}[]).map((r) => ({
		partnerId: r.partner_id,
		partnerName: null,
		partnerAvatar: null,
		lastBody: r.last_body,
		lastAt: r.last_at,
		lastFromMe: r.last_from_me,
		unread: Number(r.unread) || 0,
	}));
	const byPartner = new Map(threads.map((t) => [t.partnerId, t]));
	const partnerIds = [...byPartner.keys()];
	if (partnerIds.length > 0) {
		const { data: profiles } = await supabase
			.from('user_profiles')
			.select('id, display_name, avatar_url')
			.in('id', partnerIds);
		for (const p of profiles ?? []) {
			const t = byPartner.get(p.id as string);
			if (t) {
				t.partnerName = (p.display_name as string | null) ?? null;
				t.partnerAvatar = (p.avatar_url as string | null) ?? null;
			}
		}
	}
	// The RPC already orders newest-conversation-first; the profile merge
	// preserves it (Map iteration is insertion order).
	return [...byPartner.values()];
}

/// Full message history with one partner, oldest-first for rendering.
export async function fetchDmThread(otherId: string, limit = 200): Promise<DirectMessage[]> {
	const me = auth.user?.id;
	if (!me) return [];
	const { data, error } = await supabase
		.from(TABLES.direct_messages)
		.select('*')
		.or(
			`and(sender_id.eq.${me},recipient_id.eq.${otherId}),and(sender_id.eq.${otherId},recipient_id.eq.${me})`,
		)
		.order('created_at', { ascending: true })
		.limit(limit);
	if (error || !data) return [];
	return data as DirectMessage[];
}

/// Send a message. RLS enforces the no-block + follow-graph gate; a
/// 42501 surfaces as a friendly "can't message this person" error.
export async function sendDm(recipientId: string, body: string): Promise<DirectMessage> {
	const me = auth.user?.id;
	if (!me) throw new Error('Not signed in');
	const trimmed = body.trim();
	if (!trimmed) throw new Error('Message is empty');
	const { data, error } = await supabase
		.from(TABLES.direct_messages)
		.insert({ sender_id: me, recipient_id: recipientId, body: trimmed })
		.select('*')
		.single();
	if (error || !data) {
		if (error?.code === '42501') {
			throw new Error("You can only message people you follow (or who follow you), and who haven't blocked you.");
		}
		throw error ?? new Error('Send failed');
	}
	return data as DirectMessage;
}

/// Mark every message from `otherId` to the viewer as read.
export async function markDmThreadRead(otherId: string): Promise<void> {
	const me = auth.user?.id;
	if (!me) return;
	await supabase
		.from(TABLES.direct_messages)
		.update({ read_at: new Date().toISOString() })
		.eq('sender_id', otherId)
		.eq('recipient_id', me)
		.is('read_at', null);
}

// --- Coach-athlete roster (persona #46) -------------------------------------
//
// A coach mints a shareable invite token (createCoachInvite); the athlete
// redeems it (redeemCoachInvite -> redeem_coach_invite RPC) to form an active
// link. RLS scopes every read/write to the two parties. Profiles are joined in
// a second query, mirroring the club-member fetch pattern above.

export interface CoachAthleteLink {
	id: string;
	status: CoachAthleteStatus;
	note: string | null;
	created_at: string;
	accepted_at: string | null;
	/// The athlete on a coach's roster, or the coach on an athlete's list.
	user_id: string;
	display_name: string | null;
	avatar_url: string | null;
}

export interface PendingCoachInvite {
	id: string;
	invite_token: string;
	note: string | null;
	created_at: string;
}

/// Mint a pending invite. The token is client-generated (122-bit UUID); only
/// the coach can read their own pending rows (RLS), so it never needs the
/// column-grant lockdown clubs use. Returns the token so the caller can build
/// the /coaching/accept/<token> share link.
export async function createCoachInvite(note?: string): Promise<string> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const token = crypto.randomUUID().replace(/-/g, '');
	const { error } = await supabase.from(TABLES.coach_athletes).insert({
		coach_id: userId,
		status: 'pending',
		invite_token: token,
		note: note?.trim() || null
	});
	if (error) throw error;
	return token;
}

/// Active athletes on the signed-in coach's roster, newest acceptance first.
/// Same as `fetchMyAthletes` but surfaces the roster-query error so a
/// caller can show a "couldn't load — retry" state instead of an empty
/// roster that's indistinguishable from "no athletes yet". The profile
/// enrichment stays best-effort (a missing display name isn't a load
/// failure). Mirrors the `fetchRoutesWithError` convention.
export async function fetchMyAthletesWithError(): Promise<{
	athletes: CoachAthleteLink[];
	error: string | null;
}> {
	const userId = auth.user?.id;
	if (!userId) return { athletes: [], error: null };
	const { data: rows, error } = await supabase
		.from(TABLES.coach_athletes)
		.select('id, status, note, created_at, accepted_at, athlete_id')
		.eq('coach_id', userId)
		.eq('status', 'active')
		.order('accepted_at', { ascending: false });
	if (error) return { athletes: [], error: error.message };
	if (!rows || rows.length === 0) return { athletes: [], error: null };
	const ids = (rows as { athlete_id: string }[]).map((r) => r.athlete_id);
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', ids);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profiles ?? []) byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	return {
		athletes: (rows as Array<Record<string, unknown>>).map((r) => ({
			id: r.id as string,
			status: r.status as CoachAthleteStatus,
			note: (r.note as string | null) ?? null,
			created_at: r.created_at as string,
			accepted_at: (r.accepted_at as string | null) ?? null,
			user_id: r.athlete_id as string,
			display_name: byId.get(r.athlete_id as string)?.display_name ?? null,
			avatar_url: byId.get(r.athlete_id as string)?.avatar_url ?? null
		})),
		error: null
	};
}

export async function fetchMyAthletes(): Promise<CoachAthleteLink[]> {
	return (await fetchMyAthletesWithError()).athletes;
}

/// One row of the multi-athlete coach roster (coach_roster.md). The shape is
/// the bespoke `coach_roster_summary` RPC projection — NOT a base-table row —
/// so it lives here next to CoachAthleteLink rather than as a types.ts overlay.
/// load_acute / load_chronic are RAW distance-proxy stress sums; the page
/// derives the ACWR risk band + load trend from them via the coach_load helper
/// (the risk policy stays in one place, never in the SQL).
export interface CoachRosterRow {
	athlete_id: string;
	display_name: string | null;
	avatar_url: string | null;
	last_run_at: string | null;
	runs_7d: number;
	distance_7d_m: number;
	load_acute: number;
	load_chronic: number;
	active_plan_id: string | null;
	plan_completion_pct: number;
}

/// The whole roster in one consent-gated round-trip. Surfaces the RPC error so
/// the page can show a retry state distinct from "no athletes yet" — the
/// durable shape, mirroring fetchMyAthletesWithError. Returns no athlete data
/// to a non-coach (the RPC's `mine` CTE yields zero rows; an unauthenticated
/// caller raises, which surfaces as an error here, fail-closed).
export async function fetchCoachRosterSummaryWithError(): Promise<{
	rows: CoachRosterRow[];
	error: string | null;
}> {
	if (!auth.user?.id) return { rows: [], error: null };
	const { data, error } = await supabase.rpc('coach_roster_summary');
	if (error) return { rows: [], error: error.message };
	const rows: CoachRosterRow[] = ((data as Array<Record<string, unknown>>) ?? []).map((r) => ({
		athlete_id: r.athlete_id as string,
		display_name: (r.display_name as string | null) ?? null,
		avatar_url: (r.avatar_url as string | null) ?? null,
		last_run_at: (r.last_run_at as string | null) ?? null,
		runs_7d: Number(r.runs_7d) || 0,
		distance_7d_m: Number(r.distance_7d_m) || 0,
		load_acute: Number(r.load_acute) || 0,
		load_chronic: Number(r.load_chronic) || 0,
		active_plan_id: (r.active_plan_id as string | null) ?? null,
		plan_completion_pct: Number(r.plan_completion_pct) || 0
	}));
	return { rows, error: null };
}

export async function fetchCoachRosterSummary(): Promise<CoachRosterRow[]> {
	return (await fetchCoachRosterSummaryWithError()).rows;
}

/// One athlete's recent runs for the coach review surface
/// (`/coaching/athletes/[id]`). The RLS policy `active coach reads
/// athlete runs` (migration 20261103_001) grants a `status='active'`
/// coach SELECT on the athlete's run rows — public AND private —
/// straight off the base table, so the explicit `user_id` filter here
/// is the *athlete*, not the caller. Column-narrowed: no track
/// download (the raw GPS trace stays owner-only — decisions § 98).
/// Returns [] when the caller isn't an active coach of `athleteId`
/// (RLS simply yields zero rows — no error).
export interface AthleteRunSummary {
	id: string;
	started_at: string;
	distance_m: number;
	duration_s: number;
	is_public: boolean;
	source: RunSource;
	route_id: string | null;
	activity_type: string;
	metadata: Record<string, unknown> | null;
}

export async function fetchAthleteRuns(
	athleteId: string,
	limit = 20
): Promise<AthleteRunSummary[]> {
	if (!auth.user?.id || !athleteId) return [];
	const { data, error } = await supabase
		.from(TABLES.runs)
		.select('id, started_at, distance_m, duration_s, is_public, source, route_id, activity_type, metadata')
		.eq('user_id', athleteId)
		.order('started_at', { ascending: false })
		.limit(limit);
	if (error || !data) return [];
	return (data as Array<Record<string, unknown>>).map((r) => ({
		id: r.id as string,
		started_at: r.started_at as string,
		distance_m: r.distance_m as number,
		duration_s: r.duration_s as number,
		is_public: (r.is_public as boolean) ?? false,
		source: parseRunSource(r.source as string | null),
		route_id: (r.route_id as string | null) ?? null,
		activity_type: (r.activity_type as string | null) ?? 'run',
		metadata: (r.metadata as Record<string, unknown> | null) ?? null,
	}));
}

/// The athlete's active training plan + per-workout compliance for the
/// coach review surface. Mirrors [fetchActivePlanOverview] but scoped
/// to `athleteId` — the coach plan-read policies (migration
/// 20261116_001) grant SELECT on `training_plans` / `plan_weeks` /
/// `plan_workouts` for active-linked athletes. Null when the athlete
/// has no active plan, or the caller isn't their active coach (RLS
/// yields no rows).
export async function fetchAthletePlanOverview(
	athleteId: string
): Promise<ActivePlanOverview | null> {
	if (!auth.user?.id || !athleteId) return null;
	const { data: plan } = await supabase
		.from('training_plans')
		.select('*')
		.eq('user_id', athleteId)
		.eq('status', 'active')
		.maybeSingle();
	if (!plan) return null;
	const { weeks, workouts } = await fetchPlan(plan.id);
	const { todayISO, isWorkoutSkipped } = await import('../training/training');
	const today = todayISO();
	const todayWorkout = workouts.find((w) => w.scheduled_date === today) ?? null;
	const completed = workouts.filter(
		(w) => w.manually_completed === true || w.completed_run_id != null
	).length;
	// Skipped workouts are off the books — neither done nor an outstanding
	// to-do — so they leave the progress denominator entirely.
	const total = workouts.filter((w) => w.kind !== 'rest' && !isWorkoutSkipped(w)).length;
	const completionPct = total === 0 ? 0 : Math.round((completed / total) * 100);
	return {
		plan: plan as TrainingPlan,
		weeks: weeks ?? [],
		workouts: workouts ?? [],
		todayWorkout,
		completionPct,
	};
}

/// Assigns a coach's plan to a linked athlete via the assign_plan_to_athlete
/// RPC (migration 20270106_001). The thrown error carries the RPC's raise text
/// (e.g. the athlete already has an active plan), which the caller surfaces.
export async function assignPlanToAthlete(
	sourcePlanId: string,
	athleteId: string,
	startDate: string
): Promise<string> {
	const { data, error } = await supabase.rpc('assign_plan_to_athlete', {
		p_source_plan_id: sourcePlanId,
		p_athlete_id: athleteId,
		p_start_date: startDate
	});
	if (error) throw error;
	return data as string;
}

/// Unredeemed invites the signed-in coach has minted.
export async function fetchPendingCoachInvites(): Promise<PendingCoachInvite[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data } = await supabase
		.from(TABLES.coach_athletes)
		.select('id, invite_token, note, created_at')
		.eq('coach_id', userId)
		.eq('status', 'pending')
		.is('athlete_id', null)
		.order('created_at', { ascending: false });
	return (data as PendingCoachInvite[]) ?? [];
}

/// Active coaches the signed-in athlete is linked to.
export async function fetchMyCoaches(): Promise<CoachAthleteLink[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data: rows } = await supabase
		.from(TABLES.coach_athletes)
		.select('id, status, note, created_at, accepted_at, coach_id')
		.eq('athlete_id', userId)
		.eq('status', 'active')
		.order('accepted_at', { ascending: false });
	if (!rows || rows.length === 0) return [];
	const ids = (rows as { coach_id: string }[]).map((r) => r.coach_id);
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', ids);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profiles ?? []) byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	return (rows as Array<Record<string, unknown>>).map((r) => ({
		id: r.id as string,
		status: r.status as CoachAthleteStatus,
		note: (r.note as string | null) ?? null,
		created_at: r.created_at as string,
		accepted_at: (r.accepted_at as string | null) ?? null,
		user_id: r.coach_id as string,
		display_name: byId.get(r.coach_id as string)?.display_name ?? null,
		avatar_url: byId.get(r.coach_id as string)?.avatar_url ?? null
	}));
}

/// Redeem an invite token. Returns the coach's user id.
export async function redeemCoachInvite(token: string): Promise<string> {
	const { data, error } = await supabase.rpc('redeem_coach_invite', { token });
	if (error) throw error;
	return data as string;
}

/// End an active link (either party may call). Goes through the end_coach_link
/// RPC, not a direct UPDATE: coach_athletes has no client UPDATE policy, so a
/// coach can't reassign athlete_id to forge a link. Soft-ends via status so the
/// row and its acceptance history survive for audit.
export async function endCoachLink(id: string): Promise<void> {
	const { error } = await supabase.rpc('end_coach_link', { p_id: id });
	if (error) throw error;
}

/// Revoke (hard-delete) an unredeemed invite. RLS only permits this on the
/// coach's own pending, athlete-less rows.
export async function revokeCoachInvite(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.coach_athletes).delete().eq('id', id);
	if (error) throw error;
}

// --- Gym (Phase 4 multi-modal, decisions §63; spec docs/features/multi_modal.md) ---
//
// A gym session is a `gym_workouts` parent with N ordered `gym_sets`
// children. Mirrors the api_client Dart methods (createGymWorkout /
// fetchGymWorkoutWithSets / ...). last_modified_at is client-stamped for
// the same newer-wins reconciliation runs + gear use — there is no server
// updated_at trigger (migration 20261204_001).

export interface GymWorkout {
	id: string;
	user_id: string;
	title: string | null;
	started_at: string;
	duration_s: number | null;
	notes: string | null;
	is_public: boolean;
	external_id: string | null;
	last_modified_at: string;
	created_at: string;
}

export interface GymSet {
	id: string;
	workout_id: string;
	set_index: number;
	exercise_name: string;
	reps: number | null;
	weight_kg: number | null;
	rpe: number | null;
	/// Role this set played (warmup / working / dropset / amrap / failure /
	/// backoff); defaults to 'working' (migration 20270224_001). Shares the
	/// gym_routine_sets.set_type vocabulary — GymSetType.
	set_type: GymSetType;
	/// Optional hold/interval time in seconds for timed work (planks, holds);
	/// null for rep/load-only sets (migration 20270101_001).
	duration_s: number | null;
	/// Optional link to a public.exercises catalogue entry (migration
	/// 20270222_001). null = a free-text set (the default). exercise_name is
	/// always present regardless — the link is provenance, not the PR key.
	exercise_id: string | null;
}

export interface GymWorkoutWithSets {
	workout: GymWorkout;
	sets: GymSet[];
}

export interface GymSetInput {
	exercise_name: string;
	reps?: number | null;
	weight_kg?: number | null;
	rpe?: number | null;
	/// Set role; omit to default to 'working' (migration 20270224_001).
	set_type?: GymSetType | null;
	duration_s?: number | null;
	/// Optional catalogue link (migration 20270222_001). Omit / null for a
	/// free-text set; the editor resolves it by matching the typed name against
	/// the catalogue at save time.
	exercise_id?: string | null;
}

/// One row per historical set, joined to its workout's start time, for
/// client-side PR computation (gym_prs.ts). Owner-scoped by RLS. Fine at
/// individual-user scale; see multi_modal.md § "activities view at scale".
export interface GymSetWithDate {
	workout_id: string;
	started_at: string;
	exercise_name: string;
	reps: number | null;
	weight_kg: number | null;
	rpe: number | null;
	duration_s: number | null;
}

/// Recent gym workouts for the signed-in user, newest first. Surfaces the
/// error so the /gym list can show a "couldn't load — retry" state instead of
/// the empty "log your first workout" card (a real failure otherwise reads as a
/// brand-new lifter whose history vanished). Mirrors the
/// `fetchExerciseRecordsWithError` convention.
export async function fetchGymWorkoutsWithError(
	limit = 50,
): Promise<{ workouts: GymWorkout[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { workouts: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.gym_workouts)
		.select('*')
		.eq('user_id', userId)
		.order('started_at', { ascending: false })
		.limit(limit);
	if (error) return { workouts: [], error: error.message };
	return { workouts: (data ?? []) as GymWorkout[], error: null };
}

/// Recent gym workouts for the signed-in user, newest first.
export async function fetchGymWorkouts(limit = 50): Promise<GymWorkout[]> {
	return (await fetchGymWorkoutsWithError(limit)).workouts;
}

/// A single workout plus its sets in set_index order. Returns null when the
/// id doesn't resolve (RLS hides another user's private workout).
export async function fetchGymWorkoutWithSets(
	id: string,
): Promise<GymWorkoutWithSets | null> {
	const { data: workout, error: wErr } = await supabase
		.from(TABLES.gym_workouts)
		.select('*')
		.eq('id', id)
		.maybeSingle();
	if (wErr || !workout) return null;
	const { data: sets, error: sErr } = await supabase
		.from(TABLES.gym_sets)
		.select('*')
		.eq('workout_id', id)
		.order('set_index', { ascending: true });
	if (sErr) {
		console.error('fetchGymWorkoutWithSets sets failed', sErr);
		return { workout: workout as GymWorkout, sets: [] };
	}
	return { workout: workout as GymWorkout, sets: (sets ?? []) as GymSet[] };
}

/// Sets the user has logged, joined to their workout start time. Owner-scoped.
///
/// `sinceDays` bounds the read to workouts started within the last N days —
/// pass it on surfaces that only reason about recent training (e.g. the
/// dashboard's 90-day training-load curve + its 5 most-recent-lift cards) so a
/// multi-year lifter's whole gym_sets history (~15k rows) isn't shipped to the
/// browser on every load. Surfaces that need all-time data (the per-workout PR
/// badges on /gym + /gym/[id]) pass nothing and read the full set; all-time
/// per-exercise bests go through fetchExerciseRecords (server-aggregated)
/// instead. perf-hunt follow-up 2026-06-10.
export async function fetchGymSetHistoryWithError(opts?: {
	sinceDays?: number;
}): Promise<{ sets: GymSetWithDate[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { sets: [], error: null };
	let query = supabase
		.from(TABLES.gym_sets)
		.select('workout_id, exercise_name, reps, weight_kg, rpe, duration_s, gym_workouts!inner(started_at, user_id)')
		.eq('gym_workouts.user_id', userId);
	if (opts?.sinceDays != null) {
		const since = new Date(Date.now() - opts.sinceDays * 86_400_000).toISOString();
		query = query.gte('gym_workouts.started_at', since);
	}
	const { data, error } = await query;
	if (error) return { sets: [], error: error.message };
	const sets = ((data ?? []) as unknown[]).map((row) => {
		const r = row as {
			workout_id: string;
			exercise_name: string;
			reps: number | null;
			weight_kg: number | null;
			rpe: number | null;
			duration_s: number | null;
			gym_workouts: { started_at: string } | { started_at: string }[];
		};
		const w = Array.isArray(r.gym_workouts) ? r.gym_workouts[0] : r.gym_workouts;
		return {
			workout_id: r.workout_id,
			started_at: w?.started_at ?? '',
			exercise_name: r.exercise_name,
			reps: r.reps,
			weight_kg: r.weight_kg,
			rpe: r.rpe,
			duration_s: r.duration_s,
		};
	});
	return { sets, error: null };
}

export async function fetchGymSetHistory(opts?: {
	sinceDays?: number;
}): Promise<GymSetWithDate[]> {
	return (await fetchGymSetHistoryWithError(opts)).sets;
}

/// One per-exercise all-time strength record (heaviest set, best volume, best
/// e1rm, last performed, session count). Computed server-side by the
/// gym_exercise_records RPC (migration 20261224_001) so the client never pulls
/// raw set history to recompute it. Records are all-time maxima, so a windowed
/// read can't serve them — the aggregation lives in SQL, mirroring how run PRs
/// are SQL-maintained (the gym_prs.ts badge engine stays client-side for the
/// per-workout temporal badges). pgTAP gym_exercise_records_test.sql pins the
/// metrics against the same fixture shape gym_prs.test.ts uses.
export interface ExerciseRecord {
	exerciseName: string;
	heaviestWeightKg: number;
	heaviestWeightReps: number | null;
	bestVolumeKg: number | null;
	bestEst1RmKg: number | null;
	/// ISO timestamp of the most recent workout that included this exercise.
	lastPerformedAt: string;
	sessionCount: number;
}

/// Per-exercise all-time records for the signed-in user, most-recently-
/// performed first. One round-trip; the SQL does the aggregation.
/// Same as `fetchExerciseRecords` but surfaces the RPC error so the
/// records page can show a "couldn't load — retry" state instead of the
/// empty "no records yet" card (a real failure otherwise reads as a
/// brand-new lifter). Mirrors the `fetchMyPlansWithError` convention.
export async function fetchExerciseRecordsWithError(): Promise<{
	records: ExerciseRecord[];
	error: string | null;
}> {
	if (!auth.user?.id) return { records: [], error: null };
	const { data, error } = await supabase.rpc('gym_exercise_records');
	if (error) return { records: [], error: error.message };
	type Row = {
		exercise_name: string;
		heaviest_weight_kg: number | string;
		heaviest_weight_reps: number | null;
		best_volume_kg: number | string | null;
		best_est_1rm_kg: number | string | null;
		last_performed_at: string;
		session_count: number;
	};
	const num = (v: number | string | null): number | null =>
		v == null ? null : Number(v);
	return {
		records: ((data ?? []) as Row[]).map((r) => ({
			exerciseName: r.exercise_name,
			heaviestWeightKg: Number(r.heaviest_weight_kg),
			heaviestWeightReps: r.heaviest_weight_reps,
			bestVolumeKg: num(r.best_volume_kg),
			bestEst1RmKg: num(r.best_est_1rm_kg),
			lastPerformedAt: r.last_performed_at,
			sessionCount: r.session_count,
		})),
		error: null
	};
}

export async function fetchExerciseRecords(): Promise<ExerciseRecord[]> {
	return (await fetchExerciseRecordsWithError()).records;
}

/// Every logged set of ONE exercise (normalised-name matched server-side),
/// joined to its workout start time — for the single-exercise progression view
/// (/gym/exercise). Bounds the read to that exercise instead of pulling the
/// whole history and filtering in JS. The RPC normalises the name the same way
/// gym_prs.ts#normaliseExerciseName does, so it picks up sessions logged under
/// a different capitalisation. perf-hunt follow-up 2026-06-10.
/// Same as `fetchExerciseSetHistory` but surfaces the RPC error so the
/// single-exercise progression page can show a "couldn't load — retry"
/// state instead of an empty "no progression data" card.
export async function fetchExerciseSetHistoryWithError(
	name: string
): Promise<{ sets: GymSetWithDate[]; error: string | null }> {
	if (!auth.user?.id || !name.trim()) return { sets: [], error: null };
	const { data, error } = await supabase.rpc('gym_exercise_set_history', { p_name: name });
	if (error) return { sets: [], error: error.message };
	return {
		sets: ((data ?? []) as Array<{
			workout_id: string;
			started_at: string;
			exercise_name: string;
			reps: number | null;
			weight_kg: number | string | null;
			rpe: number | string | null;
			duration_s: number | null;
		}>).map((r) => ({
			workout_id: r.workout_id,
			started_at: r.started_at,
			exercise_name: r.exercise_name,
			reps: r.reps,
			weight_kg: r.weight_kg == null ? null : Number(r.weight_kg),
			rpe: r.rpe == null ? null : Number(r.rpe),
			duration_s: r.duration_s,
		})),
		error: null
	};
}

export async function fetchExerciseSetHistory(name: string): Promise<GymSetWithDate[]> {
	return (await fetchExerciseSetHistoryWithError(name)).sets;
}

/// Distinct exercise names the user has logged, most-used first — for the gym
/// editor's autocomplete datalist. Bounded to the count of distinct exercises
/// (dozens), so a caller that only needs the names never pulls raw set history.
/// perf-hunt follow-up 2026-06-10.
export async function fetchGymExerciseNames(): Promise<string[]> {
	if (!auth.user?.id) return [];
	const { data, error } = await supabase.rpc('gym_exercise_names');
	if (error) {
		console.error('fetchGymExerciseNames failed', error);
		return [];
	}
	return ((data ?? []) as Array<{ exercise_name: string }>).map((r) => r.exercise_name);
}

/// The exercise catalogue visible to the signed-in user: every seeded global
/// (author_id null) plus their own custom entries. RLS scopes the read; an
/// ordered name list lets the gym editor merge these into its autocomplete
/// datalist and bind a typed name to an exercise_id (migration 20270222_001).
/// Additive — a user who never picks a catalogue entry logs exactly as before.
export async function fetchExerciseCatalogue(): Promise<Exercise[]> {
	if (!auth.user?.id) return [];
	const { data, error } = await supabase
		.from(TABLES.exercises)
		.select('*')
		.order('name', { ascending: true });
	if (error) {
		console.error('fetchExerciseCatalogue failed', error);
		return [];
	}
	return (data ?? []) as Exercise[];
}

/// Create an owner-scoped custom exercise. name_key is the normalised name so
/// it binds to logged sets the same way gym_prs / gym_routine_exercises key.
/// RLS rejects an insert with any author_id other than the caller. Returns the
/// created row, or null on conflict/error (e.g. a duplicate name_key).
export async function createCustomExercise(input: {
	name: string;
	category?: ExerciseCategory;
	modality?: GymExerciseModality;
}): Promise<Exercise | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const name = input.name.trim();
	if (name.length === 0) return null;
	const nowIso = new Date().toISOString();
	const { data, error } = await supabase
		.from(TABLES.exercises)
		.insert({
			author_id: userId,
			name,
			name_key: normaliseExerciseName(name),
			category: input.category ?? 'other',
			modality: input.modality ?? 'weight_reps',
			last_modified_at: nowIso,
		})
		.select('*')
		.single();
	if (error || !data) {
		console.error('createCustomExercise failed', error);
		return null;
	}
	return data as Exercise;
}

async function replaceGymSets(workoutId: string, sets: GymSetInput[]): Promise<void> {
	const { error: delErr } = await supabase
		.from(TABLES.gym_sets)
		.delete()
		.eq('workout_id', workoutId);
	if (delErr) throw delErr;
	const rows = sets
		.map((s, i) => ({
			workout_id: workoutId,
			set_index: i,
			exercise_name: s.exercise_name.trim(),
			reps: s.reps ?? null,
			weight_kg: s.weight_kg ?? null,
			rpe: s.rpe ?? null,
			// NOT NULL column — coalesce to the working default so an omitted
			// type never sends null (migration 20270224_001).
			set_type: s.set_type ?? 'working',
			duration_s: s.duration_s ?? null,
			exercise_id: s.exercise_id ?? null,
		}))
		.filter((r) => r.exercise_name.length > 0);
	if (rows.length === 0) return;
	const { error: insErr } = await supabase.from(TABLES.gym_sets).insert(rows);
	if (insErr) throw insErr;
}

export async function createGymWorkout(input: {
	title?: string | null;
	started_at?: string;
	duration_s?: number | null;
	notes?: string | null;
	is_public?: boolean;
	sets?: GymSetInput[];
	metadata?: Record<string, unknown> | null;
}): Promise<GymWorkout> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const nowIso = new Date().toISOString();
	const { data, error } = await supabase
		.from(TABLES.gym_workouts)
		.insert({
			user_id: userId,
			title: input.title ?? null,
			started_at: input.started_at ?? nowIso,
			duration_s: input.duration_s ?? null,
			notes: input.notes ?? null,
			is_public: input.is_public ?? false,
			// gym_workouts.metadata is NOT NULL default '{}' (20270101_001).
			// Sending an explicit null bypasses the default and trips a 23502,
			// so coalesce to an empty bag when the caller omits it.
			metadata: input.metadata ?? {},
			last_modified_at: nowIso,
		})
		.select('*')
		.single();
	if (error || !data) throw error ?? new Error('createGymWorkout failed');
	const workout = data as GymWorkout;
	if (input.sets && input.sets.length > 0) {
		await replaceGymSets(workout.id, input.sets);
	}
	return workout;
}

export async function updateGymWorkout(
	id: string,
	patch: Partial<Pick<GymWorkout, 'title' | 'started_at' | 'duration_s' | 'notes' | 'is_public'>>,
	sets?: GymSetInput[],
): Promise<void> {
	const { error } = await supabase
		.from(TABLES.gym_workouts)
		.update({ ...patch, last_modified_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw error;
	if (sets !== undefined) await replaceGymSets(id, sets);
}

/// Flip a gym workout's visibility. Mirrors `setRoutePublic` — bidirectional
/// (public ↔ private). RLS guards ownership; the caller should still gate the
/// UI so non-owners never see the control. Stamps `last_modified_at` so the
/// offline newer-wins reconciliation on mobile picks the change up.
export async function setGymWorkoutPublic(id: string, isPublic: boolean): Promise<void> {
	const { error } = await supabase
		.from(TABLES.gym_workouts)
		.update({ is_public: isPublic, last_modified_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw error;
}

/// Deletes the workout; gym_sets cascade via the FK (migration 20261204_001).
export async function deleteGymWorkout(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.gym_workouts).delete().eq('id', id);
	if (error) throw error;
}

// --- Gym routines (gym_programming.md slice P1) ---
//
// A reusable plan: gym_routines parent + gym_routine_exercises + their
// gym_routine_sets. Author-only RLS (migration 20270101_001). last_modified_at
// + exercise_count are client-stamped (newer-wins sync, non-authoritative
// count — no server trigger), mirroring gym_workouts. The plan is NOT a dated
// activity, so it does not feed the activities view. P1 leaves the superset /
// progression / periodisation columns at their defaults.

export interface GymRoutineSummary {
	id: string;
	author_id: string;
	club_id: string | null;
	is_public_template: boolean;
	title: string;
	notes: string | null;
	exercise_count: number;
	last_modified_at: string;
	created_at: string;
}

export interface GymRoutineExercise {
	id: string;
	exercise_name: string;
	exercise_key: string;
	position: number;
	superset_group: number | null;
	superset_order: number | null;
	modality: GymExerciseModality;
	progression: GymProgressionScheme;
	progression_params: Record<string, unknown>;
	sets: GymRoutineSet[];
}

export interface GymRoutineSet {
	set_index: number;
	set_type: GymSetType;
	target_reps_min: number | null;
	target_reps_max: number | null;
	target_weight_kg: number | null;
	target_rpe: number | null;
	rest_s: number | null;
	target_duration_s: number | null;
	target_distance_m: number | null;
}

export interface GymRoutineDetail {
	routine: GymRoutineSummary;
	exercises: GymRoutineExercise[];
}

/// The shape routineFromWorkout / the RoutineEditor produce. Mirrors the
/// RoutineDraft from $lib/gym/gym_routine.ts.
export interface GymRoutineInput {
	title: string;
	notes?: string | null;
	exercises: Array<{
		exercise_name: string;
		exercise_key: string;
		position: number;
		superset_group?: number | null;
		superset_order?: number | null;
		modality?: GymExerciseModality;
		progression?: GymProgressionScheme;
		progression_params?: Record<string, unknown>;
		sets: Array<{
			set_index: number;
			set_type?: GymSetType;
			target_reps_min?: number | null;
			target_reps_max?: number | null;
			target_weight_kg?: number | null;
			target_rpe?: number | null;
			rest_s?: number | null;
			target_duration_s?: number | null;
			target_distance_m?: number | null;
		}>;
	}>;
}

/// Authored routines for the signed-in user, most-recently-modified first.
/// Same as `fetchGymRoutines` but surfaces the error so the routines page
/// can show a "couldn't load — retry" state rather than an empty list
/// (indistinguishable from "no routines yet"). Mirrors the
/// `fetchRoutesWithError` / `fetchMyPlansWithError` convention.
export async function fetchGymRoutinesWithError(
	limit = 100
): Promise<{ routines: GymRoutineSummary[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { routines: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.gym_routines)
		.select('id, author_id, club_id, is_public_template, title, notes, exercise_count, last_modified_at, created_at')
		.eq('author_id', userId)
		.order('last_modified_at', { ascending: false })
		.limit(limit);
	return { routines: (data ?? []) as GymRoutineSummary[], error: error?.message ?? null };
}

export async function fetchGymRoutines(limit = 100): Promise<GymRoutineSummary[]> {
	return (await fetchGymRoutinesWithError(limit)).routines;
}

/// A single routine with its exercises (by position) + their planned sets (by
/// set_index). Returns null when the id doesn't resolve (RLS hides others').
export async function fetchGymRoutineDetail(id: string): Promise<GymRoutineDetail | null> {
	const { data: routine, error: rErr } = await supabase
		.from(TABLES.gym_routines)
		.select('id, author_id, club_id, is_public_template, title, notes, exercise_count, last_modified_at, created_at')
		.eq('id', id)
		.maybeSingle();
	if (rErr || !routine) return null;
	const { data: exRows, error: eErr } = await supabase
		.from(TABLES.gym_routine_exercises)
		.select(
			'id, exercise_name, exercise_key, position, superset_group, superset_order, modality, progression, progression_params',
		)
		.eq('routine_id', id)
		.order('position', { ascending: true });
	if (eErr) {
		console.error('fetchGymRoutineDetail exercises failed', eErr);
		return { routine: routine as GymRoutineSummary, exercises: [] };
	}
	const exercises = (exRows ?? []) as Array<{
		id: string;
		exercise_name: string;
		exercise_key: string;
		position: number;
		superset_group: number | null;
		superset_order: number | null;
		modality: GymExerciseModality;
		progression: GymProgressionScheme;
		progression_params: Record<string, unknown> | null;
	}>;
	if (exercises.length === 0) {
		return { routine: routine as GymRoutineSummary, exercises: [] };
	}
	const { data: setRows, error: sErr } = await supabase
		.from(TABLES.gym_routine_sets)
		.select(
			'routine_exercise_id, set_index, set_type, target_reps_min, target_reps_max, target_weight_kg, target_rpe, rest_s, target_duration_s, target_distance_m',
		)
		.in('routine_exercise_id', exercises.map((e) => e.id))
		.order('set_index', { ascending: true });
	if (sErr) console.error('fetchGymRoutineDetail sets failed', sErr);
	const setsByExercise = new Map<string, GymRoutineSet[]>();
	for (const row of (setRows ?? []) as Array<{ routine_exercise_id: string } & GymRoutineSet>) {
		const list = setsByExercise.get(row.routine_exercise_id) ?? [];
		list.push({
			set_index: row.set_index,
			set_type: row.set_type,
			target_reps_min: row.target_reps_min,
			target_reps_max: row.target_reps_max,
			target_weight_kg: row.target_weight_kg,
			target_rpe: row.target_rpe,
			rest_s: row.rest_s,
			target_duration_s: row.target_duration_s,
			target_distance_m: row.target_distance_m,
		});
		setsByExercise.set(row.routine_exercise_id, list);
	}
	return {
		routine: routine as GymRoutineSummary,
		exercises: exercises.map((e) => ({
			id: e.id,
			exercise_name: e.exercise_name,
			exercise_key: e.exercise_key,
			position: e.position,
			superset_group: e.superset_group,
			superset_order: e.superset_order,
			modality: e.modality,
			progression: e.progression,
			progression_params: e.progression_params ?? {},
			sets: setsByExercise.get(e.id) ?? [],
		})),
	};
}

/// Insert a routine + its exercises + their planned sets. Blank-named
/// exercises are dropped. exercise_count is stamped client-side from the
/// surviving exercise list (non-authoritative cache).
export async function createGymRoutine(input: GymRoutineInput): Promise<GymRoutineSummary> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const exercises = input.exercises.filter((e) => e.exercise_name.trim().length > 0);
	const nowIso = new Date().toISOString();
	const { data, error } = await supabase
		.from(TABLES.gym_routines)
		.insert({
			author_id: userId,
			title: input.title.trim(),
			notes: input.notes ?? null,
			exercise_count: exercises.length,
			last_modified_at: nowIso,
		})
		.select('id, author_id, club_id, is_public_template, title, notes, exercise_count, last_modified_at, created_at')
		.single();
	if (error || !data) throw error ?? new Error('createGymRoutine failed');
	const routine = data as GymRoutineSummary;
	if (exercises.length === 0) return routine;

	// Batch-insert all exercises in one round-trip, then all their planned sets
	// in a second — collapsing the previous N+1 serial loop (one INSERT…select
	// per exercise, each blocking the next, plus a per-exercise sets insert)
	// into 2 round-trips regardless of routine size. `position` is
	// client-supplied and unique per routine, and there's no insert trigger
	// reading prior rows, so the rows have no inter-row dependency and the
	// returned ids map back by position. Mirrors createTrainingPlan's shape.
	const exerciseRows = exercises.map((ex) => {
		// gym_routine_exercises_superset_chk requires the group + order to be
		// both null or both set, so a standalone exercise clears both.
		const supersetGroup = ex.superset_group ?? null;
		return {
			routine_id: routine.id,
			exercise_name: ex.exercise_name.trim(),
			exercise_key: ex.exercise_key,
			position: ex.position,
			superset_group: supersetGroup,
			superset_order: supersetGroup == null ? null : ex.superset_order ?? 0,
			modality: ex.modality ?? 'weight_reps',
			progression: ex.progression ?? 'none',
			progression_params: ex.progression_params ?? {},
		};
	});
	const { data: exRows, error: exErr } = await supabase
		.from(TABLES.gym_routine_exercises)
		.insert(exerciseRows)
		.select('id, position');
	if (exErr || !exRows) throw exErr ?? new Error('createGymRoutine exercises failed');
	const idByPosition = new Map<number, string>();
	for (const r of exRows as { id: string; position: number }[]) {
		idByPosition.set(r.position, r.id);
	}
	const allSetRows = exercises.flatMap((ex) => {
		const exId = idByPosition.get(ex.position);
		if (!exId) return [];
		return ex.sets.map((s, i) => ({
			routine_exercise_id: exId,
			set_index: i,
			set_type: s.set_type ?? 'working',
			target_reps_min: s.target_reps_min ?? null,
			target_reps_max: s.target_reps_max ?? null,
			target_weight_kg: s.target_weight_kg ?? null,
			target_rpe: s.target_rpe ?? null,
			rest_s: s.rest_s ?? null,
			target_duration_s: s.target_duration_s ?? null,
			target_distance_m: s.target_distance_m ?? null,
		}));
	});
	if (allSetRows.length > 0) {
		const { error: sErr } = await supabase.from(TABLES.gym_routine_sets).insert(allSetRows);
		if (sErr) throw sErr;
	}
	return routine;
}

/// Deletes a routine; exercises + sets cascade via FK (migration 20270101_001).
/// Logged gym_workouts are untouched (the plan→log link is a metadata string,
/// not an FK).
export async function deleteGymRoutine(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.gym_routines).delete().eq('id', id);
	if (error) throw error;
}

// --- Nutrition: food_log + body_metrics (Phase 4 multi-modal) ---
//
// A food_log row is one logged item against an optional meal slot, with
// per-item macros (migration 20261204_001). last_modified_at is
// client-stamped (newer-wins sync, no server trigger), mirroring gym/gear.
// Meals are owner-private in v1 — is_public exists in the schema but no UI
// surfaces meal sharing (multi_modal.md § Social feed).

export type MealSlot = 'breakfast' | 'lunch' | 'dinner' | 'snack';

export interface FoodEntry {
	id: string;
	user_id: string;
	started_at: string;
	item_name: string;
	meal_slot: MealSlot | null;
	calories: number | null;
	protein_g: number | null;
	carbs_g: number | null;
	fat_g: number | null;
	is_public: boolean;
	external_id: string | null;
	last_modified_at: string;
	created_at: string;
}

export interface FoodEntryInput {
	item_name: string;
	meal_slot?: MealSlot | null;
	calories?: number | null;
	protein_g?: number | null;
	carbs_g?: number | null;
	fat_g?: number | null;
	started_at?: string;
	external_id?: string | null;
}

/// Food entries whose `started_at` falls in the half-open window
/// [fromIso, toIso). Surfaces the error so the daily nutrition view + the
/// per-meal-slot detail can show a "couldn't load — retry" state instead of an
/// empty day (a real failure otherwise reads as "nothing logged", inviting the
/// user to re-log meals they already have). Mirrors the
/// `fetchExerciseRecordsWithError` convention.
export async function fetchFoodLogWithError(
	fromIso: string,
	toIso: string,
): Promise<{ entries: FoodEntry[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { entries: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.food_log)
		.select('*')
		.eq('user_id', userId)
		.gte('started_at', fromIso)
		.lt('started_at', toIso)
		.order('started_at', { ascending: true });
	if (error) return { entries: [], error: error.message };
	return { entries: (data ?? []) as FoodEntry[], error: null };
}

/// Food entries whose `started_at` falls in the half-open window
/// [fromIso, toIso). Used for the daily nutrition view + ring totals.
/// Owner-scoped by RLS.
export async function fetchFoodLog(fromIso: string, toIso: string): Promise<FoodEntry[]> {
	return (await fetchFoodLogWithError(fromIso, toIso)).entries;
}

export async function createFoodEntry(input: FoodEntryInput): Promise<FoodEntry> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('not signed in');
	const now = new Date().toISOString();
	const row = {
		user_id: userId,
		item_name: input.item_name,
		meal_slot: input.meal_slot ?? null,
		calories: input.calories ?? null,
		protein_g: input.protein_g ?? null,
		carbs_g: input.carbs_g ?? null,
		fat_g: input.fat_g ?? null,
		started_at: input.started_at ?? now,
		external_id: input.external_id ?? null,
		last_modified_at: now,
	};
	const { data, error } = await supabase
		.from(TABLES.food_log)
		.insert(row)
		.select('*')
		.single();
	if (error) throw error;
	return data as FoodEntry;
}

export async function updateFoodEntry(
	id: string,
	patch: Partial<FoodEntryInput>,
): Promise<void> {
	const { error } = await supabase
		.from(TABLES.food_log)
		.update({ ...patch, last_modified_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw error;
}

export async function deleteFoodEntry(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.food_log).delete().eq('id', id);
	if (error) throw error;
}

// --- Meal templates: saved meals logged with one tap (multi_modal.md) ---
//
// A reusable plan: meal_templates parent + meal_template_items. Owner-scoped
// RLS (migration 20270218_001). last_modified_at + item_count are
// client-stamped (newer-wins sync, non-authoritative count — no server
// trigger), mirroring food_log + gym_routines. A template is NOT a dated
// activity, so it does not feed the activities view. Item shaping (logged
// entries -> draft, template -> log inputs) is the pure meal_template.ts
// parity pair; these helpers are the Supabase round-trips.

export interface MealTemplateSummary {
	id: string;
	user_id: string;
	name: string;
	meal_slot: MealSlot | null;
	item_count: number;
	last_modified_at: string;
	created_at: string;
}

export interface MealTemplateItemRow {
	position: number;
	item_name: string;
	meal_slot: MealSlot | null;
	calories: number | null;
	protein_g: number | null;
	carbs_g: number | null;
	fat_g: number | null;
	external_id: string | null;
}

export interface MealTemplateDetail {
	template: MealTemplateSummary;
	items: MealTemplateItemRow[];
}

/// The shape templateFromEntries / the save-as-meal flow hand to the create
/// call. Mirrors MealTemplateDraft from $lib/nutrition/meal_template.ts.
export interface MealTemplateInput {
	name: string;
	meal_slot?: MealSlot | null;
	items: Array<{
		position: number;
		item_name: string;
		meal_slot?: MealSlot | null;
		calories?: number | null;
		protein_g?: number | null;
		carbs_g?: number | null;
		fat_g?: number | null;
		external_id?: string | null;
	}>;
}

/// Saved meal templates for the signed-in user, most-recently-modified first.
/// Surfaces the error so the list can show a "couldn't load — retry" state
/// rather than an empty list (indistinguishable from "no templates yet"),
/// mirroring `fetchGymRoutinesWithError`.
export async function fetchMealTemplatesWithError(
	limit = 100,
): Promise<{ templates: MealTemplateSummary[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { templates: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.meal_templates)
		.select('id, user_id, name, meal_slot, item_count, last_modified_at, created_at')
		.eq('user_id', userId)
		.order('last_modified_at', { ascending: false })
		.limit(limit);
	return { templates: (data ?? []) as MealTemplateSummary[], error: error?.message ?? null };
}

export async function fetchMealTemplates(limit = 100): Promise<MealTemplateSummary[]> {
	return (await fetchMealTemplatesWithError(limit)).templates;
}

/// A single template with its items ordered by `position`. Returns null when
/// the id doesn't resolve (RLS hides others').
export async function fetchMealTemplateDetail(id: string): Promise<MealTemplateDetail | null> {
	const { data: template, error: tErr } = await supabase
		.from(TABLES.meal_templates)
		.select('id, user_id, name, meal_slot, item_count, last_modified_at, created_at')
		.eq('id', id)
		.maybeSingle();
	if (tErr || !template) return null;
	const { data: itemRows, error: iErr } = await supabase
		.from(TABLES.meal_template_items)
		.select('position, item_name, meal_slot, calories, protein_g, carbs_g, fat_g, external_id')
		.eq('template_id', id)
		.order('position', { ascending: true });
	if (iErr) console.error('fetchMealTemplateDetail items failed', iErr);
	return {
		template: template as MealTemplateSummary,
		items: (itemRows ?? []) as MealTemplateItemRow[],
	};
}

/// Insert a template + its items. Blank-named items are dropped. item_count is
/// stamped client-side from the surviving item list (non-authoritative cache).
/// Two round-trips (parent, then a single batch of items), mirroring
/// `createGymRoutine`.
export async function createMealTemplate(input: MealTemplateInput): Promise<MealTemplateSummary> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const items = input.items.filter((it) => it.item_name.trim().length > 0);
	const nowIso = new Date().toISOString();
	const { data, error } = await supabase
		.from(TABLES.meal_templates)
		.insert({
			user_id: userId,
			name: input.name.trim(),
			meal_slot: input.meal_slot ?? null,
			item_count: items.length,
			last_modified_at: nowIso,
		})
		.select('id, user_id, name, meal_slot, item_count, last_modified_at, created_at')
		.single();
	if (error || !data) throw error ?? new Error('createMealTemplate failed');
	const template = data as MealTemplateSummary;
	if (items.length === 0) return template;
	const itemRows = items.map((it, i) => ({
		template_id: template.id,
		position: i,
		item_name: it.item_name.trim(),
		meal_slot: it.meal_slot ?? null,
		calories: it.calories ?? null,
		protein_g: it.protein_g ?? null,
		carbs_g: it.carbs_g ?? null,
		fat_g: it.fat_g ?? null,
		external_id: it.external_id ?? null,
	}));
	const { error: iErr } = await supabase.from(TABLES.meal_template_items).insert(itemRows);
	if (iErr) throw iErr;
	return template;
}

/// Delete a template; its items cascade via FK (migration 20270218_001).
/// Logged food_log entries are untouched — the template is a parallel plan,
/// never linked to the entries it spawned.
export async function deleteMealTemplate(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.meal_templates).delete().eq('id', id);
	if (error) throw error;
}

/// Log every item of a template as a food_log entry at `startedAt` (default
/// now), one round-trip. Returns the count logged. This is the one-tap
/// "Log meal template" path; the slot/item shaping (item → template-default →
/// `slotOverride`, position order) is the pure `entriesFromTemplate` parity
/// helper so the resolution can't drift from the mobile twin.
export async function logMealTemplate(
	detail: MealTemplateDetail,
	opts: { startedAt?: string; slotOverride?: MealSlot | null } = {},
): Promise<number> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const inputs = entriesFromTemplate(
		{
			name: detail.template.name,
			mealSlot: detail.template.meal_slot,
			items: detail.items.map((it) => ({
				position: it.position,
				itemName: it.item_name,
				mealSlot: it.meal_slot,
				calories: it.calories,
				proteinG: it.protein_g,
				carbsG: it.carbs_g,
				fatG: it.fat_g,
				externalId: it.external_id,
			})),
		},
		opts.slotOverride ?? null,
	);
	if (inputs.length === 0) return 0;
	const startedAt = opts.startedAt ?? new Date().toISOString();
	const nowIso = new Date().toISOString();
	const rows = inputs.map((it) => ({
		user_id: userId,
		item_name: it.itemName,
		meal_slot: it.mealSlot,
		calories: it.calories,
		protein_g: it.proteinG,
		carbs_g: it.carbsG,
		fat_g: it.fatG,
		started_at: startedAt,
		external_id: it.externalId,
		last_modified_at: nowIso,
	}));
	const { error } = await supabase.from(TABLES.food_log).insert(rows);
	if (error) throw error;
	return rows.length;
}

// --- Recipes: N ingredients summed into one logged meal (multi_modal.md) ---
//
// A reusable plan: recipes parent + recipe_ingredients. Owner-scoped RLS
// (migration 20270221_001). last_modified_at + ingredient_count are
// client-stamped (newer-wins sync, non-authoritative count — no server
// trigger), like meal_templates. The difference from a meal template: logging
// a recipe sums its ingredients into ONE food_log entry (the recipe's combined
// macros, scaled by servings), not one entry per item. The summing + the
// single log input is the pure recipe.ts parity pair; these helpers are the
// Supabase round-trips. A recipe is NOT a dated activity, so it never feeds
// the activities view.

export interface RecipeSummary {
	id: string;
	user_id: string;
	name: string;
	servings: number;
	meal_slot: MealSlot | null;
	ingredient_count: number;
	last_modified_at: string;
	created_at: string;
}

export interface RecipeIngredientRow {
	position: number;
	item_name: string;
	quantity: number;
	calories: number | null;
	protein_g: number | null;
	carbs_g: number | null;
	fat_g: number | null;
	external_id: string | null;
}

export interface RecipeDetail {
	recipe: RecipeSummary;
	ingredients: RecipeIngredientRow[];
}

/// The shape recipeFromEntries / the save-as-recipe flow hand to the create
/// call. Mirrors RecipeDraft from $lib/nutrition/recipe.ts.
export interface RecipeInput {
	name: string;
	servings?: number;
	meal_slot?: MealSlot | null;
	ingredients: Array<{
		position: number;
		item_name: string;
		quantity?: number;
		calories?: number | null;
		protein_g?: number | null;
		carbs_g?: number | null;
		fat_g?: number | null;
		external_id?: string | null;
	}>;
}

/// Saved recipes for the signed-in user, most-recently-modified first.
/// Surfaces the error so the list can show a "couldn't load — retry" state
/// rather than an empty list, mirroring `fetchMealTemplatesWithError`.
export async function fetchRecipesWithError(
	limit = 100,
): Promise<{ recipes: RecipeSummary[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { recipes: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.recipes)
		.select('id, user_id, name, servings, meal_slot, ingredient_count, last_modified_at, created_at')
		.eq('user_id', userId)
		.order('last_modified_at', { ascending: false })
		.limit(limit);
	return { recipes: (data ?? []) as RecipeSummary[], error: error?.message ?? null };
}

export async function fetchRecipes(limit = 100): Promise<RecipeSummary[]> {
	return (await fetchRecipesWithError(limit)).recipes;
}

/// A single recipe with its ingredients ordered by `position`. Returns null
/// when the id doesn't resolve (RLS hides others').
export async function fetchRecipeDetail(id: string): Promise<RecipeDetail | null> {
	const { data: recipe, error: rErr } = await supabase
		.from(TABLES.recipes)
		.select('id, user_id, name, servings, meal_slot, ingredient_count, last_modified_at, created_at')
		.eq('id', id)
		.maybeSingle();
	if (rErr || !recipe) return null;
	const { data: ingredientRows, error: iErr } = await supabase
		.from(TABLES.recipe_ingredients)
		.select('position, item_name, quantity, calories, protein_g, carbs_g, fat_g, external_id')
		.eq('recipe_id', id)
		.order('position', { ascending: true });
	if (iErr) console.error('fetchRecipeDetail ingredients failed', iErr);
	return {
		recipe: recipe as RecipeSummary,
		ingredients: (ingredientRows ?? []) as RecipeIngredientRow[],
	};
}

/// Insert a recipe + its ingredients. Blank-named ingredients are dropped.
/// ingredient_count is stamped client-side from the surviving list
/// (non-authoritative cache). Two round-trips, mirroring `createMealTemplate`.
export async function createRecipe(input: RecipeInput): Promise<RecipeSummary> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const ingredients = input.ingredients.filter((it) => it.item_name.trim().length > 0);
	const nowIso = new Date().toISOString();
	const { data, error } = await supabase
		.from(TABLES.recipes)
		.insert({
			user_id: userId,
			name: input.name.trim(),
			servings: input.servings && input.servings >= 1 ? input.servings : 1,
			meal_slot: input.meal_slot ?? null,
			ingredient_count: ingredients.length,
			last_modified_at: nowIso,
		})
		.select('id, user_id, name, servings, meal_slot, ingredient_count, last_modified_at, created_at')
		.single();
	if (error || !data) throw error ?? new Error('createRecipe failed');
	const recipe = data as RecipeSummary;
	if (ingredients.length === 0) return recipe;
	const ingredientRows = ingredients.map((it, i) => ({
		recipe_id: recipe.id,
		position: i,
		item_name: it.item_name.trim(),
		quantity: it.quantity && it.quantity >= 0 ? it.quantity : 1,
		calories: it.calories ?? null,
		protein_g: it.protein_g ?? null,
		carbs_g: it.carbs_g ?? null,
		fat_g: it.fat_g ?? null,
		external_id: it.external_id ?? null,
	}));
	const { error: iErr } = await supabase.from(TABLES.recipe_ingredients).insert(ingredientRows);
	if (iErr) throw iErr;
	return recipe;
}

/// Delete a recipe; its ingredients cascade via FK (migration 20270221_001).
/// Logged food_log entries are untouched — the recipe is a parallel plan,
/// never linked to the meals it spawned.
export async function deleteRecipe(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.recipes).delete().eq('id', id);
	if (error) throw error;
}

/// Log ONE serving of a recipe as a SINGLE food_log entry at `startedAt`
/// (default now): the recipe's name + its per-serving summed macros. Returns
/// the number of entries logged (1, or 0 for an empty recipe). The summing +
/// slot resolution is the pure `logInputFromRecipe` parity helper so the
/// per-serving macros can't drift from the mobile twin.
export async function logRecipe(
	detail: RecipeDetail,
	opts: { startedAt?: string; slotOverride?: MealSlot | null } = {},
): Promise<number> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const input = logInputFromRecipe(
		{
			name: detail.recipe.name,
			servings: detail.recipe.servings,
			mealSlot: detail.recipe.meal_slot,
			ingredients: detail.ingredients.map((it) => ({
				position: it.position,
				itemName: it.item_name,
				quantity: it.quantity,
				calories: it.calories,
				proteinG: it.protein_g,
				carbsG: it.carbs_g,
				fatG: it.fat_g,
				externalId: it.external_id,
			})),
		},
		opts.slotOverride ?? null,
	);
	if (!input) return 0;
	const startedAt = opts.startedAt ?? new Date().toISOString();
	const nowIso = new Date().toISOString();
	const { error } = await supabase.from(TABLES.food_log).insert({
		user_id: userId,
		item_name: input.itemName,
		meal_slot: input.mealSlot,
		calories: input.calories,
		protein_g: input.proteinG,
		carbs_g: input.carbsG,
		fat_g: input.fatG,
		started_at: startedAt,
		external_id: input.externalId,
		last_modified_at: nowIso,
	});
	if (error) throw error;
	return 1;
}

/// The user's most recent recorded weight, or null if none. Owner-only
/// (body_metrics has no public-read policy — special-category health data,
/// migration 20261216_001).
export async function fetchLatestWeightKg(): Promise<number | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data, error } = await supabase
		.from(TABLES.body_metrics)
		.select('weight_kg')
		.eq('user_id', userId)
		.order('recorded_at', { ascending: false })
		.limit(1)
		.maybeSingle();
	if (error) {
		console.error('fetchLatestWeightKg failed', error);
		return null;
	}
	return data ? ((data as { weight_kg: number }).weight_kg ?? null) : null;
}

/// Append a weight measurement to the time-series (one row per recording —
/// the series is the history). Caller gates on health-data consent.
export async function recordWeightKg(weightKg: number): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('not signed in');
	const { error } = await supabase
		.from(TABLES.body_metrics)
		.insert({ user_id: userId, weight_kg: weightKg });
	if (error) throw error;
}

/// Erase the whole weight history. Called when the user withdraws
/// health-data consent (GDPR Art 7(3)) so the special-category series is
/// cleared alongside height/gender/DOB.
export async function clearWeightHistory(): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) return;
	const { error } = await supabase.from(TABLES.body_metrics).delete().eq('user_id', userId);
	if (error) throw error;
}

// --- Unified activities timeline (Phase 4 multi-modal History) ---

/// One row of the `activities` UNION view (runs + gym_workouts + food_log)
/// projecting (id, user_id, kind, started_at, summary). `summary` is a thin
/// per-kind jsonb the History list renders without a second fetch; the
/// detail routes load the full underlying row. Migration 20261204_001.
export interface ActivityRow {
	id: string;
	kind: 'run' | 'lift' | 'meal';
	started_at: string;
	summary: Record<string, unknown>;
}

/// Windowed, reverse-chronological feed across all logged modalities for
/// the History timeline. RLS (security_invoker on the view) scopes it to
/// the caller. Always bounded — the timeline paginates like /runs rather
/// than pulling an unbounded history (multi_modal.md § "activities view
/// at scale").
export async function fetchActivities(limit = 100): Promise<ActivityRow[]> {
	return (await fetchActivitiesWithError(limit)).activities;
}

/// Same window as `fetchActivities` but surfaces a hard fetch failure
/// instead of swallowing it into an empty feed. A network / DB error and a
/// genuinely-empty history both used to collapse to `[]`, so a transient
/// failure rendered as the "nothing logged yet" empty state on /history with
/// no retry. This sibling distinguishes the two: `error` is non-null only on
/// a real failure. Mirrors the `fetchFoodLogWithError` convention. A
/// signed-out caller is empty, not an error.
export async function fetchActivitiesWithError(
	limit = 100,
): Promise<{ activities: ActivityRow[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { activities: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.activities)
		.select('id, kind, started_at, summary')
		.eq('user_id', userId)
		.order('started_at', { ascending: false })
		.limit(limit);
	if (error) return { activities: [], error: error.message };
	const activities = ((data ?? []) as unknown[])
		.map((row) => {
			const r = row as {
				id: string | null;
				kind: string | null;
				started_at: string | null;
				summary: Record<string, unknown> | null;
			};
			return {
				id: r.id ?? '',
				kind: (r.kind ?? 'run') as ActivityRow['kind'],
				started_at: r.started_at ?? '',
				summary: r.summary ?? {},
			};
		})
		.filter((r) => r.id !== '' && r.started_at !== '');
	return { activities, error: null };
}

// ───────────────────────── Session plans (session_planner.md P1) ─────────────
// A reusable yoga/pilates session-content template: a plan head + optional
// blocks + ordered items. P1 is build/save/reuse + read; no execution. RLS
// owns authority (author / public / club). The editor supplies the full
// blocks+items shape; createSessionPlan / updateSessionPlan persist the head
// and replace the child rows (no diff — a plan is small and edited rarely, so a
// delete-all + re-insert is simpler and correct than a per-row reconcile).

export interface SessionPlanItemInput {
	movement_name: string;
	kind: SessionItemKind;
	duration_s: number | null;
	reps: number | null;
	per_side: boolean;
	tempo: string | null;
	cue: string | null;
	/// index into the editor's blocks array, or null for a flat (blockless) item.
	block_index: number | null;
}

export interface SessionPlanInput {
	title: string;
	discipline: string | null;
	equipment: string | null;
	is_public: boolean;
	club_id: string | null;
	est_duration_min: number | null;
	blocks: { name: string | null }[];
	items: SessionPlanItemInput[];
}

/** The user's own plans + any plan owned by a club they belong to. List view. */
export async function fetchSessionPlans(): Promise<SessionPlan[]> {
	const userId = auth.user?.id;
	if (!userId) return [];

	// Scope the read to the rows the list actually shows — the user's own
	// plans plus plans owned by a club they belong to. A bare select('*')
	// leaned entirely on the RLS policies to filter, forcing Postgres to
	// seq-scan every session_plan in the table and run the per-row
	// is_club_member() subquery on each. Filtering explicitly lets the
	// (author_id, updated_at) and (club_id, updated_at) indexes serve it
	// (BitmapOr), and also matches the documented intent — a stranger's
	// public plan should not appear in "my session plans".
	const { data: memberships } = await supabase
		.from(TABLES.club_members)
		.select('club_id')
		.eq('user_id', userId);
	const clubIds = (memberships ?? []).map((m: { club_id: string }) => m.club_id);

	let query = supabase.from('session_plans').select('*');
	query = clubIds.length
		? query.or(`author_id.eq.${userId},club_id.in.(${clubIds.join(',')})`)
		: query.eq('author_id', userId);
	const { data, error } = await query.order('updated_at', { ascending: false });
	if (error) throw error;
	return (data ?? []) as SessionPlan[];
}

/** A single plan with its blocks + items (read view + editor hydrate). */
export async function fetchSessionPlan(id: string): Promise<SessionPlanWithItems | null> {
	const { data: plan, error } = await supabase
		.from('session_plans')
		.select('*')
		.eq('id', id)
		.maybeSingle();
	if (error) throw error;
	if (!plan) return null;

	const [{ data: blocks }, { data: items }] = await Promise.all([
		supabase.from('session_plan_blocks').select('*').eq('plan_id', id).order('position'),
		supabase.from('session_plan_items').select('*').eq('plan_id', id).order('position')
	]);
	return {
		...(plan as SessionPlan),
		blocks: (blocks ?? []) as SessionPlanBlock[],
		items: ((items ?? []) as SessionPlanItem[])
	};
}

async function replaceSessionPlanChildren(planId: string, input: SessionPlanInput): Promise<void> {
	// Children cascade on plan delete; here we clear + re-insert to apply edits.
	await supabase.from('session_plan_items').delete().eq('plan_id', planId);
	await supabase.from('session_plan_blocks').delete().eq('plan_id', planId);

	const blockIds: string[] = [];
	if (input.blocks.length > 0) {
		const { data, error } = await supabase
			.from('session_plan_blocks')
			.insert(
				input.blocks.map((b, i) => ({
					plan_id: planId,
					position: i,
					name: b.name?.trim() || null
				}))
			)
			.select('id');
		if (error) throw error;
		// insert preserves input order, but sort defensively by nothing — map by index.
		for (const row of (data ?? []) as { id: string }[]) blockIds.push(row.id);
	}

	if (input.items.length > 0) {
		const { error } = await supabase.from('session_plan_items').insert(
			input.items.map((it, i) => ({
				plan_id: planId,
				block_id:
					it.block_index !== null && it.block_index < blockIds.length
						? blockIds[it.block_index]
						: null,
				position: i,
				movement_name: it.movement_name.trim(),
				kind: it.kind,
				duration_s: it.duration_s,
				reps: it.reps,
				per_side: it.per_side,
				tempo: it.tempo?.trim() || null,
				cue: it.cue?.trim() || null
			}))
		);
		if (error) throw error;
	}
}

export async function createSessionPlan(input: SessionPlanInput): Promise<string> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('session_plans')
		.insert({
			author_id: userId,
			club_id: input.club_id,
			title: input.title.trim(),
			discipline: input.discipline?.trim() || null,
			equipment: input.equipment?.trim() || null,
			est_duration_min: input.est_duration_min,
			is_public: input.is_public
		})
		.select('id')
		.single();
	if (error) throw error;
	const planId = (data as { id: string }).id;
	await replaceSessionPlanChildren(planId, input);
	return planId;
}

export async function updateSessionPlan(id: string, input: SessionPlanInput): Promise<void> {
	const { error } = await supabase
		.from('session_plans')
		.update({
			title: input.title.trim(),
			discipline: input.discipline?.trim() || null,
			equipment: input.equipment?.trim() || null,
			est_duration_min: input.est_duration_min,
			is_public: input.is_public,
			club_id: input.club_id,
			updated_at: new Date().toISOString()
		})
		.eq('id', id);
	if (error) throw error;
	await replaceSessionPlanChildren(id, input);
}

export async function deleteSessionPlan(id: string): Promise<void> {
	const { error } = await supabase.from('session_plans').delete().eq('id', id);
	if (error) throw error;
}

/** Flip a session plan's public visibility (owner-only via RLS). A public plan
 *  is readable logged-out at /share/session/[id]. */
export async function setSessionPlanPublic(id: string, isPublic: boolean): Promise<void> {
	const { error } = await supabase
		.from('session_plans')
		.update({ is_public: isPublic, updated_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw error;
}

/** Distinct movement names the user has used across their own session plans,
 *  most-used first, for the editor's movement-name autocomplete (mirrors
 *  fetchGymExerciseNames). RLS on session_plan_items scopes the read to the
 *  owner; a session plan carries dozens of items, not thousands, so a direct
 *  distinct over the author's own plans is cheap — no RPC needed. Case is
 *  preserved (trim only), matching the gym datalist behaviour. */
export async function fetchSessionMovementNames(): Promise<string[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data, error } = await supabase
		.from('session_plan_items')
		.select('movement_name, session_plans!inner(author_id)')
		.eq('session_plans.author_id', userId);
	if (error) {
		console.error('fetchSessionMovementNames failed', error);
		return [];
	}
	const counts = new Map<string, number>();
	for (const row of (data ?? []) as Array<{ movement_name: string | null }>) {
		const name = (row.movement_name ?? '').trim();
		if (name === '') continue;
		counts.set(name, (counts.get(name) ?? 0) + 1);
	}
	return [...counts.entries()]
		.sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
		.map(([name]) => name);
}

/** Attach (or detach with null) a session plan to a class event. Organiser-only
 *  at the DB layer (the events_session_plan_organiser trigger). */
export async function setEventSessionPlan(
	eventId: string,
	sessionPlanId: string | null
): Promise<void> {
	const { error } = await supabase
		.from('events')
		.update({ session_plan_id: sessionPlanId })
		.eq('id', eventId);
	if (error) throw error;
}

// ─── Admin moderation (web-only back-office; /admin/reports) ─────────
// Authorization is DB-enforced: every RPC below hard-denies a non-admin
// at the database (42501). am_i_admin only picks page chrome.

export interface PendingReportTarget {
	target_kind: ReportTargetKind;
	target_id: string;
	report_count: number;
	reporter_count: number;
	reasons: Record<string, number>;
	latest_at: string;
	shadow_hidden: boolean;
}

export interface TargetReport {
	id: string;
	reporter_id: string;
	reason: string;
	notes: string | null;
	status: string;
	created_at: string;
	reviewed_at: string | null;
	reviewed_by: string | null;
	resolution: string | null;
}

/** Whether the current user is a moderator. Chrome gate only — the RPCs
 *  below are the real boundary. */
export async function amIAdmin(): Promise<boolean> {
	const { data, error } = await supabase.rpc('am_i_admin');
	if (error) return false;
	return data === true;
}

/** The moderation queue: one row per reported target with pending reports. */
export async function fetchPendingReports(): Promise<PendingReportTarget[]> {
	const { data, error } = await supabase.rpc('fetch_pending_reports');
	if (error) throw error;
	return ((data ?? []) as Record<string, unknown>[]).map((r) => ({
		target_kind: r.target_kind as ReportTargetKind,
		target_id: r.target_id as string,
		report_count: Number(r.report_count ?? 0),
		reporter_count: Number(r.reporter_count ?? 0),
		reasons: (r.reasons ?? {}) as Record<string, number>,
		latest_at: r.latest_at as string,
		shadow_hidden: r.shadow_hidden === true,
	}));
}

/** Every individual report against one target (any status), newest first. */
export async function fetchReportsForTarget(
	targetKind: ReportTargetKind,
	targetId: string
): Promise<TargetReport[]> {
	const { data, error } = await supabase.rpc('fetch_reports_for_target', {
		p_target_kind: targetKind,
		p_target_id: targetId,
	});
	if (error) throw error;
	return ((data ?? []) as Record<string, unknown>[]).map((r) => ({
		id: r.id as string,
		reporter_id: r.reporter_id as string,
		reason: r.reason as string,
		notes: (r.notes ?? null) as string | null,
		status: r.status as string,
		created_at: r.created_at as string,
		reviewed_at: (r.reviewed_at ?? null) as string | null,
		reviewed_by: (r.reviewed_by ?? null) as string | null,
		resolution: (r.resolution ?? null) as string | null,
	}));
}

/** Mark all pending reports on a target reviewed/dismissed with a note.
 *  Returns the number of reports resolved. */
export async function resolveTargetReports(
	targetKind: ReportTargetKind,
	targetId: string,
	status: 'reviewed' | 'dismissed',
	resolution: string | null
): Promise<number> {
	const { data, error } = await supabase.rpc('resolve_target_reports', {
		p_target_kind: targetKind,
		p_target_id: targetId,
		p_status: status,
		p_resolution: resolution,
	});
	if (error) throw error;
	return Number(data ?? 0);
}

/** Revert an auto-hide: clear shadow_hidden on a user/club/route.
 *  Returns true if a row was actually un-hidden. Admin-gated at the DB. */
export async function adminUnhideTarget(
	targetKind: ReportTargetKind,
	targetId: string
): Promise<boolean> {
	const { data, error } = await supabase.rpc('admin_unhide_target', {
		p_target_kind: targetKind,
		p_target_id: targetId,
	});
	if (error) throw error;
	return data === true;
}

/** Club-owned session plans (the club's "session templates"). Visible to club
 *  members + writable by admins via RLS — mirrors fetchClubTemplates for
 *  training plans. */
export async function fetchClubSessionTemplates(clubId: string): Promise<SessionPlan[]> {
	const { data, error } = await supabase
		.from('session_plans')
		.select('*')
		.eq('club_id', clubId)
		.order('updated_at', { ascending: false });
	if (error) {
		console.error('fetchClubSessionTemplates failed', error);
		return [];
	}
	return (data ?? []) as SessionPlan[];
}

/** Publish a personal session plan into a club-owned copy (the original is left
 *  untouched on the user's /sessions list), mirroring publishPlanAsTemplate.
 *  Copies the head + blocks + items into a new club_id row; the publisher must
 *  own the source. Returns the new club-owned plan's id. */
export async function publishSessionAsTemplate(
	sourcePlanId: string,
	clubId: string
): Promise<string> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const source = await fetchSessionPlan(sourcePlanId);
	if (!source) throw new Error('Source session plan not found');
	if (source.author_id !== userId) throw new Error('Only the plan owner can publish');

	const input: SessionPlanInput = {
		title: source.title,
		discipline: source.discipline,
		equipment: source.equipment,
		is_public: false,
		club_id: clubId,
		est_duration_min: source.est_duration_min,
		blocks: [...source.blocks]
			.sort((a, b) => a.position - b.position)
			.map((b) => ({ name: b.name })),
		items: (() => {
			const orderedBlocks = [...source.blocks].sort((a, b) => a.position - b.position);
			const blockIndexById = new Map(orderedBlocks.map((b, i) => [b.id, i]));
			return [...source.items]
				.sort((a, b) => a.position - b.position)
				.map((it) => ({
					movement_name: it.movement_name,
					kind: it.kind,
					duration_s: it.duration_s,
					reps: it.reps,
					per_side: it.per_side,
					tempo: it.tempo,
					cue: it.cue,
					block_index: it.block_id == null ? null : (blockIndexById.get(it.block_id) ?? null)
				}));
		})()
	};
	return createSessionPlan(input);
}

/** Clone a club session template into a new personal session plan (the
 *  clone_session_template RPC enforces author/member authorisation +
 *  rate-limits server-side). Returns the new plan's id. */
export async function cloneSessionTemplate(templateId: string): Promise<string> {
	const { data, error } = await supabase.rpc('clone_session_template', {
		template_id: templateId
	});
	if (error) throw error;
	return data as string;
}

/** Club-owned gym routines published as templates (gym_routines.club_id set).
 *  RLS exposes these to club members via private.is_club_member. */
export async function fetchClubGymRoutineTemplates(clubId: string): Promise<GymRoutineSummary[]> {
	const { data, error } = await supabase
		.from(TABLES.gym_routines)
		.select('id, author_id, club_id, is_public_template, title, notes, exercise_count, last_modified_at, created_at')
		.eq('club_id', clubId)
		.order('last_modified_at', { ascending: false });
	if (error) {
		console.error('fetchClubGymRoutineTemplates failed', error);
		return [];
	}
	return (data ?? []) as GymRoutineSummary[];
}

/** Publish a personal gym routine into a club-owned template. The
 *  publish_gym_routine_as_template RPC is author + club-admin gated and
 *  deep-copies the routine + exercises + sets server-side (the personal
 *  original is left untouched). Returns the new club-owned routine id. */
export async function publishGymRoutineAsTemplate(routineId: string, clubId: string): Promise<string> {
	const { data, error } = await supabase.rpc('publish_gym_routine_as_template', {
		p_routine_id: routineId,
		p_club_id: clubId
	});
	if (error) throw error;
	return data as string;
}

/** Adopt a club gym-routine template into a new personal routine via the
 *  clone_gym_routine_template RPC (author-or-member gated, rate-limited
 *  server-side). Returns the new personal routine's id. */
export async function cloneGymRoutineTemplate(templateId: string): Promise<string> {
	const { data, error } = await supabase.rpc('clone_gym_routine_template', {
		p_template_id: templateId
	});
	if (error) throw error;
	return data as string;
}

export type PublicGymRoutineEntry = GymRoutineSummary & {
	author_handle: string | null;
};

/// Browse the public gym-routine library — routines published as public
/// templates that any signed-in user can adopt (migration 20270224_001).
/// Optional case-insensitive title search. Each entry carries the author's
/// public display name (handle) joined from user_profiles; no other author
/// data is exposed. Mirrors fetchPublicPlanLibrary + the mobile
/// `ApiClient.fetchPublicGymRoutineLibrary`.
export async function fetchPublicGymRoutineLibrary(
	query = '',
	limit = 100
): Promise<{ routines: PublicGymRoutineEntry[]; error: string | null }> {
	let q = supabase
		.from(TABLES.gym_routines)
		.select('id, author_id, club_id, is_public_template, title, notes, exercise_count, last_modified_at, created_at')
		.eq('is_public_template', true)
		.order('last_modified_at', { ascending: false })
		.limit(limit);
	const trimmed = query.trim();
	if (trimmed) q = q.ilike('title', `%${trimmed}%`);
	const { data, error } = await q;
	if (error) return { routines: [], error: error.message };
	const rows = (data ?? []) as GymRoutineSummary[];
	const authorIds = [...new Set(rows.map((r) => r.author_id))];
	const byId = new Map<string, string | null>();
	if (authorIds.length > 0) {
		const { data: profiles } = await supabase
			.from('user_profiles')
			.select('id, display_name')
			.in('id', authorIds);
		for (const p of profiles ?? []) byId.set(p.id, p.display_name);
	}
	return {
		routines: rows.map((r) => ({ ...r, author_handle: byId.get(r.author_id) ?? null })),
		error: null,
	};
}

/** Publish (or unpublish) a personal gym routine to/from the public library.
 *  The set_gym_routine_public RPC is author-gated + refuses a club-owned
 *  routine server-side; publishing flips is_public_template on the routine
 *  itself (the routine IS the template — no deep-copy, unlike the plan
 *  library). Mirrors the mobile `ApiClient.setGymRoutinePublic`. */
export async function setGymRoutinePublic(routineId: string, isPublic: boolean): Promise<void> {
	const { error } = await supabase.rpc('set_gym_routine_public', {
		p_routine_id: routineId,
		p_public: isPublic
	});
	if (error) throw error;
}

// ──────────────────── Race-director checkpoints (P1–P4) ────────────────────
//
// Aid-station checkpoint check-in → live results + cutoff board. The schema
// (event_checkpoints + checkpoint_crossings) lives in migration 20270201_001;
// see docs/features/race_director_ops.md. Crossings are written ONLY via the
// upsert_checkpoint_crossing RPC (server-side merge of two volunteers' stamps),
// never a direct table write. Health columns are column-locked from the public
// read and only reachable through fetch_checkpoint_crossings_for_organiser.

export interface EventCheckpoint {
	id: string;
	event_id: string;
	name: string;
	ordinal: number;
	route_marker_id: string | null;
	position_m: number | null;
	cutoff_elapsed_s: number | null;
	cutoff_clock: string | null;
	requires_weigh_in: boolean;
	created_by: string;
	created_at: string;
	updated_at: string;
}

/** Non-health subset of a crossing — what the column-locked public read returns
 *  and what the board renders for everyone. Health fields live only on
 *  OrganiserCrossing. */
export interface PublicCrossing {
	id: string;
	event_id: string;
	checkpoint_id: string;
	instance_start: string;
	user_id: string | null;
	bib: string | null;
	runner_name: string | null;
	in_time: string | null;
	out_time: string | null;
	recorded_at: string;
	updated_at: string;
}

/** Full crossing incl. Art 9 health columns — only ever returned by the
 *  organiser RPC (42501 to anyone who isn't an event organiser). */
export interface OrganiserCrossing extends PublicCrossing {
	body_weight_kg: number | null;
	body_weight_pct: number | null;
	medical_hold: boolean;
	medical_note: string | null;
	recorded_by: string | null;
}

export async function fetchEventCheckpoints(eventId: string): Promise<EventCheckpoint[]> {
	const { data, error } = await supabase
		.from(TABLES.event_checkpoints)
		.select(
			'id, event_id, name, ordinal, route_marker_id, position_m, cutoff_elapsed_s, cutoff_clock, requires_weigh_in, created_by, created_at, updated_at'
		)
		.eq('event_id', eventId)
		.order('ordinal', { ascending: true });
	if (error) throw error;
	return (data ?? []) as EventCheckpoint[];
}

export async function createEventCheckpoint(params: {
	eventId: string;
	name: string;
	ordinal: number;
	routeMarkerId?: string | null;
	positionM?: number | null;
	cutoffElapsedS?: number | null;
	cutoffClock?: string | null;
	requiresWeighIn?: boolean;
}): Promise<EventCheckpoint> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const name = params.name.trim();
	if (!name) throw new Error('Checkpoint name is required');
	const { data, error } = await supabase
		.from(TABLES.event_checkpoints)
		.insert({
			event_id: params.eventId,
			name,
			ordinal: params.ordinal,
			route_marker_id: params.routeMarkerId ?? null,
			position_m: params.positionM ?? null,
			cutoff_elapsed_s: params.cutoffElapsedS ?? null,
			cutoff_clock: params.cutoffClock ?? null,
			requires_weigh_in: params.requiresWeighIn ?? false,
			created_by: userId
		})
		.select(
			'id, event_id, name, ordinal, route_marker_id, position_m, cutoff_elapsed_s, cutoff_clock, requires_weigh_in, created_by, created_at, updated_at'
		)
		.single();
	if (error) throw error;
	return data as EventCheckpoint;
}

export async function updateEventCheckpoint(
	id: string,
	patch: Partial<{
		name: string;
		ordinal: number;
		routeMarkerId: string | null;
		positionM: number | null;
		cutoffElapsedS: number | null;
		cutoffClock: string | null;
		requiresWeighIn: boolean;
	}>
): Promise<void> {
	const row: Record<string, unknown> = { updated_at: new Date().toISOString() };
	if (patch.name !== undefined) row.name = patch.name.trim();
	if (patch.ordinal !== undefined) row.ordinal = patch.ordinal;
	if (patch.routeMarkerId !== undefined) row.route_marker_id = patch.routeMarkerId;
	if (patch.positionM !== undefined) row.position_m = patch.positionM;
	if (patch.cutoffElapsedS !== undefined) row.cutoff_elapsed_s = patch.cutoffElapsedS;
	if (patch.cutoffClock !== undefined) row.cutoff_clock = patch.cutoffClock;
	if (patch.requiresWeighIn !== undefined) row.requires_weigh_in = patch.requiresWeighIn;
	const { error } = await supabase.from(TABLES.event_checkpoints).update(row).eq('id', id);
	if (error) throw error;
}

export async function deleteEventCheckpoint(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.event_checkpoints).delete().eq('id', id);
	if (error) throw error;
}

/** Single writer for crossings — calls the upsert_checkpoint_crossing RPC,
 *  which authorises the caller as an organiser, merges two stamps (earliest
 *  in / latest out), and persists health fields only when the checkpoint
 *  requires_weigh_in AND p_health_consent=true. Pass health fields + consent
 *  only from the gated weigh-in UI. */
export async function upsertCheckpointCrossing(params: {
	eventId: string;
	checkpointId: string;
	instanceStart: string;
	userId?: string | null;
	bib?: string | null;
	runnerName?: string | null;
	inTime?: string | null;
	outTime?: string | null;
	healthConsent?: boolean;
	bodyWeightKg?: number | null;
	bodyWeightPct?: number | null;
	medicalHold?: boolean | null;
	medicalNote?: string | null;
}): Promise<OrganiserCrossing> {
	const { data, error } = await supabase.rpc('upsert_checkpoint_crossing', {
		p_event_id: params.eventId,
		p_checkpoint_id: params.checkpointId,
		p_instance_start: params.instanceStart,
		p_user_id: params.userId ?? null,
		p_bib: params.bib ?? null,
		p_runner_name: params.runnerName ?? null,
		p_in_time: params.inTime ?? null,
		p_out_time: params.outTime ?? null,
		p_health_consent: params.healthConsent ?? false,
		p_body_weight_kg: params.bodyWeightKg ?? null,
		p_body_weight_pct: params.bodyWeightPct ?? null,
		p_medical_hold: params.medicalHold ?? null,
		p_medical_note: params.medicalNote ?? null
	});
	if (error) throw error;
	return data as OrganiserCrossing;
}

/** Organiser board read — every crossing incl. health columns. 42501 if the
 *  caller isn't an event organiser. */
export async function fetchOrganiserCrossings(
	eventId: string,
	instanceStart: string
): Promise<OrganiserCrossing[]> {
	const { data, error } = await supabase.rpc('fetch_checkpoint_crossings_for_organiser', {
		p_event_id: eventId,
		p_instance_start: instanceStart
	});
	if (error) throw error;
	return (data ?? []) as OrganiserCrossing[];
}

/** Public results read — the column-locked non-health crossing columns, gated
 *  by event-visibility RLS. Used by the account-optional public results page. */
export async function fetchPublicCrossings(
	eventId: string,
	instanceStart: string
): Promise<PublicCrossing[]> {
	const { data, error } = await supabase
		.from(TABLES.checkpoint_crossings)
		.select(
			'id, event_id, checkpoint_id, instance_start, user_id, bib, runner_name, in_time, out_time, recorded_at, updated_at'
		)
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.order('checkpoint_id', { ascending: true })
		.order('in_time', { ascending: true });
	if (error) throw error;
	return (data ?? []) as PublicCrossing[];
}

/** Record an organiser DNF for a runner on the live board. Crossings carry no
 *  DNF flag (DNF derives from a blown cutoff in the projection), so an explicit
 *  organiser DNF is written through the account-optional event_results rail the
 *  public results + leaderboard already read. Supports both identities: an
 *  account row (user_id) upserts on (event,instance,user_id); a bib row upserts
 *  on (event,instance,bib). RLS gates the write to the event's organiser. */
export async function markCheckpointDnf(params: {
	eventId: string;
	instanceStart: string;
	userId?: string | null;
	bib?: string | null;
	runnerName?: string | null;
}): Promise<void> {
	if (!params.userId && !params.bib) throw new Error('DNF needs a user_id or a bib');
	const base = {
		event_id: params.eventId,
		instance_start: params.instanceStart,
		duration_s: 0,
		distance_m: 0,
		finisher_status: 'dnf' as const,
		updated_at: new Date().toISOString()
	};
	const { error } = params.userId
		? await supabase
				.from(TABLES.event_results)
				.upsert({ ...base, user_id: params.userId }, { onConflict: 'event_id,instance_start,user_id' })
		: await supabase.from(TABLES.event_results).upsert(
				{ ...base, bib: params.bib, finisher_name: params.runnerName ?? params.bib },
				{ onConflict: 'event_id,instance_start,bib' }
			);
	if (error) throw error;
}

// --- Achievements / badges ---
// Reads go through RLS: the owner sees all of their rows, a non-owner sees only
// is_public = true (the achievements_public_select policy). Awards are written
// only by the SECURITY DEFINER award function — no client insert/delete path.

/** A profile's public badges (or all badges, if you are the owner — RLS-gated). */
export async function fetchUserBadges(userId: string): Promise<Achievement[]> {
	const { data, error } = await supabase
		.from(TABLES.achievements)
		.select('*')
		.eq('user_id', userId)
		.order('earned_at', { ascending: false });
	if (error) throw error;
	return (data ?? []) as Achievement[];
}

/** The signed-in user's own badges (incl. private). Empty when signed out. */
export async function fetchMyBadges(): Promise<Achievement[]> {
	const { data: authUser } = await supabase.auth.getUser();
	const uid = authUser.user?.id;
	if (!uid) return [];
	return fetchUserBadges(uid);
}

/** Flip a badge's public visibility. Owner-only (enforced by RLS). */
export async function setBadgeVisibility(id: string, isPublic: boolean): Promise<void> {
	const { error } = await supabase
		.from(TABLES.achievements)
		.update({ is_public: isPublic })
		.eq('id', id);
	if (error) throw error;
}

/** Public read for the share page — returns null for a private / missing id. */
export async function fetchBadgeForShare(
	id: string
): Promise<{ badge: Achievement; ownerName: string | null } | null> {
	const { data, error } = await supabase
		.from(TABLES.achievements)
		.select('*')
		.eq('id', id)
		.eq('is_public', true)
		.maybeSingle();
	if (error || !data) return null;
	const badge = data as Achievement;
	const { data: profile } = await supabase
		.from('user_profiles')
		.select('display_name')
		.eq('id', badge.user_id)
		.maybeSingle();
	return { badge, ownerName: profile?.display_name ?? null };
}

export interface BadgeAwardFeedEntry {
	badge: Achievement;
	authorId: string;
	authorName: string | null;
	authorAvatarUrl: string | null;
}

/**
 * Public badge awards from people the viewer follows, cursor-paged over
 * (earned_at, id) like the run feed. Public rows only (RLS), newest first.
 */
export async function fetchFollowingBadgeAwards(opts?: {
	limit?: number;
	cursor?: { earned_at: string; id: string } | null;
}): Promise<BadgeAwardFeedEntry[]> {
	const limit = opts?.limit ?? 20;
	const authors = await resolveFollowedAuthorIds(null);
	if (authors.length === 0) return [];

	let q = supabase
		.from(TABLES.achievements)
		.select('*')
		.in('user_id', authors)
		.eq('is_public', true)
		.order('earned_at', { ascending: false })
		.order('id', { ascending: false })
		.limit(limit);
	if (opts?.cursor) {
		q = q.or(
			`earned_at.lt.${opts.cursor.earned_at},and(earned_at.eq.${opts.cursor.earned_at},id.lt.${opts.cursor.id})`
		);
	}
	const { data, error } = await q;
	if (error) throw error;
	const rows = (data ?? []) as Achievement[];
	if (rows.length === 0) return [];

	const ids = [...new Set(rows.map((r) => r.user_id))];
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', ids);
	const byId = new Map((profiles ?? []).map((p) => [p.id, p]));
	return rows.map((badge) => {
		const p = byId.get(badge.user_id);
		return {
			badge,
			authorId: badge.user_id,
			authorName: p?.display_name ?? null,
			authorAvatarUrl: p?.avatar_url ?? null
		};
	});
}

// ─────────────────────── Challenges & competitions ───────────────────────

function challengeFromRow(row: {
	metric: string;
	scope: string;
	activity_type: string | null;
	[k: string]: unknown;
}): Challenge {
	return {
		...row,
		metric: row.metric as ChallengeMetric,
		scope: row.scope as ChallengeScope,
		activity_type: row.activity_type as ActivityType | null
	} as Challenge;
}

export async function fetchChallenges(
	opts: { mine?: boolean } = {}
): Promise<ChallengeWithMeta[]> {
	const userId = auth.user?.id;
	// RLS already scopes visibility (public + creator + participant + club
	// member). The `mine` filter narrows to challenges the caller has joined.
	let query = supabase
		.from(TABLES.challenges)
		.select('*')
		.order('ends_at', { ascending: true });
	const { data, error } = await query;
	if (error) throw error;
	const rows = (data ?? []).map(challengeFromRow);

	// Enrich with participant counts + the caller's joined flag in two scoped
	// reads (no per-row N+1): one count-grouped read over participants for the
	// listed ids, one self-membership read.
	const ids = rows.map((r) => r.id);
	if (ids.length === 0) return [];
	const { data: parts } = await supabase
		.from(TABLES.challenge_participants)
		.select('challenge_id, user_id')
		.in('challenge_id', ids);
	const counts = new Map<string, number>();
	const mineSet = new Set<string>();
	for (const p of parts ?? []) {
		counts.set(p.challenge_id, (counts.get(p.challenge_id) ?? 0) + 1);
		if (userId && p.user_id === userId) mineSet.add(p.challenge_id);
	}
	const enriched: ChallengeWithMeta[] = rows.map((r) => ({
		...r,
		participant_count: counts.get(r.id) ?? 0,
		my_value: null,
		my_rank: null,
		joined: mineSet.has(r.id),
		completed_at: null
	}));
	return opts.mine ? enriched.filter((c) => c.joined) : enriched;
}

/**
 * Ranked, paginated, searchable Browse feed of public challenges the caller has
 * NOT joined. Server-side `browse_public_challenges` orders by popularity
 * (size + recent join velocity), suppresses dead boards, and excludes joined /
 * ended ones — so this never pulls the whole table to sort client-side.
 */
export async function browsePublicChallenges(
	opts: { search?: string | null; limit?: number; offset?: number } = {}
): Promise<ChallengeWithMeta[]> {
	const { data, error } = await supabase.rpc('browse_public_challenges', {
		p_search: opts.search?.trim() || null,
		p_limit: opts.limit ?? 24,
		p_offset: opts.offset ?? 0
	});
	if (error) throw error;
	type BrowseRow = {
		metric: string;
		scope: string;
		activity_type: string | null;
		participant_count: number;
		[k: string]: unknown;
	};
	return ((data ?? []) as BrowseRow[]).map((r) => ({
		...challengeFromRow(r),
		participant_count: r.participant_count ?? 0,
		my_value: null,
		my_rank: null,
		joined: false,
		completed_at: null
	}));
}

export async function fetchChallengeById(id: string): Promise<ChallengeWithMeta | null> {
	const userId = auth.user?.id;
	const { data, error } = await supabase
		.from(TABLES.challenges)
		.select('*')
		.eq('id', id)
		.maybeSingle();
	if (error) throw error;
	if (!data) return null;
	const challenge = challengeFromRow(data);
	const { data: parts } = await supabase
		.from(TABLES.challenge_participants)
		.select('user_id, completed_at')
		.eq('challenge_id', id);
	const joinedRow = userId ? (parts ?? []).find((p) => p.user_id === userId) : undefined;
	return {
		...challenge,
		participant_count: (parts ?? []).length,
		my_value: null,
		my_rank: null,
		joined: !!joinedRow,
		completed_at: joinedRow?.completed_at ?? null
	};
}

export async function createChallenge(input: {
	title: string;
	description?: string | null;
	metric: ChallengeMetric;
	scope: ChallengeScope;
	goal_value?: number | null;
	activity_type?: ActivityType | null;
	club_id?: string | null;
	starts_at: string;
	ends_at: string;
	is_public?: boolean;
}): Promise<Challenge> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from(TABLES.challenges)
		.insert({
			creator_id: userId,
			title: input.title.trim(),
			description: input.description?.trim() || null,
			metric: input.metric,
			scope: input.scope,
			goal_value: input.goal_value ?? null,
			activity_type: input.activity_type ?? null,
			club_id: input.club_id ?? null,
			starts_at: input.starts_at,
			ends_at: input.ends_at,
			is_public: input.is_public ?? true
		})
		.select()
		.single();
	if (error) throw error;
	return challengeFromRow(data);
}

// ─────────────────────── Charity fundraising (fundraising.md) ───────────────
// A fundraiser is polymorphic over (run | event). The public page reads the
// fundraiser row (RLS: visible when the anchor is public), the thermometer via
// fundraiser_totals, and the donation feed via fundraiser_feed (public-safe
// projection — donor identity / Stripe ids never reach the client). Donation
// checkout is a Stripe-hosted handoff; the webhook confirms the donation.

export interface CreateFundraiserInput {
	charityName: string;
	charityUrl?: string | null;
	title: string;
	story?: string | null;
	goalCents: number;
	currency?: string;
	runId?: string | null;
	eventId?: string | null;
}

function fundraiserFromRow(row: Record<string, unknown>): Fundraiser {
	return { ...(row as Fundraiser), status: row.status as FundraiserStatus };
}

export async function fetchFundraiserById(id: string): Promise<Fundraiser | null> {
	const { data, error } = await supabase.from('fundraisers').select('*').eq('id', id).maybeSingle();
	if (error || !data) return null;
	return fundraiserFromRow(data);
}

export async function fetchFundraiserForRun(runId: string): Promise<Fundraiser | null> {
	const { data, error } = await supabase
		.from('fundraisers')
		.select('*')
		.eq('run_id', runId)
		.maybeSingle();
	if (error || !data) return null;
	return fundraiserFromRow(data);
}

export async function fetchFundraiserForEvent(eventId: string): Promise<Fundraiser | null> {
	const { data, error } = await supabase
		.from('fundraisers')
		.select('*')
		.eq('event_id', eventId)
		.maybeSingle();
	if (error || !data) return null;
	return fundraiserFromRow(data);
}

export async function createFundraiser(input: CreateFundraiserInput): Promise<Fundraiser> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('fundraisers')
		.insert({
			owner_user_id: userId,
			run_id: input.runId ?? null,
			event_id: input.eventId ?? null,
			charity_name: input.charityName.trim(),
			charity_url: input.charityUrl?.trim() || null,
			title: input.title.trim(),
			story: input.story?.trim() || null,
			goal_cents: input.goalCents,
			currency: input.currency ?? 'usd'
		})
		.select('*')
		.single();
	if (error) throw error;
	return fundraiserFromRow(data);
}

export async function updateChallenge(
	id: string,
	patch: Partial<{
		title: string;
		description: string | null;
		goal_value: number | null;
		activity_type: ActivityType | null;
		starts_at: string;
		ends_at: string;
		is_public: boolean;
	}>
): Promise<void> {
	const { error } = await supabase.from(TABLES.challenges).update(patch).eq('id', id);
	if (error) throw error;
}

export async function deleteChallenge(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.challenges).delete().eq('id', id);
	if (error) throw error;
}

export async function joinChallenge(id: string, teamClubId?: string | null): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.challenge_participants)
		.insert({ challenge_id: id, user_id: userId, team_club_id: teamClubId ?? null });
	if (error) throw error;
}

export async function leaveChallenge(id: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.challenge_participants)
		.delete()
		.eq('challenge_id', id)
		.eq('user_id', userId);
	if (error) throw error;
}

export async function fetchChallengeLeaderboard(
	id: string,
	byTeam = false
): Promise<ChallengeLeaderboardRow[]> {
	const { data, error } = await supabase.rpc('challenge_leaderboard', {
		p_challenge_id: id,
		p_by_team: byTeam
	});
	if (error) throw error;
	return (data ?? []).map((r: Record<string, unknown>) => ({
		user_id: (r.user_id as string | null) ?? null,
		display_name: (r.display_name as string | null) ?? null,
		team_club_id: (r.team_club_id as string | null) ?? null,
		value: Number(r.value ?? 0),
		rank: Number(r.rank ?? 0)
	}));
}

export async function myActiveChallenges(): Promise<ChallengeWithMeta[]> {
	const { data, error } = await supabase.rpc('my_active_challenges');
	if (error) throw error;
	return (data ?? []).map((r: Record<string, unknown>) => ({
		...challengeFromRow(r as Parameters<typeof challengeFromRow>[0]),
		participant_count: Number(r.participant_count ?? 0),
		my_value: r.my_value === null || r.my_value === undefined ? null : Number(r.my_value),
		my_rank: r.my_rank === null || r.my_rank === undefined ? null : Number(r.my_rank),
		joined: true,
		completed_at: (r.completed_at as string | null) ?? null
	}));
}

/// Best-effort: ask the server to recompute the caller's completion for a
/// challenge after a run saves. Swallow-to-debug like other auxiliary effects —
/// the daily cron sweep is the durable backstop, so a transient failure here
/// never blocks the run save.
export async function recomputeChallengeCompletion(id: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) return;
	try {
		const { error } = await supabase.rpc('recompute_challenge_completion', {
			p_challenge_id: id,
			p_user_id: userId
		});
		if (error) console.debug('recomputeChallengeCompletion failed', error);
	} catch (e) {
		console.debug('recomputeChallengeCompletion threw', e);
	}
}

export async function updateFundraiser(
	id: string,
	patch: Partial<Pick<CreateFundraiserInput, 'charityName' | 'charityUrl' | 'title' | 'story' | 'goalCents'>>
): Promise<void> {
	const row: Record<string, unknown> = { updated_at: new Date().toISOString() };
	if (patch.charityName !== undefined) row.charity_name = patch.charityName.trim();
	if (patch.charityUrl !== undefined) row.charity_url = patch.charityUrl?.trim() || null;
	if (patch.title !== undefined) row.title = patch.title.trim();
	if (patch.story !== undefined) row.story = patch.story?.trim() || null;
	if (patch.goalCents !== undefined) row.goal_cents = patch.goalCents;
	const { error } = await supabase.from('fundraisers').update(row).eq('id', id);
	if (error) throw error;
}

export async function closeFundraiser(id: string): Promise<void> {
	const { error } = await supabase
		.from('fundraisers')
		.update({ status: 'closed', updated_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw error;
}

export async function fetchFundraiserTotals(id: string): Promise<FundraiserTotals | null> {
	const { data, error } = await supabase.rpc('fundraiser_totals', { p_fundraiser_id: id });
	if (error || !data || (data as unknown[]).length === 0) return null;
	const row = (data as FundraiserTotals[])[0];
	return {
		raised_cents: Number(row.raised_cents) || 0,
		donor_count: Number(row.donor_count) || 0,
		goal_cents: Number(row.goal_cents) || 0,
		currency: row.currency
	};
}

export async function fetchFundraiserFeed(
	id: string,
	limit = 50
): Promise<FundraiserFeedEntry[]> {
	const { data, error } = await supabase.rpc('fundraiser_feed', {
		p_fundraiser_id: id,
		p_limit: limit
	});
	if (error || !data) return [];
	return data as FundraiserFeedEntry[];
}

/// Begin a Stripe Checkout for a donation. The donations-checkout Edge Function
/// validates the fundraiser is open + visible + the owner can take payment,
/// inserts a pending donation row, and returns a hosted destination-charge
/// Checkout URL. The caller redirects the browser there. The donor may be
/// anonymous — no auth required.
export async function startDonationCheckout(
	fundraiserId: string,
	amountCents: number,
	opts: { displayName?: string | null; message?: string | null; isAnonymous?: boolean } = {}
): Promise<{ url: string }> {
	const { data, error } = await supabase.functions.invoke('donations-checkout', {
		body: {
			fundraiser_id: fundraiserId,
			amount_cents: amountCents,
			display_name: opts.displayName ?? null,
			message: opts.message ?? null,
			is_anonymous: opts.isAnonymous ?? false
		}
	});
	if (error) throw error;
	const url = (data as { checkout_url?: string } | null)?.checkout_url;
	if (!url) throw new Error('No checkout URL returned');
	return { url };
}
