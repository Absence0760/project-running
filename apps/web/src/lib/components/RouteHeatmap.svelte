<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { goto } from '$app/navigation';
	import maplibregl from 'maplibre-gl';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';
	import { mapStyleUrlFromEnv as mapStyleUrl } from '$lib/map-style.svelte';
	import { fetchHeatmapPoints, nearbyPublicRoutes } from '$lib/data';
	import type { Route } from '$lib/types';

	let mapEl: HTMLDivElement;
	let map: maplibregl.Map | null = null;
	let loading = $state(false);
	let lastUpdated = $state<Date | null>(null);
	let mapLoaded = false;
	let cachedFeatures: GeoJSON.Feature[] = [];
	/// True while the cursor is over the map. The legend fades out so
	/// it doesn't obstruct the area the user is inspecting.
	let pointerOnMap = $state(false);

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
			// Centre on London by default — the user can pan anywhere
			// from there. A more clever default would geo-locate but
			// browsers prompt for that and we'd rather not on an
			// already-busy first paint.
			center: [-0.1276, 51.5074],
			zoom: 11,
		});

		map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');

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
		map?.remove();
		map = null;
		if (pendingFetch) clearTimeout(pendingFetch);
		if (pendingRoutesFetch) clearTimeout(pendingRoutesFetch);
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
	<aside class="legend" class:dimmed={pointerOnMap} data-testid="heatmap-legend">
		<strong>Where people run</strong>
		<p>
			Warmer cells = more public routes pass through here. Pan to explore;
			the layer refreshes after each move. Only routes flipped public are
			counted. Zoom in to see individual routes — click any line to open it.
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
	.legend {
		position: absolute;
		top: var(--space-md);
		left: var(--space-md);
		max-width: 18rem;
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
		font-size: 0.85rem;
		color: var(--color-text);
		transition: opacity 180ms ease;
	}
	/* Fade out (and disable pointer events) when the cursor is over
	 * the map so the legend doesn't obstruct what the user is trying
	 * to inspect. They can still glance at the warm/cool colours
	 * underneath. Reappears the moment they leave the map. */
	.legend.dimmed {
		opacity: 0.15;
		pointer-events: none;
	}
	.legend.dimmed:hover {
		/* Allow the user to bring it back by hovering directly on it
		 * (i.e. the legend itself, not just the rest of the map). */
		opacity: 1;
		pointer-events: auto;
	}
	.legend strong {
		display: block;
		margin-bottom: 0.4rem;
	}
	.legend p {
		margin: 0 0 0.3rem 0;
		color: var(--color-text-secondary);
	}
	.muted {
		color: var(--color-text-tertiary) !important;
	}
</style>
