// Source-level guards pinning the streaks card + run-to-route helper
// wiring. Mirrors the segments_panel_guards pattern.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('Dashboard wires the streak card through the pure helpers', () => {
	// Reason: the streak figures must come from the unit-tested helpers,
	// not an inline reimplementation — computeRunStreaks for the windowed
	// compute, streakCardState for the sub-label decision.
	const source = read('src/routes/dashboard/+page.svelte');
	assert.match(source, /computeRunStreaks/, 'dashboard must call the pure helper');
	assert.match(source, /streakCardState\(/, 'dashboard must derive the card via streakCardState');
	assert.match(source, /class="stat-card" class:streak-active/, 'streak stat card missing');
});

test('Dashboard streak sub-label is served by the all-time RPC, not the window', () => {
	// Reason: computeRunStreaks over the ~2-year fetchRunsForDashboard
	// window under-reports a best streak that ended before the window and
	// truncates one spanning the boundary (decisions §471). The card must
	// fetch run_streaks_for_user (re-fetched per source filter) and render
	// the sub-label from streakCard, never from the windowed runStreaks.
	const source = read('src/routes/dashboard/+page.svelte');
	assert.match(source, /fetchRunStreaks\(/, 'dashboard must fetch the all-time aggregate');
	assert.match(source, /streakCard\.current/, 'current value missing');
	assert.match(source, /streakCard\.sub\.kind === 'best'/, 'best sub-label branch missing');
	assert.doesNotMatch(
		source,
		/runStreaks\.best/,
		'the windowed best must not reach the template — it reads low for a pre-window streak',
	);
});

test('fetchRunStreaks fails closed with null, never a zeroed all-time claim', () => {
	// Reason: a zeroed streak is indistinguishable from a truthful one, so
	// a failed RPC must return null (the card then suppresses the all-time
	// claim) rather than degrade to zeros like fetchRunAllTimeStats does.
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function fetchRunStreaks');
	assert.ok(start >= 0, 'Could not locate fetchRunStreaks — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
	assert.match(body, /run_streaks_for_user/, 'must call the SQL aggregate');
	assert.match(body, /if \(error \|\| !row\) return null;/, 'a failed RPC must return null');
	assert.match(body, /resolvedOptions\(\)\.timeZone/, 'must pass the browser IANA zone for local-day bucketing');
});

test('saveRunAsRoute routes through summarizeRouteFromTrack', () => {
	// Reason: the inline equirectangular distance sum was extracted
	// into the route_simplify module so it could be unit-tested. If
	// a future edit reaches for the raw simplifyTrack + manual loop
	// again, the regression test surface evaporates.
	const source = read('src/lib/core/data.ts');
	assert.match(
		source,
		/summarizeRouteFromTrack/,
		'saveRunAsRoute must use the shared helper',
	);
	// Negative guard — no leftover manual loop.
	const fn = source.match(/export async function saveRunAsRoute[\s\S]*?\n\}/);
	assert.ok(fn, 'saveRunAsRoute body missing');
	assert.doesNotMatch(
		fn![0],
		/Math\.cos\(midLat\)/,
		'inline distance loop must not survive — should be in summarizeRouteFromTrack',
	);
});
