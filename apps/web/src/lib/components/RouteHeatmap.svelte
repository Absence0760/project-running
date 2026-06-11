<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	import { mapStyleUrlFromEnv as mapStyleUrl } from '$lib/routes/map-style.svelte';
	import { watchMapResize } from '$lib/routes/map_resize';
	import {
		fetchHeatmapPoints,
		fetchRouteById,
		fetchClubsInBbox,
		fetchDiscoverableRoutesInBbox,
		type DiscoverFilter,
		type DiscoverableRoutePin,
	} from '$lib/core/data';
	import { formatDistance } from '$lib/format/units.svelte';
	import { searchPlaces, type PlaceSearchResult } from '$lib/routes/geocoding';
	import {
		DISTANCE_BANDS,
		bandForDistance,
		type DistanceBandKey,
	} from '$lib/routes/distance_bands';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { escapeHtml, safeHref } from '$lib/util/html_escape';

	let mapEl: HTMLDivElement;
	let map: maplibregl.Map | null = null;
	let geolocate: maplibregl.GeolocateControl | null = null;
	let stopResizeWatch: (() => void) | null = null;
	let loading = $state(false);
	let lastUpdated = $state<Date | null>(null);
	let mapLoaded = false;
	let cachedFeatures: GeoJSON.Feature[] = [];
	// The map is framed exactly once on first paint — either by a
	// successful geolocation fix OR (when geolocation is denied /
	// unavailable / absent) by fitting to the loaded route data. Guards
	// the fallback so panning away later never re-snaps the view.
	let didInitialFit = false;
	// Set true once geolocation has settled in a way that means it will
	// NOT frame the map (error or no API). Gates the fit-to-data fallback
	// so a still-pending fix doesn't cause a world-view → data → real-
	// location flash when geolocation is going to succeed.
	let wantDataFit = false;

	// --- Search ---
	// Uses `$lib/routes/geocoding.searchPlaces`, which transparently picks
	// MapTiler when its key is set and falls back to Nominatim
	// (OSM's free geocoder) otherwise. Either path lets the user
	// pan the map to a named place — works whether or not we have
	// a MapTiler subscription, which matters on the local Protomaps
	// dev setup. See `decisions.md § 68` for the override design.
	let searchInput: HTMLInputElement | undefined = $state();
	let searchQuery = $state('');
	let searchResults = $state<PlaceSearchResult[]>([]);
	let showResults = $state(false);
	let searchTimeout: ReturnType<typeof setTimeout> | null = null;

	function onSearchInput() {
		if (searchTimeout) clearTimeout(searchTimeout);
		searchTimeout = setTimeout(async () => {
			searchResults = await searchPlaces(searchQuery);
			showResults = searchResults.length > 0;
		}, 300);
	}

	function selectSearchResult(r: PlaceSearchResult) {
		if (!map) return;
		map.flyTo({ center: [r.lng, r.lat], zoom: 13 });
		searchQuery = '';
		searchResults = [];
		showResults = false;
		searchInput?.blur();
	}

	// Debounce key for moveend → fetch. We don't want to fire a new
	// PostGIS query on every pixel of a drag.
	let pendingFetch: ReturnType<typeof setTimeout> | null = null;
	let pendingPinsFetch: ReturnType<typeof setTimeout> | null = null;

	const HEATMAP_SOURCE = 'heatmap-pts';
	const HEATMAP_LAYER = 'heatmap-layer';
	// Routes are not drawn by default — only the single route currently
	// hovered (from its map dot or its list row) gets its line drawn here.
	// Hiding the rest keeps the map readable; revealing one on hover is
	// the Strava/Komoot-style preview. See the hover handlers below.
	const ROUTES_SOURCE = 'heatmap-routes';
	const ROUTES_LAYER_CASING = 'heatmap-routes-casing';
	const ROUTES_LAYER = 'heatmap-routes-line';
	// A halo ring placed at the hovered route's start dot so a list-row
	// hover visibly points at its dot on the map (synchronized hover).
	const ROUTE_HL_SOURCE = 'heatmap-route-hl';
	const ROUTE_HL_LAYER = 'heatmap-route-hl-layer';
	// Routes the user has pinned ("keep on map") — their lines stay drawn
	// (in violet, distinct from the cyan hover preview) until unpinned.
	const ROUTE_PINNED_SOURCE = 'heatmap-routes-pinned';
	const ROUTE_PINNED_CASING = 'heatmap-routes-pinned-casing';
	const ROUTE_PINNED_LAYER = 'heatmap-routes-pinned-line';
	const CLUB_PINS_SOURCE = 'heatmap-clubs';
	const CLUB_PINS_LAYER = 'heatmap-clubs-layer';
	const ROUTE_PINS_SOURCE = 'heatmap-route-pins';
	const ROUTE_PINS_LAYER = 'heatmap-route-pins-layer';
	const ROUTE_CLUSTER_LAYER = 'heatmap-route-pins-cluster';
	const ROUTE_CLUSTER_COUNT_LAYER = 'heatmap-route-pins-cluster-count';

	// Layer toggles. Clubs + route pins default-on. The heat layer is
	// OFF by default: at any zoom where you can read individual routes it
	// traces each route's path (densified points), which reads as "the
	// route is already shown" and fights the hidden-until-hover model.
	// The default view is basemap + dots + hover-to-preview; turn Heat on
	// in Filters to get the ambient "where people run" density.
	let showClubPins = $state(true);
	let showRoutePins = $state(true);
	let showHeatmapLayer = $state(false);
	let clubPinsCount = $state(0);
	let routePinsCount = $state(0);

	// Route-discovery lens. The chip bar swaps which routes the pin
	// layer fetches (popular / featured / friends / hidden gems) so the
	// map stops being one undifferentiated blob and becomes a route
	// browser. Mirrors the RPC's p_filter arms — see data.ts.
	let routeFilter = $state<DiscoverFilter>('popular');
	const FILTERS = $derived<{ id: DiscoverFilter; label: string; hint: string }[]>([
		{ id: 'popular', label: m('routeHeatmap.lensPopular'), hint: m('routeHeatmap.lensPopularHint') },
		{ id: 'friends', label: m('routeHeatmap.lensFriends'), hint: m('routeHeatmap.lensFriendsHint') },
		{ id: 'featured', label: m('routeHeatmap.lensFeatured'), hint: m('routeHeatmap.lensFeaturedHint') },
		{
			id: 'hidden_gems',
			label: m('routeHeatmap.lensHiddenGems'),
			hint: m('routeHeatmap.lensHiddenGemsHint'),
		},
	]);
	// The viewport's discoverable routes, kept as state so the results
	// list (and the count) render straight off the same fetch the map
	// pins use.
	let routePins = $state<DiscoverableRoutePin[]>([]);

	// Selected race-distance bands (5k / 10k / half / marathon / ultra),
	// multi-select. Empty = no distance filter. Combines with the lens.
	let selectedBands = $state<DistanceBandKey[]>([]);
	// Advanced-filters panel (lens + distance + layers) under the search.
	let filtersOpen = $state(false);
	// The results sidebar. Default-open so the surface reads as a route
	// browser; collapsible to reclaim the full map canvas.
	let sidebarOpen = $state(true);

	// Hover-to-preview state. `hoveredRouteId` drives the synchronized
	// highlight on BOTH surfaces (the list row tints + the map draws that
	// one route's line + halo). $state so the row class reacts.
	let hoveredRouteId = $state<string | null>(null);
	// id → [lng,lat][] geometry cache so re-hovering a route never refetches
	// (refetch-on-hover is the classic source of map flicker).
	const geomCache = new Map<string, [number, number][]>();
	// Debounce clearing the preview so moving the cursor between a dot and
	// its line — or between adjacent rows — doesn't flash the line off/on.
	let clearTimer: ReturnType<typeof setTimeout> | null = null;
	// Routes the user has pinned to keep their lines on the map. Only the
	// pinned routes are fetched (reusing geomCache from the hover preview),
	// so this stays cheap; the lines persist across pan / filter changes.
	let pinnedIds = $state<Set<string>>(new Set());

	const activeFilterLabel = $derived(
		FILTERS.find((f) => f.id === routeFilter)?.label ?? '',
	);
	// Count of non-default filters, shown as a badge on the Filters
	// button: a non-popular lens counts as one, plus each distance band.
	const activeFilterCount = $derived(
		(routeFilter !== 'popular' ? 1 : 0) + selectedBands.length,
	);
	const bandSummary = $derived(
		DISTANCE_BANDS.filter((b) => selectedBands.includes(b.key))
			.map((b) => b.label)
			.join(' / '),
	);

	function toggleBand(key: DistanceBandKey) {
		selectedBands = selectedBands.includes(key)
			? selectedBands.filter((k) => k !== key)
			: [...selectedBands, key];
	}
	function resetFilters() {
		routeFilter = 'popular';
		selectedBands = [];
	}

	onMount(() => {
		const prefersDark =
			typeof window !== 'undefined' &&
			window.matchMedia('(prefers-color-scheme: dark)').matches;

		map = new maplibregl.Map({
			container: mapEl,
			style: mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark),
			// World view by default. On load we auto-trigger the
			// GeolocateControl; if the user grants permission it recentres
			// on the real position and drops the user-location dot. If they
			// deny / aren't asked yet / the API isn't available, the global
			// view shows the spread of points across the dataset — strictly
			// better than the previous "everyone starts in London" default.
			center: [0, 30],
			zoom: 2,
		});
		stopResizeWatch = watchMapResize(mapEl, map);

		// Aggressive resize pass — the May 2026 layout audit caught
		// that the heatmap canvas ended up rendered at ~80 px tall
		// even with watchMapResize in place. The ResizeObserver
		// fires once when the heatmap-wrap reaches its final size,
		// but MapLibre's WebGL canvas can be allocated at the
		// mount-time size and the texture stays at that resolution
		// even after .resize() updates the projection.
		//
		// requestAnimationFrame defers to after the next paint, when
		// the flex chain has settled + the BillingIssueBanner has
		// measured + the container is at its final size. A second
		// rAF + a setTimeout cover late-arriving font/asset reflows
		// that nudge the layout one more time.
		requestAnimationFrame(() => {
			map?.resize();
			requestAnimationFrame(() => {
				map?.resize();
				setTimeout(() => map?.resize(), 100);
			});
		});

		// Dev-only e2e hook. Lets Playwright drive the map (flyTo,
		// queryRenderedFeatures, fire click events at projected lng/lat)
		// the same way `/routes/new` exposes `__routeBuilder`. Pinned
		// in CI by the `tests-e2e/routes/heatmap-pins.spec.ts` suite.
		// Production builds (`adapter-static` with DEV=false) never
		// reach this branch, so there's no leak.
		if (import.meta.env.DEV && typeof window !== 'undefined') {
			(window as unknown as { __heatmapMap?: unknown }).__heatmapMap = map;
		}
		map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
		// "Locate me" button. Built-in MapLibre primitive — no
		// MapTiler key needed, so this is the always-available
		// navigation affordance even on a Protomaps-only dev setup
		// where the search box is dormant. Kept in a ref so the load
		// handler can auto-trigger it: triggering the control (not a
		// bare getCurrentPosition) is what renders the user-location
		// dot + accuracy circle, so the dot shows on first paint
		// instead of only after the button is pressed.
		geolocate = new maplibregl.GeolocateControl({
			// enableHighAccuracy:false + a 15s timeout + a 60s maximumAge
			// mirrors the proven RouteBuilder config. The old
			// {enableHighAccuracy:true, timeout:5000} (with the implicit
			// maximumAge:0) forced a fresh high-accuracy Wi-Fi/IP fix on
			// every trigger and routinely timed out on desktop / Brave /
			// behind a VPN before it could resolve — a coarse, cacheable
			// fix is all a recentre needs.
			positionOptions: { enableHighAccuracy: false, timeout: 15000, maximumAge: 60000 },
			trackUserLocation: false,
			showAccuracyCircle: true,
			showUserLocation: true,
		});
		map.addControl(geolocate, 'top-right');
		// A successful fix frames the map on the user — mark the view as
		// framed so the fit-to-data fallback never yanks it to the dataset.
		geolocate.on('geolocate', () => {
			didInitialFit = true;
		});
		// Denied / unavailable / timed out. The control otherwise fails
		// silently (the bug that made "locate me" feel broken): surface it
		// as a toast, then fall back to framing the loaded route data
		// instead of stranding the user at the world view.
		geolocate.on('error', (err: GeolocationPositionError) => {
			showToast(
				err?.code === 1 ? m('routeHeatmap.locateDenied') : m('routeHeatmap.locateFailed'),
				'error',
			);
			wantDataFit = true;
			fitToRoutePins();
		});

		map.on('load', () => {
			if (!map) return;
			mapLoaded = true;
			// Auto-locate on first paint. Triggering the GeolocateControl
			// (rather than a bare getCurrentPosition) recentres the map AND
			// renders the user-location dot + accuracy circle, so the dot is
			// visible immediately instead of only after the button is
			// pressed. trackUserLocation is false, so this is a one-shot
			// fix-and-recentre. Denied / unavailable leaves the world view —
			// the "no idea where you are" baseline. Guard on the API so the
			// trigger is skipped where geolocation is absent.
			if (typeof navigator !== 'undefined' && navigator.geolocation) {
				geolocate?.trigger();
			} else {
				// No geolocation API at all (e.g. http:// served over a LAN
				// IP, where the browser gates it off): frame the loaded
				// route data instead of leaving the world view.
				wantDataFit = true;
				fitToRoutePins();
			}
			map.addSource(HEATMAP_SOURCE, {
				type: 'geojson',
				data: { type: 'FeatureCollection', features: cachedFeatures },
			});
			// Pinned ("kept") route lines — added first so they render
			// BELOW the hover preview. Violet so kept routes are distinct
			// from the cyan hover line; clicking one opens the route.
			map.addSource(ROUTE_PINNED_SOURCE, {
				type: 'geojson',
				data: { type: 'FeatureCollection', features: [] },
				promoteId: 'route_id',
			});
			map.addLayer({
				id: ROUTE_PINNED_CASING,
				type: 'line',
				source: ROUTE_PINNED_SOURCE,
				paint: { 'line-color': '#1e293b', 'line-width': 6, 'line-opacity': 0.45 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
			map.addLayer({
				id: ROUTE_PINNED_LAYER,
				type: 'line',
				source: ROUTE_PINNED_SOURCE,
				paint: { 'line-color': '#8b5cf6', 'line-width': 3.5 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
			map.on('click', ROUTE_PINNED_LAYER, (e) => {
				// A click on a route never navigates — it toggles "keep on
				// map". Clicking a kept line removes it. Navigation is always
				// the explicit "View route" link (sidebar row / overlap popup).
				const id = e.features?.[0]?.properties?.route_id as string | undefined;
				if (id) void togglePin(id);
			});
			map.on('mouseenter', ROUTE_PINNED_LAYER, () => {
				if (map) map.getCanvas().style.cursor = 'pointer';
			});
			map.on('mouseleave', ROUTE_PINNED_LAYER, () => {
				if (map) map.getCanvas().style.cursor = '';
			});
			// The hovered route's line. Empty until a dot / list row is
			// hovered; no minzoom, so a preview shows at whatever zoom
			// you're at. Dark casing + cyan line matches the trace
			// styling on /runs/[id] so users recognise it as a route.
			map.addSource(ROUTES_SOURCE, {
				type: 'geojson',
				data: { type: 'FeatureCollection', features: [] },
				promoteId: 'route_id',
			});
			map.addLayer({
				id: ROUTES_LAYER_CASING,
				type: 'line',
				source: ROUTES_SOURCE,
				paint: { 'line-color': '#1e293b', 'line-width': 7, 'line-opacity': 0.45 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
			map.addLayer({
				id: ROUTES_LAYER,
				type: 'line',
				source: ROUTES_SOURCE,
				paint: { 'line-color': '#22d3ee', 'line-width': 4 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
			map.on('click', ROUTES_LAYER, (e) => {
				const f = e.features?.[0];
				const id = f?.properties?.route_id as string | undefined;
				if (id) void togglePin(id);
			});
			// Moving the cursor onto the previewed line keeps it alive
			// (cancels the pending clear) so the line stays clickable.
			map.on('mouseenter', ROUTES_LAYER, () => {
				if (clearTimer) {
					clearTimeout(clearTimer);
					clearTimer = null;
				}
				if (map) map.getCanvas().style.cursor = 'pointer';
			});
			map.on('mouseleave', ROUTES_LAYER, () => {
				if (map) map.getCanvas().style.cursor = '';
				scheduleClear();
			});
			// Halo ring drawn under the hovered route's start dot, so a
			// list-row hover visibly points at its dot on the map.
			map.addSource(ROUTE_HL_SOURCE, {
				type: 'geojson',
				data: { type: 'FeatureCollection', features: [] },
			});
			map.addLayer({
				id: ROUTE_HL_LAYER,
				type: 'circle',
				source: ROUTE_HL_SOURCE,
				paint: {
					'circle-radius': 16,
					'circle-color': 'rgba(34, 211, 238, 0.16)',
					'circle-stroke-color': '#22d3ee',
					'circle-stroke-width': 2,
				},
			});
			// Discoverable-pin layers (clubs + featured/popular routes).
			// Both default-on; toggleable via the legend popover. Each
			// is its own circle layer with a click handler that
			// navigates to the entity's detail page. Sources start
			// empty + populate on the first `refreshPins()` call below.
			map.addSource(CLUB_PINS_SOURCE, {
				type: 'geojson',
				data: { type: 'FeatureCollection', features: [] },
			});
			map.addLayer({
				id: CLUB_PINS_LAYER,
				type: 'circle',
				source: CLUB_PINS_SOURCE,
				paint: {
					'circle-color': '#7FB3C2',
					'circle-radius': 9,
					'circle-stroke-color': '#0f172a',
					'circle-stroke-width': 2,
					'circle-opacity': 0.9,
				},
			});
			map.on('click', CLUB_PINS_LAYER, (e) => {
				const f = e.features?.[0];
				if (!f || !map) return;
				const slug = f.properties?.slug as string | undefined;
				const id = f.properties?.id as string | undefined;
				const name = (f.properties?.name as string) ?? m('routeHeatmap.clubFallbackName');
				const memberCount = (f.properties?.member_count as number) ?? 0;
				const locationLabel = (f.properties?.location_label as string) ?? '';
				const avatarUrl = (f.properties?.avatar_url as string) ?? '';
				const href = slug ? `/clubs/${slug}` : id ? `/clubs/${id}` : '#';
				const coords = (f.geometry as GeoJSON.Point).coordinates as [number, number];
				openClubPopup(coords, { name, memberCount, locationLabel, avatarUrl, href });
			});
			map.on('mouseenter', CLUB_PINS_LAYER, (e) => {
				if (!map) return;
				map.getCanvas().style.cursor = 'pointer';
				const f = e.features?.[0];
				if (!f) return;
				const name = (f.properties?.name as string) ?? '';
				const coords = (f.geometry as GeoJSON.Point).coordinates as [number, number];
				openHoverTip(coords, name);
			});
			map.on('mouseleave', CLUB_PINS_LAYER, () => {
				if (map) map.getCanvas().style.cursor = '';
				closeHoverTip();
			});

			// Cluster the route pins so a dense area reads as one count
			// bubble instead of an unclickable pile of overlapping dots.
			// clusterMaxZoom stops clustering once you're zoomed in far
			// enough that individual pins are distinct + tappable.
			map.addSource(ROUTE_PINS_SOURCE, {
				type: 'geojson',
				data: { type: 'FeatureCollection', features: [] },
				cluster: true,
				clusterRadius: 50,
				clusterMaxZoom: 14,
			});
			// Cluster bubble + count. Sized by how many routes it holds.
			map.addLayer({
				id: ROUTE_CLUSTER_LAYER,
				type: 'circle',
				source: ROUTE_PINS_SOURCE,
				filter: ['has', 'point_count'],
				paint: {
					'circle-color': '#F2A07B',
					'circle-opacity': 0.92,
					'circle-stroke-color': '#0f172a',
					'circle-stroke-width': 2,
					'circle-radius': [
						'step',
						['get', 'point_count'],
						14,
						10, 18,
						25, 24,
					],
				},
			});
			map.addLayer({
				id: ROUTE_CLUSTER_COUNT_LAYER,
				type: 'symbol',
				source: ROUTE_PINS_SOURCE,
				filter: ['has', 'point_count'],
				layout: {
					'text-field': ['get', 'point_count_abbreviated'],
					'text-font': ['Noto Sans Regular'],
					'text-size': 12,
				},
				paint: { 'text-color': '#0f172a' },
			});
			// Click a cluster → zoom to the point where it breaks apart.
			map.on('click', ROUTE_CLUSTER_LAYER, async (e) => {
				const f = e.features?.[0];
				const clusterId = f?.properties?.cluster_id as number | undefined;
				if (clusterId == null || !map) return;
				const src = map.getSource(ROUTE_PINS_SOURCE) as
					| maplibregl.GeoJSONSource
					| undefined;
				if (!src) return;
				try {
					const zoom = await src.getClusterExpansionZoom(clusterId);
					const coords = (f!.geometry as GeoJSON.Point).coordinates as [number, number];
					map.easeTo({ center: coords, zoom });
				} catch {
					// Expansion-zoom lookup can fail mid-tile-load; the next
					// click after the source settles succeeds. No-op here.
				}
			});
			map.on('mouseenter', ROUTE_CLUSTER_LAYER, async (e) => {
				if (!map) return;
				map.getCanvas().style.cursor = 'pointer';
				if (clearTimer) {
					clearTimeout(clearTimer);
					clearTimer = null;
				}
				const f = e.features?.[0];
				const clusterId = f?.properties?.cluster_id as number | undefined;
				if (clusterId == null) return;
				const src = map.getSource(ROUTE_PINS_SOURCE) as
					| maplibregl.GeoJSONSource
					| undefined;
				if (!src) return;
				const total = (f!.properties?.point_count as number) ?? 0;
				const coords = (f!.geometry as GeoJSON.Point).coordinates as [number, number];
				try {
					const leaves = await src.getClusterLeaves(clusterId, 12, 0);
					const routes: ClusterRoute[] = leaves.map((lf) => {
						const p = (lf.properties ?? {}) as Record<string, unknown>;
						const c = (lf.geometry as GeoJSON.Point).coordinates as [number, number];
						return {
							id: p.id as string,
							name: (p.name as string) ?? m('routeHeatmap.routeFallbackName'),
							featured: !!p.featured,
							distance_m: (p.distance_m as number) ?? 0,
							surface: (p.surface as string) ?? '',
							run_count: (p.run_count as number) ?? 0,
							lng: c[0],
							lat: c[1],
						};
					});
					openClusterPopup(coords, routes, total);
				} catch {
					// getClusterLeaves can fail mid-tile-load; harmless.
				}
			});
			map.on('mouseleave', ROUTE_CLUSTER_LAYER, () => {
				if (map) map.getCanvas().style.cursor = '';
				scheduleClear();
			});
			map.addLayer({
				id: ROUTE_PINS_LAYER,
				type: 'circle',
				source: ROUTE_PINS_SOURCE,
				// Only the unclustered (leaf) pins — clusters are handled by
				// the layers above, so the click/popup handler never fires
				// on a cluster.
				filter: ['!', ['has', 'point_count']],
				paint: {
					// Brand orange — same as the route-list thumbnails so
					// the colour reads as "this is a route" across the
					// whole product. Featured routes get a thicker gold
					// halo via the `case` expression below.
					'circle-color': '#F2A07B',
					'circle-radius': 8,
					'circle-stroke-color': [
						'case',
						['get', 'featured'],
						'#FACC15',
						'#0f172a',
					],
					'circle-stroke-width': [
						'case',
						['get', 'featured'],
						3,
						2,
					],
					'circle-opacity': 0.95,
				},
			});
			map.on('click', ROUTE_PINS_LAYER, (e) => {
				// Clicking a dot keeps that route's line on the map (toggle) —
				// it never navigates. To open the detail page, use the "View
				// route" link on the matching sidebar row (or the overlap
				// popup when several routes share a start). When several pins
				// stack under the click, defer to the overlap list rather than
				// keeping an arbitrary one.
				if (!map) return;
				const hits = map.queryRenderedFeatures(e.point, { layers: [ROUTE_PINS_LAYER] });
				const ids = new Set<string>();
				for (const h of hits) {
					const hid = h.properties?.id as string | undefined;
					if (hid) ids.add(hid);
				}
				if (ids.size > 1) return; // hover already surfaces the overlap list
				const id = e.features?.[0]?.properties?.id as string | undefined;
				if (id) void togglePin(id);
			});
			map.on('mouseenter', ROUTE_PINS_LAYER, (e) => {
				if (!map) return;
				map.getCanvas().style.cursor = 'pointer';
				if (clearTimer) {
					clearTimeout(clearTimer);
					clearTimer = null;
				}
				// How many route pins are stacked under the cursor? Beyond the
				// cluster zoom, routes that share (or nearly share) a start
				// render as overlapping leaf pins. Show the list so the user
				// picks, instead of arbitrarily previewing whichever pin
				// happens to render on top.
				const hits = map.queryRenderedFeatures(e.point, {
					layers: [ROUTE_PINS_LAYER],
				});
				const seen = new Set<string>();
				const routes: ClusterRoute[] = [];
				for (const h of hits) {
					const p = (h.properties ?? {}) as Record<string, unknown>;
					const id = p.id as string | undefined;
					if (!id || seen.has(id)) continue;
					seen.add(id);
					const c = (h.geometry as GeoJSON.Point).coordinates as [number, number];
					routes.push({
						id,
						name: (p.name as string) ?? m('routeHeatmap.routeFallbackName'),
						featured: !!p.featured,
						distance_m: (p.distance_m as number) ?? 0,
						surface: (p.surface as string) ?? '',
						run_count: (p.run_count as number) ?? 0,
						lng: c[0],
						lat: c[1],
					});
				}
				if (routes.length === 0) return;
				const coords: [number, number] = [routes[0].lng, routes[0].lat];
				if (routes.length > 1) {
					openClusterPopup(coords, routes, routes.length);
				} else {
					previewRoute(routes[0].id, coords, routes[0].name);
				}
			});
			map.on('mouseleave', ROUTE_PINS_LAYER, () => {
				if (map) map.getCanvas().style.cursor = '';
				scheduleClear();
			});

			// Standard MapLibre heatmap paint — interpolated by intensity
			// (the density of sampled points). Higher zooms taper the
			// blur radius so individual routes stay legible when the
			// user drills in.
			map.addLayer({
				id: HEATMAP_LAYER,
				type: 'heatmap',
				source: HEATMAP_SOURCE,
				// Off by default (see showHeatmapLayer) — start hidden so
				// there's no flash before the visibility $effect runs.
				layout: { visibility: showHeatmapLayer ? 'visible' : 'none' },
				paint: {
					'heatmap-radius': [
						'interpolate',
						['linear'],
						['zoom'],
						9, 4,
						12, 8,
						15, 14,
						18, 20,
					],
					'heatmap-intensity': [
						'interpolate',
						['linear'],
						['zoom'],
						9, 0.6,
						15, 1.4,
					],
					'heatmap-color': [
						'interpolate',
						['linear'],
						['heatmap-density'],
						0, 'rgba(0,0,0,0)',
						0.2, 'rgba(103, 169, 207, 0.45)',
						0.4, 'rgba(33, 102, 172, 0.65)',
						0.6, 'rgba(178, 24, 43, 0.75)',
						1.0, 'rgba(178, 24, 43, 0.9)',
					],
					// Heat is off by default; this curve applies only when a
					// user turns it on in Filters. Even then it dims as you
					// zoom in so it doesn't trace individual routes over the
					// pins at the picking zoom.
					'heatmap-opacity': [
						'interpolate',
						['linear'],
						['zoom'],
						11, 0.8,
						14, 0.45,
						16, 0.3,
					],
				},
			});
			// First fetch fires on mount in parallel with the style load
			// so the legend's "Updated" timestamp shows even when the
			// basemap can't render (no MapTiler key, network-blocked
			// vendor, etc.). If the style does load, we also refresh
			// once more here to cover the case where the mount-fetch
			// raced ahead of the source being added (cachedFeatures
			// covers that path) AND to pick up any bounds drift between
			// the constructor's centre/zoom and the first painted frame.
			refresh();
			refreshPins();
		});

		map.on('moveend', () => {
			if (pendingFetch) clearTimeout(pendingFetch);
			pendingFetch = setTimeout(refresh, 350);
			if (pendingPinsFetch) clearTimeout(pendingPinsFetch);
			pendingPinsFetch = setTimeout(refreshPins, 350);
		});

		// Kick off the first fetch immediately. The HTTP RPC doesn't
		// care whether MapLibre has loaded a style yet — and decoupling
		// the legend's status from the basemap means the user gets an
		// "Updated …" stamp even on a keyless deploy.
		refresh();
		refreshPins();
	});

	onDestroy(() => {
		if (import.meta.env.DEV && typeof window !== 'undefined') {
			(window as unknown as { __heatmapMap?: unknown }).__heatmapMap = undefined;
		}
		stopResizeWatch?.();
		currentPopup?.remove();
		currentPopup = null;
		hoverPopup?.remove();
		hoverPopup = null;
		clusterPopup?.remove();
		clusterPopup = null;
		map?.remove();
		map = null;
		if (pendingFetch) clearTimeout(pendingFetch);
		if (pendingPinsFetch) clearTimeout(pendingPinsFetch);
		if (clearTimer) clearTimeout(clearTimer);
		if (searchTimeout) clearTimeout(searchTimeout);
	});

	// ─────────────── Pin popups + hover tooltips ───────────────
	//
	// Click → popup card with name + summary + a "View …" button that
	// navigates. The user found the old "click teleports you away"
	// flow disorienting — this gives them a chance to inspect first.
	// Hover → smaller tooltip that just shows the name (so you can
	// glance over a cluster of pins without clicking each one).
	//
	// Both use MapLibre's `Popup` API. Only one popup of each kind
	// is open at a time; we re-use the handle.

	let currentPopup: maplibregl.Popup | null = null;
	let hoverPopup: maplibregl.Popup | null = null;

	/// Two initials from a name, e.g. "Richmond Run Club" → "RR".
	/// Falls back to the first letter for single-word names.
	function initialsOf(name: string): string {
		const parts = name.trim().split(/\s+/).slice(0, 2);
		if (parts.length === 0) return '?';
		if (parts.length === 1) return parts[0].charAt(0).toUpperCase();
		return (parts[0].charAt(0) + parts[1].charAt(0)).toUpperCase();
	}

	function openPopupRaw(coords: [number, number], html: string) {
		if (!map) return;
		closeHoverTip();
		currentPopup?.remove();
		// Force a resize sync before MapLibre projects the lat/lng.
		// User report from May 2026: the popup landed way below the
		// rendered tiles. Stale-transform symptom — the map's
		// internal transform can drift after a container resize if
		// the ResizeObserver hasn't caught up. Belt-and-suspenders.
		map.resize();
		currentPopup = new maplibregl.Popup({
			closeButton: true,
			closeOnClick: false,
			offset: 14,
			maxWidth: '260px',
			className: 'heatmap-pin-popup',
			// MapLibre's default behaviour is to call `.focus()` on the
			// popup root the moment it mounts. The browser then auto-
			// scrolls the nearest scroll container to bring the focused
			// element into view — for `.heatmap-wrap` (overflow:hidden,
			// still programmatically scrollable) that meant scrollTop
			// got nudged hundreds of pixels and the `.map` child shifted
			// to negative y. Two failure modes downstream:
			//   * `heatmap-pins.spec.ts:293` (layout regression test)
			//     observes `.map` at y=-448.
			//   * `heatmap-pins.spec.ts:251` (popup link click) can't
			//     reach the View-route link because the popup's
			//     projected coords leave it out of the click area.
			// `focusAfterOpen: false` is the documented escape hatch.
			focusAfterOpen: false,
		})
			.setLngLat(coords)
			.setHTML(html)
			.addTo(map);
	}

	interface ClubPopupData {
		name: string;
		memberCount: number;
		locationLabel: string;
		avatarUrl: string;
		href: string;
	}
	function openClubPopup(coords: [number, number], d: ClubPopupData) {
		const avatar = d.avatarUrl
			? `<img class="pin-avatar" src="${escapeHtml(d.avatarUrl)}" alt="" />`
			: `<span class="pin-avatar pin-avatar-initials">${escapeHtml(initialsOf(d.name))}</span>`;
		const memberLine =
			d.memberCount === 1
				? m('routeHeatmap.memberCountOne', { n: d.memberCount })
				: m('routeHeatmap.memberCountMany', { n: d.memberCount });
		const subtitle = d.locationLabel
			? `<span class="pin-popup-location">📍 ${escapeHtml(d.locationLabel)}</span>`
			: '';
		const html = `
			<div class="pin-popup pin-popup-club">
				<div class="pin-popup-head">
					${avatar}
					<div class="pin-popup-titleblock">
						<span class="pin-popup-title">${escapeHtml(d.name)}</span>
						<span class="pin-popup-meta">${memberLine}</span>
					</div>
				</div>
				${subtitle}
				<a class="pin-popup-action" href="${escapeHtml(safeHref(d.href))}"
					data-sveltekit-preload-data="hover">
					${escapeHtml(m('routeHeatmap.viewClub'))} &rarr;
				</a>
			</div>
		`;
		openPopupRaw(coords, html);
	}

	function openHoverTip(coords: [number, number], name: string) {
		if (!map || !name) return;
		hoverPopup?.remove();
		hoverPopup = new maplibregl.Popup({
			closeButton: false,
			closeOnClick: false,
			offset: 12,
			anchor: 'bottom',
			className: 'heatmap-hover-tip',
			// Same focus-grab issue as the click popup above — even
			// without a close button, the popup root takes focus on
			// mount unless we opt out.
			focusAfterOpen: false,
		})
			.setLngLat(coords)
			.setHTML(`<span>${escapeHtml(name)}</span>`)
			.addTo(map);
	}

	function closeHoverTip() {
		hoverPopup?.remove();
		hoverPopup = null;
	}

	/// Fetch + paint the club + discoverable-route pin layers for
	/// the current viewport. Runs in parallel with the heatmap and
	/// route-polyline refreshes — small RPCs, capped at 100 results
	/// each, so the wire size is negligible compared to the heatmap
	/// densification. Each layer updates independently; a failure
	/// in one doesn't cancel the other.
	// Frame the map on the loaded route pins. Runs at most once, and only
	// when geolocation has bowed out (wantDataFit) — so a working fix still
	// wins, but a denied / unavailable / absent one lands the user on the
	// route data (e.g. the Virginia routes) instead of the world view.
	function fitToRoutePins() {
		if (!map || didInitialFit || !wantDataFit || routePins.length === 0) return;
		const bounds = new maplibregl.LngLatBounds();
		for (const r of routePins) bounds.extend([r.lng, r.lat]);
		map.fitBounds(bounds, { padding: 64, maxZoom: 12, duration: 600 });
		didInitialFit = true;
	}

	async function refreshPins() {
		if (!map || !mapLoaded) return;
		// The discovery pins are the always-relevant fetch, so the status
		// (spinner + "Updated") tracks this, not the opt-in heat fetch. The
		// try/finally guarantees the spinner clears even if a fetch / setData
		// throws (e.g. a source removed mid-teardown).
		loading = true;
		try {
			const b = map.getBounds();
			const bbox = {
				minLng: b.getWest(),
				minLat: b.getSouth(),
				maxLng: b.getEast(),
				maxLat: b.getNorth(),
			};
			const [clubs, routes] = await Promise.all([
				fetchClubsInBbox(bbox),
				fetchDiscoverableRoutesInBbox({ ...bbox, filter: routeFilter, bands: selectedBands }),
			]);
			clubPinsCount = clubs.length;
			routePinsCount = routes.length;
			routePins = routes;
			// If geolocation has already bowed out, frame the view on this
			// freshly-loaded data (no-op once the view has been framed).
			fitToRoutePins();
			const clubSrc = map.getSource(CLUB_PINS_SOURCE) as
				| maplibregl.GeoJSONSource
				| undefined;
			clubSrc?.setData({
				type: 'FeatureCollection',
				features: clubs.map((c) => ({
					type: 'Feature',
					properties: {
						id: c.id,
						name: c.name,
						slug: c.slug,
						member_count: c.member_count,
						// The club popup reads these — they have to be on the
						// rendered feature, not just the fetched row.
						avatar_url: c.avatar_url,
						location_label: c.location_label,
					},
					geometry: { type: 'Point', coordinates: [c.lng, c.lat] },
				})),
			});
			const routeSrc = map.getSource(ROUTE_PINS_SOURCE) as
				| maplibregl.GeoJSONSource
				| undefined;
			routeSrc?.setData({
				type: 'FeatureCollection',
				features: routes.map((r) => ({
					type: 'Feature',
					properties: {
						id: r.id,
						name: r.name,
						featured: r.is_featured,
						distance_m: r.distance_m,
						// The route popup's elevation chip reads this off the
						// rendered feature.
						elevation_m: r.elevation_m,
						surface: r.surface,
						run_count: r.run_count,
					},
					geometry: { type: 'Point', coordinates: [r.lng, r.lat] },
				})),
			});
			lastUpdated = new Date();
		} catch (e) {
			console.warn('heatmap pins refresh failed', e);
		} finally {
			loading = false;
		}
	}

	// Layer-visibility toggles. MapLibre's `setLayoutProperty(...,
	// 'visibility', 'visible'|'none')` is the cheap way to flip a
	// layer — no source-data mutation needed. Wired to the legend
	// checkboxes below via a reactive $effect.
	// Read the toggle's reactive value FIRST, before the map-readiness
	// guard — otherwise the effect early-returns on the (mapLoaded=false)
	// first run without ever reading the $state, so Svelte never tracks
	// it and the effect won't re-run when the user flips the toggle.
	$effect(() => {
		const visible = showClubPins;
		if (!map || !mapLoaded) return;
		map.setLayoutProperty(CLUB_PINS_LAYER, 'visibility', visible ? 'visible' : 'none');
	});
	$effect(() => {
		const visible = showRoutePins;
		if (!map || !mapLoaded) return;
		const vis = visible ? 'visible' : 'none';
		for (const id of [
			ROUTE_PINS_LAYER,
			ROUTE_CLUSTER_LAYER,
			ROUTE_CLUSTER_COUNT_LAYER,
		]) {
			map.setLayoutProperty(id, 'visibility', vis);
		}
	});
	$effect(() => {
		const visible = showHeatmapLayer;
		if (!map || !mapLoaded) return;
		map.setLayoutProperty(HEATMAP_LAYER, 'visibility', visible ? 'visible' : 'none');
		// Populate the heat the first time it's turned on (refresh() is a
		// no-op while the layer is off, so the points aren't fetched until
		// here). Re-runs on every toggle; only fetches when going on.
		if (visible) void refresh();
	});
	// Re-fetch the discoverable-route pins whenever the lens or the
	// distance bands change. Both are referenced directly so the
	// dependency is explicit rather than relying on the reads inside
	// refreshPins's async body.
	$effect(() => {
		routeFilter;
		selectedBands;
		if (!map || !mapLoaded) return;
		void refreshPins();
	});
	// The map shares the row with the sidebar, so collapsing / expanding
	// it changes the canvas width — MapLibre needs an explicit resize or
	// it renders at the stale width until the next pan.
	$effect(() => {
		sidebarOpen;
		if (!map) return;
		requestAnimationFrame(() => map?.resize());
	});

	// ─────────────── Hover-to-preview a single route ───────────────
	//
	// Routes aren't drawn by default; hovering a map dot OR its list row
	// reveals that one route's line + a halo on its dot, and tints the
	// matching list row (synchronized hover — the pattern research shows
	// users like). Engineered against the classic map-flicker failure
	// modes users hate: geometry is cached so a second hover never
	// refetches, the draw is async-guarded so a stale fetch can't paint
	// after you've moved on, re-hovering the same id is a no-op, and
	// clearing is debounced so crossing between a dot and its line (or
	// adjacent rows) doesn't flash. Touch devices don't fire hover — they
	// fall back to the dot popup (tap) + the row link, so nothing is lost.

	function setSourceData(id: string, data: GeoJSON.FeatureCollection) {
		(map?.getSource(id) as maplibregl.GeoJSONSource | undefined)?.setData(data);
	}

	function previewRoute(
		id: string,
		coords: [number, number],
		name: string,
		showTip = true,
	) {
		if (clearTimer) {
			clearTimeout(clearTimer);
			clearTimer = null;
		}
		if (hoveredRouteId === id) return; // already shown — no churn, no flicker
		hoveredRouteId = id;
		// The cluster popup already names the route, so it skips the tip to
		// avoid stacking a label on top of the popup at the same dot.
		if (showTip) openHoverTip(coords, name);
		setSourceData(ROUTE_HL_SOURCE, {
			type: 'FeatureCollection',
			features: [
				{ type: 'Feature', properties: {}, geometry: { type: 'Point', coordinates: coords } },
			],
		});
		void drawRouteLine(id);
	}

	async function drawRouteLine(id: string) {
		let coords = geomCache.get(id);
		if (!coords) {
			const route = await fetchRouteById(id);
			// The cursor may have moved on while the fetch was in flight.
			if (hoveredRouteId !== id) return;
			if (!route?.waypoints || route.waypoints.length < 2) return;
			coords = route.waypoints.map((w) => [w.lng, w.lat] as [number, number]);
			geomCache.set(id, coords);
		}
		if (hoveredRouteId !== id) return;
		setSourceData(ROUTES_SOURCE, {
			type: 'FeatureCollection',
			features: [
				{
					type: 'Feature',
					properties: { route_id: id },
					geometry: { type: 'LineString', coordinates: coords },
				},
			],
		});
	}

	function scheduleClear() {
		if (clearTimer) clearTimeout(clearTimer);
		clearTimer = setTimeout(clearPreview, 90);
	}

	function clearPreview() {
		clearTimer = null;
		hoveredRouteId = null;
		closeHoverTip();
		clusterPopup?.remove();
		clusterPopup = null;
		setSourceData(ROUTES_SOURCE, { type: 'FeatureCollection', features: [] });
		setSourceData(ROUTE_HL_SOURCE, { type: 'FeatureCollection', features: [] });
	}

	// ─────────────── Pin a route's line to keep it on the map ───────────────
	//
	// Reuses geomCache (populated by the hover preview), so a pinned route is
	// fetched at most once. Pinned lines persist across pan + filter changes
	// until unpinned; the hover preview still draws on top.

	/// Fetch + cache a route's polyline if not already cached. Returns the
	/// coords (or null if unavailable).
	async function ensureGeom(id: string): Promise<[number, number][] | null> {
		const cached = geomCache.get(id);
		if (cached) return cached;
		const route = await fetchRouteById(id);
		if (!route?.waypoints || route.waypoints.length < 2) return null;
		const coords = route.waypoints.map((w) => [w.lng, w.lat] as [number, number]);
		geomCache.set(id, coords);
		return coords;
	}

	function redrawPinned() {
		const features: GeoJSON.Feature[] = [];
		for (const id of pinnedIds) {
			const coords = geomCache.get(id);
			if (coords) {
				features.push({
					type: 'Feature',
					properties: { route_id: id },
					geometry: { type: 'LineString', coordinates: coords },
				});
			}
		}
		setSourceData(ROUTE_PINNED_SOURCE, { type: 'FeatureCollection', features });
	}

	async function togglePin(id: string) {
		const next = new Set(pinnedIds);
		if (next.has(id)) {
			next.delete(id);
			pinnedIds = next;
			redrawPinned();
			return;
		}
		next.add(id);
		pinnedIds = next;
		// Draw immediately if cached; otherwise fetch then redraw (guarding
		// against an unpin that happened while the fetch was in flight).
		if (geomCache.has(id)) {
			redrawPinned();
		} else {
			await ensureGeom(id);
			if (pinnedIds.has(id)) redrawPinned();
		}
	}

	function clearPinned() {
		pinnedIds = new Set();
		setSourceData(ROUTE_PINNED_SOURCE, { type: 'FeatureCollection', features: [] });
	}

	// When a cluster of overlapping start-pins is hovered, this lists the
	// routes in it (you can't zoom apart pins that share a coordinate, so a
	// list is the only way to reach them). Sticky via the same clear-timer
	// the line preview uses; hovering a row previews that route's line,
	// clicking opens it.
	let clusterPopup: maplibregl.Popup | null = null;

	interface ClusterRoute {
		id: string;
		name: string;
		featured: boolean;
		distance_m: number;
		surface: string;
		run_count: number;
		lng: number;
		lat: number;
	}

	function openClusterPopup(
		coords: [number, number],
		routes: ClusterRoute[],
		total: number,
	) {
		if (!map) return;
		clusterPopup?.remove();
		const rowsHtml = routes
			.map((r) => {
				const star = r.featured
					? `<span class="cluster-route-star" title="${escapeHtml(m('routeHeatmap.featured'))}">★</span>`
					: '';
				const meta = [
					formatDistance(r.distance_m),
					r.surface,
					r.run_count > 0
						? r.run_count === 1
							? m('routeHeatmap.runCountOne', { n: r.run_count })
							: m('routeHeatmap.runCountMany', { n: r.run_count })
						: '',
				]
					.filter(Boolean)
					.join(' · ');
				const kept = pinnedIds.has(r.id);
				return `<div class="cluster-route ${kept ? 'kept' : ''}"
					data-route-id="${escapeHtml(r.id)}" data-lng="${r.lng}" data-lat="${r.lat}"
					data-name="${escapeHtml(r.name)}" role="button" tabindex="0"
					title="${escapeHtml(kept ? m('routeHeatmap.keptClickRemove') : m('routeHeatmap.clickKeep'))}">
					<span class="cluster-route-main">
						<span class="cluster-route-name">${star}${escapeHtml(r.name)}</span>
						<span class="cluster-route-meta">${escapeHtml(meta)}</span>
					</span>
					<a class="cluster-route-view" href="/routes/${escapeHtml(r.id)}"
						data-sveltekit-preload-data="hover" title="${escapeHtml(m('routeHeatmap.openRoutePage'))}">${escapeHtml(m('routeHeatmap.view'))} &rarr;</a>
				</div>`;
			})
			.join('');
		const more =
			total > routes.length
				? `<div class="cluster-more">${escapeHtml(m('routeHeatmap.clusterMore', { n: total - routes.length }))}</div>`
				: '';
		const html = `<div class="cluster-popup">
			<div class="cluster-popup-head">${escapeHtml(m('routeHeatmap.clusterHead', { n: total }))}</div>
			<div class="cluster-popup-list">${rowsHtml}</div>
			${more}
		</div>`;
		// Sync the map transform before projecting the lng/lat — same
		// stale-transform guard openPopupRaw uses, or the popup can land
		// at the map origin (top-left) instead of over the cluster.
		map.resize();
		clusterPopup = new maplibregl.Popup({
			closeButton: false,
			closeOnClick: false,
			offset: 14,
			maxWidth: '280px',
			className: 'heatmap-cluster-popup',
			focusAfterOpen: false,
		})
			.setLngLat(coords)
			.setHTML(html)
			.addTo(map);
		const el = clusterPopup.getElement();
		// Keep the popup + preview alive while the cursor is over it.
		el.addEventListener('mouseenter', () => {
			if (clearTimer) {
				clearTimeout(clearTimer);
				clearTimer = null;
			}
		});
		el.addEventListener('mouseleave', () => scheduleClear());
		// Delegated: hovering any row previews that route's line.
		el.addEventListener('mouseover', (ev) => {
			const row = (ev.target as HTMLElement).closest('[data-route-id]') as
				| HTMLElement
				| null;
			if (!row?.dataset.routeId) return;
			previewRoute(
				row.dataset.routeId,
				[parseFloat(row.dataset.lng ?? '0'), parseFloat(row.dataset.lat ?? '0')],
				row.dataset.name ?? '',
				false,
			);
		});
		// Delegated: clicking a row keeps that route (toggle). The "View"
		// link is left alone so it navigates to the detail page.
		el.addEventListener('click', (ev) => {
			const target = ev.target as HTMLElement;
			if (target.closest('.cluster-route-view')) return;
			const row = target.closest('[data-route-id]') as HTMLElement | null;
			if (!row?.dataset.routeId) return;
			ev.preventDefault();
			const id = row.dataset.routeId;
			void togglePin(id);
			const kept = pinnedIds.has(id);
			row.classList.toggle('kept', kept);
			row.title = kept ? m('routeHeatmap.keptClickRemove') : m('routeHeatmap.clickKeep');
		});
	}

	async function refresh() {
		// Heat is opt-in (off by default). When the layer is hidden, skip
		// the fetch entirely — densifying up to 5k points server-side then
		// throwing them away is pure wasted compute. The visibility effect
		// calls this when the user turns Heat on, and moveend re-runs it
		// only while it's on.
		if (!map || !showHeatmapLayer) return;
		const b = map.getBounds();
		try {
			const pts = await fetchHeatmapPoints({
				minLng: b.getWest(),
				minLat: b.getSouth(),
				maxLng: b.getEast(),
				maxLat: b.getNorth(),
			});
			const features: GeoJSON.Feature[] = pts.map((p) => ({
				type: 'Feature',
				geometry: { type: 'Point', coordinates: [p.lng, p.lat] },
				properties: {},
			}));
			cachedFeatures = features;
			if (mapLoaded) {
				const src = map.getSource(HEATMAP_SOURCE) as maplibregl.GeoJSONSource | undefined;
				src?.setData({ type: 'FeatureCollection', features });
			}
		} catch (e) {
			console.error('heatmap refresh failed', e);
		}
	}
</script>

<div class="discover" class:collapsed={!sidebarOpen}>
	<aside class="discover-sidebar" data-testid="discover-sidebar" aria-label={m('routeHeatmap.routeDiscovery')}>
		<div class="sidebar-search" data-testid="heatmap-search">
			<div class="search-input-row">
				<input
					bind:this={searchInput}
					bind:value={searchQuery}
					oninput={onSearchInput}
					onfocusout={() => setTimeout(() => (showResults = false), 200)}
					onfocusin={() => {
						if (searchResults.length > 0) showResults = true;
					}}
					type="text"
					placeholder={m('routeHeatmap.searchPlaceholder')}
					aria-label={m('routeHeatmap.searchAriaLabel')}
				/>
				<button
					type="button"
					class="filters-btn"
					class:active={filtersOpen}
					data-testid="filters-button"
					aria-expanded={filtersOpen}
					onclick={() => (filtersOpen = !filtersOpen)}
				>
					<span class="material-symbols">tune</span>
					<span class="filters-btn-text">{m('routeHeatmap.filters')}</span>
					{#if activeFilterCount > 0}
						<span class="filters-badge">{activeFilterCount}</span>
					{/if}
				</button>
			</div>
			{#if showResults}
				<ul class="search-results">
					{#each searchResults as result (result.lat + ':' + result.lng)}
						<li>
							<button onmousedown={() => selectSearchResult(result)}>
								{result.name}
							</button>
						</li>
					{/each}
				</ul>
			{/if}
		</div>

		{#if filtersOpen}
			<div class="filters-panel" data-testid="filters-panel">
				<div class="filter-group">
					<span class="filter-group-label">{m('routeHeatmap.show')}</span>
					<div class="chip-row" role="group" aria-label={m('routeHeatmap.routeLens')} data-testid="lens-chips">
						{#each FILTERS as f (f.id)}
							<button
								type="button"
								class="chip"
								class:active={routeFilter === f.id}
								aria-pressed={routeFilter === f.id}
								title={f.hint}
								data-filter={f.id}
								onclick={() => (routeFilter = f.id)}>{f.label}</button>
						{/each}
					</div>
				</div>
				<div class="filter-group">
					<span class="filter-group-label">{m('routeHeatmap.distance')}</span>
					<div class="chip-row" role="group" aria-label={m('routeHeatmap.raceDistance')} data-testid="band-chips">
						{#each DISTANCE_BANDS as b (b.key)}
							<button
								type="button"
								class="chip"
								class:active={selectedBands.includes(b.key)}
								aria-pressed={selectedBands.includes(b.key)}
								data-band={b.key}
								onclick={() => toggleBand(b.key)}>{b.label}</button>
						{/each}
					</div>
				</div>
				<div class="filter-group">
					<span class="filter-group-label">{m('routeHeatmap.mapLayers')}</span>
					<div class="layer-toggles">
						<label class="layer-row">
							<input type="checkbox" bind:checked={showHeatmapLayer} />
							<span>{m('routeHeatmap.heat')}</span>
						</label>
						<label class="layer-row">
							<input type="checkbox" bind:checked={showClubPins} />
							<span>{m('routeHeatmap.clubs')}</span>
							<span class="layer-count">{clubPinsCount}</span>
						</label>
					</div>
				</div>
				{#if activeFilterCount > 0}
					<button type="button" class="filters-reset" onclick={resetFilters}>
						{m('routeHeatmap.resetFilters')}
					</button>
				{/if}
			</div>
		{/if}

		<div class="results-header">
			<span class="results-count">
				<strong>{routePinsCount}</strong>
				{routePinsCount === 1 ? m('routeHeatmap.routeWordOne') : m('routeHeatmap.routeWordMany')}
			</span>
			<span class="results-lens">
				{activeFilterLabel}{#if selectedBands.length > 0} · {bandSummary}{/if}
			</span>
			{#if pinnedIds.size > 0}
				<button
					type="button"
					class="results-clear-pins"
					data-testid="clear-pins"
					onclick={clearPinned}
				>
					{m('routeHeatmap.clearKept', { n: pinnedIds.size })}
				</button>
			{:else if loading}
				<span class="results-spinner" aria-label={m('routeHeatmap.updating')} title={m('routeHeatmap.updatingTitle')}></span>
			{:else if lastUpdated}
				<span class="results-updated">
					{lastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
				</span>
			{/if}
		</div>

		<ul class="results-list" data-testid="discover-list">
			{#each routePins as r (r.id)}
				{@const band = bandForDistance(r.distance_m)}
				<li class="result-li" class:pinned={pinnedIds.has(r.id)}>
					<button
						type="button"
						class="result-row"
						class:featured={r.is_featured}
						class:hovered={hoveredRouteId === r.id}
						class:kept={pinnedIds.has(r.id)}
						data-route-id={r.id}
						aria-pressed={pinnedIds.has(r.id)}
						title={pinnedIds.has(r.id)
							? m('routeHeatmap.keptClickRemove')
							: m('routeHeatmap.clickKeepThisRoute')}
						onmouseenter={() => previewRoute(r.id, [r.lng, r.lat], r.name)}
						onmouseleave={scheduleClear}
						onclick={() => void togglePin(r.id)}
					>
						<span class="result-name">
							{#if pinnedIds.has(r.id)}<span
									class="result-kept material-symbols"
									title={m('routeHeatmap.keptOnMap')}>push_pin</span
								>{/if}
							{#if r.is_featured}<span class="result-star" title={m('routeHeatmap.featured')}>★</span>{/if}
							{r.name}
						</span>
						<span class="result-meta">
							{#if band}<span class="result-band">{band.label}</span>{/if}
							<span>{formatDistance(r.distance_m)}</span>
							{#if r.surface}<span>· {r.surface}</span>{/if}
							{#if r.run_count > 0}<span>· {r.run_count === 1 ? m('routeHeatmap.runCountOne', { n: r.run_count }) : m('routeHeatmap.runCountMany', { n: r.run_count })}</span>{/if}
						</span>
					</button>
					<a
						class="result-view"
						href="/routes/{r.id}"
						data-sveltekit-preload-data="hover"
						data-testid="result-view"
						title={m('routeHeatmap.openRoutePage')}
					>
						{m('routeHeatmap.view')}<span class="material-symbols">arrow_forward</span>
					</a>
				</li>
			{:else}
				<li class="results-empty">
					{m('routeHeatmap.emptyState')}
				</li>
			{/each}
		</ul>
	</aside>

	<div class="discover-map-wrap">
		<button
			type="button"
			class="sidebar-toggle"
			data-testid="sidebar-toggle"
			onclick={() => (sidebarOpen = !sidebarOpen)}
			aria-label={sidebarOpen ? m('routeHeatmap.hideRouteList') : m('routeHeatmap.showRouteList')}
			aria-expanded={sidebarOpen}
		>
			<span class="material-symbols">{sidebarOpen ? 'chevron_left' : 'chevron_right'}</span>
		</button>
		<div bind:this={mapEl} class="map"></div>
	</div>
</div>

<style>
	.discover {
		display: flex;
		flex-direction: row;
		height: 100%;
		min-height: 28rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
	}
	/* Results sidebar — search + filters + the scrollable route list.
	 * Sits beside the map (not over it) so nothing overlaps. */
	.discover-sidebar {
		display: flex;
		flex-direction: column;
		width: 23rem;
		max-width: 40%;
		flex-shrink: 0;
		min-height: 0;
		background: var(--color-surface);
		border-inline-end: 1px solid var(--color-border);
	}
	.discover.collapsed .discover-sidebar {
		display: none;
	}
	.discover-map-wrap {
		position: relative;
		flex: 1 1 auto;
		min-width: 0;
		display: flex;
	}
	.map {
		flex: 1 1 auto;
		min-width: 0;
		min-height: 0;
	}
	/* Collapse handle floating on the map's leading edge. */
	.sidebar-toggle {
		position: absolute;
		top: 50%;
		inset-inline-start: 0;
		transform: translateY(-50%);
		z-index: 2;
		display: flex;
		align-items: center;
		justify-content: center;
		width: 22px;
		height: 48px;
		padding: 0;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-inline-start: 0;
		border-start-end-radius: var(--radius-md);
		border-end-end-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.sidebar-toggle:hover {
		color: var(--color-text);
	}

	/* Search row: place-search input + the Filters toggle button. */
	.sidebar-search {
		padding: var(--space-md);
		border-bottom: 1px solid var(--color-border);
		flex-shrink: 0;
	}
	.search-input-row {
		display: flex;
		gap: 0.5rem;
	}
	.search-input-row input {
		flex: 1 1 auto;
		min-width: 0;
		padding: 0.5rem 0.75rem;
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		color: var(--color-text);
	}
	.search-input-row input:focus {
		outline: 2px solid var(--color-accent);
		outline-offset: 1px;
	}
	.filters-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		flex-shrink: 0;
		padding: 0.4rem 0.7rem;
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		cursor: pointer;
	}
	.filters-btn:hover,
	.filters-btn.active {
		color: var(--color-primary);
		border-color: var(--color-primary);
	}
	.filters-btn .material-symbols {
		font-size: 1.1rem;
	}
	.filters-badge {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 1.1rem;
		height: 1.1rem;
		padding: 0 0.3rem;
		font-size: 0.7rem;
		font-weight: 700;
		color: var(--color-on-primary, #fff);
		background: var(--color-primary);
		border-radius: 999px;
	}
	.search-results {
		margin: 0.5rem 0 0;
		padding: 0;
		list-style: none;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		max-height: 14rem;
		overflow-y: auto;
	}
	.search-results li button {
		width: 100%;
		text-align: start;
		padding: 0.5rem 0.75rem;
		background: transparent;
		border: 0;
		font-size: 0.85rem;
		color: var(--color-text);
		cursor: pointer;
	}
	.search-results li button:hover {
		background: var(--color-surface-hover);
	}

	/* Advanced filters: lens + race-distance bands + map layers. */
	.filters-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		padding: var(--space-md);
		border-bottom: 1px solid var(--color-border);
		flex-shrink: 0;
	}
	.filter-group {
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
	}
	.filter-group-label {
		font-size: 0.7rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
	}
	.chip-row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
	}
	.chip {
		padding: 0.3rem 0.7rem;
		font-size: 0.8rem;
		font-weight: 600;
		white-space: nowrap;
		color: var(--color-text-secondary);
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: 999px;
		cursor: pointer;
		transition: color var(--transition-fast), background var(--transition-fast),
			border-color var(--transition-fast);
	}
	.chip:hover {
		color: var(--color-text);
		border-color: var(--color-primary);
	}
	.chip.active {
		color: var(--color-on-primary, #fff);
		background: var(--color-primary);
		border-color: var(--color-primary);
	}
	.layer-toggles {
		display: flex;
		gap: 1rem;
	}
	.layer-row {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		font-size: 0.8rem;
		color: var(--color-text);
		cursor: pointer;
		user-select: none;
	}
	.layer-row input[type='checkbox'] {
		margin: 0;
		accent-color: var(--color-primary);
	}
	.layer-count {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	.filters-reset {
		align-self: flex-start;
		padding: 0.3rem 0.6rem;
		font-size: 0.78rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		background: transparent;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		cursor: pointer;
	}
	.filters-reset:hover {
		color: var(--color-text);
		border-color: var(--color-primary);
	}

	/* Results header + scrollable list (the textual twin of the pins). */
	.results-header {
		display: flex;
		align-items: baseline;
		gap: 0.5rem;
		padding: 0.6rem var(--space-md);
		border-bottom: 1px solid var(--color-border);
		flex-shrink: 0;
		font-size: 0.82rem;
	}
	.results-count strong {
		font-variant-numeric: tabular-nums;
	}
	.results-lens {
		color: var(--color-text-tertiary);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.results-updated {
		margin-inline-start: auto;
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	.results-spinner {
		margin-inline-start: auto;
		width: 10px;
		height: 10px;
		border: 2px solid var(--color-border);
		border-top-color: var(--color-primary);
		border-radius: 50%;
		animation: spin 0.8s linear infinite;
	}
	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}
	.results-list {
		margin: 0;
		padding: 0;
		list-style: none;
		overflow-y: auto;
		flex: 1 1 auto;
		min-height: 0;
	}
	.result-li {
		display: flex;
		align-items: stretch;
		border-bottom: 1px solid var(--color-border);
	}
	/* The row body is a button: clicking it keeps the route on the map
	 * (toggle). Reset the native button chrome so it reads as a list row. */
	.result-row {
		flex: 1 1 auto;
		min-width: 0;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 0.2rem;
		padding: 0.6rem var(--space-md);
		text-align: start;
		font: inherit;
		color: var(--color-text);
		background: transparent;
		border: 0;
		cursor: pointer;
		appearance: none;
	}
	.result-row:hover,
	.result-row.hovered {
		background: var(--color-surface-hover);
	}
	/* A kept route gets a violet left rail + a filled pin glyph in the name
	 * so the list mirrors the violet line drawn on the map. */
	.result-row.kept {
		box-shadow: inset 3px 0 0 #8b5cf6;
	}
	.result-kept {
		font-size: 0.95rem;
		color: #8b5cf6;
		font-variation-settings: 'FILL' 1;
		vertical-align: -0.15em;
		margin-inline-end: 0.1rem;
	}
	/* "View route" link at the trailing edge — the only navigation. */
	.result-view {
		flex-shrink: 0;
		display: flex;
		align-items: center;
		gap: 0.1rem;
		padding: 0 var(--space-sm);
		font-size: 0.72rem;
		font-weight: 600;
		text-decoration: none;
		color: var(--color-primary);
		border-inline-start: 1px solid var(--color-border);
		transition: color var(--transition-fast), background var(--transition-fast);
	}
	.result-view:hover {
		background: var(--color-surface-hover);
	}
	.result-view .material-symbols {
		font-size: 1rem;
	}
	.results-clear-pins {
		margin-inline-start: auto;
		padding: 0.1rem 0.5rem;
		font-size: 0.72rem;
		font-weight: 600;
		color: #8b5cf6;
		background: transparent;
		border: 1px solid #8b5cf6;
		border-radius: 999px;
		cursor: pointer;
	}
	.results-clear-pins:hover {
		background: rgba(139, 92, 246, 0.12);
	}
	/* Hovering the dot on the map tints + accents its row (and vice
	 * versa) — the synchronized hover that ties the two surfaces. Uses
	 * an inset box-shadow so it layers over the featured gold border
	 * instead of clobbering it. */
	.result-row.hovered {
		box-shadow: inset 3px 0 0 var(--color-primary);
	}
	.result-row.featured {
		border-inline-start: 3px solid #facc15;
	}
	.result-name {
		font-size: 0.88rem;
		font-weight: 600;
		line-height: 1.25;
	}
	.result-star {
		color: #facc15;
	}
	.result-meta {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.3rem;
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	.result-band {
		font-weight: 700;
		color: var(--color-primary);
		background: var(--color-primary-light);
		padding: 0.02rem 0.4rem;
		border-radius: 999px;
	}
	.results-empty {
		padding: 1.25rem var(--space-md);
		font-size: 0.82rem;
		color: var(--color-text-tertiary);
	}

	/* Narrow viewports: stack the sidebar above the map as a top sheet. */
	@media (max-width: 40rem) {
		.discover {
			flex-direction: column;
		}
		.discover-sidebar {
			width: auto;
			max-width: none;
			max-height: 55%;
			border-inline-end: 0;
			border-bottom: 1px solid var(--color-border);
		}
		.sidebar-toggle {
			top: 0;
			inset-inline-start: 50%;
			transform: translateX(-50%);
			width: 48px;
			height: 22px;
			border: 1px solid var(--color-border);
			border-top: 0;
			border-radius: 0 0 var(--radius-md) var(--radius-md);
		}
	}

	/*
	 * MapLibre popups live OUTSIDE the Svelte component's DOM tree
	 * (they're attached to map._container directly), so component-
	 * scoped styles don't reach them. `:global(...)` is required.
	 * Two popup classes:
	 *   - .heatmap-pin-popup — click-anchored card with title +
	 *     subtitle + a "View …" action link.
	 *   - .heatmap-hover-tip — small name-only badge on hover.
	 */
	:global(.maplibregl-popup.heatmap-pin-popup) {
		max-width: 260px;
	}
	:global(.heatmap-pin-popup .maplibregl-popup-content) {
		background: var(--color-surface);
		color: var(--color-text);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-lg);
		padding: 0.6rem 0.8rem 0.7rem;
	}
	:global(.heatmap-pin-popup .maplibregl-popup-tip) {
		border-top-color: var(--color-border);
		border-bottom-color: var(--color-border);
	}
	:global(.heatmap-pin-popup .maplibregl-popup-close-button) {
		font-size: 1.2rem;
		color: var(--color-text-secondary);
		padding: 0 0.4rem;
	}
	/* Head row — avatar/star + title block side by side. */
	:global(.heatmap-pin-popup .pin-popup-head) {
		display: flex;
		align-items: center;
		gap: 0.55rem;
		margin-bottom: 0.4rem;
	}
	:global(.heatmap-pin-popup .pin-popup-titleblock) {
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
		min-width: 0;
		flex: 1;
	}
	:global(.heatmap-pin-popup .pin-popup-title) {
		font-weight: 700;
		font-size: 0.95rem;
		line-height: 1.2;
		color: var(--color-text);
	}
	:global(.heatmap-pin-popup .pin-popup-meta) {
		font-size: 0.72rem;
		color: var(--color-text-tertiary);
	}
	/* Avatar — circle 32px. Image OR initials fallback. */
	:global(.heatmap-pin-popup .pin-avatar) {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 32px;
		height: 32px;
		border-radius: 50%;
		background: var(--color-primary-light);
		color: var(--color-primary);
		font-weight: 700;
		font-size: 0.75rem;
		flex-shrink: 0;
		object-fit: cover;
	}
	:global(.heatmap-pin-popup .pin-popup-location) {
		display: block;
		font-size: 0.75rem;
		color: var(--color-text-secondary);
		margin-bottom: 0.5rem;
	}
	:global(.heatmap-pin-popup .pin-popup-action) {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 100%;
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-primary);
		text-decoration: none;
		padding: 0.4rem 0.7rem;
		border: 1px solid var(--color-primary);
		border-radius: var(--radius-sm);
		transition: background var(--transition-fast);
		background: transparent;
	}
	:global(.heatmap-pin-popup .pin-popup-action:hover) {
		background: var(--color-primary-light);
	}

	/* Hover tooltip — small, no border, no close button. Closes on
	 * mouseleave via JS. */
	:global(.maplibregl-popup.heatmap-hover-tip) {
		max-width: 240px;
		pointer-events: none;
	}
	:global(.heatmap-hover-tip .maplibregl-popup-content) {
		background: var(--color-surface);
		color: var(--color-text);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		box-shadow: var(--shadow-md);
		padding: 0.3rem 0.6rem;
		font-size: 0.78rem;
		font-weight: 500;
	}
	:global(.heatmap-hover-tip .maplibregl-popup-tip) {
		border-top-color: var(--color-border);
		border-bottom-color: var(--color-border);
	}

	/* Cluster list popup — the routes that share (or nearly share) a start
	 * point, since overlapping pins can't be zoomed apart. Each row previews
	 * its line on hover and opens the route on click. */
	:global(.maplibregl-popup.heatmap-cluster-popup) {
		max-width: 280px;
	}
	:global(.heatmap-cluster-popup .maplibregl-popup-content) {
		background: var(--color-surface);
		color: var(--color-text);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-lg);
		padding: 0.4rem;
	}
	:global(.heatmap-cluster-popup .maplibregl-popup-tip) {
		border-top-color: var(--color-border);
		border-bottom-color: var(--color-border);
	}
	:global(.heatmap-cluster-popup .cluster-popup-head) {
		padding: 0.3rem 0.5rem;
		font-size: 0.72rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-tertiary);
	}
	:global(.heatmap-cluster-popup .cluster-popup-list) {
		max-height: 16rem;
		overflow-y: auto;
	}
	/* Row = keep-on-click target; the trailing View link is the only
	 * navigation. Lay them out side by side. */
	:global(.heatmap-cluster-popup .cluster-route) {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.4rem 0.5rem;
		border-radius: var(--radius-sm);
		color: var(--color-text);
		cursor: pointer;
	}
	:global(.heatmap-cluster-popup .cluster-route:hover) {
		background: var(--color-surface-hover);
	}
	:global(.heatmap-cluster-popup .cluster-route-main) {
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
		flex: 1 1 auto;
		min-width: 0;
	}
	:global(.heatmap-cluster-popup .cluster-route.kept) {
		box-shadow: inset 3px 0 0 #8b5cf6;
	}
	:global(.heatmap-cluster-popup .cluster-route.kept .cluster-route-name) {
		color: #8b5cf6;
	}
	:global(.heatmap-cluster-popup .cluster-route-view) {
		flex-shrink: 0;
		font-size: 0.72rem;
		font-weight: 600;
		text-decoration: none;
		color: var(--color-primary);
		white-space: nowrap;
	}
	:global(.heatmap-cluster-popup .cluster-route-view:hover) {
		text-decoration: underline;
	}
	:global(.heatmap-cluster-popup .cluster-route-name) {
		font-size: 0.85rem;
		font-weight: 600;
		line-height: 1.2;
	}
	:global(.heatmap-cluster-popup .cluster-route-star) {
		color: #facc15;
		margin-inline-end: 0.2rem;
	}
	:global(.heatmap-cluster-popup .cluster-route-meta) {
		font-size: 0.72rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	:global(.heatmap-cluster-popup .cluster-more) {
		padding: 0.35rem 0.5rem 0.1rem;
		font-size: 0.72rem;
		font-style: italic;
		color: var(--color-text-tertiary);
	}

</style>
