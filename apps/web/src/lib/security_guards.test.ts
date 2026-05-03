// Source-level guards that pin in place the security invariants for
// thumbnail rendering on the web app. Each test reads a source file as
// text and asserts a pattern is present, with a reason a future editor
// can read before deciding it's safe to break.
//
// Mirrors the `thumbnail privacy-zone clipping` group in
// `apps/mobile_android/test/architecture_guards_test.dart` — the two
// rules must stay in lockstep.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('RunTrackPreview routes non-owner fetches through clip-public-track EF', () => {
	// Reason: feed thumbnails are shown to non-owner viewers. The pre-
	// 20260619_001 pattern was "fetchTrackByPath then clipTrackForUser
	// client-side" but that leaked the unclipped blob via direct
	// Storage download. Non-owner thumbnails must now go through
	// fetchClippedTrackForRun (which calls the clip-public-track Edge
	// Function — server-side download + clip). Owners keep the direct
	// path since the per-user-folder Storage policy still gates them.
	const source = read('src/lib/components/RunTrackPreview.svelte');
	assert.match(
		source,
		/fetchClippedTrackForRun/,
		'RunTrackPreview must use fetchClippedTrackForRun for non-owner viewers — direct Storage download leaks the unclipped blob. See decisions §33.',
	);
});

test('feed page passes runId + ownerUserId to RunTrackPreview', () => {
	// Reason: the EF non-owner clip path needs the run id (server
	// resolves track_url + clips inline). Without the prop,
	// RunTrackPreview can't reach the EF and renders a placeholder
	// instead of the clipped polyline.
	const source = read('src/routes/feed/+page.svelte');
	assert.match(
		source,
		/<RunTrackPreview[^>]*runId=/s,
		'Feed page must thread the run id into RunTrackPreview so the clip-public-track EF can resolve it.',
	);
	assert.match(
		source,
		/<RunTrackPreview[^>]*ownerUserId=/s,
		'Feed page must thread the run owner id into RunTrackPreview so the privacy-zone clip kicks in.',
	);
});

test('RunTrackPreview cache is bounded (LRU)', () => {
	// Reason: without the cap a long session through 1000+ runs holds
	// every deserialised track in memory until reload. JS Map preserves
	// insertion order so dropping `keys().next()` evicts the oldest.
	const source = read('src/lib/components/RunTrackPreview.svelte');
	assert.match(
		source,
		/CACHE_MAX/,
		'RunTrackPreview cache must have a bounded size — see the CACHE_MAX constant.',
	);
	assert.match(
		source,
		/CACHE\.keys\(\)\.next\(\)/,
		'LRU eviction must drop the oldest entry when the cache is full.',
	);
});

test('routes/[id] page clips waypoints for non-owner viewers', () => {
	// Reason: pre-prod privacy-zones audit found this surface rendered
	// `<RunMap track={route.waypoints} />` with no clip step. Bookmarked,
	// public, and club routes were leaking the unclipped polyline to
	// non-owners. Must use fetchClippedRouteForViewer (decisions §33).
	const source = read('src/routes/routes/[id]/+page.svelte');
	assert.match(
		source,
		/fetchClippedRouteForViewer/,
		'/routes/[id] must call fetchClippedRouteForViewer for non-owner viewers — direct route.waypoints render leaks the unclipped polyline. See decisions §33.',
	);
	// The renderer must hand displayWaypoints to RunMap, not the raw
	// route.waypoints (which is the unclipped row column for non-owners).
	assert.match(
		source,
		/<RunMap[^>]*track=\{displayWaypoints/s,
		'/routes/[id] must render <RunMap track={displayWaypoints}> rather than route.waypoints — the raw column is the unclipped polyline.',
	);
});

test('routes list + clubs Routes tab use RouteTrackPreview', () => {
	// Reason: same audit. Both list-view surfaces had bare
	// <TrackPreview points={route.waypoints} /> — fine for owned rows
	// but leaks bookmarked / club / public rows. RouteTrackPreview wraps
	// the raw thumbnail with the same lazy clip + cache pattern as
	// RunTrackPreview so non-owner viewers see clipped output.
	const routesList = read('src/routes/routes/+page.svelte');
	assert.match(
		routesList,
		/<RouteTrackPreview/,
		'My Routes list must use <RouteTrackPreview> rather than bare <TrackPreview> — bookmarked others-routes leak otherwise. See decisions §33.',
	);
	const clubsPage = read('src/routes/clubs/[slug]/+page.svelte');
	assert.match(
		clubsPage,
		/<RouteTrackPreview/,
		'Clubs page Routes tab must use <RouteTrackPreview> — club-route thumbnails (other admins / members) need the clip pass for non-owner viewers.',
	);
});

test('RouteTrackPreview routes non-owner fetches through clip_route_for_viewer', () => {
	// Reason: the clip RPC is the only path that returns clipped
	// waypoints without first leaking the row's `waypoints` column to
	// the wire. Owner reads use the row directly; non-owner reads must
	// call fetchClippedRouteForViewer.
	const source = read('src/lib/components/RouteTrackPreview.svelte');
	assert.match(
		source,
		/fetchClippedRouteForViewer/,
		'RouteTrackPreview must use fetchClippedRouteForViewer for non-owner viewers — bare route.waypoints render leaks the unclipped polyline. See decisions §33.',
	);
	assert.match(
		source,
		/CACHE_MAX/,
		'RouteTrackPreview must have a bounded cache — see RunTrackPreview for the LRU shape.',
	);
});

test('fetchClippedRouteForViewer fails closed on RPC error', () => {
	// Reason: same as clipTrackForUser. Returning the input on RPC
	// error would defeat the helper. The empty-input early-return is
	// not relevant here (the helper takes only an id), so we only
	// assert that the error branch returns [].
	const source = read('src/lib/data.ts');
	const fnMatch = source.match(
		/export async function fetchClippedRouteForViewer[\s\S]*?^}/m,
	);
	assert.ok(fnMatch, 'Could not locate fetchClippedRouteForViewer body — rename?');
	const body = fnMatch![0];
	const errBranch = body.match(/if \(error\) \{[\s\S]*?\}/);
	assert.ok(errBranch, 'fetchClippedRouteForViewer must have an explicit error branch');
	assert.match(
		errBranch![0],
		/return \[\];/,
		'fetchClippedRouteForViewer must return [] on RPC failure — see decisions §33.',
	);
});

test('public-runs readers go through the public_runs view', () => {
	// Reason: pre-prod public-rows audit found that `select * from runs
	// where is_public = true` exposes external_id, training-plan-linkage
	// metadata, sync-state metadata, and link-existence to private
	// routes/events. The public_runs view (migration 20260626_001)
	// strips these. Every public-runs reader must read from the view,
	// not the base table.
	const source = read('src/lib/data.ts');

	// Slice the source between two known landmarks per function. Each
	// helper ends well before the next public-export so we can scan a
	// reasonable window. We don't try to perfectly delimit a function
	// body (nested type literals trip a naive `^}` regex); we just need
	// a window that contains the .from() call and nothing else.
	function bodyAfter(needle: string, until: string): string {
		const start = source.indexOf(needle);
		assert.ok(start >= 0, `Could not locate '${needle}' — rename?`);
		const end = source.indexOf(until, start + needle.length);
		assert.ok(
			end > start,
			`Could not locate landmark '${until}' after '${needle}'`,
		);
		return source.slice(start, end);
	}
	const fetchPublicRunBody = bodyAfter(
		'export async function fetchPublicRun(',
		'export async function deleteRun(',
	);
	const fetchFollowingFeedBody = bodyAfter(
		'export async function fetchFollowingFeed(',
		'export async function clipTrackForUser(',
	);
	const fetchPublicRunsByUserBody = bodyAfter(
		'export async function fetchPublicRunsByUser(',
		'// ─────────────────────── Kudos',
	);

	for (const [name, body] of [
		['fetchPublicRun', fetchPublicRunBody],
		['fetchFollowingFeed', fetchFollowingFeedBody],
		['fetchPublicRunsByUser', fetchPublicRunsByUserBody],
	] as const) {
		assert.match(
			body,
			/\.from\(['"]public_runs['"]\)/,
			`${name} must read from the public_runs view rather than the runs table — see decisions §33 and migration 20260626_001.`,
		);
		assert.doesNotMatch(
			body,
			/\.from\(['"]runs['"]\)/,
			`${name} must NOT read from the bare runs table — that path leaks external_id, training-plan-linkage metadata, etc.`,
		);
	}
});

test('clipTrackForUser fails closed on RPC error', () => {
	// Reason: returning the unclipped input on RPC error was the
	// privacy leak this helper exists to prevent. Fail-closed (return
	// []) so a transient outage renders an empty map for non-owner
	// viewers instead of leaking the full track. The empty-input
	// early-return is fine — it returns the empty input which is the
	// same shape as `[]`.
	const source = read('src/lib/data.ts');
	const fnMatch = source.match(
		/export async function clipTrackForUser[\s\S]*?^}/m,
	);
	assert.ok(fnMatch, 'Could not locate clipTrackForUser body — rename?');
	const body = fnMatch![0];
	// The `if (error) { ... }` branch must return [], not points.
	const errBranch = body.match(/if \(error\) \{[\s\S]*?\}/);
	assert.ok(errBranch, 'clipTrackForUser must have an explicit error branch');
	assert.match(
		errBranch![0],
		/return \[\];/,
		'clipTrackForUser must return [] on RPC failure — see decisions §33.',
	);
	assert.doesNotMatch(
		errBranch![0],
		/return points/,
		'clipTrackForUser must not fall back to the input track on RPC error — that is the leak this helper exists to prevent.',
	);
});
