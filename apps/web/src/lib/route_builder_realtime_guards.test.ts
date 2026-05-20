// Source-level guards for two recent fixes on the web side. Each
// test reads a Svelte file as text and asserts a pattern is present,
// with a reason a future editor can read before deciding it's safe
// to break.
//
// 1. RouteBuilder.svelte mutate functions (addWaypoint /
//    insertWaypoint / removeWaypoint / undoWaypoint) all end in
//    `emitUpdate()`. The parent page reads waypointCount + the
//    Calculate-button gating + the "Click to start" overlay off
//    the update event; missing this call leaves the sidebar UI
//    stuck at "0 waypoints" even after the user has dropped pins.
//    Pre-fix, only updateStraightLine's <2-waypoint early return
//    emitted, which silently broke the Calculate gate from the
//    second click onwards. See `apps/web/src/lib/components/
//    RouteBuilder.svelte` and the in-line addWaypoint comment.
//
// 2. /clubs/[slug] + /clubs/[slug]/events/[id] expose a
//    `realtime-ready` class on the page wrapper via a broadcast
//    roundtrip: subscribe → on SUBSCRIBED, send a self-broadcast
//    "ready-ping" → listen for the echo → flip realtimeReady true.
//    The roundtrip proves the channel is fully wired bidirectionally;
//    a plain SUBSCRIBED ack trails the postgres_changes filter
//    setup by a tick and isn't a safe signal on its own. The
//    multi-context e2e suite (event-race-control.spec.ts +
//    realtime.spec.ts) relies on this signal. Pin the shape so a
//    refactor that drops it from either page fails here loudly.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('RouteBuilder.svelte: addWaypoint emits an update', () => {
	const src = read('src/lib/components/RouteBuilder.svelte');
	// Match `export function addWaypoint` up to the next `}` that
	// matches the function's body, then assert emitUpdate is inside.
	const m = src.match(
		/export function addWaypoint\([^)]*\) \{[\s\S]*?\n\t\}/,
	);
	assert.ok(m, 'addWaypoint must exist as a top-level exported function');
	assert.match(
		m![0],
		/emitUpdate\(\)/,
		'addWaypoint must call emitUpdate() so the parent page learns ' +
			'about the new waypoint. Without it, waypointCount stays ' +
			'wrong, Calculate stays disabled, and the empty-state overlay ' +
			'never clears — exactly the regression def4839 fixed.',
	);
});

test('RouteBuilder.svelte: insertWaypoint emits an update', () => {
	const src = read('src/lib/components/RouteBuilder.svelte');
	const m = src.match(
		/export function insertWaypoint\([^)]*\) \{[\s\S]*?\n\t\}/,
	);
	assert.ok(m, 'insertWaypoint must exist');
	assert.match(
		m![0],
		/emitUpdate\(\)/,
		'insertWaypoint mutates `waypoints` (splice) and must emit so ' +
			'the parent sees the new count.',
	);
});

test('RouteBuilder.svelte: removeWaypoint emits an update', () => {
	const src = read('src/lib/components/RouteBuilder.svelte');
	const m = src.match(
		/export function removeWaypoint\([^)]*\) \{[\s\S]*?\n\t\}/,
	);
	assert.ok(m, 'removeWaypoint must exist');
	assert.match(
		m![0],
		/emitUpdate\(\)/,
		'removeWaypoint mutates `waypoints` and must emit so the parent ' +
			'sees the decreased count + the Calculate button re-disables ' +
			'when count drops below 2.',
	);
});

test('RouteBuilder.svelte: undoWaypoint emits an update', () => {
	const src = read('src/lib/components/RouteBuilder.svelte');
	const m = src.match(
		/export function undoWaypoint\([^)]*\) \{[\s\S]*?\n\t\}/,
	);
	assert.ok(m, 'undoWaypoint must exist');
	assert.match(
		m![0],
		/emitUpdate\(\)/,
		'undoWaypoint pops `waypoints` and must emit so Ctrl+Z is ' +
			'visible in the sidebar (waypointCount drops, Calculate ' +
			're-evaluates).',
	);
});

// ──────────────────────────────────────────────────────────────────
// Realtime-ready broadcast roundtrip

function assertRealtimeReadyBroadcastRoundtrip(
	source: string,
	pageName: string,
): void {
	// Channel is opted into receiving its own broadcasts.
	assert.match(
		source,
		/config:\s*\{\s*broadcast:\s*\{\s*self:\s*true\s*\}\s*\}/,
		`${pageName}: channel must declare \`config: { broadcast: { self: true } }\` ` +
			'so the ready-ping echoes back to the sender. Without ' +
			'self-receive, the broadcast handler below never fires and ' +
			'realtimeReady stays false — every test that waits on ' +
			'.realtime-ready times out.',
	);

	// The ready-ping listener is registered.
	assert.match(
		source,
		/\.on\(\s*['"]broadcast['"]\s*,\s*\{\s*event:\s*['"]ready-ping['"]\s*\}/,
		`${pageName}: the ready-ping broadcast handler must be ` +
			"registered with `.on('broadcast', { event: 'ready-ping' }, ...)`. " +
			'It is what flips realtimeReady = true.',
	);

	// On SUBSCRIBED the page sends the self-broadcast.
	assert.match(
		source,
		/\.send\(\s*\{\s*type:\s*['"]broadcast['"],\s*event:\s*['"]ready-ping['"]/,
		`${pageName}: the .subscribe() callback must send a ` +
			"`{ type: 'broadcast', event: 'ready-ping', ... }` message " +
			'on SUBSCRIBED so the roundtrip can complete.',
	);

	// The wrapper exposes the class:realtime-ready binding.
	assert.match(
		source,
		/class:realtime-ready=\{realtimeReady\}/,
		`${pageName}: the rendered page wrapper must carry ` +
			'`class:realtime-ready={realtimeReady}`. The e2e suite waits ' +
			'on `.realtime-ready` before triggering its service-role ' +
			'INSERTs / Arm-race clicks; without the class binding the ' +
			'multi-context tests race the postgres_changes filter wiring.',
	);
}

test('/clubs/[slug] page exposes the realtime-ready broadcast roundtrip', () => {
	const src = read('src/routes/clubs/[slug]/+page.svelte');
	assertRealtimeReadyBroadcastRoundtrip(src, '/clubs/[slug]');
});

test('/clubs/[slug]/events/[id] page exposes the realtime-ready broadcast roundtrip', () => {
	const src = read('src/routes/clubs/[slug]/events/[id]/+page.svelte');
	assertRealtimeReadyBroadcastRoundtrip(src, '/clubs/[slug]/events/[id]');
});

// ──────────────────────────────────────────────────────────────────
// Linked cursor: ElevationProfile hover → RunMap hover-marker.
// The chart raises `onhover(idx | null)`; the parent state propagates
// idx to RunMap, which paints a pulsing dot at track[idx]. Source-
// level guards on each piece so a refactor can't silently disconnect
// the chain.

test('ElevationProfile.svelte: exposes onhover prop driven by crosshair', () => {
	const src = read('src/lib/components/ElevationProfile.svelte');
	assert.match(
		src,
		/onhover\?:\s*\(idx:\s*number\s*\|\s*null\)\s*=>\s*void/,
		'ElevationProfile must declare an onhover prop of shape (idx | null) ' +
			'so the parent can drive a chart-to-map linked cursor.',
	);
	// And the prop must actually fire — search for the effect that
	// dispatches the current crosshair idx.
	assert.match(
		src,
		/onhover\?\.\(/,
		'ElevationProfile must invoke onhover (e.g. via an effect on the ' +
			"crosshair index) — declaring the prop alone doesn't help if it's never fired.",
	);
	assert.match(
		src,
		/lastEmittedIdx/,
		'ElevationProfile should dedupe identical idx emits across rapid ' +
			'pointermove ticks (lastEmittedIdx guard); otherwise the parent ' +
			'gets a callback storm.',
	);
});

test('RunMap.svelte: accepts hoverIdx + renders the hover-marker', () => {
	const src = read('src/lib/components/RunMap.svelte');
	assert.match(
		src,
		/hoverIdx\?:\s*number\s*\|\s*null/,
		'RunMap must declare a hoverIdx prop of shape (number | null).',
	);
	assert.match(
		src,
		/renderHoverMarker/,
		'RunMap must define a renderHoverMarker helper that paints a ' +
			'marker at track[hoverIdx].',
	);
	// The marker is reused across ticks (mutated, not rebuilt) — keep
	// that contract so dragging the chart cursor doesn't churn DOM.
	assert.match(
		src,
		/hoverMarker\.setLngLat/,
		'RunMap should reuse the same hover-marker handle and only ' +
			'mutate its position (not rebuild on every tick).',
	);
	// data-testid is the affordance the e2e suite waits on.
	assert.match(
		src,
		/data-testid['"][^>]*chart-hover-marker/,
		'RunMap should tag the hover-marker DOM with ' +
			'data-testid="chart-hover-marker" so the e2e test can pin it.',
	);
});

test('/runs/[id] wires ElevationProfile.onhover into RunMap.hoverIdx', () => {
	const src = read('src/routes/runs/[id]/+page.svelte');
	assert.match(
		src,
		/let chartHoverIdx\s*=\s*\$state<number \| null>/,
		'/runs/[id] must hold chartHoverIdx state so the chart can feed ' +
			'the map.',
	);
	assert.match(
		src,
		/hoverIdx=\{chartHoverIdx\}/,
		'RunMap must receive hoverIdx={chartHoverIdx}.',
	);
	assert.match(
		src,
		/onhover=\{\(idx\)\s*=>\s*\(chartHoverIdx = idx\)\}/,
		'ElevationProfile must feed chartHoverIdx via its onhover prop.',
	);
});

test('/share/run/[id] (RunShareView) wires the same linked cursor', () => {
	const src = read('src/lib/components/RunShareView.svelte');
	assert.match(
		src,
		/let chartHoverIdx/,
		'RunShareView must hold chartHoverIdx state.',
	);
	assert.match(src, /hoverIdx=\{chartHoverIdx\}/);
	assert.match(src, /onhover=\{\(idx\)\s*=>\s*\(chartHoverIdx = idx\)\}/);
});

test('/routes/[id] wires the linked cursor and aligns elevations with displayWaypoints', () => {
	const src = read('src/routes/routes/[id]/+page.svelte');
	// Elevations must be derived from displayWaypoints (not the raw
	// route.waypoints) so the chart idx-space matches the clipped
	// polyline non-owners see. Without this, the chart's idx → map
	// marker lookup lands at a point the user can't see.
	assert.match(
		src,
		/let elevations\s*=\s*\$derived\(displayWaypoints\.map/,
		'/routes/[id] elevations must derive from displayWaypoints, not ' +
			'route.waypoints — keeps the chart idx-space aligned with the ' +
			'polyline (matters for non-owners with a clipped trace).',
	);
	assert.match(src, /let chartHoverIdx/);
	assert.match(src, /hoverIdx=\{chartHoverIdx\}/);
	assert.match(src, /onhover=\{\(idx\)\s*=>\s*\(chartHoverIdx = idx\)\}/);
});

test('events page also broadcasts race-state-changed alongside DB writes', () => {
	// Reason: race_sessions writes (Arm / GO / End) on a freshly
	// subscribed channel can land inside the postgres_changes
	// filter-wiring window and get dropped on the subscriber side.
	// The event page works around this by emitting a
	// `race-state-changed` broadcast right after each write — the
	// broadcast path is gated only on the JOIN ack (which we've
	// already proven complete via the ready-ping roundtrip above).
	// Members listen for both: broadcast = fast path, postgres_changes
	// = late-joiner fallback. See fix in 2b08d04.
	const src = read('src/routes/clubs/[slug]/events/[id]/+page.svelte');
	assert.match(
		src,
		/broadcastRaceStateChanged/,
		'event page must declare the `broadcastRaceStateChanged()` helper.',
	);
	assert.match(
		src,
		/event:\s*['"]race-state-changed['"]/,
		"helper must emit a `'race-state-changed'` broadcast event.",
	);
	// And the handlers all call it after their respective writes.
	for (const hdr of ['handleArm', 'handleStart', 'confirmEndRace']) {
		const fn = src.match(
			new RegExp(`async function ${hdr}\\([^)]*\\)[\\s\\S]*?\\n\\t\\}`),
		);
		assert.ok(fn, `${hdr} must exist`);
		assert.match(
			fn![0],
			/broadcastRaceStateChanged\(\)/,
			`${hdr} must call broadcastRaceStateChanged() after the ` +
				'race_sessions write so the fast-path delivers to ' +
				'subscribed members without waiting for postgres_changes.',
		);
	}
});
