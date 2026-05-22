<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { goto } from '$app/navigation';
	import maplibregl from 'maplibre-gl';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	import { mapStyleUrlFromEnv as mapStyleUrl } from '$lib/map-style.svelte';
	import { watchMapResize } from '$lib/map_resize';
	import {
		fetchHeatmapPoints,
		nearbyPublicRoutes,
		fetchClubsInBbox,
		fetchDiscoverableRoutesInBbox,
	} from '$lib/data';
	import { formatDistance } from '$lib/units.svelte';
	import { searchPlaces, type PlaceSearchResult } from '$lib/geocoding';
	import type { Route } from '$lib/types';

	let mapEl: HTMLDivElement;
	let map: maplibregl.Map | null = null;
	let stopResizeWatch: (() => void) | null = null;
	/// The "Where people run" legend defaults to compact (info icon
	/// only) so it doesn't eat real estate. Click to expand. The
	/// May 2026 real-estate pass surfaced that the 18rem-wide
	/// card-style legend was the second-biggest waste of canvas
	/// after the page padding.
	let legendExpanded = $state(false);
	let loading = $state(false);
	let lastUpdated = $state<Date | null>(null);
	let mapLoaded = false;
	let cachedFeatures: GeoJSON.Feature[] = [];
	/// True while the cursor is over the map. The legend fades out so
	/// it doesn't obstruct the area the user is inspecting.
	let pointerOnMap = $state(false);

	// --- Search ---
	// Uses `$lib/geocoding.searchPlaces`, which transparently picks
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
	let pendingRoutesFetch: ReturnType<typeof setTimeout> | null = null;
	let pendingPinsFetch: ReturnType<typeof setTimeout> | null = null;

	const HEATMAP_SOURCE = 'heatmap-pts';
	const HEATMAP_LAYER = 'heatmap-layer';
	const ROUTES_SOURCE = 'heatmap-routes';
	const ROUTES_LAYER_CASING = 'heatmap-routes-casing';
	const ROUTES_LAYER = 'heatmap-routes-line';
	const CLUB_PINS_SOURCE = 'heatmap-clubs';
	const CLUB_PINS_LAYER = 'heatmap-clubs-layer';
	const ROUTE_PINS_SOURCE = 'heatmap-route-pins';
	const ROUTE_PINS_LAYER = 'heatmap-route-pins-layer';
	/// Minimum zoom at which we overlay individual public routes as
	/// clickable polylines. Below this the heatmap density is the
	/// honest signal — too many routes drawn over a large viewport
	/// is visual noise + pulls way more polylines than necessary.
	const ROUTES_OVERLAY_MIN_ZOOM = 12;

	// Discoverable-pin layer toggles. Both default-on; the user can
	// hide either via the legend popover.
	let showClubPins = $state(true);
	let showRoutePins = $state(true);
	let showHeatmapLayer = $state(true);
	let clubPinsCount = $state(0);
	let routePinsCount = $state(0);

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
			// Clickable public-route overlay. Only visible at zoom >=
			// ROUTES_OVERLAY_MIN_ZOOM so the heatmap stays the dominant
			// signal at city + region scales. Subtle outline + cyan line
			// — matches the trace-casing colour scheme on /runs/[id] so
			// users recognise it as a route.
			map.addSource(ROUTES_SOURCE, {
				type: 'geojson',
				data: { type: 'FeatureCollection', features: [] },
				promoteId: 'route_id',
			});
			map.addLayer({
				id: ROUTES_LAYER_CASING,
				type: 'line',
				source: ROUTES_SOURCE,
				minzoom: ROUTES_OVERLAY_MIN_ZOOM,
				paint: { 'line-color': '#1e293b', 'line-width': 6, 'line-opacity': 0.4 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
			map.addLayer({
				id: ROUTES_LAYER,
				type: 'line',
				source: ROUTES_SOURCE,
				minzoom: ROUTES_OVERLAY_MIN_ZOOM,
				paint: { 'line-color': '#22d3ee', 'line-width': 3 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
			map.on('click', ROUTES_LAYER, (e) => {
				const f = e.features?.[0];
				const id = f?.properties?.route_id as string | undefined;
				if (id) void goto(`/routes/${id}`);
			});
			// Pointer cursor over a route so the affordance is discoverable.
			map.on('mouseenter', ROUTES_LAYER, () => {
				if (map) map.getCanvas().style.cursor = 'pointer';
			});
			map.on('mouseleave', ROUTES_LAYER, () => {
				if (map) map.getCanvas().style.cursor = '';
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
				const href = slug ? `/clubs/${slug}` : id ? `/clubs/${id}` : '#';
				const coords = (f.geometry as GeoJSON.Point).coordinates as [number, number];
				openPinPopup(coords, {
					title: name,
					subtitle: `${memberCount} member${memberCount === 1 ? '' : 's'}`,
					href,
					actionLabel: 'View club',
					accentClass: 'pin-popup-club',
				});
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

			map.addSource(ROUTE_PINS_SOURCE, {
				type: 'geojson',
				data: { type: 'FeatureCollection', features: [] },
			});
			map.addLayer({
				id: ROUTE_PINS_LAYER,
				type: 'circle',
				source: ROUTE_PINS_SOURCE,
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
				const name = (f.properties?.name as string) ?? 'Route';
				const featured = !!f.properties?.featured;
				const distance = (f.properties?.distance_m as number) ?? 0;
				const surface = (f.properties?.surface as string) ?? '';
				const runCount = (f.properties?.run_count as number) ?? 0;
				const subtitleBits = [
					formatDistance(distance),
					surface,
					runCount > 0
						? `run ${runCount} time${runCount === 1 ? '' : 's'}`
						: '',
				].filter(Boolean);
				const coords = (f.geometry as GeoJSON.Point).coordinates as [number, number];
				openPinPopup(coords, {
					title: name,
					subtitle: subtitleBits.join(' · '),
					href: `/routes/${id}`,
					actionLabel: 'View route',
					accentClass: featured
						? 'pin-popup-route pin-popup-featured'
						: 'pin-popup-route',
					featured,
				});
			});
			map.on('mouseenter', ROUTE_PINS_LAYER, (e) => {
				if (!map) return;
				map.getCanvas().style.cursor = 'pointer';
				const f = e.features?.[0];
				if (!f) return;
				const name = (f.properties?.name as string) ?? '';
				const coords = (f.geometry as GeoJSON.Point).coordinates as [number, number];
				openHoverTip(coords, name);
			});
			map.on('mouseleave', ROUTE_PINS_LAYER, () => {
				if (map) map.getCanvas().style.cursor = '';
				closeHoverTip();
			});

			// Standard MapLibre heatmap paint — interpolated by intensity
			// (the density of sampled points). Higher zooms taper the
			// blur radius so individual routes stay legible when the
			// user drills in.
			map.addLayer({
				id: HEATMAP_LAYER,
				type: 'heatmap',
				source: HEATMAP_SOURCE,
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
					'heatmap-opacity': 0.85,
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
			refreshRoutes();
			refreshPins();
		});

		map.on('moveend', () => {
			if (pendingFetch) clearTimeout(pendingFetch);
			pendingFetch = setTimeout(refresh, 350);
			if (pendingRoutesFetch) clearTimeout(pendingRoutesFetch);
			pendingRoutesFetch = setTimeout(refreshRoutes, 350);
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
		stopResizeWatch?.();
		currentPopup?.remove();
		currentPopup = null;
		hoverPopup?.remove();
		hoverPopup = null;
		map?.remove();
		map = null;
		if (pendingFetch) clearTimeout(pendingFetch);
		if (pendingRoutesFetch) clearTimeout(pendingRoutesFetch);
		if (pendingPinsFetch) clearTimeout(pendingPinsFetch);
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

	interface PinPopupOpts {
		title: string;
		subtitle: string;
		href: string;
		actionLabel: string;
		accentClass: string;
		featured?: boolean;
	}

	function escapeHtml(s: string): string {
		return s
			.replace(/&/g, '&amp;')
			.replace(/</g, '&lt;')
			.replace(/>/g, '&gt;')
			.replace(/"/g, '&quot;')
			.replace(/'/g, '&#39;');
	}

	function openPinPopup(coords: [number, number], opts: PinPopupOpts) {
		if (!map) return;
		closeHoverTip();
		currentPopup?.remove();
		const star = opts.featured
			? '<span class="pin-popup-star" title="Featured">★</span>'
			: '';
		const html = `
			<div class="pin-popup ${opts.accentClass}">
				<div class="pin-popup-head">
					${star}
					<span class="pin-popup-title">${escapeHtml(opts.title)}</span>
				</div>
				<div class="pin-popup-subtitle">${escapeHtml(opts.subtitle)}</div>
				<a class="pin-popup-action" href="${escapeHtml(opts.href)}"
					data-sveltekit-preload-data="hover">
					${escapeHtml(opts.actionLabel)} &rarr;
				</a>
			</div>
		`;
		currentPopup = new maplibregl.Popup({
			closeButton: true,
			closeOnClick: false,
			offset: 14,
			maxWidth: '220px',
			className: 'heatmap-pin-popup',
		})
			.setLngLat(coords)
			.setHTML(html)
			.addTo(map);
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
		const b = map.getBounds();
		const bbox = {
			minLng: b.getWest(),
			minLat: b.getSouth(),
			maxLng: b.getEast(),
			maxLat: b.getNorth(),
		};
		const [clubs, routes] = await Promise.all([
			fetchClubsInBbox(bbox),
			fetchDiscoverableRoutesInBbox(bbox),
		]);
		clubPinsCount = clubs.length;
		routePinsCount = routes.length;
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
	}

	// Layer-visibility toggles. MapLibre's `setLayoutProperty(...,
	// 'visibility', 'visible'|'none')` is the cheap way to flip a
	// layer — no source-data mutation needed. Wired to the legend
	// checkboxes below via a reactive $effect.
	$effect(() => {
		if (!map || !mapLoaded) return;
		map.setLayoutProperty(
			CLUB_PINS_LAYER,
			'visibility',
			showClubPins ? 'visible' : 'none',
		);
	});
	$effect(() => {
		if (!map || !mapLoaded) return;
		map.setLayoutProperty(
			ROUTE_PINS_LAYER,
			'visibility',
			showRoutePins ? 'visible' : 'none',
		);
	});
	$effect(() => {
		if (!map || !mapLoaded) return;
		map.setLayoutProperty(
			HEATMAP_LAYER,
			'visibility',
			showHeatmapLayer ? 'visible' : 'none',
		);
	});

	/// Fetch + render clickable public-route polylines for the current
	/// viewport. Only fires when the map is zoomed in enough that the
	/// overlay would be readable (and the polyline count manageable).
	/// Uses the existing nearbyPublicRoutes RPC which already returns
	/// Route shape with waypoints — no new migration required.
	async function refreshRoutes() {
		if (!map || !mapLoaded) return;
		const src = map.getSource(ROUTES_SOURCE) as
			| maplibregl.GeoJSONSource
			| undefined;
		if (!src) return;
		if (map.getZoom() < ROUTES_OVERLAY_MIN_ZOOM) {
			// Above the threshold the overlay is hidden anyway, but
			// clear stale data so re-zoom-in shows fresh routes.
			src.setData({ type: 'FeatureCollection', features: [] });
			return;
		}
		const c = map.getCenter();
		const b = map.getBounds();
		// Radius = half-diagonal of the viewport, capped at 25 km so a
		// fully zoomed-out city view doesn't ask for everything.
		const halfDiag = haversineM(
			b.getNorth(),
			b.getWest(),
			c.lat,
			c.lng,
		);
		const radiusM = Math.min(Math.max(halfDiag, 1000), 25_000);
		try {
			const routes = await nearbyPublicRoutes({
				lat: c.lat,
				lng: c.lng,
				radiusM,
				limit: 50,
			});
			const features: GeoJSON.Feature[] = routes
				.filter((r: Route) => r.waypoints && r.waypoints.length >= 2)
				.map((r: Route) => ({
					type: 'Feature',
					properties: { route_id: r.id, name: r.name },
					geometry: {
						type: 'LineString',
						coordinates: r.waypoints.map((w) => [w.lng, w.lat]),
					},
				}));
			src.setData({ type: 'FeatureCollection', features });
		} catch (e) {
			console.warn('heatmap routes refresh failed', e);
		}
	}

	function haversineM(
		lat1: number,
		lng1: number,
		lat2: number,
		lng2: number,
	): number {
		const R = 6371000;
		const toRad = (d: number) => (d * Math.PI) / 180;
		const dLat = toRad(lat2 - lat1);
		const dLng = toRad(lng2 - lng1);
		const a =
			Math.sin(dLat / 2) ** 2 +
			Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
		return 2 * R * Math.asin(Math.sqrt(a));
	}

	async function refresh() {
		if (!map) return;
		const b = map.getBounds();
		loading = true;
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
			lastUpdated = new Date();
		} catch (e) {
			console.error('heatmap refresh failed', e);
		} finally {
			loading = false;
		}
	}
</script>

<div
	class="heatmap-wrap"
	role="region"
	aria-label="Public route heatmap"
	onpointerenter={() => (pointerOnMap = true)}
	onpointerleave={() => (pointerOnMap = false)}
>
	<div bind:this={mapEl} class="map"></div>

	<div class="search-box" data-testid="heatmap-search">
		<input
			bind:this={searchInput}
			bind:value={searchQuery}
			oninput={onSearchInput}
			onfocusout={() => setTimeout(() => (showResults = false), 200)}
			onfocusin={() => {
				if (searchResults.length > 0) showResults = true;
			}}
			type="text"
			placeholder="Search for a place…"
			aria-label="Search for a place to centre the heatmap on"
		/>
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

	<aside
		class="legend"
		class:expanded={legendExpanded}
		class:dimmed={pointerOnMap && !legendExpanded}
		data-testid="heatmap-legend"
	>
		<button
			type="button"
			class="legend-toggle"
			onclick={() => (legendExpanded = !legendExpanded)}
			aria-expanded={legendExpanded}
			aria-label={legendExpanded ? 'Collapse legend' : 'Show legend'}
		>
			<span class="material-symbols">{legendExpanded ? 'close' : 'info'}</span>
			{#if loading && !legendExpanded}
				<span class="legend-pulse" aria-hidden="true"></span>
			{/if}
		</button>
		{#if legendExpanded}
			<div class="legend-body">
				<strong>Where people run</strong>
				<p>
					Warmer cells = more public routes pass through here. Pan to
					explore; the layer refreshes after each move. Zoom in to see
					individual routes — click any line to open it.
				</p>

				<!-- Layer toggles. Each independently flips the matching
					 MapLibre layer's `visibility` via a $effect above.
					 The count chip after each label surfaces "how much
					 stuff is in your current viewport" — useful signal
					 when panning a region with no clubs or no popular
					 routes. -->
				<div class="legend-toggles" role="group" aria-label="Map layers">
					<label class="legend-row">
						<input type="checkbox" bind:checked={showHeatmapLayer} />
						<span class="legend-swatch legend-swatch-heat" aria-hidden="true"></span>
						<span>Heatmap density</span>
					</label>
					<label class="legend-row">
						<input type="checkbox" bind:checked={showRoutePins} />
						<span class="legend-swatch legend-swatch-route" aria-hidden="true"></span>
						<span>Popular &amp; featured routes</span>
						<span class="legend-count">{routePinsCount}</span>
					</label>
					<label class="legend-row">
						<input type="checkbox" bind:checked={showClubPins} />
						<span class="legend-swatch legend-swatch-club" aria-hidden="true"></span>
						<span>Clubs</span>
						<span class="legend-count">{clubPinsCount}</span>
					</label>
				</div>

				{#if loading}
					<p class="muted"><em>Updating…</em></p>
				{:else if lastUpdated}
					<p class="muted">
						Updated {lastUpdated.toLocaleTimeString([], {
							hour: '2-digit',
							minute: '2-digit',
						})}
					</p>
				{/if}
			</div>
		{/if}
	</aside>
</div>

<style>
	.heatmap-wrap {
		position: relative;
		/* Fill the available viewport below the page chrome. The
		 * parent /routes page now drops its bottom padding on the
		 * heatmap tab (see /routes/+page.svelte) so this 100% goes
		 * edge-to-edge instead of leaving a strip of dead canvas. */
		height: 100%;
		min-height: 24rem;
		border-radius: var(--radius-lg);
		overflow: hidden;
	}
	.map {
		position: absolute;
		inset: 0;
	}
	.search-box {
		position: absolute;
		top: var(--space-md);
		/* Top-center: legend is top-left, MapLibre controls are
		 * top-right. The search box gets the empty middle slot so
		 * it doesn't fight either. */
		left: 50%;
		transform: translateX(-50%);
		width: min(22rem, calc(100% - 16rem));
		z-index: 2;
	}
	.search-box input {
		width: 100%;
		padding: 0.5rem 0.75rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
		font-size: 0.9rem;
		color: var(--color-text);
	}
	.search-box input:focus {
		outline: 2px solid var(--color-accent);
		outline-offset: 1px;
	}
	.search-results {
		margin: 0;
		padding: 0;
		list-style: none;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
		margin-top: 0.25rem;
		max-height: 16rem;
		overflow-y: auto;
	}
	.search-results li button {
		width: 100%;
		text-align: left;
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
	/*
	 * Legend is a single info-icon button when collapsed — same
	 * footprint as MapLibre's controls. Click expands to a 16rem
	 * description card. The collapsed state keeps real estate
	 * available for the heatmap canvas; users opt in when they
	 * want context.
	 */
	.legend {
		position: absolute;
		top: var(--space-md);
		left: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		transition: opacity 180ms ease;
		/* Pointer events: the button needs them; in dimmed mode the
		 * outer .legend is set to `none` so map clicks pass through.
		 * The button re-enables them on the button itself via the
		 * default browser style — when dimmed the button is
		 * non-interactive too, restored on hover (see :hover below). */
	}
	.legend.dimmed {
		opacity: 0.35;
		pointer-events: none;
	}
	.legend.dimmed:hover {
		opacity: 1;
		pointer-events: auto;
	}
	.legend-toggle {
		position: relative;
		display: flex;
		align-items: center;
		justify-content: center;
		width: 36px;
		height: 36px;
		padding: 0;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
		color: var(--color-text-secondary);
		cursor: pointer;
		transition: color var(--transition-fast),
			border-color var(--transition-fast);
	}
	.legend-toggle:hover {
		color: var(--color-text);
		border-color: var(--color-primary);
	}
	.legend-toggle .material-symbols {
		font-size: 1.25rem;
	}
	/* Pulsing dot while the heatmap is fetching new points — same
	 * "I'm working" signal the legend used to communicate in its
	 * full state, now bound to the collapsed icon. */
	.legend-pulse {
		position: absolute;
		top: 4px;
		right: 4px;
		width: 8px;
		height: 8px;
		background: var(--color-primary);
		border-radius: 50%;
		animation: pulse 1.4s ease-in-out infinite;
	}
	@keyframes pulse {
		0%, 100% { opacity: 0.4; transform: scale(0.85); }
		50% { opacity: 1; transform: scale(1.1); }
	}
	.legend-body {
		max-width: 16rem;
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
		font-size: 0.85rem;
		color: var(--color-text);
	}
	.legend-body strong {
		display: block;
		margin-bottom: 0.4rem;
	}
	.legend-body p {
		margin: 0 0 0.3rem 0;
		color: var(--color-text-secondary);
	}
	.muted {
		color: var(--color-text-tertiary) !important;
	}

	/*
	 * Layer toggle rows. Each is a label wrapping a checkbox + a
	 * coloured swatch + a name + an optional count chip. The swatch
	 * mirrors the actual layer colour (heatmap warm-red, route
	 * orange, club teal) so the legend doubles as a colour key.
	 */
	.legend-toggles {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
		margin: var(--space-sm) 0;
		padding: var(--space-sm) 0;
		border-top: 1px solid var(--color-border);
		border-bottom: 1px solid var(--color-border);
	}
	.legend-row {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		font-size: 0.8rem;
		color: var(--color-text);
		cursor: pointer;
		user-select: none;
	}
	.legend-row input[type='checkbox'] {
		margin: 0;
		accent-color: var(--color-primary);
	}
	.legend-swatch {
		display: inline-block;
		width: 14px;
		height: 14px;
		border-radius: 50%;
		flex-shrink: 0;
	}
	.legend-swatch-heat {
		background: radial-gradient(
			circle,
			rgba(178, 24, 43, 0.9) 0%,
			rgba(178, 24, 43, 0.3) 100%
		);
	}
	.legend-swatch-route {
		background: #f2a07b;
		border: 2px solid #facc15;
	}
	.legend-swatch-club {
		background: #7fb3c2;
		border: 2px solid #0f172a;
	}
	.legend-count {
		margin-left: auto;
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
		background: var(--color-bg-secondary);
		padding: 0.05rem 0.4rem;
		border-radius: 999px;
		min-width: 1.5rem;
		text-align: center;
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
		max-width: 220px;
	}
	:global(.heatmap-pin-popup .maplibregl-popup-content) {
		background: var(--color-surface);
		color: var(--color-text);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-lg);
		padding: var(--space-sm) var(--space-md) var(--space-md);
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
	:global(.heatmap-pin-popup .pin-popup-head) {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		margin-bottom: 0.25rem;
	}
	:global(.heatmap-pin-popup .pin-popup-title) {
		font-weight: 700;
		font-size: 0.95rem;
		line-height: 1.2;
	}
	:global(.heatmap-pin-popup .pin-popup-star) {
		color: #facc15;
		font-size: 1rem;
		line-height: 1;
	}
	:global(.heatmap-pin-popup .pin-popup-subtitle) {
		color: var(--color-text-secondary);
		font-size: 0.78rem;
		margin-bottom: 0.6rem;
	}
	:global(.heatmap-pin-popup .pin-popup-action) {
		display: inline-block;
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-primary);
		text-decoration: none;
		padding: 0.25rem 0.5rem;
		border: 1px solid var(--color-primary);
		border-radius: var(--radius-sm);
		transition: background var(--transition-fast);
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
