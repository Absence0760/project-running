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
}

export async function backfill(
	supabase: DbClient,
	userId: string,
	accessToken: string,
	lookbackDays: number,
): Promise<BackfillResult> {
	const afterEpoch = Math.floor((Date.now() - lookbackDays * 86400_000) / 1000);
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

	let rateLimited = false;
	// Only an end-of-window exit may claim the lookback window was walked to
	// its end. Every other `break` below — Strava throttling us, an upstream
	// error, a malformed page, the 20-page safety cap — leaves activities in
	// the window unfetched, and only the throttle case had a field to say so.
	// The window is relative to `Date.now()`, so the unfetched activities stay
	// reachable by a re-sync ONLY until they age past `lookbackDays`: a sync
	// that reports "complete" when it is not is a data loss on a 90-day fuse,
	// because the runner has been told there is nothing left to fetch.
	let complete = false;
	while (true) {
		const url = `https://www.strava.com/api/v3/athlete/activities?after=${afterEpoch}&per_page=${pageSize}&page=${page}`;
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
		const activities = (await resp.json()) as StravaActivity[];
		// A non-array body is a malformed page, not the end of the window.
		if (!Array.isArray(activities)) break;
		if (activities.length === 0) {
			complete = true;
			break;
		}

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
	if (complete) {
		await supabase
			.from('integrations')
			.update({ last_sync_at: new Date().toISOString() })
			.eq('user_id', userId)
			.eq('provider', 'strava');
	}

	return { imported, skipped, failed, rate_limited: rateLimited, complete };
}
