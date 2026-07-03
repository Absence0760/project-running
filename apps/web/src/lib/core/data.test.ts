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
