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

test('NotificationsList.removeGroup fires one batched delete, not one per member', () => {
	// Reason: removeGroup awaited remove(row.id) for every member of a
	// collapsed group — N sequential DELETEs (issue #350). It must collect
	// the ids and call the batched deleteNotifications ONCE, keeping the
	// optimistic local removal + per-unread-row unread-count decrement.
	const source = read('src/lib/components/NotificationsList.svelte');
	const fnMatch = source.match(/async function removeGroup[\s\S]*?\n\t}/);
	assert.ok(fnMatch, 'Could not locate removeGroup — rename?');
	const body = fnMatch![0];
	assert.match(
		body,
		/deleteNotifications\(ids\)/,
		'removeGroup must dismiss the whole group with one deleteNotifications(ids) call.',
	);
	assert.doesNotMatch(
		body,
		/remove\(row\.id/,
		'removeGroup must not loop the single-delete remove(row.id) per member — that is the N+1 issue #350 fixed.',
	);
	assert.match(
		body,
		/notificationStore\.decrement\(\)/,
		'removeGroup must keep decrementing the unread badge per removed unread row.',
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
