import type { DbClient } from '../_shared/database.ts';
import {
	type RawRunRow,
	type StravaActivity,
	collectRunIdentities,
	ingestActivity,
	isCrossProviderDuplicate,
	isStravaRunFamily,
} from '../_shared/strava.ts';

// The page walk behind both `connect` and `sync`, lifted out of `index.ts` so
// its exits can be exercised without standing up `Deno.serve`.

export interface BackfillResult {
	imported: number;
	skipped: number;
	failed: number;
	rate_limited: boolean;
	complete: boolean;
	/// A re-sync continues from where this walk stopped rather than starting
	/// the window again. Implies `complete === false`.
	resumable: boolean;
}

/// The slice of Strava's activity list a walk still has to cover, in epoch
/// seconds. `before` is null for "up to now".
///
/// `from` is the oldest instant the JOB covers, which is not the same as the
/// oldest instant still to fetch: everything between `from` and `after` has
/// already been walked by an earlier attempt. Without it a resume cannot tell
/// whether the caller's window is contained in the job's — and the two are
/// never equal, because `after` is recomputed from the clock on every call, so
/// comparing against it refuses every same-lookback re-sync there is.
export interface WalkWindow {
	from: number;
	after: number;
	before: number | null;
}

/// What a walk actually saw, which is what lets the next one skip it. The
/// direction is MEASURED off the page rather than assumed: Strava returns the
/// activity list oldest-first when `after` is set and newest-first otherwise,
/// and which of those a resume has to trust decides which end of the walked
/// span is the frontier. Reading it off the page costs one comparison and
/// removes the assumption.
export interface WalkedSpan {
	min: number;
	max: number;
	ascending: boolean;
}

const SYNC_CURSOR_VERSION = 1;

/// Read a stored resume point. Fails closed on anything it cannot read as one
/// — an older shape, a truncated write, a hand-edited row — because the
/// fallback is walking the whole window again, which is correct and merely
/// costs Strava request budget. Believing a malformed cursor would skip runs.
export function parseSyncCursor(raw: unknown): WalkWindow | null {
	if (typeof raw !== 'string' || raw.length === 0) return null;
	let parsed: unknown;
	try {
		parsed = JSON.parse(raw);
	} catch (_) {
		return null;
	}
	if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
	const o = parsed as Record<string, unknown>;
	if (o.v !== SYNC_CURSOR_VERSION) return null;
	const from = o.from;
	const after = o.after;
	const before = o.before ?? null;
	if (typeof from !== 'number' || !Number.isInteger(from) || from <= 0) return null;
	if (typeof after !== 'number' || !Number.isInteger(after) || after < from) return null;
	if (before !== null) {
		if (typeof before !== 'number' || !Number.isInteger(before) || before <= after) return null;
	}
	return { from, after, before: before as number | null };
}

export function serialiseSyncCursor(w: WalkWindow): string {
	return JSON.stringify({ v: SYNC_CURSOR_VERSION, from: w.from, after: w.after, before: w.before });
}

/// The window a resume should walk, given the one this walk was covering and
/// the span it got through. Returns null when the remainder is not strictly
/// smaller than what we started with — a cursor that does not narrow is a
/// resume that makes no progress, and storing one would loop a runner between
/// two syncs forever.
export function nextWalkWindow(window: WalkWindow, walked: WalkedSpan | null): WalkWindow | null {
	if (!walked) return null;
	if (walked.ascending) {
		if (walked.max <= window.after) return null;
		if (window.before !== null && walked.max >= window.before) return null;
		return { from: window.from, after: walked.max, before: window.before };
	}
	if (window.before !== null && walked.min >= window.before) return null;
	if (walked.min <= window.after) return null;
	return { from: window.from, after: window.after, before: walked.min };
}

export async function backfill(
	supabase: DbClient,
	userId: string,
	accessToken: string,
	lookbackDays: number,
): Promise<BackfillResult> {
	const requestedAfter = Math.floor((Date.now() - lookbackDays * 86400_000) / 1000);
	let page = 1;
	const pageSize = 50;
	let imported = 0;
	let skipped = 0;
	let failed = 0;

	// Resolve privacy_default ONCE for the whole backfill (persona #27) so
	// imported runs match the user's chosen visibility. Only an explicit
	// 'public' default publishes; followers/private/unset and any read error
	// fall closed to private.
	let importIsPublic = false;
	try {
		const { data: settings } = await supabase
			.from('user_settings')
			.select('prefs')
			.eq('user_id', userId)
			.maybeSingle();
		const prefs = (settings?.prefs ?? null) as Record<string, unknown> | null;
		importIsPublic = prefs?.privacy_default === 'public';
	} catch (_) {
		importIsPublic = false;
	}

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

	// Cross-provider near-duplicate guard. The `seen` set above only catches
	// a re-import of the SAME Strava activity; it never sees the same effort
	// that already arrived under another source (a Garmin watch auto-uploaded
	// to Strava, an Apple HealthKit copy, a Garmin bulk-export ZIP). Pull
	// every existing run's start time + distance ACROSS ALL SOURCES so we can
	// skip an activity that already exists under any provider.
	//
	// PAGE the read: PostgREST caps an unbounded SELECT at 1000 rows, so a pro
	// with 1000+ runs would otherwise compare against an arbitrary slice and
	// re-import duplicates anyway — the exact failure this guard exists to
	// close. `collectRunIdentities` loops `.range()` in 1000-row chunks
	// (mirrors `fetchRuns` on web).
	const existingIdentities = await collectRunIdentities((from, to) =>
		supabase
			.from('runs')
			.select('started_at, distance_m')
			.eq('user_id', userId)
			.order('started_at', { ascending: false })
			.range(from, to)
			.then(({ data, error }): RawRunRow[] | null => (error ? null : (data as RawRunRow[]))),
	);

	// Resume where the last walk stopped. A stored cursor is honoured only when
	// the caller has not asked to reach FURTHER BACK than it does: a runner
	// widening `lookbackDays` is asking for history the cursor's window does
	// not contain, and the wider walk covers the cursor's remainder anyway, so
	// silently narrowing them to it would answer a different question. When it
	// is honoured the window is strictly larger than the request, which is the
	// point — the job gets finished rather than restarted.
	const { data: integrationRow } = await supabase
		.from('integrations')
		.select('sync_cursor')
		.eq('user_id', userId)
		.eq('provider', 'strava')
		.maybeSingle();
	const storedCursor = parseSyncCursor(integrationRow?.sync_cursor);
	const resumedFrom = storedCursor && requestedAfter >= storedCursor.from ? storedCursor : null;
	const window: WalkWindow = resumedFrom ??
		{ from: requestedAfter, after: requestedAfter, before: null };

	// The frontier a resume measures from, accumulated across every page the
	// walk got through — every activity on the page, not just the run-family
	// ones, because the cursor describes what was FETCHED rather than what was
	// ingested.
	let walked: WalkedSpan | null = null;

	let rateLimited = false;
	// Only an end-of-window exit may claim the lookback window was walked to
	// its end. Every other `break` below — Strava throttling us, an upstream
	// error, a transport failure, a malformed page, the 20-page safety cap —
	// leaves activities in the window unfetched.
	// The window is relative to `Date.now()`, so the unfetched activities stay
	// reachable by a re-sync ONLY until they age past `lookbackDays`: a sync
	// that reports "complete" when it is not is a data loss on a 90-day fuse,
	// because the runner has been told there is nothing left to fetch.
	let complete = false;
	while (true) {
		const beforeParam = window.before === null ? '' : `&before=${window.before}`;
		const url =
			`https://www.strava.com/api/v3/athlete/activities?after=${window.after}${beforeParam}` +
			`&per_page=${pageSize}&page=${page}`;
		// A transport failure is a truncation like any other, not a reason to
		// throw away the walk. `fetch` rejects on DNS / TLS / a dropped
		// connection and `resp.json()` on an HTML error page served by
		// anything sitting in front of Strava; both used to propagate past
		// `handleSync` into `withSentry`, which answers 500 `internal_error`.
		// The activities ingested so far are in the database either way, so
		// the only thing that changes is whether the runner is told about
		// them — and a 500 tells them the sync failed outright.
		let activities: StravaActivity[];
		try {
			const resp = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
			if (resp.status === 429 || resp.status === 503) {
				// Strava rate-limit / maintenance — surface to the caller so
				// the client can show "Strava is rate-limiting us, try again
				// in 15 minutes" rather than treating partial as success.
				console.warn('strava backfill rate-limited', { page, status: resp.status });
				rateLimited = true;
				break;
			}
			if (!resp.ok) {
				// Bail on the first non-rate-limit failure rather than looping
				// forever — a partial import is still useful, but it is a PARTIAL
				// one: `complete` stays false so the caller says so.
				console.warn('strava backfill upstream error', { page, status: resp.status });
				break;
			}
			activities = (await resp.json()) as StravaActivity[];
		} catch (err) {
			console.warn('strava backfill transport error', {
				page,
				error: err instanceof Error ? err.name : 'unknown',
			});
			break;
		}
		// A non-array body is a malformed page, not the end of the window.
		if (!Array.isArray(activities)) break;
		if (activities.length === 0) {
			complete = true;
			break;
		}
		walked = extendWalkedSpan(walked, activities);

		for (const act of activities) {
			// Restrict to run-family activities (Run / TrailRun / VirtualRun
			// / Walk / Hike). Strava's `sport_type` is the modern field;
			// `type` is the legacy fallback. Routed through the shared
			// helper so the allowlist stays in one place — ingestActivity
			// now also rejects defensively (persona-hunt Pro #3).
			if (!isStravaRunFamily(act.sport_type ?? act.type)) continue;
			if (seen.has(String(act.id))) {
				skipped++;
				continue;
			}
			const startMs = Date.parse(act.start_date);
			if (
				Number.isFinite(startMs) &&
				isCrossProviderDuplicate(
					{ startedAtMs: startMs, distanceM: Math.round(act.distance) },
					existingIdentities,
				)
			) {
				// Already present under another source — skip so we don't
				// double-insert the same physical activity.
				skipped++;
				continue;
			}
			try {
				await ingestActivity(supabase, userId, accessToken, act, importIsPublic);
				imported++;
			} catch (_) {
				failed++;
			}
		}

		if (activities.length < pageSize) {
			complete = true;
			break;
		}
		page++;
		if (page > 20) break; // safety cap — 1000 activities per sync
	}

	// `last_sync_at` is the moment the whole window was last walked, and both
	// tiles render it as "Last synced <ago>". Stamping it after a truncated
	// backfill is the second sentence telling the runner the import finished;
	// leaving it alone keeps the previous, true value — or, on a first connect
	// that never completed, the honest "waiting for first sync".
	const nextCursor = complete ? null : nextWalkWindow(window, walked);
	const patch: { last_sync_at?: string; sync_cursor?: string | null } = {};
	if (complete) {
		patch.last_sync_at = new Date().toISOString();
		// A finished window subsumes any resume point inside it.
		patch.sync_cursor = null;
	} else if (nextCursor) {
		patch.sync_cursor = serialiseSyncCursor(nextCursor);
	}
	// A truncation that got nowhere writes nothing, so a cursor this walk
	// resumed from and failed to advance survives for the next attempt.
	if (Object.keys(patch).length > 0) {
		await supabase
			.from('integrations')
			.update(patch)
			.eq('user_id', userId)
			.eq('provider', 'strava');
	}

	return {
		imported,
		skipped,
		failed,
		rate_limited: rateLimited,
		complete,
		resumable: !complete && (nextCursor !== null || resumedFrom !== null),
	};
}

function extendWalkedSpan(
	current: WalkedSpan | null,
	activities: StravaActivity[],
): WalkedSpan | null {
	const stamps: number[] = [];
	for (const act of activities) {
		const ms = Date.parse(act.start_date);
		if (Number.isFinite(ms)) stamps.push(Math.floor(ms / 1000));
	}
	if (stamps.length === 0) return current;
	const min = Math.min(...stamps);
	const max = Math.max(...stamps);
	// Direction off THIS page: Strava orders the list oldest-first when
	// `after` is set and newest-first otherwise, and a page of one cannot say
	// which, so a tie reads as oldest-first — the shape the walk always
	// requests. Later pages overwrite the reading; the frontier is only ever
	// consulted for the last page a walk got through.
	const ascending = stamps[stamps.length - 1] >= stamps[0];
	return current === null
		? { min, max, ascending }
		: { min: Math.min(current.min, min), max: Math.max(current.max, max), ascending };
}
