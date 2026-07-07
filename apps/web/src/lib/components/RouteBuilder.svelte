<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	// Single source of truth for the OSRM endpoint — env-overridable via
	// PUBLIC_OSRM_URL so a self-hosted backend can replace the public
	// demo server without code edits.
	import { OSRM_BASE_URL, assertOsrmConfiguredForProd } from '$lib/routes/routing';
	import { SegmentCache, segmentCacheKey } from '$lib/routes/segment_cache';
	import {
		DEFAULT_SCALE_FACTOR,
		NEAR_POINT_M,
		bisectScale,
		generateLoopWaypoints,
		initScaleRange,
		isValidTargetDistance,
		isWithinAcceptBand,
		selectLoopAnchors,
	} from '$lib/routes/route_loop';
	import { nearestInsertIndex } from '$lib/routes/insert_index';
	import type { RoutePreference } from '$lib/routes/generate/graphhopper';
	import { supabase } from '$lib/core/supabase';
	import { formatDistance, getUnit } from '$lib/format/units.svelte';
	import { m as t } from '$lib/i18n/store.svelte';
	import { searchPlaces } from '$lib/routes/geocoding';
	import { showToast } from '$lib/stores/toast.svelte';
	import { watchMapResize } from '$lib/routes/map_resize';
	import { fetchElevations, sampleCoordinates, calculateElevationGain } from '$lib/routes/elevation';
	import { hasAcceptedConsent } from '$lib/settings/consent.svelte';
	import {
		closestPointDistanceM,
		formatWaypointRanges,
		haversineM as routingHaversineM,
		identifyFailedWaypoints,
		OSRM_SNAP_RADIUS_M,
		QUALITY_THRESHOLDS,
		qualityWarning,
		validateRouteQuality,
		type RoutedSegment,
	} from '$lib/routes/routing_quality';
	import type { TrackPoint } from '$lib/types';

	// Bound the recentre pan to a fixed, snappy duration. maplibre's default
	// flyTo scales the duration by travel distance, so recentring from the
	// world-view fallback ([0,20] z2, used when geolocation is denied) to a city
	// zoom would otherwise fly a cinematic multi-second arc across the globe. A
	// flat 800ms pan is clearly visible feedback for a "use my location" /
	// typed-coordinate / search recentre.
	const RECENTRE_FLY_MS = 800;

	let {
		mode = 'road',
		onupdate = (_data: {
			waypoints: number;
			distance: number;
			elevation: number;
			elevations: number[];
			coordinates: [number, number][];
			routed: boolean;
			waypointList: TrackPoint[];
		}) => {},
		onmapclick = (_lngLat: { lng: number; lat: number }): boolean => false,
		onerror = (_message: string | null, _severity: 'error' | 'warning' = 'error') => {},
		onbusy = (_busy: boolean) => {},
		ongeneratemismatch = (_achievedM: number, _targetM: number, _largestLoopM?: number) => {},
		onprorequired = () => {},
		onrequestclear = (): boolean => false
	}: {
		mode?: 'road' | 'trail';
		onupdate?: (data: {
			waypoints: number;
			distance: number;
			elevation: number;
			elevations: number[];
			coordinates: [number, number][];
			/// True only when `coordinates` is an OSRM-snapped polyline
			/// (calculateRoute / generateLoop succeeded). False during the
			/// straight-line preview between dropped waypoints, and false
			/// after any clear / failure. The parent uses this to gate
			/// Save without having to guess from coordinate counts (which
			/// can match either preview or snapped polyline).
			routed: boolean;
			/// Snapshot of the freehand waypoints themselves (not just the
			/// count) so the parent can render a focusable, keyboard-
			/// operable waypoint list — the map markers are mouse-only.
			waypointList: TrackPoint[];
		}) => void;
		onmapclick?: (lngLat: { lng: number; lat: number }) => boolean;
		/**
		 * Called with a non-null message when routing fails or partially
		 * fails, and with null when the next successful calculation
		 * clears the error. `severity` distinguishes hard failures (no
		 * usable route) from partial-success warnings (route is drawn
		 * but some segments are missing). The parent decides styling.
		 */
		onerror?: (message: string | null, severity?: 'error' | 'warning') => void;
		/**
		 * Called whenever the routing state toggles. The parent uses
		 * this to surface a Cancel button (`cancelGeneration()`) while
		 * a long-running batch is in flight — generate-loop in
		 * particular can take ~30s on slow connections.
		 */
		onbusy?: (busy: boolean) => void;
		/**
		 * Called after generateLoop when the produced loop falls outside the
		 * accept band — the road network couldn't form a loop at the target.
		 * Carries the achieved + target distances (metres) so the parent can
		 * offer to accept the achievable distance instead of a dead-end warning.
		 * `largestLoopM`, when present, is the largest genuinely clean loop the
		 * graph-cycle search found near the start (often far from `achievedM`,
		 * which is the out-and-back fallback) — the parent uses it to offer the
		 * explicit "generate that real loop" choice.
		 */
		ongeneratemismatch?: (achievedM: number, targetM: number, largestLoopM?: number) => void;
		/**
		 * Called when the server declined generation with 403 pro_required —
		 * server-side generation is a Pro perk and this caller is free tier.
		 * The builder still falls back to the in-browser heuristic (the free
		 * path); the parent uses this to surface the upgrade affordance.
		 */
		onprorequired?: () => void;
		/**
		 * Called when the Escape keyboard shortcut requests a clear. Return
		 * `true` to signal the parent has taken ownership (e.g. opened a
		 * confirm dialog), in which case the builder does NOT clear itself —
		 * this keeps the Esc shortcut behind the same confirm gate as the
		 * Clear button. Return `false` (the default) to let Esc clear directly.
		 */
		onrequestclear?: () => boolean;
	} = $props();

	let mapContainer: HTMLDivElement;
	let searchInput = $state<HTMLInputElement>();
	let map: maplibregl.Map;
	// MapTiler logs the requester IP per tile fetch, so the basemap is
	// not instantiated before the user has accepted the cookie banner
	// (audit/cookie-consent). Starts true only when consent is already
	// on record; otherwise the "Load map" tap is the affirmative act.
	let mapConsented = $state(hasAcceptedConsent());
	let waypoints: TrackPoint[] = [];
	let routeCoordinates: [number, number][] = [];
	let routeElevations: number[] = [];
	let markers: maplibregl.Marker[] = [];
	/// 0-based indices of waypoints flagged by the post-routing quality
	/// pass — failed snaps, deviation outliers, or detour-segment
	/// endpoints. These markers render in red so the user can see at a
	/// glance which clicks are causing the warning text. Cleared on any
	/// waypoint mutation; repopulated after Calculate Route.
	let implicatedWaypoints = new Set<number>();
	let distanceMarkers: maplibregl.Marker[] = [];
	let isRouting = $state(false);
	$effect(() => {
		onbusy(isRouting);
	});
	// Re-stamp the km/mi distance markers when the user flips the
	// preference on /settings while a route is drawn. Reading
	// getUnit() inside the effect makes Svelte subscribe to the
	// module-level signal; updateDistanceMarkers picks up the new
	// unit on its next call. The `map &&` guard avoids running
	// before onMount (the route layer doesn't exist yet).
	$effect(() => {
		getUnit();
		if (map && routeCoordinates.length >= 2) updateDistanceMarkers();
	});
	let mapStyle = $state<'streets' | 'satellite' | 'terrain'>('streets');
	let nearStart = false;
	let routeVersion = 0;
	let preRouteWaypoints: TrackPoint[] = []; // generateLoop restore-on-failure snapshot
	/// Caches OSRM-snapped segments across re-routes so each new
	/// waypoint placement only fetches the one new segment instead of
	/// re-running every prior segment. This is what keeps a long route
	/// (50-100 points) responsive under the auto-route-on-every-pin
	/// behaviour below — see segment_cache.ts.
	const segmentCache = new SegmentCache();
	/// Debounce for auto-routing. A human drops pins slower than this,
	/// so each placement still routes promptly; the debounce only
	/// coalesces bursts (a programmatic loop, or fast double-clicks)
	/// into a single pass. Routing runs with `skipBusyToggle` so it
	/// never raises `isRouting` — if it did, the map-click guard would
	/// swallow the next pin and placement would feel sticky.
	const AUTO_ROUTE_DEBOUNCE_MS = 140;
	let autoRouteTimer: ReturnType<typeof setTimeout> | undefined;

	/// Schedule a road-snap of the current waypoints. Called after every
	/// waypoint mutation so the user never has to press a button. The
	/// `routeVersion` cancellation inside recalculateRoute makes a later
	/// call supersede an in-flight one (latest pin wins), mirroring the
	/// mobile builder.
	function scheduleAutoRoute() {
		clearTimeout(autoRouteTimer);
		autoRouteTimer = setTimeout(() => {
			// A generateLoop owns the routing pipeline while it iterates
			// (it holds isRouting=true); don't fight it. Incremental
			// auto-routing never raises isRouting, so this only guards
			// against the generate path.
			if (isRouting) return;
			if (waypoints.length < 2) return;
			recalculateRoute({ skipBusyToggle: true });
		}, AUTO_ROUTE_DEBOUNCE_MS);
	}
	let searchQuery = $state('');
	let searchResults = $state<{ name: string; lng: number; lat: number }[]>([]);
	let showResults = $state(false);
	let searchTimeout: ReturnType<typeof setTimeout>;
	let keyHandler: (e: KeyboardEvent) => void;
	let geoWatchId: number | null = null;
	let stopResizeWatch: (() => void) | null = null;

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;

	// Style URLs honour the PUBLIC_TILE_STYLE_URL override the same
	// way the other map components do (see `decisions.md § 68`). On a
	// local Protomaps dev stack we don't have separate satellite /
	// terrain styles — all three fall back to the single self-hosted
	// style so the style-switcher buttons in the route-builder UI
	// still work (they just don't visually differ). On the MapTiler
	// production path the three distinct slugs are used.
	const TILE_STYLE_OVERRIDE = (env.PUBLIC_TILE_STYLE_URL ?? '').trim();
	const MAP_STYLES: Record<string, string> = TILE_STYLE_OVERRIDE.length > 0
		? {
			streets: TILE_STYLE_OVERRIDE,
			satellite: TILE_STYLE_OVERRIDE,
			terrain: TILE_STYLE_OVERRIDE,
		}
		: {
			streets: `https://api.maptiler.com/maps/${prefersDark ? 'streets-v2-dark' : 'streets-v2'}/style.json?key=${PUBLIC_MAPTILER_KEY}`,
			satellite: `https://api.maptiler.com/maps/hybrid/style.json?key=${PUBLIC_MAPTILER_KEY}`,
			terrain: `https://api.maptiler.com/maps/outdoor-v2/style.json?key=${PUBLIC_MAPTILER_KEY}`,
		};

	const SNAP_DISTANCE_PX = 25;
	const METRES_PER_MILE = 1609.344;

	// --- Search ---

	async function handleSearch(query: string) {
		if (query.length < 2) {
			searchResults = [];
			showResults = false;
			return;
		}
		// Use the shared `searchPlaces` helper so the search works
		// regardless of whether MapTiler is configured. When the key
		// is set we go through MapTiler (faster + better ranking);
		// otherwise we fall back to Nominatim (OSM's free geocoder),
		// which keeps the local Protomaps dev stack functional.
		// See `decisions.md § 68` for the override design.
		searchResults = await searchPlaces(query);
		showResults = searchResults.length > 0;
	}

	function onSearchInput() {
		clearTimeout(searchTimeout);
		searchTimeout = setTimeout(() => handleSearch(searchQuery), 300);
	}

	function selectSearchResult(result: { name: string; lng: number; lat: number }) {
		recentreMap([result.lng, result.lat], 15);
		searchQuery = '';
		searchResults = [];
		showResults = false;
		searchInput?.blur();
	}

	// map.getSource throws (rather than returning undefined) while the
	// style is still loading — a waypoint added before the style fetch
	// resolves, or a style that never loads at all (bad/missing tile
	// key), reaches the source reads in that window. The sources simply
	// don't exist yet, so treat the throw as "no source" and let the
	// caller's optional-chaining skip the draw.
	function getGeoJSONSource(id: string): maplibregl.GeoJSONSource | undefined {
		try {
			return map.getSource(id) as maplibregl.GeoJSONSource | undefined;
		} catch {
			return undefined;
		}
	}

	// --- Waypoint markers ---

	function getMarkerColor(index: number, implicated: boolean): string {
		// Red wins over the green start-marker convention — the user's
		// problem is more important to surface than "this is point 1".
		if (implicated) return '#ef4444';
		if (index === 0) return '#22c55e';
		return '#3b82f6';
	}

	function createWaypointMarker(
		lngLat: { lng: number; lat: number },
		index: number,
		implicated = false,
		hidden = false,
	): maplibregl.Marker {
		// Custom DOM element so the marker can carry the 1-based
		// waypoint number as a label — matches the mobile twin where
		// each pin shows its index. Helps users count waypoints + tell
		// which pin to drag when a route has many. Falls back to a
		// plain circle (no number) when generation marks the pin as
		// `hidden` — scaffolding pins shouldn't show a count.
		const el = document.createElement('div');
		el.className = 'waypoint-marker';
		const color = getMarkerColor(index, implicated);
		const dot = document.createElement('div');
		dot.className = 'waypoint-marker-dot';
		dot.style.backgroundColor = color;
		if (!hidden) {
			const label = document.createElement('span');
			label.className = 'waypoint-marker-label';
			label.textContent = String(index + 1);
			dot.appendChild(label);
		}
		el.appendChild(dot);
		const marker = new maplibregl.Marker({
			element: el,
			draggable: true,
		})
			.setLngLat([lngLat.lng, lngLat.lat])
			.addTo(map);
		// Tagged so updateMarkerStyles can detect implicated → default
		// transitions and only rebuild the markers that actually changed.
		(marker as unknown as { __implicated: boolean; __hidden: boolean }).__implicated = implicated;
		(marker as unknown as { __implicated: boolean; __hidden: boolean }).__hidden = hidden;
		// generate-loop iterations create the interior radial waypoints
		// with hidden=true so they don't flash on the map across each
		// bisection attempt. display:none also makes the element
		// pointer-events:none so the user can't accidentally interact
		// with scaffolding pins.
		if (hidden) marker.getElement().style.display = 'none';

		// Track drag state to distinguish click from drag
		let wasDragged = false;

		marker.on('dragstart', () => {
			wasDragged = true;
		});

		marker.on('dragend', () => {
			const currentIndex = markers.indexOf(marker);
			if (currentIndex === -1) return;
			// During generation, the start marker is the only visible
			// pin (interior scaffolding is display:none). A drag would
			// bump routeVersion → bail the iteration → restore from
			// snapshot — but the marker would visibly sit in the wrong
			// place until the restore lands. Snap it back to the data
			// position to keep the visual consistent, and let the user
			// try again after generation finishes or they Cancel.
			if (isRouting) {
				marker.setLngLat([waypoints[currentIndex].lng, waypoints[currentIndex].lat]);
				setTimeout(() => {
					wasDragged = false;
				}, 0);
				return;
			}
			// Any waypoint mutation has to invalidate an in-flight
			// recalculateRoute so the stale result doesn't overwrite
			// the post-drag state. The bump fires at the next version
			// checkpoint inside recalculateRoute and causes it to return
			// false instead of writing routeCoordinates.
			routeVersion++;
			const pos = marker.getLngLat();
			waypoints[currentIndex] = { lat: pos.lat, lng: pos.lng };
			routeCoordinates = [];
			routeElevations = [];
			// The previous quality pass referenced the old position;
			// drop its red markers so they don't mislead the user about
			// the post-drag state. The next Calculate Route will repaint
			// any that are still problematic.
			clearImplicatedMarkers();
			updateStraightLine();
			// Re-snap automatically — only the two segments adjacent to
			// the dragged pin are cache misses, so this is cheap.
			scheduleAutoRoute();
			// IMPORTANT: reset wasDragged here, not just in the click
			// handler. The browser doesn't fire a `click` event after a
			// drag (mouseup with movement skips the synthetic click),
			// so the flag would otherwise stay `true` and silently eat
			// the next legitimate click on this marker — the exact
			// "click an existing marker to back-track doesn't work
			// after dragging it" bug the audit caught. Defer one tick
			// so any synthetic click that DID fire (some browsers do
			// emit click after a no-movement drag) lands first.
			setTimeout(() => {
				wasDragged = false;
			}, 0);
		});

		// Tell the user clicking the marker does something. Replaces
		// the default `move` cursor that maplibre applies to draggable
		// markers, which gave no hint that clicking back-tracks the
		// route through this point.
		marker.getElement().style.cursor = 'pointer';

		// Click on marker without dragging
		marker.getElement().addEventListener('click', (e: MouseEvent) => {
			if (wasDragged) {
				wasDragged = false;
				return;
			}
			e.stopPropagation();
			// Ignore back-track clicks during isRouting — same reasoning
			// as the contextmenu handler below.
			if (isRouting) return;
			const currentIndex = markers.indexOf(marker);

			// Click on start marker with 3+ waypoints = close the loop
			if (currentIndex === 0 && waypoints.length >= 3) {
				addWaypoint({ lng: waypoints[0].lng, lat: waypoints[0].lat });
				return;
			}

			// Click on any other marker = back-track through it. The
			// new waypoint is appended at the same lat/lng so OSRM has
			// to route from the current end back through this point on
			// the next Calculate. Without a tiny visual offset the new
			// pin sits exactly on top of the clicked one and looks
			// like nothing happened.
			const pos = marker.getLngLat();
			addWaypoint({ lng: pos.lng, lat: pos.lat });
		});

		// Right-click to delete. Ignored during isRouting so a stray
		// right-click during a slow generateLoop doesn't mutate
		// waypoints (which would bump routeVersion and bail the
		// iteration, then leave the user with a half-removed pin).
		marker.getElement().addEventListener('contextmenu', (e: MouseEvent) => {
			e.preventDefault();
			e.stopPropagation();
			if (isRouting) return;
			const currentIndex = markers.indexOf(marker);
			if (currentIndex !== -1) removeWaypoint(currentIndex);
		});

		return marker;
	}

	function updateMarkerStyles() {
		// MapLibre's built-in marker can't change color after creation,
		// so we destroy + rebuild any markers whose implicated state
		// has flipped. Markers whose color is already correct are left
		// alone, preserving any in-flight drag handlers.
		for (let i = 0; i < markers.length; i++) {
			const existing = markers[i];
			const lngLat = existing.getLngLat();
			const wasImplicated =
				(existing as unknown as { __implicated?: boolean }).__implicated === true;
			const wasHidden =
				(existing as unknown as { __hidden?: boolean }).__hidden === true;
			const shouldBeImplicated = implicatedWaypoints.has(i);
			if (wasImplicated === shouldBeImplicated) continue;
			existing.remove();
			// Preserve the hidden state across rebuilds — otherwise a
			// quality-pass flip from blue to red on a scaffolding pin
			// would suddenly make it visible mid-iteration.
			markers[i] = createWaypointMarker(
				{ lng: lngLat.lng, lat: lngLat.lat },
				i,
				shouldBeImplicated,
				wasHidden,
			);
		}
		renumberMarkers();
	}

	// Rewrite each visible marker's number label to match its current
	// array index. createWaypointMarker bakes the 1-based number in at
	// creation, so a splice (mid-route insert, or deleting a non-last
	// waypoint) shifts every later marker's index and leaves it showing a
	// stale number — a duplicate appears and the top number goes missing.
	// updateMarkerStyles is the funnel every waypoint mutation passes
	// through, so renumbering here keeps the labels correct for all of
	// insert / remove / drag / undo. Hidden scaffolding pins (generateLoop
	// iterations) carry no label span and are skipped.
	function renumberMarkers() {
		for (let i = 0; i < markers.length; i++) {
			const label = markers[i]
				.getElement()
				.querySelector('.waypoint-marker-label');
			if (label) label.textContent = String(i + 1);
		}
	}

	function clearImplicatedMarkers() {
		// Any waypoint mutation invalidates the previous quality pass.
		// Reset before the mutation; updateMarkerStyles flips reds
		// back to default colors.
		if (implicatedWaypoints.size === 0) return;
		implicatedWaypoints = new Set();
		updateMarkerStyles();
	}


	// --- Km distance markers ---

	function updateDistanceMarkers() {
		// Remove old markers
		distanceMarkers.forEach((m) => m.remove());
		distanceMarkers = [];

		if (routeCoordinates.length < 2) return;

		// Use the user's preferred unit so the numbered circles match
		// the sidebar's "1.92 mi" stat. Previously hardcoded to km,
		// which left mile-mode users seeing markers spaced every km
		// but labelled like miles.
		const intervalM = getUnit() === 'mi' ? METRES_PER_MILE : 1000;
		let accumulated = 0;
		let nextMark = intervalM;

		for (let i = 1; i < routeCoordinates.length; i++) {
			const segDist = haversine(routeCoordinates[i - 1], routeCoordinates[i]);
			accumulated += segDist;

			if (accumulated >= nextMark) {
				const el = document.createElement('div');
				el.className = 'km-marker';
				el.textContent = `${Math.round(nextMark / intervalM)}`;

				const marker = new maplibregl.Marker({ element: el })
					.setLngLat(routeCoordinates[i])
					.addTo(map);
				distanceMarkers.push(marker);

				nextMark += intervalM;
			}
		}
	}

	// --- Routing ---

	/**
	 * Snap each interior waypoint to the nearest real road via OSRM's
	 * /nearest service. Endpoints (start and the close pin for a
	 * loop, or endAt for point-to-point) are returned untouched so
	 * the visible pin stays where the user clicked.
	 *
	 * After snapping, dedupe adjacent waypoints that landed within
	 * 30m of each other — two seeds on the same street segment
	 * would otherwise force OSRM into a tiny back-and-forth on the
	 * same road, which is exactly the visual artifact this is
	 * meant to eliminate.
	 *
	 * `versionAtStart` is the routeVersion captured by the caller
	 * before the snap began; if it drifts mid-snap (cancel, mutation
	 * race) the helper short-circuits — both per-request before
	 * issuing each fetch, and post-await after parallel results
	 * land — so a cancel doesn't have to wait for all N /nearest
	 * calls to drain.
	 */
	async function snapWaypointsToRoads(
		waypointsToSnap: TrackPoint[],
		versionAtStart: number,
	): Promise<TrackPoint[]> {
		// audit/third-party-data-flows: refuse to ship waypoints to the
		// community OSRM endpoint in prod. The helper in $lib/routes/routing.ts
		// asserts on its own; this component builds URLs inline (custom
		// retry / batching) and bypasses those helpers, so we re-assert
		// at every call site that issues OSRM fetches.
		assertOsrmConfiguredForProd();
		const lastIdx = waypointsToSnap.length - 1;
		const snapped = await Promise.all(
			waypointsToSnap.map(async (wp, i) => {
				// Don't snap endpoints — user's visible pin must stay put.
				if (i === 0 || i === lastIdx) return wp;
				if (versionAtStart !== routeVersion) return wp;
				try {
					const url = `${OSRM_BASE_URL}/nearest/v1/foot/${wp.lng},${wp.lat}?number=1&radiuses=${OSRM_SNAP_RADIUS_M}`;
					const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
					if (!res.ok) return wp;
					if (versionAtStart !== routeVersion) return wp;
					const data = (await res.json()) as {
						code?: string;
						waypoints?: { location?: [number, number] }[];
					};
					if (data.code !== 'Ok' || !data.waypoints?.[0]?.location) return wp;
					const [lng, lat] = data.waypoints[0].location;
					return { lat, lng };
				} catch {
					return wp;
				}
			}),
		);

		// Dedupe adjacent snaps that landed on the same road segment.
		// Always keep the first and last entries (endpoints) — drop
		// only interior collisions. A 30m threshold is loose enough
		// to swallow snap-jitter on the same edge but tight enough
		// that genuinely distinct nearby seeds stay.
		const deduped: TrackPoint[] = [snapped[0]];
		for (let i = 1; i < snapped.length - 1; i++) {
			const prev = deduped[deduped.length - 1];
			if (routingHaversineM(prev, snapped[i]) > 30) {
				deduped.push(snapped[i]);
			}
		}
		if (snapped.length > 1) deduped.push(snapped[snapped.length - 1]);
		return deduped;
	}

	async function recalculateRoute(opts: {
		/// generateLoop holds isRouting=true across its whole iteration
		/// loop; when it calls into recalculateRoute it passes this so
		/// the inner finally doesn't flip the spinner off between
		/// attempts (which previously admitted a brief window of
		/// user clicks and a visible flicker).
		skipBusyToggle?: boolean;
		/// Suppress the deviation / detour / partial-success warnings.
		/// generateLoop's scaffolding waypoints are invisible, so
		/// telling the user to "drag the red markers" makes no sense.
		/// Hard failures (okSegments === 0 → throw → catch → onerror)
		/// still bubble — the caller can replace that with a
		/// generation-specific message.
		suppressSoftWarnings?: boolean;
	} = {}): Promise<boolean> {
		if (waypoints.length < 2) {
			routeCoordinates = [];
			routeElevations = [];
			updateRouteLine();
			updateDistanceMarkers();
			emitUpdate();
			return false;
		}

		if (!opts.skipBusyToggle) isRouting = true;
		routeVersion++;
		const currentVersion = routeVersion;
		// Clear any stale error from a previous failed attempt.
		onerror(null);

		try {
			// audit/third-party-data-flows: same assertion as snapWaypoints —
			// refuse the community OSRM endpoint in prod. Done inside the try
			// so onerror is reachable if the assertion throws.
			assertOsrmConfiguredForProd();
			// Route each segment — batched in groups of 3 to avoid OSRM rate limits
			const BATCH_SIZE = 3;
			// Per-fetch timeout. The public OSRM demo server is frequently
			// overloaded and can hang for 30s+ before returning a 504; we
			// bail out aggressively so the spinner never lasts longer than
			// (FETCH_TIMEOUT_MS * retries * segments) in the worst case.
			const FETCH_TIMEOUT_MS = 8000;
			const segments: { from: TrackPoint; to: TrackPoint }[] = [];
			for (let i = 0; i < waypoints.length - 1; i++) {
				segments.push({ from: waypoints[i], to: waypoints[i + 1] });
			}
			const segKeys = segments.map((s) => segmentCacheKey(s.from, s.to));

			async function fetchSegment(from: TrackPoint, to: TrackPoint, retries = 2): Promise<unknown> {
				const coords = `${from.lng},${from.lat};${to.lng},${to.lat}`;
				// `radiuses=` caps how far OSRM can reach to find a road for
				// each waypoint. Default OSRM is "unlimited" — that's how a
				// click near a stream ends up snapping to a road 800m away.
				// 100m is loose enough that a click near a known path still
				// snaps but rejects the absurd cases. OSRM returns
				// `code: "NoSegment"` when no road is in range; we treat
				// that as a normal segment failure (counted in okSegments).
				const radius = OSRM_SNAP_RADIUS_M;
				const url = `${OSRM_BASE_URL}/route/v1/foot/${coords}?overview=full&geometries=geojson&radiuses=${radius};${radius}`;
				for (let attempt = 0; attempt <= retries; attempt++) {
					// Honor cancellation between retries. Without this check,
					// a cancelGeneration() call mid-batch had to wait for all
					// 3 retries × FETCH_TIMEOUT_MS per segment to drain
					// before the batch-loop check upstream could fire (up to
					// ~25s of dead-end work per segment). Checking here
					// short-circuits inside the slow path too.
					if (currentVersion !== routeVersion) return { code: 'Error' };
					try {
						const res = await fetch(url, {
							signal: AbortSignal.timeout(FETCH_TIMEOUT_MS)
						});
						// Same check after the await — the cancel might've
						// landed while the fetch was in flight.
						if (currentVersion !== routeVersion) return { code: 'Error' };
						if (res.ok) return res.json();
						if (attempt < retries) await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
					} catch {
						// Timeouts land here as AbortError; network errors too.
						if (currentVersion !== routeVersion) return { code: 'Error' };
						if (attempt < retries) await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
					}
				}
				return { code: 'Error' };
			}

			// Build per-segment results, falling back to a straight line
			// for segments OSRM couldn't snap. The old behaviour silently
			// dropped failed segments, which produced absurd-looking routes
			// (a few hundred metres of snapped path glued together by
			// invisible jumps) and meant a click on an unmapped private
			// path killed the whole save. Now every segment contributes
			// to the merged polyline — the warning banner tells the user
			// which bits are straight-line fallbacks.
			//
			// Each entry starts as its straight-line fallback; a cache hit
			// or a successful fetch upgrades it to ok=true. Only the
			// uncached ("miss") segments hit OSRM, so re-routing after a
			// single new waypoint costs one round-trip, not N.
			const perSegment: {
				ok: boolean;
				from: TrackPoint;
				to: TrackPoint;
				polyline: [number, number][];
				distanceM: number;
			}[] = segments.map((s) => ({
				ok: false,
				from: s.from,
				to: s.to,
				polyline: [
					[s.from.lng, s.from.lat],
					[s.to.lng, s.to.lat],
				],
				distanceM: routingHaversineM(s.from, s.to),
			}));

			const missIdx: number[] = [];
			for (let i = 0; i < segments.length; i++) {
				const hit = segmentCache.get(segKeys[i]);
				if (hit) {
					perSegment[i] = {
						ok: true,
						from: segments[i].from,
						to: segments[i].to,
						polyline: hit.polyline,
						distanceM: hit.distanceM,
					};
				} else {
					missIdx.push(i);
				}
			}

			// Fetch only the cache misses — batched in groups of 3 with a
			// 200ms inter-batch cooldown, same shape as before.
			for (let b = 0; b < missIdx.length; b += BATCH_SIZE) {
				if (currentVersion !== routeVersion) return false;

				const batchIdx = missIdx.slice(b, b + BATCH_SIZE);
				const batchResults = await Promise.all(
					batchIdx.map((i) => fetchSegment(segments[i].from, segments[i].to))
				);
				for (let j = 0; j < batchIdx.length; j++) {
					const i = batchIdx[j];
					const data = batchResults[j] as {
						code: string;
						routes?: { geometry: { coordinates: [number, number][] }; distance?: number }[];
					};
					if (data.code === 'Ok' && data.routes?.[0]) {
						const polyline = data.routes[0].geometry.coordinates;
						const distanceM = data.routes[0].distance ?? 0;
						perSegment[i] = { ok: true, from: segments[i].from, to: segments[i].to, polyline, distanceM };
						// Cache successes only — a straight-line fallback from
						// a transient hiccup must re-try next pass, not stick.
						segmentCache.set(segKeys[i], { polyline, distanceM });
					}
				}

				if (b + BATCH_SIZE < missIdx.length) {
					await new Promise((r) => setTimeout(r, 200));
				}
			}

			if (currentVersion !== routeVersion) return false;

			const okSegments = perSegment.filter((s) => s.ok).length;
			const allCoords: [number, number][] = [];
			for (const s of perSegment) {
				if (allCoords.length > 0 && s.polyline.length > 0) {
					allCoords.push(...s.polyline.slice(1));
				} else {
					allCoords.push(...s.polyline);
				}
			}

			if (okSegments === 0) {
				throw new Error(
					t('routeBuilder.routingServiceUnavailable')
				);
			}
			// Build the implicated-waypoint set from three diagnostics —
			// failed snaps, deviation outliers, and detour-segment
			// endpoints — then push the colour update through
			// updateMarkerStyles() so the user sees red pins for the
			// markers the warning text is naming.
			const implicated = new Set<number>();
			for (const oneBasedIdx of identifyFailedWaypoints(perSegment)) {
				implicated.add(oneBasedIdx - 1);
			}
			// Deviation: per-waypoint distance to the merged polyline.
			// Reuses the qualityWarning threshold (60m) so the marker
			// colour and the banner text refer to the same set of
			// outliers.
			for (let i = 0; i < waypoints.length; i++) {
				const d = closestPointDistanceM(waypoints[i], allCoords);
				if (d > QUALITY_THRESHOLDS.deviationWarnM) implicated.add(i);
			}
			// Detour: paint both endpoints of any segment that took a
			// > 2.5x route between its clicks. Straight-line-fallback
			// segments have ratio exactly 1, so they don't trip this.
			perSegment.forEach((s, i) => {
				const straightLine = routingHaversineM(s.from, s.to);
				if (straightLine < 1) return;
				const ratio = s.distanceM / straightLine;
				if (ratio > QUALITY_THRESHOLDS.detourWarnRatio) {
					implicated.add(i);
					implicated.add(i + 1);
				}
			});

			if (okSegments < perSegment.length) {
				// Partial success — identify the specific waypoints that
				// couldn't snap, fall back to straight lines through them,
				// and tell the user which markers to nudge if they want a
				// snapped route.
				if (!opts.suppressSoftWarnings) {
					const failedWaypoints = identifyFailedWaypoints(perSegment);
					const failedSegments = perSegment.length - okSegments;
					const wpList = formatWaypointRanges(failedWaypoints);
					const wpClause =
						failedWaypoints.length > 0
							? ' ' +
								t(
									failedWaypoints.length === 1
										? 'routeBuilder.waypointCouldntSnapOne'
										: 'routeBuilder.waypointCouldntSnapMany',
									{ list: wpList, radius: OSRM_SNAP_RADIUS_M },
								)
							: ' ' +
								t(
									failedSegments === 1
										? 'routeBuilder.segmentCouldntSnapOne'
										: 'routeBuilder.segmentCouldntSnapMany',
									{ n: failedSegments },
								);
					onerror(
						`${t('routeBuilder.routedSegments', { ok: okSegments, total: perSegment.length })}${wpClause} ${t('routeBuilder.dragRedMarkersSuffix')}`,
						'warning',
					);
				}
			} else {
				// Every segment came back. Now check whether the route
				// actually sticks close to the user's clicks — radiuses=
				// caps the snap at the endpoints but doesn't stop OSRM
				// from routing via a wild detour BETWEEN waypoints.
				const routedSegments: RoutedSegment[] = perSegment.map((s) => ({
					from: s.from,
					to: s.to,
					polyline: s.polyline,
					distanceM: s.distanceM,
				}));
				if (!opts.suppressSoftWarnings) {
					const quality = validateRouteQuality(routedSegments);
					const warn = qualityWarning(quality);
					if (warn) {
						onerror(
							`${warn} ${t('routeBuilder.redMarkersHighlight')}`,
							'warning',
						);
					}
				}
			}

			implicatedWaypoints = implicated;
			updateMarkerStyles();

			routeCoordinates = allCoords;

			const { sampled } = sampleCoordinates(routeCoordinates, 100);
			const elevations = await fetchElevations(sampled);

			if (currentVersion !== routeVersion) return false;

			if (sampled.length < routeCoordinates.length) {
				routeElevations = interpolateElevations(elevations, sampled.length, routeCoordinates.length);
			} else {
				routeElevations = elevations;
			}

			updateRouteLine();
			clearPreviewLine();
			// Clear the straight-line preview now that we have the real route
			const wpSrc = getGeoJSONSource('waypoint-lines');
			wpSrc?.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
			updateDistanceMarkers();
			emitUpdate();
			return true;
		} catch (err) {
			if (currentVersion === routeVersion) {
				console.error('Routing failed:', err);
				// generateLoop wants to replace the generic message with
				// a generation-specific one (the public OSRM was fine,
				// we just couldn't snap any of the scaffolding seeds).
				// Suppress here and let the caller emit its own.
				if (!opts.suppressSoftWarnings) {
					onerror(
						err instanceof Error
							? err.message
							: t('routeBuilder.routingFailed'),
						'error',
					);
				}
				// Clear the stale in-flight route so the UI doesn't show a
				// partial or empty line.
				routeCoordinates = [];
				routeElevations = [];
				updateRouteLine();
				emitUpdate();
			}
			return false;
		} finally {
			if (!opts.skipBusyToggle && currentVersion === routeVersion) {
				isRouting = false;
			}
		}
	}

	function interpolateElevations(sampled: number[], sampledCount: number, totalCount: number): number[] {
		if (sampledCount === 0) return Array(totalCount).fill(0);
		if (sampledCount === 1) return Array(totalCount).fill(sampled[0]);
		const result: number[] = [];
		const step = (sampledCount - 1) / (totalCount - 1);
		for (let i = 0; i < totalCount; i++) {
			const pos = i * step;
			const low = Math.floor(pos);
			const high = Math.min(Math.ceil(pos), sampledCount - 1);
			const frac = pos - low;
			result.push(sampled[low] * (1 - frac) + sampled[high] * frac);
		}
		return result;
	}

	function updateRouteLine() {
		const routeSource = getGeoJSONSource('route');
		const overlapSource = getGeoJSONSource('route-overlap');
		if (!routeSource || !overlapSource) return;

		// Render the full route as a single line — no overlap splitting
		routeSource.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: routeCoordinates } });
		overlapSource.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
	}

	// --- Preview line ---

	function updatePreviewLine(lngLat: { lng: number; lat: number }) {
		const source = getGeoJSONSource('preview-line');
		if (!source || waypoints.length === 0) return;
		// Don't show cursor preview if route is already calculated
		if (routeCoordinates.length > 0) return;
		const last = waypoints[waypoints.length - 1];
		source.setData({
			type: 'Feature', properties: {},
			geometry: { type: 'LineString', coordinates: [[last.lng, last.lat], [lngLat.lng, lngLat.lat]] }
		});
	}

	function clearPreviewLine() {
		const source = getGeoJSONSource('preview-line');
		if (!source) return;
		source.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
	}

	// --- Snap to start detection ---

	function checkSnapToStart(e: maplibregl.MapMouseEvent): boolean {
		if (waypoints.length < 3) { nearStart = false; return false; }
		const startPx = map.project([waypoints[0].lng, waypoints[0].lat]);
		const cursorPx = e.point;
		const dist = Math.sqrt((startPx.x - cursorPx.x) ** 2 + (startPx.y - cursorPx.y) ** 2);
		nearStart = dist < SNAP_DISTANCE_PX;
		updateStartMarkerPulse();
		return nearStart;
	}

	function updateStartMarkerPulse() {
		// With built-in markers, we just rely on the cursor change to indicate snap-to-start
	}

	// --- Click on route to insert waypoint ---

	// Which segment a mid-route click lands on. Delegates to the pure,
	// unit-tested helper that uses true point-to-segment distance — see
	// insert_index.ts for why the old midpoint heuristic mis-picked.
	function findInsertIndex(lngLat: maplibregl.LngLat): number {
		return nearestInsertIndex(waypoints, { lat: lngLat.lat, lng: lngLat.lng });
	}

	function isClickOnRoute(e: maplibregl.MapMouseEvent): boolean {
		if (routeCoordinates.length < 2) return false;
		// Check if click is within 12px of the route line
		const features = map.queryRenderedFeatures(
			[[e.point.x - 12, e.point.y - 12], [e.point.x + 12, e.point.y + 12]],
			{ layers: ['route-line', 'route-overlap-line'] }
		);
		return features.length > 0;
	}

	// --- Stats ---

	function emitUpdate() {
		const gain = calculateElevationGain(routeElevations);
		let distance = 0;
		for (let i = 1; i < routeCoordinates.length; i++) {
			distance += haversine(routeCoordinates[i - 1], routeCoordinates[i]);
		}
		onupdate({
			waypoints: waypoints.length, distance, elevation: gain,
			elevations: routeElevations, coordinates: routeCoordinates,
			routed: routeCoordinates.length >= 2,
			waypointList: waypoints.map((w) => ({ ...w })),
		});
	}

	function haversine(a: [number, number], b: [number, number]): number {
		const R = 6371000;
		const toRad = (d: number) => (d * Math.PI) / 180;
		const dLat = toRad(b[1] - a[1]);
		const dLng = toRad(b[0] - a[0]);
		const sinLat = Math.sin(dLat / 2);
		const sinLng = Math.sin(dLng / 2);
		const h = sinLat * sinLat + Math.cos(toRad(a[1])) * Math.cos(toRad(b[1])) * sinLng * sinLng;
		return R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
	}

	// --- Public API ---

	// Any waypoint mutation after a Calculate Route makes the snapped
	// polyline stale — the user added a back-track / inserted a
	// mid-route point / deleted one, and OSRM hasn't been re-run.
	// Mirror dragend: drop the snapped state so the map reverts to
	// the straight-line preview that includes the new waypoint, and
	// emitUpdate carries the empty `coordinates` array back to the
	// parent so its `routed` flag (gated on coordinates.length >= 2)
	// disables Save until the user recalculates.
	function invalidateCalculatedRoute() {
		// Bump BEFORE the early-return: even when the polyline is
		// already empty, an in-flight recalculateRoute might be a few
		// microseconds away from writing into it. Bumping the version
		// is the only safe signal that "the world changed under you,
		// drop your result."
		routeVersion++;
		if (routeCoordinates.length === 0 && routeElevations.length === 0) return;
		routeCoordinates = [];
		routeElevations = [];
		distanceMarkers.forEach((m) => m.remove());
		distanceMarkers = [];
		updateRouteLine();
	}

	export function addWaypoint(lngLat: { lng: number; lat: number }) {
		if (nearStart && waypoints.length >= 3) {
			lngLat = { lng: waypoints[0].lng, lat: waypoints[0].lat };
		}

		invalidateCalculatedRoute();
		clearImplicatedMarkers();
		const point: TrackPoint = { lat: lngLat.lat, lng: lngLat.lng };
		waypoints.push(point);

		const marker = createWaypointMarker(lngLat, waypoints.length - 1);
		markers.push(marker);
		updateMarkerStyles();
		nearStart = false;
		updateStartMarkerPulse();
		updateStraightLine();
		// Notify the parent so waypointCount / Calculate-button-gating /
		// the empty-state overlay all update. Without this, dropping
		// pins on the map leaves the page in its "Click to start" state
		// and Calculate stays disabled until the user runs Calculate
		// (which won't happen because Calculate is disabled).
		emitUpdate();
		scheduleAutoRoute();
	}

	export function insertWaypoint(lngLat: { lng: number; lat: number }, atIndex: number) {
		invalidateCalculatedRoute();
		clearImplicatedMarkers();
		const point: TrackPoint = { lat: lngLat.lat, lng: lngLat.lng };
		waypoints.splice(atIndex, 0, point);

		const marker = createWaypointMarker(lngLat, atIndex);
		markers.splice(atIndex, 0, marker);
		updateMarkerStyles();
		updateStraightLine();
		emitUpdate();
		scheduleAutoRoute();
	}

	export function removeWaypoint(index: number) {
		// Mutating waypoints mid-routing bumps routeVersion and bails the
		// in-flight iteration half-done — the same hazard the marker
		// contextmenu handler guards against. Guard here too so the
		// keyboard delete path (parent waypoint list) can't hit it.
		if (isRouting) return;
		if (index < 0 || index >= waypoints.length) return;
		if (waypoints.length <= 1 && index === 0) {
			clearWaypoints();
			return;
		}
		invalidateCalculatedRoute();
		clearImplicatedMarkers();
		waypoints.splice(index, 1);
		const marker = markers.splice(index, 1)[0];
		marker?.remove();
		updateMarkerStyles();
		updateStraightLine();
		emitUpdate();
		scheduleAutoRoute();
	}

	/**
	 * Programmatic equivalent of dragging a marker — the keyboard path
	 * (arrow-nudge from the parent's waypoint list) has no drag events,
	 * so it moves the point through here. Mirrors the dragend handler:
	 * invalidate the snapped polyline, reposition the marker, redraw
	 * the preview, re-route.
	 */
	export function moveWaypoint(index: number, lngLat: { lng: number; lat: number }) {
		if (isRouting) return;
		if (index < 0 || index >= waypoints.length) return;
		invalidateCalculatedRoute();
		clearImplicatedMarkers();
		waypoints[index] = { lat: lngLat.lat, lng: lngLat.lng };
		markers[index]?.setLngLat([lngLat.lng, lngLat.lat]);
		updateStraightLine();
		emitUpdate();
		scheduleAutoRoute();
	}

	export function undoWaypoint() {
		if (waypoints.length === 0) return;
		// Invalidate any in-flight recalculateRoute — see invalidateCalculatedRoute.
		routeVersion++;
		clearImplicatedMarkers();
		const popped = waypoints.pop();
		const marker = markers.pop();
		marker?.remove();
		// When the popped waypoint was the closing pin of a loop (it
		// sat on top of waypoints[0]), the remaining sequence is no
		// longer a runnable shape — a subsequent Recalculate would
		// route start → m1 → m2 (half loop). Pop one more so the
		// data ends in a sensibly route-able sequence. Typical
		// trigger: Ctrl+Z after a Generate-by-distance loop.
		if (
			popped &&
			waypoints.length >= 2 &&
			routingHaversineM(popped, waypoints[0]) < NEAR_POINT_M
		) {
			waypoints.pop();
			const m = markers.pop();
			m?.remove();
		}
		updateMarkerStyles();
		clearPreviewLine();
		updateStraightLine();
		emitUpdate();
		scheduleAutoRoute();
	}

	export function clearWaypoints() {
		// Invalidate any in-flight recalculateRoute — Esc during a slow
		// OSRM batch must not let the late result repopulate the polyline.
		routeVersion++;
		// Drop any pending auto-route so a late timer doesn't re-snap a
		// route the user just cleared.
		clearTimeout(autoRouteTimer);
		waypoints = [];
		routeCoordinates = [];
		routeElevations = [];
		implicatedWaypoints = new Set();
		markers.forEach((m) => m.remove());
		markers = [];
		distanceMarkers.forEach((m) => m.remove());
		distanceMarkers = [];
		nearStart = false;
		isRouting = false;
		clearPreviewLine();
		updateRouteLine();
		updateStraightLine();
		emitUpdate();
	}

	/**
	 * Duplicate the route in reverse to create an out-and-back, OR
	 * reverse direction when the current sequence is already a loop.
	 *
	 * For a normal point-to-point sequence: append the waypoints in
	 * reverse (minus the last, which is the turnaround) so OSRM has
	 * to route back the way it came.
	 *
	 * For a loop (waypoints[0] ≈ waypoints[last], typical after the
	 * generate-loop collapse), the classic out-and-back math
	 * produces a nonsensical sequence — `[start, m1, m2, start, m2,
	 * m1]` — that doubles back on the loop instead of out-and-back-
	 * ing. In that case we reverse the interior order so a
	 * Recalculate runs the loop in the opposite direction. This is
	 * what "out & back" effectively means for a closed loop.
	 */
	export function outAndBack() {
		if (waypoints.length < 2) return;
		// Invalidate any in-flight recalculateRoute — see invalidateCalculatedRoute.
		routeVersion++;

		const isLoop =
			waypoints.length >= 3 &&
			routingHaversineM(waypoints[0], waypoints[waypoints.length - 1]) < NEAR_POINT_M;

		// Clear markers first — both branches rebuild from waypoints.
		markers.forEach((m) => m.remove());
		markers = [];

		if (isLoop) {
			// Reverse interior order: [start, m1, m2, ..., close] →
			// [start, ..., m2, m1, close]. start and close are
			// pinned (close still equals start) so the loop stays
			// closed in the new direction.
			const interior = waypoints.slice(1, -1).reverse();
			waypoints = [waypoints[0], ...interior, waypoints[waypoints.length - 1]];
		} else {
			// Classic out-and-back: append reversed waypoints minus
			// the turnaround so OSRM routes back the way it came.
			const reversed = waypoints.slice(0, -1).reverse();
			waypoints = [...waypoints, ...reversed];
		}

		for (let i = 0; i < waypoints.length; i++) {
			const marker = createWaypointMarker(
				{ lng: waypoints[i].lng, lat: waypoints[i].lat },
				i,
			);
			markers.push(marker);
		}
		updateMarkerStyles();

		// Drop the old polyline; the auto-route below re-snaps the new
		// (doubled / reversed) waypoint sequence.
		routeCoordinates = [];
		routeElevations = [];
		updateStraightLine();
		scheduleAutoRoute();
	}

	/**
	 * Switch map style between streets, satellite, and terrain.
	 */
	export function setMapStyle(style: 'streets' | 'satellite' | 'terrain') {
		if (!map || mapStyle === style) return;
		mapStyle = style;
		map.setStyle(MAP_STYLES[style]);

		// Re-add sources and layers after style change
		map.once('style.load', () => {
			addMapSourcesAndLayers();
			// Redraw existing route or straight lines
			if (routeCoordinates.length > 0) {
				updateRouteLine();
			} else {
				updateStraightLine();
			}
		});
	}

	/**
	 * Interrupt an in-flight generate-loop (or calculate-route)
	 * batch. Bumping routeVersion makes recalculateRoute return
	 * false at its next checkpoint, and generateLoop's iteration
	 * version check (`routeVersion !== beforeIter + 1`) bails on
	 * the next loop. The try/finally in generateLoop guarantees
	 * isRouting resets, which fires the onbusy(false) callback
	 * the parent uses to hide the Cancel button.
	 *
	 * Designed for a user-visible Cancel control next to the
	 * spinner — the public OSRM demo's per-segment timeout is 8s,
	 * so a stuck batch can otherwise tie the UI up for ~30s.
	 */
	export function cancelGeneration() {
		if (!isRouting) return;
		routeVersion++;
	}

	/**
	 * Show or hide the pre-generate Start / End picker markers.
	 *
	 * Generate-by-distance lets the user click "Pick start on map" /
	 * "Pick end on map" + click the map to set the loop's anchor
	 * point(s). Pre-fix, those picks updated page-level state but did
	 * NOT paint a marker on the map — the user saw only a text label
	 * in the sidebar and had to click Generate to confirm where their
	 * pick actually landed. Field report:
	 *   "i click the add start location on the map the marker only
	 *    shows after i click Generate X km loop"
	 *
	 * The page now calls these in a $effect so the marker tracks the
	 * picked coords in real time. Both markers are independent of the
	 * `waypoints[]` array — they're transient UI affordances that
	 * `generateLoop` clears as it plants the real seed waypoints.
	 *
	 * Pass `null` to remove a marker (e.g. user cleared the start
	 * pick, or generation has started and is taking over).
	 */
	let generationStartMarker: maplibregl.Marker | undefined;
	let generationEndMarker: maplibregl.Marker | undefined;

	export function setGenerationStart(lngLat: { lng: number; lat: number } | null) {
		generationStartMarker = setGenerationEndpointMarker(
			generationStartMarker,
			lngLat,
			'start',
		);
	}

	export function setGenerationEnd(lngLat: { lng: number; lat: number } | null) {
		generationEndMarker = setGenerationEndpointMarker(
			generationEndMarker,
			lngLat,
			'end',
		);
	}

	function setGenerationEndpointMarker(
		existing: maplibregl.Marker | undefined,
		lngLat: { lng: number; lat: number } | null,
		role: 'start' | 'end',
	): maplibregl.Marker | undefined {
		if (!map) return existing;
		if (!lngLat) {
			existing?.remove();
			return undefined;
		}
		const at: [number, number] = [lngLat.lng, lngLat.lat];
		if (existing) {
			existing.setLngLat(at);
			return existing;
		}
		const el = document.createElement('div');
		el.className = `generation-endpoint generation-endpoint-${role}`;
		el.setAttribute('data-testid', `generation-endpoint-${role}`);
		el.title = role === 'start' ? t('routeBuilder.generateStart') : t('routeBuilder.generateEnd');
		return new maplibregl.Marker({ element: el }).setLngLat(at).addTo(map);
	}

	/**
	 * Try the server-side generator (GraphHopper round_trip via the
	 * /api/routes/generate Lambda). Returns true when it produced a loop
	 * and rendered it; false to tell the caller to fall back to the
	 * in-browser OSRM heuristic — the endpoint is unconfigured (501, e.g.
	 * local dev with no GraphHopper) or the engine is down (502/503).
	 *
	 * Bails to false WITHOUT mutating map state if a cancel (routeVersion
	 * bump) lands during a fetch, and performs no mutation before the
	 * success guards pass, so a fall-through leaves the pre-generate state
	 * untouched for the OSRM path to take over.
	 */
	async function generateLoopFromServer(
		start: { lat: number; lng: number },
		targetDistanceM: number,
		startVersion: number,
		preference?: RoutePreference,
	): Promise<boolean> {
		// Server generation is a Pro perk: the endpoint wants the user JWT in
		// `x-supabase-authorization` (CloudFront's OAC owns `Authorization`).
		// A failed session read just sends no header — the server answers 401
		// and the heuristic fallback takes over, same as any other non-200.
		let token: string | undefined;
		try {
			token = (await supabase.auth.getSession()).data.session?.access_token;
		} catch {
			token = undefined;
		}
		if (routeVersion !== startVersion) return false;
		let res: Response;
		try {
			res = await fetch('/api/routes/generate', {
				method: 'POST',
				headers: {
					'content-type': 'application/json',
					...(token ? { 'X-Supabase-Authorization': `Bearer ${token}` } : {}),
				},
				body: JSON.stringify(
					preference ? { start, targetDistanceM, preference } : { start, targetDistanceM },
				),
			});
		} catch {
			return false;
		}
		if (routeVersion !== startVersion) return false;
		if (res.status === 403) {
			// Free tier — tell the parent so it can offer the upgrade, then let
			// the in-browser heuristic serve the route (the free path).
			try {
				const body = (await res.json()) as { error?: unknown };
				// Re-check after the async body read: a stale request must not pop
				// the upsell for a route the user has already abandoned.
				if (routeVersion === startVersion && body?.error === 'pro_required') onprorequired();
			} catch {
				/* malformed body — treat as a plain failed request */
			}
			return false;
		}
		if (!res.ok) return false;
		let data: { coordinates?: unknown; distanceM?: unknown; largestLoopM?: unknown };
		try {
			data = await res.json();
		} catch {
			return false;
		}
		if (routeVersion !== startVersion) return false;
		const coords = data?.coordinates;
		if (!Array.isArray(coords) || coords.length < 2) return false;
		const polyline = coords as [number, number][];
		// Largest genuinely clean loop the graph search found near this start (only
		// present when the served loop is an out-and-back fallback). Powers the
		// "best loop near you is ~X km" choice below.
		const largestLoopM =
			typeof data.largestLoopM === 'number' && Number.isFinite(data.largestLoopM) && data.largestLoopM > 0
				? data.largestLoopM
				: undefined;

		// Render the finished server polyline directly — no OSRM re-route.
		markers.forEach((mk) => mk.remove());
		markers = [];
		routeCoordinates = polyline;

		const { sampled } = sampleCoordinates(routeCoordinates, 100);
		const elevations = await fetchElevations(sampled);
		if (routeVersion !== startVersion) return false;
		routeElevations =
			sampled.length < routeCoordinates.length
				? interpolateElevations(elevations, sampled.length, routeCoordinates.length)
				: elevations;

		updateRouteLine();
		clearPreviewLine();
		const wpSrc = getGeoJSONSource('waypoint-lines');
		wpSrc?.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
		updateDistanceMarkers();
		// Collapse to start + two sampled midpoints + close so a later
		// manual Recalculate reproduces the loop; rebuilds visible markers
		// and emits the routed update.
		collapseGeneratedScaffolding(start, undefined);

		// Warn using the rendered polyline's own length (haversine sum) so
		// the message matches the sidebar stat exactly. round_trip hits the
		// target far more reliably than the old heuristic, so this rarely
		// fires — but a genuinely constrained network can still fall short.
		let actualDistance = 0;
		for (let i = 1; i < routeCoordinates.length; i++) {
			actualDistance += haversine(routeCoordinates[i - 1], routeCoordinates[i]);
		}
		if (!isWithinAcceptBand(targetDistanceM, actualDistance)) {
			const longer = actualDistance > targetDistanceM;
			const pct = Math.round((Math.abs(actualDistance - targetDistanceM) / targetDistanceM) * 100);
			onerror(
				t(longer ? 'routeBuilder.generatedDistanceLonger' : 'routeBuilder.generatedDistanceShorter', {
					distance: formatDistance(actualDistance),
					pct,
					target: formatDistance(targetDistanceM),
				}),
				'warning',
			);
			// Hand the parent the structured shortfall so it can offer the explicit
			// 3-way choice — generate the largest real loop nearby (largestLoopM),
			// accept this achievable out-and-back distance, or try a different start.
			// The road network here can't form a clean loop at the target.
			ongeneratemismatch(actualDistance, targetDistanceM, largestLoopM);
		} else {
			onerror(null);
		}
		return true;
	}

	/**
	 * Generate a loop route of approximately the target distance from the start point.
	 */
	export async function generateLoop(
		targetDistanceM: number,
		startFrom?: { lat: number; lng: number },
		endAt?: { lat: number; lng: number },
		preference?: RoutePreference
	): Promise<boolean> {
		// Refuse re-entry. generateLoop overwrites waypoints + markers on
		// every iteration; a second concurrent call would have its state
		// trampled by the first call's next iteration mid-flight.
		if (isRouting) return false;
		// Refuse before-map-ready. The fallback below reads map.getCenter()
		// directly and would crash on undefined.
		if (!map) return false;
		// Reject garbage targets — NaN / Infinity / non-positive — so a
		// caller bug can't push the iteration into an infinite or
		// degenerate scaleFactor chase. The slider in /routes/new
		// already clamps to [1, 42] km but this is the API boundary.
		if (!isValidTargetDistance(targetDistanceM)) return false;
		// Refuse when the user hasn't picked a start AND the map is
		// still showing the world view (zoom < 6 = continental scale).
		// Without this, generation runs from map.getCenter() which is
		// [0, 20] (mid-Atlantic) when geolocation was denied — every
		// waypoint lands in the ocean and generation hard-fails with a
		// confusing "Routing service unavailable" error.
		if (!startFrom && map.getZoom() < 6) {
			onerror(
				t('routeBuilder.panAndPickStart'),
				'error',
			);
			return false;
		}

		const start: { lat: number; lng: number } = startFrom
			? { lat: startFrom.lat, lng: startFrom.lng }
			: (() => { const c = map.getCenter(); return { lat: c.lat, lng: c.lng }; })();

		let scaleFactor = DEFAULT_SCALE_FACTOR;
		// Deterministic per-call seed so the three attempts all radiate
		// from the same orientation — comparing actual vs target distance
		// across runs with a re-randomised pattern would chase noise.
		const radialSeedRad = Math.random() * Math.PI * 2;
		const maxAttempts = 4;
		let scaleRange = initScaleRange();
		// Track the best (closest-to-target) attempt across iterations.
		// OSRM's actual distance is a noisy function of scale in twisty
		// suburban grids — the iteration can oscillate without ever
		// landing in the ±15% acceptance band. We always want to keep
		// whichever attempt got closest, not whichever happened to be
		// the last one tried.
		let bestPolyline: [number, number][] | null = null;
		let bestElevations: number[] = [];
		let bestDistance = Infinity;
		let bestDelta = Infinity;

		// Snapshot the pre-generate state for restore-on-failure.
		// Without this, a Cancel or hard-failure exit would leave the
		// iteration's scaffolding (8 waypoints, only `start` visible) on
		// the map — the user is stranded with an inconsistent state they
		// can't recover from short of pressing Esc.
		preRouteWaypoints = waypoints.map((w) => ({ ...w }));

		// Hold isRouting=true across the whole iteration loop. Without
		// this, recalculateRoute's own finally would flip it back to
		// false between attempts — admitting user clicks and flickering
		// the spinner. The try/finally below also guarantees the flag
		// resets even if the iteration throws.
		isRouting = true;
		// Tracks whether the post-loop processing finished with a
		// successful collapse. The finally below uses it to restore
		// the pre-generate snapshot when the iteration bailed (cancel,
		// mutation race, every attempt failed to route).
		let success = false;
		try {

		// Loop case (no distinct end pin): try the server-side GraphHopper
		// round_trip generator first. It hits the target distance far more
		// reliably than the radial-scaffold heuristic below, which is kept
		// only as the fallback when the endpoint is unconfigured (dev) or
		// the engine is down. Point-to-point (distinct end) stays on the
		// heuristic — round_trip is loop-only.
		const isLoopCase =
			!endAt ||
			routingHaversineM(
				{ lng: start.lng, lat: start.lat },
				{ lng: endAt.lng, lat: endAt.lat },
			) < NEAR_POINT_M;
		if (isLoopCase) {
			const startVersion = routeVersion;
			const served = await generateLoopFromServer(start, targetDistanceM, startVersion, preference);
			if (routeVersion !== startVersion) return false;
			if (served) {
				success = true;
				return true;
			}
		}

		for (let attempt = 0; attempt < maxAttempts; attempt++) {
			// Capture before the iteration's mutations so we can detect a
			// non-gated interruption (Esc / drag / right-click / Ctrl+Z)
			// that fired during the awaited recalculateRoute. Those paths
			// bump routeVersion via invalidateCalculatedRoute or directly;
			// recalculateRoute bumps it exactly once. So a healthy
			// iteration ends with routeVersion === beforeIter + 1. Anything
			// greater means someone else mutated mid-flight — bail
			// instead of overwriting their state on the next iteration.
			const beforeIter = routeVersion;

			const seeds = generateLoopWaypoints({
				start,
				end: endAt,
				targetDistanceM,
				scaleFactor,
				radialSeedRad,
			});
			// Snap each interior seed to the nearest road BEFORE
			// routing. Without this, a radial seed often lands
			// mid-block (a yard, a parking lot, a stretch of road
			// with no nearby intersection) and OSRM has to route a
			// long detour to reach it — visible as the "stops half
			// way down a road and misses a nice loop" symptom.
			// snapWaypointsToRoads keeps endpoints exact (the user
			// pinned them) and dedupes adjacent snaps that landed on
			// the same street so two seeds don't force a tiny back-
			// and-forth on the same edge.
			const newWaypoints = await snapWaypointsToRoads(seeds, beforeIter);
			if (routeVersion !== beforeIter) return false;

			markers.forEach((m) => m.remove());
			markers = [];
			waypoints = newWaypoints;
			// Render visible markers only for the endpoints (start +
			// close-for-point-to-point); the interior radial waypoints
			// are scaffolding for OSRM, not user clicks, and flashing
			// rings of pins across bisection attempts looks broken.
			// They stay in the markers array (so indexOf-based handlers
			// keep pointing at the right waypoint) but with
			// display:none on the DOM element. The post-loop collapse
			// rebuilds visible markers for the anchors.
			const lastIdx = waypoints.length - 1;
			for (let i = 0; i < waypoints.length; i++) {
				const isEndpoint = i === 0 || (endAt != null && i === lastIdx);
				const marker = createWaypointMarker(
					{ lng: waypoints[i].lng, lat: waypoints[i].lat },
					i,
					false,
					!isEndpoint,
				);
				markers.push(marker);
			}
			updateMarkerStyles();
			routeCoordinates = [];
			routeElevations = [];

			await recalculateRoute({ skipBusyToggle: true, suppressSoftWarnings: true });

			if (routeVersion !== beforeIter + 1) return false;

			if (routeCoordinates.length < 2) break;

			let actualDistance = 0;
			for (let i = 1; i < routeCoordinates.length; i++) {
				actualDistance += haversine(routeCoordinates[i - 1], routeCoordinates[i]);
			}

			// Track the closest-to-target attempt so we can restore it
			// if subsequent iterations drift away.
			const delta = Math.abs(targetDistanceM - actualDistance);
			if (delta < bestDelta) {
				bestDelta = delta;
				bestDistance = actualDistance;
				bestPolyline = routeCoordinates.slice();
				bestElevations = routeElevations.slice();
			}

			if (isWithinAcceptBand(targetDistanceM, actualDistance)) break;
			// Bisection beats the multiplicative-ratio approach when
			// OSRM's response is non-monotonic (small scale change
			// flips a segment between a direct road and a multi-block
			// detour). Each attempt narrows [lower, upper] from one
			// side, so 4 attempts shrink the [0.05, 2] starting range
			// to ~1/16 of its width — more than enough to surround
			// the target unless the road network can't get there.
			const advised = bisectScale(scaleRange, scaleFactor, targetDistanceM, actualDistance);
			scaleFactor = advised.scale;
			scaleRange = advised.range;
		}

		// If the last attempt drifted away from the best one, restore.
		if (bestPolyline && routeCoordinates.length >= 2) {
			let currentDistance = 0;
			for (let i = 1; i < routeCoordinates.length; i++) {
				currentDistance += haversine(routeCoordinates[i - 1], routeCoordinates[i]);
			}
			const currentDelta = Math.abs(targetDistanceM - currentDistance);
			if (bestDelta < currentDelta) {
				routeCoordinates = bestPolyline;
				routeElevations = bestElevations;
				updateRouteLine();
				updateDistanceMarkers();
			}
		}

		updateStraightLine();

		// Collapse the algorithm's 8 scaffolding waypoints down to the
		// 4 anchors the user actually cares about: their start, two
		// midpoints sampled from the snapped polyline (at ~1/3 and
		// ~2/3 along), and the close. The 6 interior radial seeds
		// were implementation detail. 4 anchors is the minimum that
		// lets a manual Recalculate reproduce the loop — start →
		// close on its own would degenerate (no route, or a straight
		// shortcut for point-to-point); 3 collapses a loop into an
		// out-and-back. Anchors sampled FROM the polyline have zero
		// deviation, so the deviation/detour warnings stay quiet by
		// construction.
		if (routeCoordinates.length >= 2) {
			collapseGeneratedScaffolding(start, endAt);
			// Tell the user when we couldn't get close to their target
			// instead of silently shipping an 8 mi "3 mi" loop. The
			// road network in some areas (twisty suburbs, sparse
			// rural) forces OSRM to take long detours regardless of
			// the seed pattern; we surface that honestly instead of
			// hiding it behind the success path.
			if (bestDistance !== Infinity && !isWithinAcceptBand(targetDistanceM, bestDistance)) {
				const longer = bestDistance > targetDistanceM;
				const pct = Math.round((Math.abs(bestDistance - targetDistanceM) / targetDistanceM) * 100);
				onerror(
					t(longer ? 'routeBuilder.generatedDistanceLonger' : 'routeBuilder.generatedDistanceShorter', { distance: formatDistance(bestDistance), pct, target: formatDistance(targetDistanceM) }),
					'warning',
				);
			} else {
				onerror(null);
			}
			success = true;
			return true;
		}
		// Hard failure: every iteration's recalculateRoute either
		// snapped no segments (radius too small for the road network)
		// or got interrupted by a mutation. The generic "Routing
		// service unavailable" was suppressed (suppressSoftWarnings)
		// so we can surface a generation-specific message instead.
		onerror(
			t('routeBuilder.couldntGenerateLoop', { target: formatDistance(targetDistanceM) }),
			'error',
		);
		return false;
		} finally {
			if (!success) {
				// Restore the pre-generate state — clears scaffolding
				// markers, repopulates whatever waypoints the user had
				// before (often none), and refreshes the preview line.
				// Idempotent against early returns from the version
				// check inside the for-loop, the break on
				// routeCoordinates.length<2, and the hard-failure path.
				restoreFromPreRouteSnapshot();
			}
			isRouting = false;
		}
	}

	/// Mirror of the start of collapseGeneratedScaffolding but using
	/// preRouteWaypoints as the source. Called from generateLoop's
	/// finally when success is false so the user isn't left with
	/// a half-baked scaffolding state on cancel or hard failure.
	function restoreFromPreRouteSnapshot() {
		markers.forEach((m) => m.remove());
		markers = [];
		waypoints = preRouteWaypoints.map((w) => ({ ...w }));
		routeCoordinates = [];
		routeElevations = [];
		implicatedWaypoints = new Set();
		distanceMarkers.forEach((m) => m.remove());
		distanceMarkers = [];
		for (let i = 0; i < waypoints.length; i++) {
			const marker = createWaypointMarker(
				{ lng: waypoints[i].lng, lat: waypoints[i].lat },
				i,
			);
			markers.push(marker);
		}
		updateMarkerStyles();
		updateRouteLine();
		updateStraightLine();
	}

	function collapseGeneratedScaffolding(
		start: { lat: number; lng: number },
		endAt?: { lat: number; lng: number },
	) {
		if (routeCoordinates.length < 2) return;
		const close = endAt ?? start;
		const anchors = selectLoopAnchors(routeCoordinates, start, close);

		markers.forEach((m) => m.remove());
		markers = [];
		waypoints = anchors.map((a) => ({ lat: a.lat, lng: a.lng }));
		// The previous implicated-waypoint indices referenced the
		// scaffolding set we just discarded; clear before rebuilding
		// markers so updateMarkerStyles doesn't paint random pins red.
		implicatedWaypoints = new Set();
		for (let i = 0; i < waypoints.length; i++) {
			const marker = createWaypointMarker(
				{ lng: waypoints[i].lng, lat: waypoints[i].lat },
				i,
			);
			markers.push(marker);
		}
		updateMarkerStyles();
		// Sync the parent's waypointCount stat (collapsed from 8 to 4
		// or fewer) without changing the snapped polyline.
		emitUpdate();
	}

	export function getMapStyle() { return mapStyle; }
	export function getMapCenter() { return map ? map.getCenter() : null; }

	/**
	 * Recentre the map on a point. When the style has finished loading we
	 * animate a short pan; before then we snap with jumpTo.
	 *
	 * Why the load gate: an animated flyTo silently no-ops until the map is
	 * loaded, because the render loop that advances the easing only starts once
	 * the style is in. A recentre fired in that window (the style is slow to
	 * return from MapTiler, or absent in e2e) would be dropped and the map would
	 * sit frozen at its initial centre — exactly what intermittently failed the
	 * route-builder recentre e2e tests. jumpTo sets the camera immediately and
	 * works regardless of load state, so the recentre is never lost.
	 */
	function recentreMap(center: [number, number], zoom: number) {
		if (!map) return;
		if (map.loaded()) {
			map.flyTo({ center, zoom, duration: RECENTRE_FLY_MS });
		} else {
			map.jumpTo({ center, zoom });
		}
	}

	/**
	 * Pan + zoom the map to a point. Used by the sidebar's "use my
	 * location" / typed-coordinate / pick affordances so setting a
	 * Generate start/end gives visual confirmation — pre-fix those only
	 * updated a sidebar label and painted a marker that could be
	 * off-screen, so on the default world view the click looked dead.
	 */
	export function flyTo(lngLat: { lng: number; lat: number }, zoom = 15) {
		recentreMap([lngLat.lng, lngLat.lat], zoom);
	}

	/**
	 * Show straight dashed lines between waypoints as a preview before routing.
	 */
	function updateStraightLine() {
		const wpSource = getGeoJSONSource('waypoint-lines');
		if (!wpSource) return;

		// If we have a calculated route, hide the straight-line preview
		if (routeCoordinates.length > 0) {
			wpSource.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
			return;
		}

		// No calculated route — clear route/overlap and show straight-line preview
		const routeSource = getGeoJSONSource('route');
		const overlapSource = getGeoJSONSource('route-overlap');
		if (routeSource) {
			routeSource.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
		}
		if (overlapSource) {
			overlapSource.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
		}

		if (waypoints.length < 2) {
			wpSource.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
			emitUpdate();
			return;
		}

		// Draw dashed straight lines between waypoints
		const coords: [number, number][] = waypoints.map((w) => [w.lng, w.lat]);
		wpSource.setData({
			type: 'Feature', properties: {},
			geometry: { type: 'LineString', coordinates: coords }
		});

		// Emit basic distance estimate from straight lines
		let distance = 0;
		for (let i = 1; i < coords.length; i++) {
			distance += haversine(coords[i - 1], coords[i]);
		}
		onupdate({
			waypoints: waypoints.length, distance, elevation: 0,
			elevations: [], coordinates: coords,
			// Straight-line preview, not a snapped path — Save must
			// stay disabled until the user actually calculates or
			// generates a route.
			routed: false,
			waypointList: waypoints.map((w) => ({ ...w })),
		});
	}

	export function getRouteData() {
		return {
			waypoints: [...waypoints],
			coordinates: [...routeCoordinates],
			elevations: [...routeElevations]
		};
	}

	// --- Map setup ---

	function startMap() {
		if (map || !mapContainer) return;
		const defaultCenter: [number, number] = [0, 20];
		const defaultZoom = 2;

		const doInit = (center: [number, number], zoom: number) => {
			map = new maplibregl.Map({
				container: mapContainer,
				style: MAP_STYLES.streets,
				center, zoom
			});
			setupMap();
		};

		navigator.geolocation.getCurrentPosition(
			(pos) => doInit([pos.coords.longitude, pos.coords.latitude], 16),
			() => doInit(defaultCenter, defaultZoom),
			// Keep the timeout short so a cold start doesn't delay the map render,
			// but accept a cached fix (maximumAge) so a recent position centres on
			// the user instantly instead of falling back to defaultCenter.
			{ timeout: 3000, maximumAge: 600000 }
		);
	}

	function loadMapNow() {
		mapConsented = true;
		// The map container only mounts once `mapConsented` flips, so
		// wait one microtask for the DOM before initialising.
		queueMicrotask(startMap);
	}

	onMount(() => {
		if (mapConsented) startMap();

		// Keyboard shortcuts
		keyHandler = (e: KeyboardEvent) => {
			// Don't trigger shortcuts when typing in search
			if (e.target instanceof HTMLInputElement) return;

			if ((e.metaKey || e.ctrlKey) && e.key === 'z') {
				e.preventDefault();
				// Ctrl+Z during isRouting would mutate waypoints and
				// bail the iteration. Esc below stays enabled — it
				// doubles as cancel-and-clear, which is the user's
				// intentional "stop everything" escape hatch.
				if (isRouting) return;
				undoWaypoint();
			}
			if (e.key === 'Escape') {
				// Route Esc through the parent's clear-request hook so it sits
				// behind the same confirm dialog as the Clear button. When the
				// parent takes ownership (opens a confirm), stop the event here:
				// the confirm dialog mounts a window-level Escape-to-close
				// listener during this same keypress, and window is later in the
				// bubble order than this document listener — without stopping it,
				// the very keystroke that opens the dialog would also dismiss it.
				if (onrequestclear()) {
					e.stopPropagation();
				} else {
					clearWaypoints();
				}
			}
		};
		document.addEventListener('keydown', keyHandler);
	});

	function goToMyLocation() {
		// `navigator.geolocation` is gated to secure contexts in
		// modern browsers (localhost counts as secure). On `http://`
		// over a LAN it'll be undefined — surface that explicitly.
		if (!navigator.geolocation) {
			showToast(t('routeBuilder.geolocationNeedsHttps'), 'error');
			return;
		}
		// The previous handler had an empty error callback, so a
		// denied permission, position-unavailable, or timeout left
		// the user staring at a non-responsive button. Surface each
		// failure mode as a toast so the user knows the click landed.
		navigator.geolocation.getCurrentPosition(
			(pos) => recentreMap([pos.coords.longitude, pos.coords.latitude], 17),
			(err) => {
				// Compare against the numeric `code` literals from the
				// GeolocationPositionError spec — not `err.PERMISSION_DENIED`
				// etc., because those constants aren't reliably present on
				// the error instance in every implementation (they live on
				// the prototype interface).
				const msg =
					err.code === 1
						? t('routeBuilder.locationPermissionDenied')
						: err.code === 2
							? t('routeBuilder.locationUnavailable')
							: err.code === 3
								? t('routeBuilder.locationTimedOut')
								: t('routeBuilder.locationFailed');
				showToast(msg, 'error');
			},
			// Accept a cached fix up to 60s old (maximumAge) so a repeat click
			// returns instantly instead of forcing a fresh network fix, and give
			// a cold desktop/Brave fix a realistic 15s. The old `{ timeout: 5000 }`
			// with the default maximumAge:0 forced a fresh IP/Wi-Fi lookup every
			// click and routinely timed out before it could resolve.
			{ enableHighAccuracy: false, timeout: 15000, maximumAge: 60000 },
		);
	}

	function addMapSourcesAndLayers() {
		const empty = { type: 'Feature' as const, properties: {}, geometry: { type: 'LineString' as const, coordinates: [] as [number, number][] } };
		map.addSource('route', { type: 'geojson', data: empty });
		map.addSource('route-overlap', { type: 'geojson', data: empty });
		map.addSource('preview-line', { type: 'geojson', data: empty });
		map.addSource('waypoint-lines', { type: 'geojson', data: empty });

		map.addLayer({
			id: 'route-casing', type: 'line', source: 'route',
			paint: { 'line-color': '#1d4ed8', 'line-width': 8, 'line-opacity': 0.25 },
			layout: { 'line-join': 'round', 'line-cap': 'round' }
		});
		map.addLayer({
			id: 'route-line', type: 'line', source: 'route',
			paint: { 'line-color': '#3b82f6', 'line-width': 4 },
			layout: { 'line-join': 'round', 'line-cap': 'round' }
		});
		map.addLayer({
			id: 'route-overlap-casing', type: 'line', source: 'route-overlap',
			paint: { 'line-color': '#9333ea', 'line-width': 8, 'line-opacity': 0.25 },
			layout: { 'line-join': 'round', 'line-cap': 'round' }
		});
		map.addLayer({
			id: 'route-overlap-line', type: 'line', source: 'route-overlap',
			paint: { 'line-color': '#a855f7', 'line-width': 4 },
			layout: { 'line-join': 'round', 'line-cap': 'round' }
		});
		map.addLayer({
			id: 'route-arrows', type: 'symbol', source: 'route',
			layout: {
				'symbol-placement': 'line', 'symbol-spacing': 80,
				'text-field': '▶', 'text-size': 12,
				'text-rotation-alignment': 'map', 'text-keep-upright': false
			},
			paint: { 'text-color': '#1d4ed8' }
		});
		map.addLayer({
			id: 'waypoint-lines', type: 'line', source: 'waypoint-lines',
			paint: { 'line-color': '#3b82f6', 'line-width': 2.5, 'line-dasharray': [6, 4], 'line-opacity': 0.6 },
			layout: { 'line-join': 'round', 'line-cap': 'round' }
		});
		map.addLayer({
			id: 'preview-line', type: 'line', source: 'preview-line',
			paint: { 'line-color': '#94a3b8', 'line-width': 2, 'line-dasharray': [4, 4] }
		});
	}

	function setupMap() {
		map.addControl(new maplibregl.NavigationControl(), 'top-right');
		// Auto-resize on any container dimension change. Catches the
		// initial-mount mismeasurement (flex children don't always
		// have their final rect at mount) AND any later SplitPane
		// drag. See `$lib/routes/map_resize` for the why.
		stopResizeWatch = watchMapResize(mapContainer, map);

		// Single load handler for all map setup
		let locationMarker: maplibregl.Marker | null = null;

		map.on('load', () => {
			// User location dot (non-interactive, clicks pass through)
			geoWatchId = navigator.geolocation.watchPosition(
				(pos) => {
					const lngLat: [number, number] = [pos.coords.longitude, pos.coords.latitude];
					if (!locationMarker) {
						const el = document.createElement('div');
						el.className = 'user-location-dot';
						locationMarker = new maplibregl.Marker({ element: el }).setLngLat(lngLat).addTo(map);
					} else {
						locationMarker.setLngLat(lngLat);
					}
				},
				() => {},
				{ enableHighAccuracy: true }
			);
			addMapSourcesAndLayers();
		});

		// Click handler — let parent intercept first, then insert mid-route or append
		map.on('click', (e: maplibregl.MapMouseEvent) => {
			if (isRouting) return;

			// Let parent handle the click (e.g. for picking start/end point)
			if (onmapclick(e.lngLat)) return;

			// Only consider mid-route insertion if:
			// 1. Clicking on the route line
			// 2. There are 3+ waypoints (need at least a "middle")
			// 3. The click is NOT near the last waypoint (user is extending, not inserting)
			if (isClickOnRoute(e) && waypoints.length >= 3) {
				const lastWp = waypoints[waypoints.length - 1];
				const distToLast = haversine(
					[e.lngLat.lng, e.lngLat.lat],
					[lastWp.lng, lastWp.lat]
				);
				// If click is more than 100m from the last waypoint, it's a mid-route insert
				if (distToLast > 100) {
					const idx = findInsertIndex(e.lngLat);
					// Only insert if it's not at the end
					if (idx < waypoints.length) {
						insertWaypoint(e.lngLat, idx);
						return;
					}
				}
			}
			addWaypoint(e.lngLat);
		});

		// Mouse move: preview line + snap detection + cursor changes
		map.on('mousemove', (e: maplibregl.MapMouseEvent) => {
			if (waypoints.length > 0) {
				updatePreviewLine(e.lngLat);
			}
			checkSnapToStart(e);

			// Change cursor when hovering mid-route (not near end)
			let showInsertCursor = false;
			if (routeCoordinates.length >= 2 && waypoints.length >= 3 && isClickOnRoute(e)) {
				const lastWp = waypoints[waypoints.length - 1];
				const distToLast = haversine([e.lngLat.lng, e.lngLat.lat], [lastWp.lng, lastWp.lat]);
				showInsertCursor = distToLast > 100;
			}

			if (showInsertCursor) {
				map.getCanvas().style.cursor = 'copy';
			} else if (nearStart) {
				map.getCanvas().style.cursor = 'pointer';
			} else {
				map.getCanvas().style.cursor = 'crosshair';
			}
		});

		map.on('mouseout', () => {
			clearPreviewLine();
			nearStart = false;
			updateStartMarkerPulse();
			map.getCanvas().style.cursor = 'crosshair';
		});

		// Disable context menu on map
		map.getCanvas().addEventListener('contextmenu', (e) => e.preventDefault());
	}

	onDestroy(() => {
		clearTimeout(searchTimeout);
		if (geoWatchId !== null) navigator.geolocation.clearWatch(geoWatchId);
		stopResizeWatch?.();
		markers.forEach((m) => m.remove());
		distanceMarkers.forEach((m) => m.remove());
		map?.remove();
		if (keyHandler) document.removeEventListener('keydown', keyHandler);
	});

	// When mode changes, clear any calculated route so user re-calculates
	$effect(() => {
		const _mode = mode;
		if (routeCoordinates.length > 0) {
			routeCoordinates = [];
			routeElevations = [];
			updateStraightLine();
		}
	});
</script>

<div class="map-wrapper">
	{#if mapConsented}
	<div class="search-box">
		<div class="search-row">
			<input
				bind:this={searchInput}
				bind:value={searchQuery}
				oninput={onSearchInput}
				onfocusout={() => setTimeout(() => (showResults = false), 200)}
				onfocusin={() => { if (searchResults.length > 0) showResults = true; }}
				type="text"
				placeholder={t('routeBuilder.searchPlaceholder')}
			/>
			<button class="locate-btn" onclick={goToMyLocation} title={t('routeBuilder.goToMyLocation')} aria-label={t('routeBuilder.goToMyLocation')}>
				<span class="material-symbols">my_location</span>
			</button>
		</div>
		{#if showResults}
			<ul class="search-results">
				{#each searchResults as result}
					<li>
						<button onmousedown={() => selectSearchResult(result)}>
							{result.name}
						</button>
					</li>
				{/each}
			</ul>
		{/if}
	</div>

	{#if isRouting}
		<div class="routing-indicator">
			<div class="routing-spinner"></div>
			{t('routeBuilder.calculatingRoute')}
		</div>
	{/if}

	<div class="shortcuts-hint">
		<span><kbd>Ctrl</kbd>+<kbd>Z</kbd> {t('routeBuilder.shortcutUndo')}</span>
		<span><kbd>Esc</kbd> {t('routeBuilder.shortcutClear')}</span>
		<span>{t('routeBuilder.shortcutRightClickDelete')}</span>
	</div>
	{/if}

	<div bind:this={mapContainer} class="map-container"></div>

	{#if !mapConsented}
		<!--
			audit/cookie-consent: MapTiler logs the requester IP per tile
			fetch, so the builder basemap loads only after the visitor
			opts in. Overlaid on the (empty) map container so the bind
			stays stable for when the map does initialise.
		-->
		<div class="map-consent" data-testid="route-builder-consent">
			<div class="map-consent-card">
				<h3>{t('runMap.consentTitle')}</h3>
				<p>
					{t('runMap.consentPrefix')}<strong>MapTiler</strong>{t('runMap.consentMiddle')}<strong>{t('runMap.loadMap')}</strong>{t('runMap.consentBeforeLink')}<a href="/cookie-notice">{t('runMap.cookieNotice')}</a>{t('runMap.consentSuffix')}
				</p>
				<button type="button" class="btn btn-primary" onclick={loadMapNow}>
					{t('runMap.loadMap')}
				</button>
			</div>
		</div>
	{/if}
</div>

<style>
	.map-wrapper {
		width: 100%;
		height: 100%;
		position: relative;
	}

	.map-container {
		width: 100%;
		height: 100%;
	}

	.map-consent {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		z-index: 3;
	}

	.map-consent-card {
		max-width: 28rem;
		text-align: center;
		padding: var(--space-lg) var(--space-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
		color: var(--color-text);
	}

	.map-consent-card h3 {
		margin: 0 0 var(--space-sm);
		font-size: 1.05rem;
	}

	.map-consent-card p {
		margin: 0 0 var(--space-md);
		color: var(--color-text-secondary);
		line-height: 1.5;
		font-size: 0.9rem;
	}

	/* Numbered waypoint markers — parity with the mobile twin. The
	   1-based label sits inside the coloured dot so users can count
	   waypoints + tell which pin to drag when a route has many.
	   Hidden scaffolding pins from generate-loop iterations skip
	   the label (the dot is still here but `display:none` on the
	   parent .maplibregl-marker hides the whole element). */
	:global(.waypoint-marker) {
		cursor: pointer;
	}
	:global(.waypoint-marker-dot) {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 26px;
		height: 26px;
		border-radius: 50%;
		border: 2px solid #fff;
		box-shadow: 0 1px 4px rgba(0, 0, 0, 0.35);
	}
	:global(.waypoint-marker-label) {
		color: #fff;
		font-size: 11px;
		font-weight: 700;
		line-height: 1;
		font-family:
			system-ui,
			-apple-system,
			sans-serif;
	}

	/* Search */
	.search-box {
		position: absolute;
		top: 12px;
		inset-inline-start: 12px;
		z-index: 10;
		width: 320px;
	}

	.search-row {
		display: flex;
		gap: 6px;
	}

	.search-box input {
		flex: 1;
		padding: 10px 14px;
		border: none;
		border-radius: 8px;
		font-size: 0.9rem;
		background: var(--color-surface);
		color: var(--color-text);
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
	}

	.search-box input:focus {
		outline: none;
		box-shadow: 0 2px 12px rgba(0, 0, 0, 0.25);
	}
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	.search-box input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}


	.locate-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 40px;
		height: 40px;
		border: none;
		border-radius: 8px;
		background: var(--color-surface);
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
		cursor: pointer;
		color: var(--color-text);
		flex-shrink: 0;
	}

	.locate-btn:hover {
		background: var(--color-bg-tertiary);
		color: var(--color-primary);
	}

	.locate-btn .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.2rem;
	}

	.search-results {
		list-style: none;
		margin: 4px 0 0;
		padding: 0;
		background: var(--color-surface);
		border-radius: 8px;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
		overflow: hidden;
	}

	.search-results li button {
		display: block;
		width: 100%;
		padding: 10px 14px;
		border: none;
		background: none;
		text-align: start;
		font-size: 0.85rem;
		cursor: pointer;
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.search-results li button:hover {
		background: var(--color-bg-tertiary);
	}

	.search-results li + li {
		border-top: 1px solid var(--color-border);
	}

	/* Routing indicator */
	.routing-indicator {
		position: absolute;
		top: 12px;
		left: 50%;
		transform: translateX(-50%);
		z-index: 10;
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 8px 16px;
		background: var(--color-surface);
		border-radius: 20px;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
		font-size: 0.8rem;
		font-weight: 500;
		color: var(--color-primary);
	}

	.routing-spinner {
		width: 14px;
		height: 14px;
		border: 2px solid var(--color-border);
		border-top-color: var(--color-primary);
		border-radius: 50%;
		animation: spin 0.6s linear infinite;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	/* Keyboard shortcuts hint. Pinned bottom-RIGHT, not bottom-left:
	   the parent page's "Click anywhere to start" empty-state card
	   (.canvas-empty) owns the bottom-left corner, and the two used to
	   stack — this hint (z-index 10) covered the onboarding card
	   (z-index 5). Bottom-right is otherwise free (MapLibre's nav
	   control is top-right). */
	.shortcuts-hint {
		position: absolute;
		bottom: 12px;
		inset-inline-end: 12px;
		z-index: 10;
		display: flex;
		gap: 12px;
		padding: 6px 12px;
		background: rgba(0, 0, 0, 0.6);
		border-radius: 6px;
		font-size: 0.7rem;
		color: rgba(255, 255, 255, 0.8);
	}

	.shortcuts-hint kbd {
		background: rgba(255, 255, 255, 0.15);
		padding: 1px 4px;
		border-radius: 3px;
		font-family: inherit;
		font-size: 0.65rem;
	}

	/* Km markers */
	:global(.km-marker) {
		width: 20px;
		height: 20px;
		border-radius: 50%;
		background: var(--color-surface);
		border: 2px solid var(--color-primary);
		font-size: 8px;
		font-weight: 700;
		color: var(--color-primary);
		display: flex;
		align-items: center;
		justify-content: center;
		pointer-events: none;
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
	}

	/* User location dot */
	:global(.user-location-dot) {
		width: 14px;
		height: 14px;
		border-radius: 50%;
		background: #4285f4;
		border: 2.5px solid white;
		box-shadow: 0 0 0 3px rgba(66, 133, 244, 0.3);
		pointer-events: none;
	}

	/* Generate-by-distance pre-Generate picker markers. The user
	   needs visual confirmation of WHERE their picked start/end
	   landed before clicking Generate — pre-fix, the only signal
	   was a lat,lng text label in the sidebar, which forced a
	   click-Generate-and-see-what-happens dance. Green = start
	   (matches the watch's "go" semantics + Strava's start chevron),
	   red = end. */
	:global(.generation-endpoint) {
		width: 22px;
		height: 22px;
		border-radius: 50% 50% 50% 0;
		transform: rotate(-45deg);
		border: 2.5px solid white;
		box-shadow: 0 2px 6px rgba(0, 0, 0, 0.35);
		pointer-events: none;
	}
	:global(.generation-endpoint-start) {
		background: #16a34a;
	}
	:global(.generation-endpoint-end) {
		background: #dc2626;
	}
</style>
