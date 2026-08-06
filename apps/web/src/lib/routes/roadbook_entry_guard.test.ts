// The roadbook's discoverability contract (issue #666 M4).
//
// `buildRoadbook` has exactly one page consumer — /routes/[id]/roadbook —
// and the route-detail page carries its only in-app link. That link used
// to render behind `{#if markerPins.length > 0}`, so a runner who had
// never placed a course marker had no way to discover that a crew sheet
// exists at all: the surface was reachable only by typing the URL.
//
// The roadbook does not need markers. With none, `buildRoadbook` still
// projects a start → finish sheet off the route's line and the goal
// time, which is a useful pacing sheet on its own — the tests below
// prove that rather than asserting it. So the link is shown always and
// disabled (with a stated reason) only for the one input the builder
// genuinely cannot walk: a route with fewer than two positions.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { buildRoadbook } from './roadbook';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

const ROUTE_DETAIL = 'src/routes/routes/[id]/+page.svelte';

test('route detail links the roadbook without a course-marker precondition', () => {
	const src = read(ROUTE_DETAIL);
	const link = src.indexOf('/roadbook`}');
	assert.ok(link > 0, 'route detail must link /routes/[id]/roadbook');

	// The enclosing `{#if ...}` is the last one opened before the link.
	const guardStart = src.lastIndexOf('{#if', link);
	const guard = src.slice(guardStart, src.indexOf('}', guardStart) + 1);
	assert.ok(
		!/markerPins/.test(guard),
		`the roadbook link must not be gated on course markers, found: ${guard}`
	);
	assert.match(
		guard,
		/displayWaypoints\.length >= 2/,
		`the roadbook link's only gate is a walkable line, found: ${guard}`
	);
});

test('the no-line branch disables the roadbook affordance and states the reason', () => {
	const src = read(ROUTE_DETAIL);
	const link = src.indexOf('/roadbook`}');
	const elseAt = src.indexOf('{:else}', link);
	const endAt = src.indexOf('{/if}', elseAt);
	assert.ok(elseAt > 0 && endAt > elseAt, 'the roadbook link needs an else branch');

	const fallback = src.slice(elseAt, endAt);
	assert.match(fallback, /disabled/, 'the fallback must disable rather than hide the affordance');
	assert.match(
		fallback,
		/roadbook\.needsRouteLine/,
		'a disabled affordance must say why it is disabled'
	);
	assert.match(
		fallback,
		/roadbook\.crewSheet/,
		'the disabled affordance keeps the same name, so the surface stays discoverable'
	);
});

test('a route with no markers still yields a usable roadbook — the reason hiding it was wrong', () => {
	// 1 km due east, 100 m of climb, one hour goal.
	const line = [
		{ lat: 0, lng: 0, ele: 0 },
		{ lat: 0, lng: 0.0044966, ele: 50 },
		{ lat: 0, lng: 0.0089932, ele: 100 },
	];
	const rb = buildRoadbook(line, [], { goalSeconds: 3600, model: 'effort' });

	// Assert the population, not only the property (§534): the sheet is
	// non-empty, spans the whole route, and carries real projections.
	assert.equal(rb.legs.length, 2, 'a marker-less roadbook is start + finish');
	assert.equal(rb.legs[0].checkpoint, 'start');
	assert.equal(rb.legs[1].checkpoint, 'finish');
	assert.ok(rb.totalDistM > 900, `expected ~1 km, got ${rb.totalDistM}`);
	assert.ok(rb.totalGainM > 90, `expected ~100 m gain, got ${rb.totalGainM}`);
	assert.equal(rb.legs[1].projectedElapsedS, 3600);
});
