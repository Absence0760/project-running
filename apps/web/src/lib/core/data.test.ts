// Source-level guards for core/data.ts read/write invariants that can't
// be behaviourally unit-tested without a live Supabase stack (these
// functions call the `supabase` singleton directly). Each test reads a
// source file as text and pins a security / data-integrity property with
// a reason a future editor can read before deciding it's safe to break.
//
// Runs with cwd = apps/web (the `test:unit` script), so `read` resolves
// cwd-relative paths — same convention as security_guards.test.ts.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('fetchRunsForDashboard is bounded + column-narrowed, not the unbounded select(*) scan', () => {
	// Reason: /dashboard's onMount used to call the unbounded fetchRuns()
	// (`select('*')`, paging the ENTIRE history 1000 rows at a time incl.
	// the metadata jsonb bag) on every paint of the highest-traffic page
	// (issue #332). It must instead window by date via dashboardRunsWindowStart
	// and narrow the select — never regress to `select('*')` or drop the
	// `.gte('started_at', …)` window (that resurrects the full-history scan).
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function fetchRunsForDashboard');
	assert.ok(start >= 0, 'Could not locate fetchRunsForDashboard — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
	assert.match(
		body,
		/dashboardRunsWindowStart\(/,
		'fetchRunsForDashboard must window via dashboardRunsWindowStart — an unwindowed fetch is the bug.',
	);
	assert.match(
		body,
		/\.gte\('started_at',\s*windowStart\.toISOString\(\)\)/,
		'fetchRunsForDashboard must filter started_at against the window cutoff.',
	);
	assert.doesNotMatch(
		body,
		/\.select\('\*'\)/,
		'fetchRunsForDashboard must column-narrow — select(*) ships the metadata jsonb bag per row.',
	);
	assert.match(
		body,
		/\.select\(\s*['"`][^'"`]*started_at[^'"`]*distance_m/,
		'fetchRunsForDashboard must select the explicit consumer columns (started_at, distance_m, …).',
	);
	// The dashboard page must call the bounded reader, not the unbounded one.
	const page = read('src/routes/dashboard/+page.svelte');
	assert.match(
		page,
		/fetchRunsForDashboard\(\)/,
		'/dashboard must load runs via the bounded fetchRunsForDashboard.',
	);
	assert.doesNotMatch(
		page,
		/\bfetchRuns\(\)/,
		'/dashboard must not call the unbounded fetchRuns() — that is the #332 regression.',
	);
	// Lifetime headline stats must come from the cheap aggregate, not the
	// windowed set (which would truncate a deep-history runner's totals).
	assert.match(
		page,
		/fetchRunAllTimeStats\(\)/,
		'/dashboard must source lifetime totals from fetchRunAllTimeStats, not the ~2-year window.',
	);
});

test('fetchRunAllTimeStats uses a HEAD count + single-row max, ships no run payload', () => {
	// Reason: the Total-runs / Longest-run cards are labelled "all sources" /
	// "all time"; windowing the dashboard fetch to ~2 years would silently
	// truncate them for a deep-history (Strava-migrant) runner — the exact
	// case the old unbounded scan protected. The aggregate must stay a
	// count-only HEAD read + a one-row max, never a full-history read.
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function fetchRunAllTimeStats');
	assert.ok(start >= 0, 'Could not locate fetchRunAllTimeStats — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
	assert.match(
		body,
		/count:\s*'exact',\s*head:\s*true/,
		'total runs must be a HEAD count query — it must not ship rows.',
	);
	assert.match(
		body,
		/\.order\('distance_m',\s*\{\s*ascending:\s*false\s*\}\)\s*[\s\S]*?\.limit\(1\)/,
		'longest run must be a single-row max (order desc + limit 1), not a client-side scan.',
	);
});

test('the period drilldown never rolls up an all-time total from the dashboard window', () => {
	// Reason: #332's fix bounded /dashboard's run fetch, then passed the same
	// bounded set to <PeriodSummary> — which has an "all time" tab and
	// unbounded Previous paging. The all-time modal opened by the "Longest
	// run / all time" card therefore reported totals short by everything
	// older than the window, disagreeing with the card that opened it
	// (issue #664). The component must consult periodNeedsFullHistory, and
	// the dashboard must hand it both the bound and a full-history loader.
	const component = read('src/lib/components/PeriodSummary.svelte');
	assert.match(
		component,
		/periodNeedsFullHistory\(/,
		'PeriodSummary must decide via periodNeedsFullHistory whether the prop set can answer the period.',
	);
	const page = read('src/routes/dashboard/+page.svelte');
	const usage = page.slice(page.indexOf('<PeriodSummary'));
	assert.match(
		usage,
		/coveredFrom=/,
		'/dashboard must tell PeriodSummary how far back its windowed run set reaches.',
	);
	assert.match(
		usage,
		/loadFullHistory=/,
		'/dashboard must give PeriodSummary a full-history loader for periods past the window.',
	);
});

test('fetchRunsForPeriodSummary ships the whole history column-narrowed, and surfaces failure', () => {
	// Reason: the drilldown lists every run, so it genuinely needs every row
	// — the saving is per-row width. `select('*')` here would ship the
	// metadata jsonb bag over a lifetime of runs, which is exactly the #332
	// scan. It must also throw rather than degrade to [], or a fetch failure
	// renders as a silently-short total (issue #664).
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function fetchRunsForPeriodSummary');
	assert.ok(start >= 0, 'Could not locate fetchRunsForPeriodSummary — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
	assert.match(
		body,
		/columns:\s*PERIOD_SUMMARY_RUN_COLUMNS/,
		'fetchRunsForPeriodSummary must column-narrow via PERIOD_SUMMARY_RUN_COLUMNS.',
	);
	assert.match(
		body,
		/throwOnError:\s*true/,
		'a failed history fetch must throw, not degrade to an incomplete total.',
	);
	assert.doesNotMatch(
		source.slice(source.indexOf('PERIOD_SUMMARY_RUN_COLUMNS =')).split('\n')[0],
		/\*/,
		'PERIOD_SUMMARY_RUN_COLUMNS must be an explicit column list, never `*`.',
	);
	// The standalone deep-link route shares the narrowed reader.
	const route = read('src/routes/dashboard/period/[type]/[date]/+page.svelte');
	assert.match(
		route,
		/fetchRunsForPeriodSummary\(\)/,
		'/dashboard/period must use the narrowed history reader, not the select(*) fetchRuns().',
	);
	assert.doesNotMatch(
		route,
		/\bfetchRuns\(\)/,
		'/dashboard/period must not call the unbounded select(*) fetchRuns().',
	);
});

test('fetchRouteById clips waypoints for non-owner club members (RLS is not the boundary)', () => {
	// Reason: RLS lets an active club member SELECT the base `routes`
	// row, which carries the unclipped polyline + geom + start_point. The
	// owner-read branch used to return that row verbatim to ANY caller RLS
	// let through — so a non-owner club member received the runner's
	// unclipped waypoints (audit/privacy-zones High). The owner check —
	// not RLS — must gate the raw geometry: when user_id != viewerId the
	// waypoints go through fetchClippedRouteForViewer and geom/start_point
	// are nulled, matching the public branch. See decisions §33.
	const source = read('src/lib/core/data.ts');
	const fnMatch = source.match(
		/export async function fetchRouteById[\s\S]*?^}/m,
	);
	assert.ok(fnMatch, 'Could not locate fetchRouteById body — rename?');
	const body = fnMatch![0];
	assert.match(
		body,
		/rest\.user_id\s*!==\s*viewerId/,
		'fetchRouteById must compare the row owner against the viewer — RLS surfacing the base row to a club member is not consent to see the unclipped polyline.',
	);
	// The non-owner branch (everything after the owner-check) must clip
	// and strip the raw geometry columns.
	const nonOwnerBranch = body.slice(body.indexOf('rest.user_id !== viewerId'));
	assert.match(
		nonOwnerBranch,
		/fetchClippedRouteForViewer/,
		'The non-owner branch must route waypoints through fetchClippedRouteForViewer — the base row polyline is unclipped.',
	);
	assert.match(
		nonOwnerBranch,
		/waypoints:\s*clipped/,
		'The non-owner branch must return the clipped waypoints, not the raw row waypoints.',
	);
	assert.match(
		nonOwnerBranch,
		/geom:\s*null/,
		'The non-owner branch must null `geom` — it is unclipped geometry the club member must not receive.',
	);
	assert.match(
		nonOwnerBranch,
		/start_point:\s*null/,
		'The non-owner branch must null `start_point` — it leaks the run start location.',
	);
});

test('fetchRoutesWithError selects a narrowed column set, never geom, for the routes list', () => {
	// Reason: `routes.geom` is a geography(LineString) duplicating `waypoints`
	// purely for server-side spatial queries; no client reads it. `select('*')`
	// on the owned-routes query + both saved-route lookups shipped the full geom
	// binary over the wire alongside waypoints, ~doubling the geometry payload of
	// the busiest routes page for zero rendering benefit (issue #344). The queries
	// must enumerate ROUTE_LIST_COLS (base table) / PUBLIC_ROUTE_LIST_COLS (view)
	// — omitting geom + start_point but covering every column the "My routes" list
	// AND the route pickers (RunEditor / EventEditor / club transfer) read.
	const source = read('src/lib/core/data.ts');

	const listCols = source.match(/const ROUTE_LIST_COLS\s*=\s*\n?\s*'([^']*)'/);
	assert.ok(listCols, 'Could not locate the ROUTE_LIST_COLS constant — rename?');
	const cols = listCols![1].split(',').map((c) => c.trim());
	assert.ok(!cols.includes('geom'), 'ROUTE_LIST_COLS must not select geom — server-spatial-only, doubles the wire payload.');
	assert.ok(!cols.includes('start_point'), 'ROUTE_LIST_COLS must not select start_point — no client reader.');
	// Every column a consumer of fetchRoutes / fetchRoutesWithError reads:
	// the /routes list, plus the RunEditor / EventEditor / club-transfer pickers.
	for (const needed of [
		'id',
		'user_id',
		'club_id',
		'name',
		'distance_m',
		'elevation_m',
		'surface',
		'waypoints',
		'is_starred',
		'run_count',
		'created_at',
	]) {
		assert.ok(cols.includes(needed), `ROUTE_LIST_COLS must include ${needed} — a routes-list/picker consumer reads it.`);
	}

	const fnMatch = source.match(/export async function fetchRoutesWithError[\s\S]*?\n}/);
	assert.ok(fnMatch, 'Could not locate fetchRoutesWithError — rename?');
	const body = fnMatch![0];
	assert.doesNotMatch(
		body,
		/\.select\('\*'\)/,
		'fetchRoutesWithError must not select(\'*\') — the owned + saved lookups ship geom for nothing.',
	);
	assert.match(
		body,
		/\.from\('routes'\)\s*\.select\(ROUTE_LIST_COLS\)/,
		'The owned + saved base-table reads must select ROUTE_LIST_COLS.',
	);
	assert.match(
		body,
		/\.from\('public_routes'\)\s*\.select\(PUBLIC_ROUTE_LIST_COLS\)/,
		'The saved public_routes lookup must select the view-scoped PUBLIC_ROUTE_LIST_COLS.',
	);
});

// ── Mobile twin cross-checks (packages/api_client is shared, no iOS twin) ──

test('api_client.dart fetchRouteById clips for non-owner club members', () => {
	// Reason: the mobile twin had the same leak — the ownerRow branch
	// returned _routeFromRow(ownerRow) (unclipped waypoints) to any caller
	// RLS let through, including non-owner club members. It must gate on
	// the owner id and route non-owner waypoints through the clip RPC.
	const source = read('../../packages/api_client/lib/src/api_client.dart');
	const start = source.indexOf('fetchRouteById(');
	assert.ok(start >= 0, 'Could not locate fetchRouteById in api_client.dart — rename?');
	const end = source.indexOf('_clipRouteForViewer(String routeId)', start);
	assert.ok(end > start, 'Could not locate the _clipRouteForViewer helper after fetchRouteById.');
	const body = source.slice(start, end);
	assert.match(
		body,
		/ownerId\s*==\s*viewerId/,
		'api_client.dart fetchRouteById must compare the row owner against the viewer before returning the unclipped ownerRow.',
	);
	assert.match(
		body,
		/_clipRouteForViewer\(routeId\)/,
		'api_client.dart fetchRouteById must clip waypoints for non-owner viewers via _clipRouteForViewer.',
	);
});

test('api_client.dart round-trips runs.route_id on read and both write paths', () => {
	// Reason: _runFromRow used to drop route_id, so the newer-wins merge
	// wiped a run's route link to null on the next sync after
	// linkRunToRoute(); saveRun / saveRunsBatch omitted it too, so the
	// upsert re-wrote route_id = null. All three must carry it or the link
	// can't survive a round-trip (Critical data-loss finding).
	const source = read('../../packages/api_client/lib/src/api_client.dart');
	assert.match(
		source,
		/routeId:\s*r\.routeId/,
		'_runFromRow (read) + saveRunsBatch (write) must set routeId: r.routeId.',
	);
	assert.match(
		source,
		/routeId:\s*run\.routeId/,
		'saveRun (write) must set routeId: run.routeId — omitting it re-writes route_id = null on upsert.',
	);
});

test('fetchRouteById anon/public branch assembles waypoints from the server clip', () => {
	// Reason: the live spectator page (`/live/[id]`) is a public share
	// surface — anon viewers reach it with just the link. When the
	// owner-read returns nothing (anon / stranger), the public branch
	// must read metadata from the `public_routes` view (which omits
	// waypoints/geom/start_point by construction) and take the polyline
	// only from clip_route_for_viewer, so an anon spectator's next-cutoff
	// card is built from privacy-clipped waypoints (audit/privacy-zones
	// Medium, 2026-07-02).
	const source = read('src/lib/core/data.ts');
	const fnMatch = source.match(/export async function fetchRouteById[\s\S]*?^}/m);
	assert.ok(fnMatch, 'Could not locate fetchRouteById body — rename?');
	const body = fnMatch![0];
	const publicBranch = body.slice(body.indexOf('assemblePublicRoute'));
	assert.ok(
		publicBranch.length > 'assemblePublicRoute'.length,
		'fetchRouteById must fall through to assemblePublicRoute for callers the routes RLS rejects (anon / strangers).',
	);
	assert.match(
		publicBranch,
		/from\('public_routes'\)/,
		'The public branch must read metadata from the public_routes view, never the base routes table.',
	);
	assert.match(
		publicBranch,
		/fetchClippedRouteForViewer\(id\)/,
		'The public branch must source the polyline from clip_route_for_viewer.',
	);
	assert.match(
		publicBranch,
		/waypoints:\s*assembled\.clipped/,
		'The assembled public route must carry the clipped waypoints, nothing else.',
	);
});

test('live spectator next-cutoff card sources waypoints through the clipped route reader', () => {
	// Reason: the /live/[id] next-cutoff ETA card projects live position
	// against the linked route's waypoints, and the viewer is usually NOT
	// the route owner (club member, follower, or anon with the share
	// link). fetchRouteById is the owner-aware reader — it hands the raw
	// polyline only to the owner and clips for everyone else — so the
	// page must build the roadbook from it and never query the routes
	// table directly, which would resurrect the unclipped wire-leak the
	// audit/privacy-zones Medium finding tracked (closed at the
	// data-fetch root, 2026-07-02).
	const source = read('src/routes/live/[id]/+page.svelte');
	const fnMatch = source.match(/async function loadRouteCutoffs[\s\S]*?\n\t}/);
	assert.ok(fnMatch, 'Could not locate loadRouteCutoffs — rename?');
	const body = fnMatch![0];
	assert.match(
		body,
		/fetchRouteById\(run\.route_id\)/,
		'loadRouteCutoffs must fetch the route via fetchRouteById (the owner-aware, privacy-clipping reader).',
	);
	assert.match(
		body,
		/route\?\.waypoints/,
		'The roadbook waypoints must come from the fetched (clipped-for-non-owners) route, not another source.',
	);
	assert.doesNotMatch(
		source,
		/\.from\('routes'\)/,
		'The live spectator page must not read the base routes table directly — RLS surfaces unclipped club-owned rows to club members.',
	);
	assert.doesNotMatch(
		source,
		/\.from\('public_routes'\)/,
		'Route reads on this page go through $lib/core/data, not inline view queries.',
	);
});

test('plans/new loads club templates with one batched query, not one per club', () => {
	// Reason: the template picker used to call fetchClubTemplates inside a
	// clubs.map — one round-trip per club (N+1, audit/db-performance
	// Medium). The scope is a single training_plans read filtered on all
	// club ids at once; the data layer groups per club so the picker's
	// club-ordered display is unchanged.
	const page = read('src/routes/plans/new/+page.svelte');
	assert.match(
		page,
		/fetchClubTemplatesForClubs\(/,
		'plans/new must load templates through the batched fetchClubTemplatesForClubs.',
	);
	assert.doesNotMatch(
		page,
		/fetchClubTemplates\(/,
		'plans/new must not call the single-club fetchClubTemplates per club — that is the N+1.',
	);
	const data = read('src/lib/core/data.ts');
	const fnMatch = data.match(
		/export async function fetchClubTemplatesForClubs[\s\S]*?\n}/,
	);
	assert.ok(fnMatch, 'Could not locate fetchClubTemplatesForClubs — rename?');
	assert.match(
		fnMatch![0],
		/\.in\('club_id', clubIds\)/,
		'fetchClubTemplatesForClubs must filter all club ids in ONE query.',
	);
});

test('enrichClubs reads the trigger-maintained member_count cache, not a per-member roster recount', () => {
	// Reason: clubs.member_count is a denormalised, trigger-maintained cache
	// (migration 20260906_001; derived_state.md cache=authoritative-query
	// contract) added SPECIFICALLY so enrichClubs would stop computing it with
	// a post-query aggregate. CLUB_SELECT_COLS already selects member_count on
	// every club row, and the search_clubs RPC branch already reads
	// r.member_count. enrichClubs must trust the cache — it must NOT fire a
	// second `club_members ... status = 'active'` count query pulling one row
	// per active member across every club just to re-derive (and stomp) a value
	// already on the row (bug-hunt-2026-07 H1, issue #331). The viewer
	// role/status query stays — that is per-user membership, not a recount.
	const source = read('src/lib/core/data.ts');
	const fnMatch = source.match(/async function enrichClubs[\s\S]*?\n}/);
	assert.ok(fnMatch, 'Could not locate enrichClubs — rename?');
	const body = fnMatch![0];
	assert.match(
		body,
		/member_count:\s*c\.member_count/,
		'enrichClubs must read member_count from the already-fetched row (the trigger-maintained cache), not a recount map.',
	);
	assert.doesNotMatch(
		body,
		/count:\s*'exact'/,
		"enrichClubs must not issue a { count: 'exact' } roster query — member_count is the authoritative cache on the row.",
	);
	assert.doesNotMatch(
		body,
		/\.eq\('status',\s*'active'\)/,
		"enrichClubs must not re-scan active club_members to recount — that is the redundant per-member fetch #331 removed.",
	);
});

test('deleteNotifications batches into one .in() delete, guards empty, surfaces errors', () => {
	// Reason: bulk-dismissing a collapsed notification group used to await
	// deleteNotification(id) in a for-loop — one DELETE round-trip per
	// member, so dismissing a 20-member group fired 20 sequential requests
	// (issue #350). The batched path must delete all ids in ONE query via
	// .in('id', ids), short-circuit an empty list (an empty .in() would
	// match nothing but still round-trips), and throw the supabase error
	// (supabase-js resolves {error}, never throws — dropping the check
	// silently swallows a failed bulk-dismiss while the row vanishes).
	const source = read('src/lib/core/data.ts');
	const fnMatch = source.match(/export async function deleteNotifications[\s\S]*?\n}/);
	assert.ok(fnMatch, 'Could not locate deleteNotifications — rename?');
	const body = fnMatch![0];
	assert.match(
		body,
		/\.in\('id', ids\)/,
		'deleteNotifications must delete every id in ONE query via .in(\'id\', ids) — a per-id loop is the N+1 issue #350 fixed.',
	);
	assert.match(
		body,
		/if \(ids\.length === 0\) return;/,
		'deleteNotifications must short-circuit an empty id list.',
	);
	assert.match(
		body,
		/if \(error\) throw error;/,
		'deleteNotifications must throw the supabase error — a swallowed failure leaves the row gone from the UI but present in the DB.',
	);
});

test('NotificationsList dismisses a whole group in one batched delete, not one per member', () => {
	// Reason: removeGroup awaited remove(row.id) for every member of a
	// collapsed group — N sequential DELETEs (issue #350). Both the single
	// and the group dismiss now route through one `dismiss` helper that
	// defers the mutation (decisions § 514), so the batching invariant lives
	// there: one deleteNotifications(ids) call for however many rows the
	// intent covers, never a per-id loop. The unread badge is decremented
	// by the whole count and only INSIDE commit — while the undo offer
	// stands the rows are still on the server and still unread, so an early
	// decrement would report a count the server disagrees with for the
	// entire window.
	const source = read('src/lib/components/NotificationsList.svelte');
	const fnMatch = source.match(/function dismiss\([\s\S]*?\n\t}/);
	assert.ok(fnMatch, 'Could not locate the dismiss helper — rename?');
	const body = fnMatch![0];
	assert.match(
		body,
		/deleteNotifications\(ids\)/,
		'dismiss must drop every id with one deleteNotifications(ids) call.',
	);
	assert.doesNotMatch(
		body,
		/for \(|\.map\(\(r\) => deleteNotification/,
		'dismiss must not loop a per-id delete — that is the N+1 issue #350 fixed.',
	);
	assert.match(
		body,
		/commit: async \(\) => \{\s*await deleteNotifications\(ids\);\s*notificationStore\.decrement\(unread\);/,
		'the unread badge must be decremented by the batch count, inside commit.',
	);
	assert.match(
		source,
		/function removeGroup[\s\S]*?dismiss\(/,
		'removeGroup must hand the whole group to the shared dismiss helper.',
	);
});

test('setRunPublic is a real toggle: writes the caller boolean and surfaces errors', () => {
	// Reason: the one-way makeRunPublic it replaces hardcoded
	// `is_public: true`, so a live-shared run could never be made
	// private again (issue #251 — a solo runner's location trace stayed
	// public with no undo). The function must write the caller's
	// boolean, scope the update to the one run id, and throw on the
	// supabase error (supabase-js resolves {error}, it never throws —
	// dropping the check silently swallows a failed revoke while the
	// UI reports "Run is now private").
	const source = read('src/lib/core/data.ts');
	const fnMatch = source.match(/export async function setRunPublic[\s\S]*?\n}/);
	assert.ok(fnMatch, 'Could not locate setRunPublic — rename?');
	const body = fnMatch![0];
	assert.match(
		body,
		/\.update\(\{ is_public: isPublic \}\)/,
		'setRunPublic must write the isPublic parameter — a hardcoded true resurrects the no-undo bug.',
	);
	assert.match(
		body,
		/\.eq\('id', id\)/,
		'setRunPublic must scope the update to the single run id.',
	);
	assert.match(
		body,
		/if \(error\) throw error;/,
		'setRunPublic must throw the supabase error — callers surface it as a toast, not a silent no-op.',
	);
	assert.doesNotMatch(
		source,
		/makeRunPublic\(/,
		'The one-way makeRunPublic must stay deleted — visibility flips go through the bidirectional setRunPublic.',
	);
});

test('the profile-join fetchers chunk `.in()` so >~100 members do not silently empty', () => {
	// Reason: PostgREST serialises `.in('id', ids)` into the request URL.
	// A club / event with more than ~100 members overflows the gateway's
	// request-line limit and the profile-join leg silently returns null —
	// every display_name/avatar_url degrades to a placeholder with no error
	// (issue #325). The fix routes every such leg through fetchProfilesByIds,
	// which chunks the id set. This guard pins that (a) the helper chunks and
	// (b) no fetcher rebuilds the inline unchunked profile-join it replaced.
	const source = read('src/lib/core/data.ts');
	const helper = source.match(/async function fetchProfilesByIds[\s\S]*?\n}/);
	assert.ok(helper, 'Could not locate fetchProfilesByIds — rename?');
	assert.match(
		helper![0],
		/chunk\(userIds, FEED_FOLLOWEE_CHUNK\)/,
		'fetchProfilesByIds must chunk the id set through chunk(..., FEED_FOLLOWEE_CHUNK).',
	);
	assert.match(
		helper![0],
		/mergeProfilePages\(/,
		'fetchProfilesByIds must merge the per-chunk pages via mergeProfilePages.',
	);
	// The three named member/attendee fetchers must resolve profiles through
	// the chunked helper, not an inline `.in('id', userIds)` read. Slice each
	// body to the next top-level `export` — the multi-line return-type object
	// makes a `\n}`-anchored match stop early.
	for (const fn of ['fetchPendingRequests', 'fetchClubMembers', 'fetchEventAttendees']) {
		const start = source.indexOf(`export async function ${fn}`);
		assert.ok(start >= 0, `Could not locate ${fn} — rename?`);
		const nextExport = source.indexOf('\nexport ', start + 1);
		const body = source.slice(start, nextExport === -1 ? undefined : nextExport);
		assert.match(
			body,
			/await fetchProfilesByIds\(userIds\)/,
			`${fn} must resolve member profiles through the chunked fetchProfilesByIds.`,
		);
		assert.doesNotMatch(
			body,
			/\.in\('id', userIds\)/,
			`${fn} must not rebuild the unchunked inline profile-join (issue #325).`,
		);
	}
});

test('fetchFollowingBadgeAwards chunks the followee `.in()` (no silently-empty badge feed)', () => {
	// Reason: a viewer following >~100 people overflowed the gateway on the
	// primary `.in('user_id', authors)` query, silently returning null — an
	// empty badge feed with no error (issue #325). The fix chunks the followee
	// set, queries each chunk with the same cursor + ordering + limit, and
	// merges by earned_at via mergeRecencyPages.
	const source = read('src/lib/core/data.ts');
	// Anchor past the multi-line params object so the non-greedy `\n}` lands on
	// the function's real closing brace, not the opts type's brace.
	const fnMatch = source.match(
		/const authors = await resolveFollowedAuthorIds\(null\);[\s\S]*?\n}/,
	);
	assert.ok(fnMatch, 'Could not locate fetchFollowingBadgeAwards — rename?');
	const body = fnMatch![0];
	assert.match(
		body,
		/chunk\(authors, FEED_FOLLOWEE_CHUNK\)/,
		'fetchFollowingBadgeAwards must chunk the followee set.',
	);
	assert.match(
		body,
		/mergeRecencyPages\(pages, limit, \(r\) => r\.earned_at\)/,
		'It must merge the per-chunk pages by earned_at.',
	);
	assert.doesNotMatch(
		body,
		/\.in\('user_id', authors\)/,
		'It must not query the whole followee set in one unchunked `.in()` (issue #325).',
	);
});

test('updateEvent scopes the write to a single event row and throws on error', () => {
	// Reason: updateEvent is the edit-event write path (issue #335). It must
	// target the `events` table, apply the patch, and filter to the one id —
	// an unfiltered `.update()` would rewrite every event row. RLS
	// `is_event_organiser` is the authoritative gate, but the id filter is the
	// client-side contract the editor depends on. It must also surface DB
	// errors (fail-closed) rather than swallowing them.
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function updateEvent');
	assert.ok(start >= 0, 'Could not locate updateEvent — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
	assert.match(
		body,
		/\.from\('events'\)\s*\.update\(/,
		'updateEvent must update the events table with the patch.',
	);
	assert.match(
		body,
		/\.eq\('id', id\)/,
		'updateEvent must scope the update to the single event id — never an unfiltered write.',
	);
	assert.match(
		body,
		/if \(error\) throw error;/,
		'updateEvent must throw on a DB error, not swallow it.',
	);
});

test('eventHasAthleticData is fail-safe: an unknown / errored read returns true (warn when unsure)', () => {
	// Reason: the editor uses this to decide whether to warn before switching
	// an athletic event to a non-athletic category (which orphans its
	// leaderboard + race rows, issue #335). The guard must fail SAFE — if the
	// results/sessions count can't be read (RLS, network, throw), it must
	// return true so the warning still fires, never false (which would let the
	// destructive switch through silently).
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function eventHasAthleticData');
	assert.ok(start >= 0, 'Could not locate eventHasAthleticData — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
	assert.match(
		body,
		/if \(resultsRes\.error \|\| sessionsRes\.error\) return true;/,
		'eventHasAthleticData must return true when either count read errors.',
	);
	assert.match(
		body,
		/catch \{\s*return true;\s*\}/,
		'eventHasAthleticData must return true on a thrown read (fail-safe warn).',
	);
	assert.match(
		body,
		/event_results[\s\S]*race_sessions/,
		'eventHasAthleticData must check both event_results and race_sessions.',
	);
});

test('/live/[id] hydrateBacklog fetches newest-first + capped, then replays reversed', () => {
	// Reason: hydrateBacklog seeded the spectator trace with EVERY
	// live_run_pings row for the run, ordered oldest-first and with no
	// `.limit()` (issue #334). Over 48h retention @ ~5s cadence a long ultra
	// broadcast accumulates ~34.5k rows, so either the anon share-link load
	// downloads + `pushPing`s tens of thousands of rows, or a PostgREST row
	// cap returns the OLDEST 1000 and freezes the spectator near the run
	// start with a gap. It must mirror `fetchRecentRacePings`: order
	// descending, `.limit(1000)`, then replay reversed so the NEWEST ping is
	// the last one pushed and wins the trace/pan — never regress to an
	// ascending, unlimited scan.
	const source = read('src/routes/live/[id]/+page.svelte');
	const start = source.indexOf('async function hydrateBacklog');
	assert.ok(start >= 0, 'Could not locate hydrateBacklog — rename?');
	const next = source.indexOf('\n\tfunction subscribeLive', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
	// Isolate the Supabase-Realtime fallback query (the Go-hub branch above
	// it returns early before this fetch).
	const queryStart = body.indexOf(".from('live_run_pings')");
	assert.ok(queryStart >= 0, 'hydrateBacklog must still read live_run_pings.');
	const query = body.slice(queryStart);
	assert.match(
		query,
		/\.order\('at',\s*\{\s*ascending:\s*false\s*\}\)/,
		'The backlog fetch must be newest-first — an ascending fetch surfaces the OLDEST rows under a row cap (issue #334).',
	);
	assert.match(
		query,
		/\.limit\(1000\)/,
		'The backlog fetch must cap at 1000 rows — mirror fetchRecentRacePings; an unbounded fetch ships ~34.5k rows on an anon load (issue #334).',
	);
	assert.doesNotMatch(
		query,
		/ascending:\s*true/,
		'The backlog fetch must not order ascending (issue #334 regression).',
	);
	// Descending rows must be replayed in reverse so the last pushPing is the
	// newest ping (matches the /live/event replay).
	assert.match(
		body,
		/for\s*\(\s*let i = rows\.length - 1;\s*i >= 0;\s*i--\s*\)\s*pushPing\(rows\[i\]\)/,
		'Newest-first rows must be replayed reversed so the newest ping wins the trace.',
	);
});

test('computeGlobalSegmentEffortsForRun bounds its gate and its fetch by ONE shared constant', () => {
	// Reason: the rescore gate compares an UNCAPPED count(*) of the active
	// catalogue against a stamp written from a CAPPED fetch. If the gate's
	// clamp and the fetch's `.limit()` are separate literals they drift, and
	// once the catalogue passes the fetch cap the stamp saturates —
	// `activeCount > scored` is then permanently true and every run re-scores
	// on EVERY view forever, a net pessimisation over having no gate at all
	// (same heavy fetch, plus a count query and a metadata read + write per
	// view). The only structural defence is that both sides read the same
	// exported constant, so a bare numeric literal here is the bug.
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function computeGlobalSegmentEffortsForRun');
	assert.ok(start >= 0, 'Could not locate computeGlobalSegmentEffortsForRun — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
	assert.match(
		body,
		/fetchGlobalSegmentsWithError\(GLOBAL_SEGMENT_SCORING_LIMIT\)/,
		'The catalogue fetch must be bounded by the shared GLOBAL_SEGMENT_SCORING_LIMIT, not a literal.',
	);
	assert.doesNotMatch(
		body,
		/fetchGlobalSegmentsWithError\(\s*\d+\s*\)/,
		'A numeric literal here drifts from the gate clamp — that is the saturation bug.',
	);
	assert.match(
		source,
		/GLOBAL_SEGMENT_SCORING_LIMIT,?\n\}\s*from '\.\/data_normalise'|GLOBAL_SEGMENT_SCORING_LIMIT,/,
		'data.ts must import the limit from data_normalise (where the gate clamps against it).',
	);
});

test('computeGlobalSegmentEffortsForRun re-reads runs.metadata immediately before the stamp write', () => {
	// Reason: `runs.metadata` is a whole-column jsonb write. The function
	// reads the bag up front to evaluate the rescore gate, then spends
	// seconds fetching the catalogue and running the haversine match before
	// writing the stamp back. Merging the stamp into that stale copy
	// silently reverts any title / notes edit the owner made in the window —
	// the run-detail edit dialog writes the same column. The bag must be
	// re-read immediately before the write, the same read-adjacent-to-write
	// discipline updateRunMetadata follows.
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function computeGlobalSegmentEffortsForRun');
	assert.ok(start >= 0, 'Could not locate computeGlobalSegmentEffortsForRun — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);

	const fetchAt = body.indexOf('fetchGlobalSegmentsWithError(');
	const stampAt = body.indexOf('stampGlobalSegmentsScored(');
	const writeAt = body.indexOf('.update({ metadata: next })');
	assert.ok(fetchAt >= 0 && stampAt >= 0 && writeAt >= 0, 'scoring pass / stamp / write missing');

	// A metadata read must sit between the expensive pass and the write.
	const reads: number[] = [];
	for (let i = body.indexOf(".select('metadata')"); i >= 0; i = body.indexOf(".select('metadata')", i + 1)) {
		reads.push(i);
	}
	assert.ok(
		reads.some((at) => at > fetchAt && at < stampAt),
		"The stamp must be built from a runs.metadata bag re-read AFTER the catalogue fetch — merging the gate's pre-pass copy reverts a concurrent title/notes edit.",
	);

	// …and the stamp must not be fed the gate's pre-pass copy.
	const stampCall = body.slice(stampAt, writeAt);
	assert.doesNotMatch(
		stampCall,
		/\brunMetadata\b/,
		'stampGlobalSegmentsScored must not merge into runMetadata (the pre-pass read) — that is the clobber.',
	);
});

test('saveRun writes elevation_gain_m alongside the metadata key', () => {
	// Reason: migration 20270302_001 promoted total ascent to the first-class
	// `runs.elevation_gain_m` column because the vert challenge aggregate sums
	// BASE columns, not the jsonb bag — its contract is "writers populate both".
	// saveRun is the ONLY writer of elevation on any platform, and it wrote the
	// metadata key alone, so every vert challenge board summed
	// coalesce(elevation_gain_m, 0) over nulls and sat at 0 m forever.
	// Keep BOTH writes: recap's Dart twin still reads metadata.elevation_m, so
	// setting the column without the key would open a web/mobile divergence.
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function saveRun(input');
	assert.ok(start >= 0, 'Could not locate saveRun — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
	assert.match(
		body,
		/row\.elevation_gain_m = input\.elevation_m/,
		'saveRun must set the promoted elevation_gain_m column'
	);
	assert.match(
		body,
		/mergedMetadata\[METADATA_KEYS\.elevation_m\] = input\.elevation_m/,
		'saveRun must keep writing metadata.elevation_m for the readers that use it'
	);
});

test('the Strava ZIP importer lands embedded bests like the Garmin one', () => {
	// Reason: refresh_personal_records_for_user reads the promoted fastest-window
	// columns (fastest_5k_s etc.), which only arrive via saveRun's embedded_bests.
	// garmin-zip computes them; strava-zip did not, so a migrating user's 30 km
	// long run never yielded the 19:30 5K hiding inside its track and five years
	// of imported history produced zero embedded bests.
	const source = read('src/lib/integrations/strava-zip.ts');
	assert.match(
		source,
		/embedded_bests: computeEmbeddedBests\(track\)/,
		'strava-zip must pass embedded_bests when it parsed a track'
	);
});

test('fetchGymWorkouts windows by date server-side, the way its run sibling does', () => {
	// Reason: fetchGymWorkoutsWithError used to take a `limit` and nothing else,
	// so /nutrition pulled the newest N sessions and filtered them in the
	// browser. A diary day older than the caller's N most recent lifts then
	// contributed no gym calories to that day's exercise add-on — an under-read
	// indistinguishable from "the lift isn't logged yet" (decisions.md § 591
	// shipped it as a stated limitation; § 597 closed it). The bounds must stay
	// PostgREST filters: a timestamptz comparison in the database is the real
	// one, where a string compare of the `+00:00` Postgres rendering against a
	// `…Z` bound drops the row landing exactly on local midnight.
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function fetchGymWorkoutsWithError');
	assert.ok(start >= 0, 'Could not locate fetchGymWorkoutsWithError — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
	assert.match(
		body,
		/\.gte\('started_at',\s*opts\.startedAtFrom\)/,
		'fetchGymWorkoutsWithError must apply startedAtFrom as an inclusive .gte, like fetchRuns.'
	);
	assert.match(
		body,
		/\.lt\('started_at',\s*opts\.startedAtBefore\)/,
		'fetchGymWorkoutsWithError must apply startedAtBefore as an exclusive .lt, like fetchRuns.'
	);

	// And /nutrition must hand it the viewed day's window rather than a bare
	// row cap — the whole point of the parameters.
	const page = read('src/routes/nutrition/+page.svelte');
	assert.match(
		page,
		/fetchGymWorkouts\(\{\s*startedAtFrom: dayWindow\.startIso,\s*startedAtBefore: dayWindow\.endIso,?\s*\}\)/,
		'/nutrition must window the gym fetch by the viewed day, not pull the newest N.'
	);
	assert.doesNotMatch(
		page,
		/GYM_FETCH_LIMIT/,
		'the newest-N cap is what the window replaces; keeping it re-creates the under-read.'
	);
});
