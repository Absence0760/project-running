<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { goto } from '$app/navigation';
	import maplibregl from 'maplibre-gl';
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

	let mapEl: HTMLDivElement;
	let map: maplibregl.Map | null = null;
	let stopResizeWatch: (() => void) | null = null;
	let loading = $state(false);
	let lastUpdated = $state<Date | null>(null);
	let mapLoaded = false;
	let cachedFeatures: GeoJSON.Feature[] = [];

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
	const FILTERS: { id: DiscoverFilter; label: string; hint: string }[] = [
		{ id: 'popular', label: 'Popular', hint: 'Routes people actually run' },
		{ id: 'friends', label: 'Friends', hint: 'Routes from people you follow' },
		{ id: 'featured', label: 'Featured', hint: 'Hand-picked routes' },
		{ id: 'hidden_gems', label: 'Hidden gems', hint: 'Quiet routes nobody has run yet' },
	];
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
			// World view by default. We try to geolocate immediately
			// after mount; if the user grants permission, flyTo the
			// real position. If they deny / aren't asked yet / the
			// API isn't available, the global view shows the spread
			// of points across the dataset — strictly better than the
			// previous "everyone starts in London" default.
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
		// Background-fetch the user's location + recentre. Browsers
		// prompt for permission on the first call; deny / unavailable
		// just leaves the world view, which is the right "no idea
		// where you are" baseline. The 5 s timeout is the same we
		// use elsewhere — long enough for a real GPS lock on a
		// laptop, short enough that the page doesn't feel stuck.
		if (typeof navigator !== 'undefined' && navigator.geolocation) {
			navigator.geolocation.getCurrentPosition(
				(pos) => {
					map?.flyTo({
						center: [pos.coords.longitude, pos.coords.latitude],
						zoom: 12,
						essential: true,
					});
				},
				() => {
					// Silent: world view is the fallback by design.
				},
				{ timeout: 5000 },
			);
		}

		map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
		// "Locate me" button. Built-in MapLibre primitive — no
		// MapTiler key needed, so this is the always-available
		// navigation affordance even on a Protomaps-only dev setup
		// where the search box is dormant.
		map.addControl(
			new maplibregl.GeolocateControl({
				positionOptions: { enableHighAccuracy: true, timeout: 5000 },
				trackUserLocation: false,
				showAccuracyCircle: true,
				showUserLocation: true,
			}),
			'top-right',
		);

		map.on('load', () => {
			if (!map) return;
			mapLoaded = true;
			map.addSource(HEATMAP_SOURCE, {
				type: 'geojson',
				data: { type: 'FeatureCollection', features: cachedFeatures },
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
				if (id) void goto(`/routes/${id}`);
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
				const name = (f.properties?.name as string) ?? 'Club';
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
			map.on('mouseenter', ROUTE_CLUSTER_LAYER, () => {
				if (map) map.getCanvas().style.cursor = 'pointer';
			});
			map.on('mouseleave', ROUTE_CLUSTER_LAYER, () => {
				if (map) map.getCanvas().style.cursor = '';
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
				const f = e.features?.[0];
				if (!f || !map) return;
				const id = f.properties?.id as string | undefined;
				if (!id) return;
				const coords = (f.geometry as GeoJSON.Point).coordinates as [number, number];
				openRoutePopup(coords, {
					id,
					name: (f.properties?.name as string) ?? 'Route',
					featured: !!f.properties?.featured,
					distance_m: (f.properties?.distance_m as number) ?? 0,
					elevation_m: (f.properties?.elevation_m as number) ?? null,
					surface: (f.properties?.surface as string) ?? '',
					run_count: (f.properties?.run_count as number) ?? 0,
				});
			});
			map.on('mouseenter', ROUTE_PINS_LAYER, (e) => {
				if (!map) return;
				map.getCanvas().style.cursor = 'pointer';
				const f = e.features?.[0];
				if (!f) return;
				const id = f.properties?.id as string | undefined;
				const name = (f.properties?.name as string) ?? '';
				const coords = (f.geometry as GeoJSON.Point).coordinates as [number, number];
				if (id) previewRoute(id, coords, name);
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

	function escapeHtml(s: string): string {
		return s
			.replace(/&/g, '&amp;')
			.replace(/</g, '&lt;')
			.replace(/>/g, '&gt;')
			.replace(/"/g, '&quot;')
			.replace(/'/g, '&#39;');
	}

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
		const memberLine = `${d.memberCount} member${d.memberCount === 1 ? '' : 's'}`;
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
				<a class="pin-popup-action" href="${escapeHtml(d.href)}"
					data-sveltekit-preload-data="hover">
					View club &rarr;
				</a>
			</div>
		`;
		openPopupRaw(coords, html);
	}

	interface RoutePopupData {
		id: string;
		name: string;
		featured: boolean;
		distance_m: number;
		elevation_m: number | null;
		surface: string;
		run_count: number;
	}
	function openRoutePopup(coords: [number, number], d: RoutePopupData) {
		const stats: string[] = [];
		stats.push(
			`<span class="pin-stat"><span class="pin-stat-icon">📏</span>${escapeHtml(formatDistance(d.distance_m))}</span>`,
		);
		if (d.elevation_m != null && d.elevation_m > 0) {
			stats.push(
				`<span class="pin-stat"><span class="pin-stat-icon">⛰</span>${Math.round(d.elevation_m)} m</span>`,
			);
		}
		if (d.surface) {
			stats.push(
				`<span class="pin-stat"><span class="pin-stat-icon">🛣</span>${escapeHtml(d.surface)}</span>`,
			);
		}
		if (d.run_count > 0) {
			stats.push(
				`<span class="pin-stat"><span class="pin-stat-icon">🏃</span>${d.run_count} run${d.run_count === 1 ? '' : 's'}</span>`,
			);
		}
		const star = d.featured
			? '<span class="pin-popup-star" title="Featured">★</span>'
			: '';
		const html = `
			<div class="pin-popup pin-popup-route ${d.featured ? 'pin-popup-featured' : ''}">
				<div class="pin-popup-head">
					${star}
					<div class="pin-popup-titleblock">
						<span class="pin-popup-title">${escapeHtml(d.name)}</span>
						${d.featured ? '<span class="pin-popup-badge">Featured route</span>' : ''}
					</div>
				</div>
				<div class="pin-popup-stats">${stats.join('')}</div>
				<a class="pin-popup-action" href="/routes/${escapeHtml(d.id)}"
					data-sveltekit-preload-data="hover">
					View route &rarr;
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
	async function refreshPins() {
		if (!map || !mapLoaded) return;
		// The discovery pins are the always-relevant fetch, so the status
		// (spinner + "Updated") tracks this, not the opt-in heat fetch.
		loading = true;
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
					featured: r.featured,
					distance_m: r.distance_m,
					surface: r.surface,
					run_count: r.run_count,
				},
				geometry: { type: 'Point', coordinates: [r.lng, r.lat] },
			})),
		});
		lastUpdated = new Date();
		loading = false;
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

	function previewRoute(id: string, coords: [number, number], name: string) {
		if (clearTimer) {
			clearTimeout(clearTimer);
			clearTimer = null;
		}
		if (hoveredRouteId === id) return; // already shown — no churn, no flicker
		hoveredRouteId = id;
		openHoverTip(coords, name);
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
		setSourceData(ROUTES_SOURCE, { type: 'FeatureCollection', features: [] });
		setSourceData(ROUTE_HL_SOURCE, { type: 'FeatureCollection', features: [] });
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
	<aside class="discover-sidebar" data-testid="discover-sidebar" aria-label="Route discovery">
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
					placeholder="Search a place…"
					aria-label="Search for a place to centre the map on"
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
					<span class="filters-btn-text">Filters</span>
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
					<span class="filter-group-label">Show</span>
					<div class="chip-row" role="group" aria-label="Route lens" data-testid="lens-chips">
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
					<span class="filter-group-label">Distance</span>
					<div class="chip-row" role="group" aria-label="Race distance" data-testid="band-chips">
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
					<span class="filter-group-label">Map layers</span>
					<div class="layer-toggles">
						<label class="layer-row">
							<input type="checkbox" bind:checked={showHeatmapLayer} />
							<span>Heat</span>
						</label>
						<label class="layer-row">
							<input type="checkbox" bind:checked={showClubPins} />
							<span>Clubs</span>
							<span class="layer-count">{clubPinsCount}</span>
						</label>
					</div>
				</div>
				{#if activeFilterCount > 0}
					<button type="button" class="filters-reset" onclick={resetFilters}>
						Reset filters
					</button>
				{/if}
			</div>
		{/if}

		<div class="results-header">
			<span class="results-count">
				<strong>{routePinsCount}</strong>
				{routePinsCount === 1 ? 'route' : 'routes'}
			</span>
			<span class="results-lens">
				{activeFilterLabel}{#if selectedBands.length > 0} · {bandSummary}{/if}
			</span>
			{#if loading}
				<span class="results-spinner" aria-label="Updating" title="Updating…"></span>
			{:else if lastUpdated}
				<span class="results-updated">
					{lastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
				</span>
			{/if}
		</div>

		<ul class="results-list" data-testid="discover-list">
			{#each routePins as r (r.id)}
				{@const band = bandForDistance(r.distance_m)}
				<li>
					<a
						class="result-row"
						class:featured={r.featured}
						class:hovered={hoveredRouteId === r.id}
						href="/routes/{r.id}"
						data-sveltekit-preload-data="hover"
						data-route-id={r.id}
						onmouseenter={() => previewRoute(r.id, [r.lng, r.lat], r.name)}
						onmouseleave={scheduleClear}
					>
						<span class="result-name">
							{#if r.featured}<span class="result-star" title="Featured">★</span>{/if}
							{r.name}
						</span>
						<span class="result-meta">
							{#if band}<span class="result-band">{band.label}</span>{/if}
							<span>{formatDistance(r.distance_m)}</span>
							{#if r.surface}<span>· {r.surface}</span>{/if}
							{#if r.run_count > 0}<span>· {r.run_count} run{r.run_count === 1 ? '' : 's'}</span>{/if}
						</span>
					</a>
				</li>
			{:else}
				<li class="results-empty">
					No routes here yet. Pan the map, zoom out, or change the filters.
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
			aria-label={sidebarOpen ? 'Hide route list' : 'Show route list'}
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
	.result-row {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		padding: 0.6rem var(--space-md);
		text-decoration: none;
		color: var(--color-text);
		border-bottom: 1px solid var(--color-border);
	}
	.result-row:hover,
	.result-row.hovered {
		background: var(--color-surface-hover);
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
	:global(.heatmap-pin-popup .pin-popup-star) {
		color: #facc15;
		font-size: 1.2rem;
		line-height: 1;
		flex-shrink: 0;
	}
	:global(.heatmap-pin-popup .pin-popup-badge) {
		display: inline-block;
		font-size: 0.65rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: #facc15;
		background: rgba(250, 204, 21, 0.12);
		padding: 0.05rem 0.4rem;
		border-radius: 999px;
		align-self: flex-start;
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
	/* Route stats — icon + value chips on one row. */
	:global(.heatmap-pin-popup .pin-popup-stats) {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem 0.8rem;
		margin-bottom: 0.6rem;
	}
	:global(.heatmap-pin-popup .pin-stat) {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	:global(.heatmap-pin-popup .pin-stat-icon) {
		font-size: 0.85rem;
		opacity: 0.7;
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

</style>
