// Source-level guards pinning the streaks card + run-to-route helper
// wiring. Mirrors the segments_panel_guards pattern.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('Dashboard wires the streak card through computeRunStreaks()', () => {
	// Reason: the streak figures must come from the pure helper, not
	// an inline reimplementation. The helper is unit-tested; an
	// inline reimplementation would drift silently.
	const source = read('src/routes/dashboard/+page.svelte');
	assert.match(source, /computeRunStreaks/, 'dashboard must call the pure helper');
	assert.match(source, /class="stat-card" class:streak-active/, 'streak stat card missing');
});

test('Dashboard streak card surfaces both current and best', () => {
	// Reason: the "best" number is what motivates a runner to extend
	// the streak. Surfacing only "current" loses that.
	const source = read('src/routes/dashboard/+page.svelte');
	assert.match(source, /runStreaks\.current/, 'current value missing');
	assert.match(source, /runStreaks\.best/, 'best value missing');
});

test('saveRunAsRoute routes through summarizeRouteFromTrack', () => {
	// Reason: the inline equirectangular distance sum was extracted
	// into the route_simplify module so it could be unit-tested. If
	// a future edit reaches for the raw simplifyTrack + manual loop
	// again, the regression test surface evaporates.
	const source = read('src/lib/data.ts');
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
