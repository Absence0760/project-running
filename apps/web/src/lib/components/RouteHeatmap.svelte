<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { goto } from '$app/navigation';
	import maplibregl from 'maplibre-gl';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	import { mapStyleUrlFromEnv as mapStyleUrl } from '$lib/map-style.svelte';
	import { watchMapResize } from '$lib/map_resize';
	import { fetchHeatmapPoints, nearbyPublicRoutes } from '$lib/data';
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

	const HEATMAP_SOURCE = 'heatmap-pts';
	const HEATMAP_LAYER = 'heatmap-layer';
	const ROUTES_SOURCE = 'heatmap-routes';
	const ROUTES_LAYER_CASING = 'heatmap-routes-casing';
	const ROUTES_LAYER = 'heatmap-routes-line';
	/// Minimum zoom at which we overlay individual public routes as
	/// clickable polylines. Below this the heatmap density is the
	/// honest signal — too many routes drawn over a large viewport
	/// is visual noise + pulls way more polylines than necessary.
	const ROUTES_OVERLAY_MIN_ZOOM = 12;

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
		});

		map.on('moveend', () => {
			if (pendingFetch) clearTimeout(pendingFetch);
			pendingFetch = setTimeout(refresh, 350);
			if (pendingRoutesFetch) clearTimeout(pendingRoutesFetch);
			pendingRoutesFetch = setTimeout(refreshRoutes, 350);
		});

		// Kick off the first fetch immediately. The HTTP RPC doesn't
		// care whether MapLibre has loaded a style yet — and decoupling
		// the legend's status from the basemap means the user gets an
		// "Updated …" stamp even on a keyless deploy.
		refresh();
	});

	onDestroy(() => {
		stopResizeWatch?.();
		map?.remove();
		map = null;
		if (pendingFetch) clearTimeout(pendingFetch);
		if (pendingRoutesFetch) clearTimeout(pendingRoutesFetch);
		if (searchTimeout) clearTimeout(searchTimeout);
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
					explore; the layer refreshes after each move. Only routes
					flipped public are counted. Zoom in to see individual routes
					— click any line to open it.
				</p>
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
</style>
