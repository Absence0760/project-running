// Source-level guards for core/data.ts read/write invariants that can't
// be behaviourally unit-tested without a live Supabase stack (these
// functions call the `supabase` singleton directly). Each test reads a
// source file as text and pins a security / data-integrity property with
// a reason a future editor can read before deciding it's safe to break.
//
// Runs with cwd = apps/web (the `test:unit` script), so `read` resolves
// cwd-relative paths — same convention as privacy_guards.test.ts.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

import { stripComments } from './strip_comments';
// Type-only, so nothing in `data.ts` (the supabase singleton, `$env/static/public`)
// is evaluated when this file runs under `tsx --test`.
import type { PeriodSummaryRun } from './data';

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
	// Anchored on the whole tuple, not its first line: since § 1330 the
	// constant is a multi-line `as const satisfies RunColumns` array, so
	// reading one line proved nothing about what it names.
	const tuple = /const PERIOD_SUMMARY_RUN_COLUMNS = \[([^\]]*)\]/.exec(source);
	assert.ok(tuple, 'PERIOD_SUMMARY_RUN_COLUMNS must be a column tuple — re-anchor.');
	assert.doesNotMatch(
		tuple[1],
		/[*]|metadata/,
		'PERIOD_SUMMARY_RUN_COLUMNS must be an explicit column list, never `*` ' +
			'and never the metadata jsonb bag the drilldown does not read.',
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
	//
	// The COLUMN SET itself is no longer declared here: `routes/route_list_columns.ts`
	// owns it and derives both the select string and `RouteListItem` from one
	// tuple, and its own suite pins the contents — including a compile-time
	// proof that `publicRouteListFill` covers exactly the difference between
	// the two lists. What this guard still owns is the QUERIES: that they
	// enumerate those constants rather than reaching for `select('*')` again.
	const source = read('src/lib/core/data.ts');

	assert.match(
		source,
		/import \{[^;]*\bROUTE_LIST_COLS\b[^;]*\bPUBLIC_ROUTE_LIST_COLS\b[^;]*\} from '\.\.\/routes\/route_list_columns'/,
		'core/data.ts must take both column lists from routes/route_list_columns — a local copy is the drift the module exists to close.',
	);

	// Anchored on the NEXT top-level export rather than on the first `\n}`,
	// which is the idiom the guards further down this file use. The lazy
	// brace form read the whole body until the return type became a
	// multi-line object literal, at which point `\n}> {` closed the match on
	// the SIGNATURE and every assertion below was made against it.
	const start = source.indexOf('export async function fetchRoutesWithError(');
	assert.ok(start >= 0, 'Could not locate fetchRoutesWithError — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
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
		'_runFromRow (read) must set routeId: r.routeId.',
	);
	// The write half moved: runRowFromRun in core_models is now the only
	// place a Run becomes a runs row, so the link is carried there and the
	// writers are checked for delegating to it rather than for the literal.
	const shaper = read('../../packages/core_models/lib/src/run_row_shape.dart');
	assert.match(
		shaper,
		/routeId:\s*run\.routeId/,
		'runRowFromRun must set routeId: run.routeId — omitting it re-writes route_id = null on upsert.',
	);
	for (const writer of ['saveRun', 'saveRunsBatch']) {
		const start = source.search(new RegExp(`Future<[\\w<>, ]*>\\s+${writer}\\(`));
		assert.ok(start >= 0, `Could not locate ${writer} in api_client.dart — rename?`);
		assert.ok(
			source.slice(start, start + 4000).includes('runRowFromRun('),
			`${writer} must build its row through runRowFromRun, or route_id stops round-tripping.`,
		);
	}
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

test('deleteNotifications is one delete_notifications RPC call, guards empty, surfaces errors', () => {
	// Reason: bulk-dismissing a collapsed group used to await
	// deleteNotification(id) in a for-loop — one DELETE per member (issue
	// #350). Batching it into `.in('id', ids)` fixed the N+1 and inherited a
	// worse failure: PostgREST serialises an `in` filter into the request
	// URL, so a large dismiss is at the mercy of the gateway's request-line
	// budget — a 414 refusal on the local stack past roughly 200 ids, an
	// empty 200 on the gateway decisions § 653 observed. Chunking to dodge
	// that bound is not the fix either; it trades the failure for a partial
	// dismiss, and the undo offer is already spent by the time chunk 3 of 5
	// fails.
	//
	// The array rides the RPC's POST body, which has no such bound, so the
	// whole dismiss is ONE statement in ONE transaction (migration
	// 20270529_001). That atomicity is what this file can observe: a single
	// awaited call with the full id list, never a loop and never a re-chunk.
	const source = read('src/lib/core/data.ts');
	const fnMatch = source.match(/export async function deleteNotifications[\s\S]*?\n}/);
	assert.ok(fnMatch, 'Could not locate deleteNotifications — rename?');
	const body = fnMatch![0];
	assert.match(
		body,
		/supabase\.rpc\('delete_notifications', \{ p_ids: ids \}\)/,
		'deleteNotifications must hand the whole id list to the delete_notifications RPC — that is what makes the dismiss one transaction.',
	);
	assert.doesNotMatch(
		body,
		/\.in\(/,
		'deleteNotifications must not go back to an `in` filter — past the gateway request-line budget it fails, and which way it fails is a property of the deployment (decisions § 653).',
	);
	assert.doesNotMatch(
		body,
		/for \(|\.map\(|while \(|chunk/i,
		'deleteNotifications must not loop or chunk — either shape can leave the dismiss partial, which is the whole reason the RPC exists.',
	);
	assert.equal(
		(body.match(/await /g) ?? []).length,
		1,
		'deleteNotifications must await exactly one call — a second round-trip is a second transaction.',
	);
	assert.match(
		body,
		/if \(ids\.length === 0\) return;/,
		'deleteNotifications must short-circuit an empty id list.',
	);
	assert.match(
		body,
		/if \(error\) throw error;/,
		'deleteNotifications must throw the supabase error — a swallowed failure leaves the row gone from the UI but present in the DB. The RPC also RAISES past its 1000-id cap rather than truncating, and that refusal must reach the caller.',
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

test('the profile-join fetchers chunk `.in()` so >~100 members are not lost', () => {
	// Reason: PostgREST serialises `.in('id', ids)` into the request URL.
	// A club / event with more than ~100 members overflows the gateway's
	// request-line budget and the profile-join leg is lost — every
	// display_name/avatar_url degrades to a placeholder, and which way the
	// gateway refuses is a property of the deployment (decisions § 653,
	// issue #325). The fix routes every such leg through fetchProfilesByIds,
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

test('the exercise-calorie surfaces decide day membership by instant, never by string', () => {
	// Reason: Postgres renders a timestamptz as `2026-08-13T04:00:00+00:00`
	// while a JS bound is built as `…T04:00:00.000Z`. Those are the same moment,
	// but '+' sorts below '.', so a lexicographic compare drops a row landing
	// EXACTLY on a local-midnight boundary — which for a day window is precisely
	// the row most likely to be there (decisions.md § 591). Three surfaces feed
	// exerciseCaloriesForDay: /nutrition and /nutrition/targets window the fetch
	// server-side (a real timestamptz comparison), /dashboard cannot — its runs
	// and gym reads are the shared batch a dozen cards consume — so it filters
	// through isWithinWindow. None of them may go back to `iso >= startIso`.
	const targets = read('src/routes/nutrition/targets/+page.svelte');
	assert.match(
		targets,
		/fetchRuns\(\{\s*startedAtFrom: dayWindow\.startIso,\s*startedAtBefore: dayWindow\.endIso,?\s*\}\)/,
		'/nutrition/targets must window its run fetch by the day, not filter the newest N.'
	);
	assert.match(
		targets,
		/fetchGymWorkouts\(\{\s*startedAtFrom: dayWindow\.startIso,\s*startedAtBefore: dayWindow\.endIso,?\s*\}\)/,
		'/nutrition/targets must window its gym fetch by the day too.'
	);
	assert.match(
		targets,
		/diaryWindow\(isoDateOf\(new Date\(\)\)\)/,
		'the window must come from diaryWindow, which steps the calendar (a DST day is 23 or 25 h).'
	);

	const dashboard = read('src/routes/dashboard/+page.svelte');
	assert.match(
		dashboard,
		/runs\.filter\(\(r\) => isWithinWindow\(r\.started_at, today\)\)/,
		"/dashboard's today filter must compare instants via isWithinWindow."
	);
	assert.match(
		dashboard,
		/gymWorkouts\.filter\(\(w\) => isWithinWindow\(w\.started_at, today\)\)/,
		"/dashboard's today gym filter must compare instants via isWithinWindow."
	);

	// The dashboard's own window is built from the calendar, not from a 24 h
	// step — that is the § 589 half of the same day bug. (Its unrelated rolling
	// N-day cutoffs are `Math.round`ed and unaffected, so this is scoped to the
	// nutrition read rather than grepping the whole file.)
	const nutritionRead = dashboard.slice(
		dashboard.indexOf('async function loadTodaysNutrition'),
		dashboard.indexOf('function applyDashboardSettings')
	);
	assert.match(
		nutritionRead,
		/new Date\(day\.getFullYear\(\), day\.getMonth\(\), day\.getDate\(\) \+ 1\)/,
		"/dashboard's tomorrow bound must step the calendar, not add 24 h (decisions § 589)."
	);
	assert.doesNotMatch(
		nutritionRead,
		/86_?400_?000/,
		'a local day is 23 or 25 hours across a DST transition (decisions § 589).'
	);

	for (const [name, source] of [
		['/nutrition', read('src/routes/nutrition/+page.svelte')],
		['/nutrition/targets', targets],
		['/dashboard', nutritionRead],
	] as const) {
		assert.doesNotMatch(
			source,
			/const isToday = \(iso: string\)/,
			`${name} must not re-introduce the string-compare isToday predicate.`
		);
	}
});
test('setEventPricing names the one non-partial arbiter and keeps a single branch', () => {
	// Reason: event_pricing shipped with two PARTIAL unique indexes, and
	// Postgres only infers a partial index as an ON CONFLICT arbiter when the
	// statement carries a matching WHERE clause — which PostgREST never emits.
	// Every call raised 42P10, so no event could ever be priced and the whole
	// paid-registration rail was unreachable (decisions §580). Migration
	// 20270518_001 replaced both with one non-partial `nulls not distinct`
	// index on (event_id, instance_start); the caller must name exactly that
	// pair. Naming `event_id` alone — the old series branch — is the specific
	// regression that reintroduces 42P10, because no index is keyed on it.
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function setEventPricing');
	assert.ok(start >= 0, 'Could not locate setEventPricing — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);

	assert.match(
		body,
		/onConflict:\s*'event_id,instance_start'/,
		'setEventPricing must arbitrate on (event_id, instance_start) — the only unique on the table.'
	);
	assert.doesNotMatch(
		body,
		/onConflict:\s*'event_id'/,
		"the 'event_id' branch names no index and raises 42P10 — the arbiter is non-partial, so one branch covers both shapes."
	);
	// A NULL instance_start is the series price. Coercing it away (or dropping
	// the key) would make every series write land as a per-instance override.
	assert.match(
		body,
		/instance_start:\s*input\.instance_start\s*\?\?\s*null/,
		'setEventPricing must send instance_start (null = the series price), not omit it.'
	);
});

test('fetchGymRoutineHistory aggregates on the server, never re-windows gym_workouts', () => {
	// Reason: the routine-history panel used to read up to 500 gym_workouts
	// rows carrying `metadata.routine_id` and reduce them client-side just to
	// show a count. A count is an aggregate — an unbounded PostgREST select
	// truncates at db.max-rows and still answers 200, so any client window
	// silently under-reports a lifter who has run one routine for years. The
	// read must stay on the gym_routine_history RPC; a `.from(gym_workouts)`
	// select with a `.limit()` here is the regression.
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function fetchGymRoutineHistory');
	assert.ok(start >= 0, 'Could not locate fetchGymRoutineHistory — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
	assert.match(
		body,
		/supabase\.rpc\('gym_routine_history'/,
		'fetchGymRoutineHistory must read the server-side aggregate RPC.'
	);
	assert.doesNotMatch(
		body,
		/\.from\(/,
		'fetchGymRoutineHistory must not fall back to a windowed gym_workouts select.'
	);
	assert.match(
		body,
		/if \(error\) throw error;/,
		'a failed read must throw so the panel offers a retry — never an empty history.'
	);
	// The panel asks for exactly the rows it lists, and reads the count off the
	// aggregate rather than off the page it renders.
	const panel = read('src/lib/components/GymRoutineHistory.svelte');
	assert.match(
		panel,
		/fetchGymRoutineHistory\(routineId, RECENT_LIMIT\)/,
		'the panel must bound its page explicitly, not take whatever arrives.'
	);
	assert.doesNotMatch(
		panel,
		/recentSessions\.length/,
		'the count shown must be the aggregate sessionCount, never the bounded page length.'
	);
});

test('the safety-contact list + remove are owner-scoped on BOTH clients, not left to RLS', () => {
	// Reason: `safety_contacts` carries FOUR permissive policies, not two —
	// "owner read"/"owner delete" (owner_id = auth.uid()) AND "linked contact
	// read"/"linked contact delete" (contact_user_id = auth.uid()), both from
	// migration 20261218_001 and both still present after 20270416_001's
	// initplan wrap. Permissive policies OR, so an unfiltered select returns
	// the UNION: your contacts plus every relationship in which someone else
	// named YOU and you confirmed — rendered as your own list, under your own
	// email address, with a Remove button. That button was not a no-op: the
	// linked-contact DELETE policy let it through, so pressing it stripped the
	// OTHER person's emergency contact. RLS is a security boundary (what you
	// MAY read), never a query specification (what you WANT) — both clients
	// must say `owner_id` out loud. Withdrawing from a relationship you are the
	// contact of is declineSafetyRequest / decline_safety_contact.
	const web = read('src/lib/core/data.ts');
	const webFetchStart = web.indexOf('export async function fetchMySafetyContacts');
	assert.ok(webFetchStart >= 0, 'Could not locate fetchMySafetyContacts — rename?');
	const webFetch = web.slice(webFetchStart, web.indexOf('\nexport ', webFetchStart + 1));
	assert.match(
		webFetch,
		/\.eq\('owner_id',\s*userId\)/,
		'fetchMySafetyContacts must filter owner_id — RLS alone returns the contact-of union.'
	);
	assert.match(
		webFetch,
		/if \(!userId\) return \{ contacts: \[\], error: /,
		'a signed-out read must report, never render as "you have no emergency contacts".'
	);

	const webRemoveStart = web.indexOf('export async function removeSafetyContact');
	assert.ok(webRemoveStart >= 0, 'Could not locate removeSafetyContact — rename?');
	const webRemove = web.slice(webRemoveStart, web.indexOf('\nexport ', webRemoveStart + 1));
	assert.match(
		webRemove,
		/\.eq\('owner_id',\s*userId\)/,
		'removeSafetyContact must scope the delete to owner_id — an id-only delete reaches ' +
			"a row naming the caller as someone else's contact and deletes it."
	);

	// Mobile runs the same two queries against the same policies.
	const dart = read('../../packages/api_client/lib/src/api_client.dart');
	const dartFetchStart = dart.indexOf('Future<List<SafetyContact>> fetchMySafetyContacts(');
	assert.ok(dartFetchStart >= 0, 'Could not locate the Dart fetchMySafetyContacts — rename?');
	const dartFetch = dart.slice(dartFetchStart, dart.indexOf('\n  /// ', dartFetchStart + 1));
	assert.match(
		dartFetch,
		/\.eq\(SafetyContactRow\.colOwnerId,\s*userId\)/,
		'the Dart list read must filter owner_id for the same reason the web one does.'
	);

	const dartRemoveStart = dart.indexOf('Future<void> removeSafetyContact(');
	assert.ok(dartRemoveStart >= 0, 'Could not locate the Dart removeSafetyContact — rename?');
	const dartRemove = dart.slice(dartRemoveStart, dart.indexOf('\n  /// ', dartRemoveStart + 1));
	assert.match(
		dartRemove,
		/\.eq\(SafetyContactRow\.colOwnerId,\s*userId\)/,
		'the Dart delete must scope to owner_id — the linked-contact DELETE policy is permissive.'
	);
});

test('the contact-of section reads the OTHER half deliberately, and withdraws by decline', () => {
	// Reason: §720 scoped both clients' list read to `owner_id`, which is
	// exactly the rows this section needs — so it has to ask for the other
	// half by name. The linked-contact SELECT policy already permits the
	// query; nothing about it may lean on RLS to supply the predicate.
	// And the action on such a row is `decline_safety_contact`, NOT
	// `removeSafetyContact`: the latter is owner-scoped and would match no
	// row here, so a "withdraw" button wired to it toasts success while the
	// runner's contact list is untouched — the failure mode that reads as
	// working, which is the worst kind on a consent surface.
	const web = read('src/lib/core/data.ts');
	const start = web.indexOf('export async function fetchSafetyContactOf');
	assert.ok(start >= 0, 'Could not locate fetchSafetyContactOf — rename?');
	const body = web.slice(start, web.indexOf('\nexport ', start + 1));
	assert.match(
		body,
		/\.eq\('contact_user_id',\s*userId\)/,
		'fetchSafetyContactOf must name contact_user_id — RLS is not the scope.'
	);
	assert.match(
		body,
		/if \(!userId\) return \{ relationships: \[\], error: /,
		'a signed-out read must report, never render as "you are nobody\'s contact".'
	);

	const page = read('src/routes/settings/safety/+page.svelte');
	const withdrawAt = page.indexOf('async function handleWithdraw');
	assert.ok(withdrawAt >= 0, 'Could not locate handleWithdraw — rename?');
	const withdraw = page.slice(withdrawAt, page.indexOf('\n\t}', withdrawAt));
	assert.match(
		withdraw,
		/declineSafetyRequest\(rel\.id\)/,
		'withdrawing from a relationship you are the CONTACT of is decline_safety_contact.'
	);
	assert.doesNotMatch(
		withdraw,
		/removeSafetyContact/,
		'removeSafetyContact is owner-scoped — it silently matches nothing on a contact-of row.'
	);
});

test('every race-import availability probe asks the results leg, not the listings sync', () => {
	// Reason: a card that offers an IMPORT has to ask the leg that would run.
	// The two Edge Functions read different credentials — the sync walks an
	// upcoming-races feed, the import fetches a finisher list — so a sync
	// verdict is not binding on the import, and RunSignUp's probe asking the
	// sync advertised an import whose very next call could 503 (decisions
	// § 1041 moved every mobile probe; this closes the web half).
	//
	// Derived from RACE_IMPORT_PROBES rather than naming the three functions,
	// so a fourth leg added to the map is read here the moment it exists.
	// Blanked, or the next function's doc comment naming the sync it does NOT
	// use is read as a use of it.
	const source = stripComments(read('src/lib/core/data.ts'));
	const map = source.slice(
		source.indexOf('const RACE_IMPORT_PROBES'),
		source.indexOf('export function isRaceImportProviderConfigured')
	);
	assert.ok(map.length > 0, 'RACE_IMPORT_PROBES moved — re-anchor this guard');
	const entries = [...map.matchAll(/^\t(\w+):\s*(\w+)/gm)].map((m) => ({
		leg: m[1],
		fn: m[2]
	}));

	// Population: an empty parse would satisfy every assertion below.
	assert.ok(entries.length >= 3, `parsed only ${entries.length} probes — map reshaped?`);

	for (const { leg, fn } of entries) {
		const start = source.indexOf(`export async function ${fn}(`);
		assert.ok(start >= 0, `${fn} is not an exported function in data.ts`);
		const next = source.indexOf('\nexport ', start + 1);
		const body = source.slice(start, next > start ? next : undefined);
		assert.match(
			body,
			/invoke\('race-results-import'/,
			`${fn} must probe race-results-import — the listings sync gates a different credential`
		);
		assert.match(
			body,
			/probe:\s*true/,
			`${fn} must pass probe: true — without it the call performs a real import`
		);
		assert.match(
			body,
			new RegExp(`provider:\\s*'${leg}'`),
			`${fn} is registered under '${leg}' but does not name that provider`
		);
		assert.ok(
			!body.includes('race-listings-sync'),
			`${fn} still invokes race-listings-sync`
		);
		// A probe asks one question and one answer says yes. Grading the status
		// instead read a 401 (raised before the function touches a credential)
		// and a 400 unknown_provider (a leg that does not exist) as proof the
		// card was live — decisions § 1067.
		assert.match(
			body,
			/return probeSaysConfigured\(error\);/,
			`${fn} must report through probeSaysConfigured — any failure at all leaves the question unanswered`
		);
	}
});

test('every data.ts RPC names its function as a checked literal, never through a cast', () => {
	// Reason: `database.types.ts` is generated so that `supabase.rpc()` can
	// check the function name AND the argument object against the deployed
	// routine. Casting the name (`'foo' as never`) turns that off for the whole
	// call — the params cast goes with it — so a renamed function, a dropped
	// parameter or a mistyped argument would reach production as a runtime 404
	// / 400 from PostgREST rather than as a build failure. The going-count call
	// carried both casts for months after the migration that made them
	// unnecessary landed; the comment excusing them named a regeneration that
	// had already happened.
	//
	// The check is not live yet: `core/supabase.ts` calls `createBrowserClient`
	// with no `Database` generic, which defaults to `any`, so today every
	// `.rpc()` and `.from()` in this file is unchecked whatever it is written
	// as. That is filed separately, measured. This guard is what keeps the call
	// sites in the shape the generic will check the day it is passed — a cast
	// survives it silently.
	const source = stripComments(read('src/lib/core/data.ts'));
	const calls = [...source.matchAll(/\.rpc\(\s*([^,)]+)/g)].map((m) => m[1].trim());

	// Population: an empty parse would satisfy the assertion below.
	assert.ok(calls.length >= 10, `parsed only ${calls.length} rpc calls — reshaped?`);

	for (const name of calls) {
		assert.match(
			name,
			/^'[a-z0-9_]+'$/,
			`.rpc(${name}) does not name its function as a bare string literal — a cast or a computed name disables the generated type check`
		);
	}
});

test('fetchUpcomingEvents windows the candidate set server-side, not the club\'s oldest 200', () => {
	// Reason: the read is `order('starts_at', ascending).limit(200)` over every
	// event the club has ever had. Without a server-side predicate that is the
	// OLDEST 200 rows — a weekly series accumulates 200 finished one-offs in
	// four years — so every future event falls past the cap and the club's
	// Events tab reports "no upcoming events" permanently, getting worse as the
	// club gets older. The client-side `next_instance_start >= now` filter
	// cannot recover a row the query never returned. Same shape
	// `fetchRunsForDashboard` and `fetchWeeklyMileage` already carry guards for.
	//
	// The predicate must stay a SUPERSET of what is live: a recurring series
	// with no until-date has to be admitted (its end may be a `recurrence_count`
	// only `nextLiveInstance` can evaluate), or a count-limited series
	// disappears from the tab while it is still running.
	const source = stripComments(read('src/lib/core/data.ts'));
	const start = source.indexOf('export async function fetchUpcomingEvents');
	assert.ok(start >= 0, 'fetchUpcomingEvents moved — re-anchor this guard');
	const body = source.slice(start, source.indexOf('\nexport ', start + 1));

	assert.match(
		body,
		/\.or\(/,
		'the candidate set must be narrowed server-side — an ascending cap over the whole history windows the wrong end of it',
	);
	assert.match(
		body,
		/starts_at\.gte\.\$\{nowIso\}/,
		'a one-off is a candidate only when it has not happened yet',
	);
	assert.match(
		body,
		/recurrence_freq\.not\.is\.null,recurrence_until\.is\.null/,
		'a recurring series with no until-date must be admitted — its end may be a recurrence_count',
	);
	assert.match(
		body,
		/recurrence_freq\.not\.is\.null,recurrence_until\.gte\.\$\{nowIso\}/,
		'and one whose until-date is still ahead',
	);
	// Nesting depth: a PostgREST filter this build cannot parse 400s into the
	// discarded `error` and empties the tab exactly as the bug did, so the
	// clauses stay at the one `and(...)`-inside-`or=` depth the file already
	// exercises rather than nesting a second `or(` inside an `and(`.
	assert.doesNotMatch(
		body,
		/and\([^)]*or\(/,
		'no `or(` nested inside an `and(` — that depth is unexercised in this file',
	);
});

test('every "answered empty" read that a stranger can hit reports the failure separately', () => {
	// Reason: supabase-js RESOLVES `{data: null, error}` rather than throwing,
	// so `const { data } = await …` turns a transport fault, an RLS refusal and
	// a genuinely absent row into one indistinguishable null. Each of these
	// four then rendered a confident falsehood: "Run not found" to every
	// recipient of a shared link; a routes list with the runner's bookmarks
	// silently missing and `error: null` beside it; a club owner stripped of
	// their admin controls and offered "Join"; and a fundraiser page telling a
	// donor the campaign they followed a link to does not exist.
	//
	// `fetchRunById` and `fetchClubBySlug` were each fixed for exactly this and
	// carry comments saying so. These are the same collapse elsewhere.
	const source = stripComments(read('src/lib/core/data.ts'));
	const bodyOf = (name: string): string => {
		const start = source.indexOf(`export async function ${name}(`);
		assert.ok(start >= 0, `${name} moved — re-anchor this guard`);
		const next = source.indexOf('\nexport ', start + 1);
		return source.slice(start, next > start ? next : undefined);
	};

	// The public run read a stranger hits. PGRST116 is the only "no row".
	const publicRun = bodyOf('fetchPublicRun');
	assert.match(
		publicRun,
		/Promise<\{ run: Run \| null; error: string \| null \}>/,
		'fetchPublicRun must report the failure alongside the row, like fetchRunById',
	);
	assert.match(
		publicRun,
		/error\.code !== 'PGRST116'/,
		'only "no rows matched" may read as a genuine miss',
	);
	assert.doesNotMatch(
		publicRun,
		/const \{ data \} =/,
		'binding data alone is the defect — the error must be read',
	);

	// The entitlement read behind /runs/[id]'s non-owner branch.
	const attribution = bodyOf('fetchPublicRunAttribution');
	assert.match(
		attribution,
		/Promise<\{ attribution: PublicRunAttribution \| null; error: string \| null \}>/,
		'fetchPublicRunAttribution must report its failure — a caller cannot otherwise tell "not yours" from "unknown"',
	);
	assert.match(
		attribution,
		/if \(error\) return \{ attribution: null, error: error\.message \};/,
		'the public_runs read is the entitlement; its failure is not a non-entitlement',
	);

	// The saved half of "My routes" — three reads, none of which was checked.
	const routes = bodyOf('fetchRoutesWithError');
	assert.ok(
		routes.indexOf('if (savedIdsRes.error)') >= 0 &&
			routes.indexOf('if (savedIdsRes.error)') < routes.indexOf('savedIdsRes.data ?? []'),
		'the saved-id read must be checked BEFORE its rows are defaulted to [] — a failed read is not an empty bookmark list',
	);
	assert.match(
		routes,
		/savedBaseRes\.error \?\? savedPublicRes\.error/,
		'both saved-body reads must be checked — each carries a whole class of bookmark',
	);

	// Fundraisers: the two sibling reads that swallowed where the third throws.
	for (const fn of ['fetchFundraiserForRun', 'fetchFundraiserForEvent']) {
		const body = bodyOf(fn);
		assert.doesNotMatch(
			body,
			/if \(error \|\| !data\) return null;/,
			`${fn} must not collapse a failed read into "no campaign" — fetchFundraiserById throws and says why`,
		);
		assert.match(body, /if \(error\) throw error;/, `${fn} must throw on a failed read`);
	}
});

test('enrichClubs reports a failed membership read instead of asserting non-membership', () => {
	// Reason: `viewer_role` decides whether an owner sees their admin controls
	// and whether a member is offered "Join". It is derived from one
	// club_members read whose error was discarded, so a blip logged every
	// member out of their own club while the enclosing `{ clubs, error }` said
	// `error: null`. The irony is local: `fetchClubBySlug`'s doc comment
	// describes precisely this collapse for the club row, one call above the
	// membership row that still had it.
	const source = stripComments(read('src/lib/core/data.ts'));
	const start = source.indexOf('async function enrichClubs(');
	assert.ok(start >= 0, 'enrichClubs moved — re-anchor this guard');
	const body = source.slice(start, source.indexOf('\nexport ', start + 1));
	assert.match(
		body,
		/Promise<\{ clubs: ClubWithMeta\[\]; error: string \| null \}>/,
		'enrichClubs must return the failure in the same shape its callers already return',
	);
	assert.match(
		body,
		/if \(rolesRes\.error\)/,
		'the membership read must be checked before any role is asserted',
	);

	// And every caller has to propagate it — three hand the shape straight
	// back, the fourth is the single-club read.
	// Counting call sites is not enough: a caller can keep the call and drop the
	// error (`{ clubs: (await enrichClubs(rows)).clubs, error: null }`), which
	// is the original defect wearing the new shape. Every site must either hand
	// the whole result back or branch on its error.
	const sites = [...source.matchAll(/^.*enrichClubs\(/gm)]
		.map((m) => m[0])
		.filter((line) => !line.includes('async function enrichClubs('));
	assert.equal(
		sites.length,
		4,
		`enrichClubs has ${sites.length} call sites, expected 4 — check the new one propagates the error`,
	);
	for (const line of sites) {
		assert.ok(
			/return (await )?enrichClubs\(/.test(line) ||
				/\? enrichClubs\(/.test(line) ||
				/const \{ clubs: \w+, error: \w+ \} = await enrichClubs\(/.test(line),
			`this enrichClubs call site drops the error rather than propagating it: ${line.trim()}`,
		);
	}
	assert.match(
		source,
		/const \{ clubs: enrichedClubs, error: rolesError \} = await enrichClubs\(\[data\]\);\s*\n\s*if \(rolesError\) return \{ club: null, error: rolesError \};/,
		'fetchClubBySlug must surface a membership-read failure rather than returning the club with no role',
	);
});

test('the exact tallies are counted by the database, never by a page of rows', () => {
	// Reason: `.select()` returns at most the deployment's PostgREST row
	// ceiling and gives NO signal when it truncates, so a tally built by
	// counting returned rows is a count of the page, presented as a count of
	// the set. Two of these sit on a money path and a membership check:
	//
	//  - fetchEventRsvpSummary's own doc says the going/maybe/declined/
	//    waitlisted counts "must stay exact even when the displayed roster is
	//    only its first page", and it then read every attendee row and tallied
	//    them here. Past the ceiling the capacity + waitlist math believes a
	//    full event has room, and the viewer's own row can fall outside the
	//    page — `viewerStatus` reads null and the page re-shows "Register for
	//    £X" to someone who has already paid, burning a Stripe session and a
	//    capacity-holding pending order.
	//  - fetchChallenges / fetchChallengeById lengthed a participants array
	//    for a number that is already a trigger-maintained column on the row
	//    (`challenges.participant_count`, 20270308_001, derived_state.md), and
	//    found the caller's own membership by scanning that same page.
	const source = stripComments(read('src/lib/core/data.ts'));
	const bodyOf = (name: string): string => {
		const start = source.indexOf(`export async function ${name}(`);
		assert.ok(start >= 0, `${name} moved — re-anchor this guard`);
		const next = source.indexOf('\nexport ', start + 1);
		return source.slice(start, next > start ? next : undefined);
	};

	const rsvp = bodyOf('fetchEventRsvpSummary');
	assert.match(
		rsvp,
		/count: 'exact', head: true/,
		'the per-status tallies must be counted server-side',
	);
	assert.doesNotMatch(
		rsvp,
		/summary\.\w+ \+= 1/,
		'tallying returned rows is the defect — the page is not the set',
	);
	assert.match(
		rsvp,
		/\.eq\('user_id', viewerId\)/,
		"the viewer's own status must be its own scoped read, not a scan of a page",
	);

	// Both challenge readers take the count off the cached column.
	for (const fn of ['fetchChallenges', 'fetchChallengeById']) {
		const body = bodyOf(fn);
		assert.match(
			body,
			/participant_count: \([\w.]+ as \{ participant_count\?: number \}\)\.participant_count \?\? 0/,
			`${fn} must read the trigger-maintained challenges.participant_count cache`,
		);
		assert.doesNotMatch(
			body,
			/\(parts \?\? \[\]\)\.length|counts\.set\(/,
			`${fn} must not re-derive the count from a participants page`,
		);
		assert.match(
			body,
			/\.eq\('user_id', userId\)/,
			`${fn} must scope the participants read to the caller`,
		);
	}
});

test('the club slug is derived by the shared helper, never re-spelled here', () => {
	// Reason: `clubs.slug` is persisted and becomes the club's public URL, and
	// the phone derives it too. When both rails spelled out "lower-case, then
	// [^a-z0-9]+ to -" they read as one expression while being two functions —
	// the runtimes' `toLowerCase` disagree at U+0130 — so `İzmir` minted
	// `i-zmir` here and `izmir` on the phone (decisions § 1251 + § 1279). The
	// derivation must stay in `social/club_slug.ts`, whose mirror suite is what
	// pins the two platforms to one answer.
	const source = stripComments(read('src/lib/core/data.ts'));
	assert.match(
		source,
		/import \{[^}]*\bclubSlug\b[^}]*\} from '\.\.\/social\/club_slug'/,
		'core/data.ts must import the shared clubSlug derivation.',
	);
	assert.match(
		source,
		/clubSlug\(input\.name\) \|\| CLUB_SLUG_FALLBACK/,
		'the empty-slug substitute is the shared literal, not a copy of it here.',
	);
	assert.doesNotMatch(
		source,
		/\[\^a-z0-9\]/,
		'core/data.ts must not re-spell the slug character class — call clubSlug.',
	);
	assert.doesNotMatch(
		source,
		/toLowerCase\(\)[\s\S]{0,80}?replace\(/,
		'a lower-case feeding a strip is the slug derivation re-grown; call clubSlug.',
	);
});

/// The three enumerated reads in this file and the row types they are handed
/// back as have to describe the SAME column set, and every name in them has to
/// be one the client is granted.
///
/// Both halves are derived, never restated: the column sets come out of the
/// `.select()` literals in `data.ts`, the type sets out of the `Omit<…Row, …>`
/// overlays in `types.ts` crossed with the generated `database.types.ts`, and
/// the grant out of a replay of every migration. A literal repeated here would
/// be a fourth declaration that agrees until it doesn't ([§ 641]).
function generatedColumns(table: string): Set<string> {
	const types = read('src/lib/database.types.ts');
	const start = types.indexOf(`      ${table}: {`);
	assert.ok(start > 0, `could not locate ${table} in database.types.ts — re-anchor`);
	const row = types.slice(
		types.indexOf('Row: {', start) + 'Row: {'.length,
		types.indexOf('Insert: {', start),
	);
	return new Set(
		row
			.split('\n')
			.map((l) => l.trim())
			.filter((l) => l.includes(':'))
			.map((l) => l.split(':')[0].trim()),
	);
}

/// The keys an `Omit<XRow, 'a' | 'b'> & { a: Narrow }` overlay declares: every
/// generated column, less the omitted ones, plus whatever the intersection
/// puts back. A column omitted and NOT put back is the deliberate withholding
/// this guard is about.
function overlayColumns(alias: string, table: string): Set<string> {
	const src = read('src/lib/types.ts');
	const decl = src.slice(src.indexOf(`export type ${alias} = Omit<`));
	assert.ok(decl.length > 0, `could not locate the ${alias} overlay — re-anchor`);
	const omitEnd = decl.indexOf('> & {');
	const intersectionEnd = decl.indexOf('\n};');
	const omitted = [...decl.slice(0, omitEnd).matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
	const readded = [...decl.slice(omitEnd, intersectionEnd).matchAll(/^\t(\w+)\??:/gm)].map(
		(m) => m[1],
	);
	const keys = generatedColumns(table);
	for (const c of omitted) keys.delete(c);
	for (const c of readded) keys.add(c);
	return keys;
}

/// The columns `authenticated` may SELECT, replayed from every migration in
/// filename order: a bare `revoke select on <t>` clears the set, a
/// `grant select (a, b) on <t>` adds to it, a bare `grant select on <t>` means
/// every column. Column-level REVOKE is deliberately not modelled — it is a
/// no-op while the role holds the table-level grant, which is precisely why
/// `20260723_001` was rewritten into the revoke-then-column-grant shape.
function grantedColumns(table: string): Set<string> | 'all' {
	const dir = '../backend/supabase/migrations';
	let granted: Set<string> | 'all' = 'all';
	for (const f of readdirSync(resolve(dir)).sort()) {
		if (!f.endsWith('.sql')) continue;
		const sql = read(dir, f).replace(/--[^\n]*/g, '');
		const revoke = new RegExp(`revoke\\s+select\\s+on\\s+(?:public\\.)?${table}\\s+from\\b`, 'i');
		if (revoke.test(sql)) granted = new Set();
		const grant = new RegExp(
			`grant\\s+select\\s*(\\(([^)]*)\\))?\\s*on\\s+(?:public\\.)?${table}\\s+to\\b`,
			'gi',
		);
		for (const m of sql.matchAll(grant)) {
			if (!m[2]) {
				granted = 'all';
				continue;
			}
			if (granted === 'all') continue;
			for (const c of m[2].split(',')) granted.add(c.trim());
		}
	}
	return granted;
}

function selectLiteral(constant: string): string[] {
	const source = read('src/lib/core/data.ts');
	const m = source.match(new RegExp(`const ${constant}\\s*=\\s*\\n?\\s*'([^']*)'`));
	assert.ok(m, `could not locate ${constant} in data.ts — re-anchor`);
	return m[1].split(',').map((c) => c.trim());
}

test('the enumerated club / event reads and the row types they are read as name the same columns', () => {
	// Reason: a narrowed select handed back under the table's full row type is
	// `undefined` at runtime behind a type that declares it, with no throw and
	// no error (§ 1294 / § 1327 / § 1329). `routes` shipped that way for eleven
	// columns and `events` for three. Equality in BOTH directions is the point:
	// a column added to the overlay without being added to the projection is
	// the original defect, and one added to the projection without the overlay
	// is a column paid for on the wire and unreadable.
	for (const [constant, alias, table] of [
		['EVENT_SELECT_COLS', 'Event', 'events'],
		['CLUB_SELECT_COLS', 'Club', 'clubs'],
	] as const) {
		assert.deepEqual(
			[...selectLiteral(constant)].sort(),
			[...overlayColumns(alias, table)].sort(),
			`${constant} and the ${alias} overlay describe different column sets`,
		);
	}
});

test('the club roster read and ClubMember name the same columns', () => {
	// Reason: the same claim for the one enumerated read whose column list is
	// written inline rather than as a shared constant. `activity_waiver_ack_at`
	// is left out on purpose — on a public club anyone may read the roster, and
	// when a member signed the liability waiver is not public roster data — so
	// the overlay must not promise it either.
	const source = read('src/lib/core/data.ts');
	const selects = [...source.matchAll(/\.select\('(club_id, user_id, role, status[^']*)'\)/g)].map(
		(m) => m[1].split(',').map((c) => c.trim()),
	);
	assert.equal(selects.length, 2, 'expected the two club_members roster reads — re-anchor');
	const declared = [...overlayColumns('ClubMember', 'club_members')].sort();
	for (const cols of selects) assert.deepEqual([...cols].sort(), declared);
});

test('no enumerated read, and no row type, names a column the client is not granted', () => {
	// Reason: SELECT on `clubs` and `events` is revoked wholesale and re-granted
	// column by column (migration 20260818_001, plus the later per-column
	// grants), so a name outside that set does not read as null — it raises
	// 42501 and the whole query fails. `invite_token`, `location_point`,
	// `host_user_id`, `meet_lat` and `meet_lng` are the withheld five; the
	// precise meet point is reachable only through the member-gated
	// `get_event_meet_point` RPC, and the payout recipient not at all.
	for (const [constant, alias, table] of [
		['EVENT_SELECT_COLS', 'Event', 'events'],
		['CLUB_SELECT_COLS', 'Club', 'clubs'],
	] as const) {
		const granted = grantedColumns(table);
		assert.notEqual(granted, 'all', `${table} SELECT is not column-scoped any more — re-anchor`);
		const allowed = granted as Set<string>;
		for (const c of selectLiteral(constant)) {
			assert.ok(allowed.has(c), `${constant} asks for ${c}, which ${table} does not grant`);
		}
		for (const c of overlayColumns(alias, table)) {
			assert.ok(allowed.has(c), `${alias} declares ${c}, which ${table} does not grant`);
		}
	}
});


// ── Compile-time: a narrowed run read cannot be read for what it did not fetch ──
//
// `svelte-check` is the gate for these, not `tsx --test`: a read of an absent
// field yields `undefined` rather than throwing, so the only assertion that can
// see the defect is one the compiler makes (§ 1294 / § 1330).

/// The period drilldown projects five of `runs`' twenty-four columns. Each of
/// these was a field `Run` promised and the query never fetched. The
/// `@ts-expect-error` is the mutation test: widen the return type back to
/// `Run[]` and every directive here reports unused, which fails the build.
export const periodSummaryWithheldReadsDoNotCompile = (r: PeriodSummaryRun) => [
	// @ts-expect-error — the jsonb bag the drilldown does not read
	r.metadata,
	// @ts-expect-error — not in PERIOD_SUMMARY_RUN_COLUMNS
	r.elevation_gain_m,
	// @ts-expect-error — not in PERIOD_SUMMARY_RUN_COLUMNS
	r.activity_type,
	// @ts-expect-error — not in PERIOD_SUMMARY_RUN_COLUMNS
	r.is_dnf,
	// @ts-expect-error — a lazy Storage download, never a column
	r.track_url,
];

/// The five it does read have to stay readable, or the narrowing has gone too
/// far and the pin above is the only thing still passing.
export const periodSummaryReadsCompile = (r: PeriodSummaryRun) => [
	r.id,
	r.started_at,
	r.distance_m,
	r.duration_s,
	r.source,
];
