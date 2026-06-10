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

// ──────────────────────────────────────────────────────────────────
// Generate-by-distance picker markers.
//
// Field report: picking a start on the map only confirmed the
// selection in the sidebar (a lat,lng text label); the visual
// marker on the map appeared only after clicking Generate, leaving
// the user to verify the pick by side effect. The fix exposes
// setGenerationStart / setGenerationEnd on RouteBuilder and the page
// wires them via $effect so the marker tracks the picked coords in
// real time. Pin the API + the wiring so a refactor that drops
// either side fails here loudly.

test('RouteBuilder.svelte: exposes setGenerationStart + setGenerationEnd', () => {
	const src = read('src/lib/components/RouteBuilder.svelte');
	assert.match(
		src,
		/export function setGenerationStart\(/,
		'setGenerationStart export must exist — the page calls it from a ' +
			'$effect to paint the picked start point on the map.',
	);
	assert.match(
		src,
		/export function setGenerationEnd\(/,
		'setGenerationEnd export must exist for parity with the optional ' +
			'end-point picker.',
	);
	// data-testid lets the e2e suite assert presence without coupling
	// to a CSS-class-only marker.
	assert.match(
		src,
		/data-testid['"]?[^'"]*generation-endpoint-/,
		'Endpoint markers must be tagged with data-testid="generation-' +
			'endpoint-start" / "-end" so the e2e suite can assert on them.',
	);
});

test('/routes/new wires picked start/end into RouteBuilder markers', () => {
	const src = read('src/routes/routes/new/+page.svelte');
	assert.match(
		src,
		/builder\?\.setGenerationStart\(startPoint\)/,
		'Page must feed startPoint into builder.setGenerationStart() ' +
			'(inside a $effect) so the green flag tracks every change.',
	);
	assert.match(
		src,
		/builder\?\.setGenerationEnd\(endPoint\)/,
		'Page must feed endPoint into builder.setGenerationEnd() so the ' +
			'red flag tracks every change.',
	);
});

// ──────────────────────────────────────────────────────────────────
// Heatmap improvements: clickable routes overlay, legend hides on
// hover, fills the viewport.

test('RouteHeatmap exposes route polylines clickable to /routes/[id]', () => {
	// The heatmap was redesigned (57b9d588 + 18fdee4c): clicking a route
	// now PINS it on the map for comparison instead of navigating away,
	// and routes are opened from the discover sidebar's result list via
	// an explicit "view" link. The invariant the guard protects is
	// unchanged — a route spotted on the heatmap must be openable at
	// /routes/[id] — so it now pins the explicit view link rather than
	// the old goto()-on-click + min-zoom overlay.
	const src = read('src/lib/components/RouteHeatmap.svelte');
	assert.match(
		src,
		/href="\/routes\/\{[^}]+\}"/,
		'The result list must link each route to /routes/[id] so the user ' +
			'can open the route they spotted on the heatmap.',
	);
	assert.match(
		src,
		/data-testid="result-view"/,
		'The per-route "view" link must keep its result-view testid so the ' +
			'e2e suite can assert routes are openable from the heatmap.',
	);
});

test('RouteHeatmap legend collapses out of the way', () => {
	// The hover-to-dim legend was replaced by a collapsible discover
	// sidebar (same goal: get the route list out of the way while the
	// user inspects the map). The invariant is now a toggleable sidebar
	// whose collapsed state is driven by `sidebarOpen`.
	const src = read('src/lib/components/RouteHeatmap.svelte');
	assert.match(
		src,
		/class:collapsed=\{!sidebarOpen\}/,
		'The discover sidebar must collapse when sidebarOpen is false so it ' +
			'gets out of the way of the map.',
	);
	assert.match(
		src,
		/data-testid="sidebar-toggle"[\s\S]*?aria-expanded=\{sidebarOpen\}/,
		'The sidebar toggle must reflect open/closed state via aria-expanded ' +
			'(accessible collapse control).',
	);
});

test('/routes heatmap tab navigates to its own full-viewport route', () => {
	// May 2026: the heatmap moved out of the /routes tab template
	// into a standalone /routes/heatmap route so it can own the
	// full layout column without fighting the routes-page flex
	// chain that caused the canvas to render at y=-345 inside the
	// tab branch. The /routes page now ONLY redirects when the
	// heatmap tab is picked; the actual layout work lives in
	// /routes/heatmap/+page.svelte.
	const pageSrc = read('src/routes/routes/+page.svelte');
	assert.match(
		pageSrc,
		/goto\(['"]\/routes\/heatmap['"]/,
		"/routes must redirect to /routes/heatmap when the heatmap " +
			'tab is selected — the tab branch no longer mounts the ' +
			'heatmap inline.',
	);
	const heatmapSrc = read('src/routes/routes/heatmap/+page.svelte');
	assert.match(
		heatmapSrc,
		/position:\s*fixed/,
		'The standalone heatmap route must position the wrapper as ' +
			'`fixed` against the viewport so the canvas escapes the ' +
			'flex chain that previously caused y=-345 sizing bugs.',
	);
});

test('RouteTrackPreview renders a static map image when a key is available', () => {
	const src = read('src/lib/components/RouteTrackPreview.svelte');
	assert.match(
		src,
		/buildStaticMapUrl\(/,
		'RouteTrackPreview must call buildStaticMapUrl to construct a ' +
			'MapTiler Static Maps URL with the polyline drawn on top — ' +
			'fixes the "I only see the line, not the map" complaint on ' +
			'the /routes grid.',
	);
	assert.match(
		src,
		/loading="lazy"/,
		'Static-map images must be lazy-loaded — a long list of route ' +
			'cards otherwise fires N MapTiler requests on page load.',
	);
	assert.match(
		src,
		/data-testid="route-preview-map"/,
		'The static-map img must be tagged with ' +
			'data-testid="route-preview-map" so the e2e can pin it.',
	);
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

// 3. Route-builder "locate / set point" affordances must recentre the
//    map, and the keyboard-shortcuts hint must not share the bottom-left
//    corner with the empty-state onboarding card. Both came from the
//    "this page feels very unusable" field report:
//      - the start/end "use my location" + typed-coord buttons set a
//        sidebar label + painted a marker but never panned the map, so
//        on the default world view the click looked dead;
//      - the "Click anywhere to start" card (.canvas-empty, z-index 5)
//        sat UNDER the shortcuts hint (.shortcuts-hint, z-index 10),
//        both pinned bottom-left.

test('RouteBuilder.svelte: exposes a flyTo export for sidebar recentring', () => {
	const src = read('src/lib/components/RouteBuilder.svelte');
	assert.match(
		src,
		/export function flyTo\(\s*lngLat[^)]*\)\s*\{[\s\S]*?map\.flyTo\(/,
		'RouteBuilder must export flyTo() that calls map.flyTo — the page ' +
			'uses it to recentre on a located / typed Generate start/end so ' +
			'the click has visible feedback.',
	);
});

test('RouteBuilder.svelte: shortcuts hint is pinned bottom-RIGHT, not bottom-left', () => {
	const src = read('src/lib/components/RouteBuilder.svelte');
	const block = src.match(/\.shortcuts-hint\s*\{[\s\S]*?\}/);
	assert.ok(block, '.shortcuts-hint rule must exist');
	assert.match(
		block![0],
		/inset-inline-end:/,
		'.shortcuts-hint must pin to inset-inline-end (bottom-right) so it ' +
			'stops covering the bottom-left .canvas-empty onboarding card.',
	);
	assert.doesNotMatch(
		block![0],
		/inset-inline-start:/,
		'.shortcuts-hint must NOT use inset-inline-start — that puts it back ' +
			'in the bottom-left corner on top of the .canvas-empty card.',
	);
});

test('routes/new/+page.svelte: useMyLocation pans the map + guards geolocation', () => {
	const src = read('src/routes/routes/new/+page.svelte');
	const fn = src.match(/function useMyLocation\([^)]*\)\s*\{[\s\S]*?\n\t\}/);
	assert.ok(fn, 'useMyLocation must exist');
	assert.match(
		fn![0],
		/if \(!navigator\.geolocation\)/,
		'useMyLocation must guard a missing navigator.geolocation (insecure ' +
			'context) instead of throwing uncaught — matches the map locate button.',
	);
	assert.match(
		fn![0],
		/builder\?\.flyTo\(/,
		'useMyLocation must call builder.flyTo on success so the map recentres ' +
			'on the located point — without it the button looks dead on the ' +
			'default world view.',
	);
});

test('routes/new/+page.svelte: applyCoords pans the map to the typed point', () => {
	const src = read('src/routes/routes/new/+page.svelte');
	const fn = src.match(/function applyCoords\([^)]*\)\s*\{[\s\S]*?\n\t\}/);
	assert.ok(fn, 'applyCoords must exist');
	assert.match(
		fn![0],
		/builder\?\.flyTo\(/,
		'applyCoords must call builder.flyTo so a typed Generate start/end ' +
			'(likely off-screen) is brought into view.',
	);
});

// 4. routes/new export filenames must survive a non-ASCII route name.
//    The basename sanitizer strips every non-[A-Za-z0-9-_ ] char, so a
//    Japanese / emoji name (or the localized "untitled" fallback in a
//    non-Latin locale) collapses to "" and the download was named just
//    ".gpx" / ".kml". exportBasename() guards with an 'route' fallback.
test('routes/new/+page.svelte: export filename has a non-empty basename fallback', () => {
	const src = read('src/routes/routes/new/+page.svelte');
	const fn = src.match(/function exportBasename\([^)]*\)[^{]*\{[\s\S]*?\n\t\}/);
	assert.ok(fn, 'exportBasename() helper must exist');
	assert.match(
		fn![0],
		/\|\|\s*['"]route['"]/,
		"exportBasename must fall back to a constant ('route') so a non-Latin " +
			'name never yields a bare ".gpx" / ".kml" filename.',
	);
	// Both export handlers must route through it (no inline sanitizer left).
	for (const h of ['handleExportGpx', 'handleExportKml']) {
		const hh = src.match(new RegExp(`function ${h}\\([^)]*\\)\\s*\\{[\\s\\S]*?\\n\\t\\}`));
		assert.ok(hh, `${h} must exist`);
		assert.match(
			hh![0],
			/exportBasename\(/,
			`${h} must build its filename via exportBasename(), not an inline ` +
				'sanitizer that can produce an empty basename.',
		);
	}
});

// 5. RouteBuilder mid-route insertion must use the pure point-to-segment
//    helper, not a distance-to-midpoint heuristic. The midpoint version
//    mis-picked the segment for a click near the far end of a long
//    segment (a shorter neighbour's midpoint scored closer), inserting
//    the new waypoint into the wrong segment. See insert_index.ts +
//    insert_index.test.ts.
test('RouteBuilder.svelte: findInsertIndex delegates to nearestInsertIndex', () => {
	const src = read('src/lib/components/RouteBuilder.svelte');
	assert.match(
		src,
		/import \{ nearestInsertIndex \} from '\$lib\/routes\/insert_index'/,
		'RouteBuilder must import the pure nearestInsertIndex helper.',
	);
	const fn = src.match(/function findInsertIndex\([^)]*\)[^{]*\{[\s\S]*?\n\t\}/);
	assert.ok(fn, 'findInsertIndex must exist');
	assert.match(
		fn![0],
		/nearestInsertIndex\(/,
		'findInsertIndex must delegate to nearestInsertIndex (point-to-segment).',
	);
	assert.doesNotMatch(
		fn![0],
		/midpoint|\(a\.lng \+ b\.lng\) \/ 2/,
		'findInsertIndex must NOT reintroduce the distance-to-midpoint heuristic.',
	);
});

// 6. Numbered pin labels must be renumbered after a waypoint splice.
//    createWaypointMarker bakes the 1-based number in at creation, so a
//    mid-route insert / middle delete shifts later indices and leaves
//    stale numbers (a duplicate appears, the top number goes missing).
//    updateMarkerStyles is the mutation funnel, so it must renumber.
test('RouteBuilder.svelte: updateMarkerStyles renumbers pin labels after a splice', () => {
	const src = read('src/lib/components/RouteBuilder.svelte');
	const fn = src.match(/function updateMarkerStyles\([^)]*\)[^{]*\{[\s\S]*?\n\t\}/);
	assert.ok(fn, 'updateMarkerStyles must exist');
	assert.match(
		fn![0],
		/renumberMarkers\(\)/,
		'updateMarkerStyles must call renumberMarkers() so insert / remove ' +
			'keep the 1..N pin numbers correct.',
	);
	const rn = src.match(/function renumberMarkers\([^)]*\)[^{]*\{[\s\S]*?\n\t\}/);
	assert.ok(rn, 'renumberMarkers helper must exist');
	assert.match(
		rn![0],
		/waypoint-marker-label[\s\S]*textContent\s*=\s*String\(i \+ 1\)/,
		'renumberMarkers must rewrite each label span to its current index+1.',
	);
});
