<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';
	import { mapStyleUrl } from '$lib/map-style.svelte';
	import { fetchHeatmapPoints } from '$lib/data';

	let mapEl: HTMLDivElement;
	let map: maplibregl.Map | null = null;
	let loading = $state(false);
	let lastUpdated = $state<Date | null>(null);

	// Debounce key for moveend → fetch. We don't want to fire a new
	// PostGIS query on every pixel of a drag.
	let pendingFetch: ReturnType<typeof setTimeout> | null = null;

	const HEATMAP_SOURCE = 'heatmap-pts';
	const HEATMAP_LAYER = 'heatmap-layer';

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
			map.addSource(HEATMAP_SOURCE, {
				type: 'geojson',
				data: { type: 'FeatureCollection', features: [] },
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
			refresh();
		});

		map.on('moveend', () => {
			if (pendingFetch) clearTimeout(pendingFetch);
			pendingFetch = setTimeout(refresh, 350);
		});
	});

	onDestroy(() => {
		map?.remove();
		map = null;
		if (pendingFetch) clearTimeout(pendingFetch);
	});

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
			const src = map.getSource(HEATMAP_SOURCE) as maplibregl.GeoJSONSource | undefined;
			src?.setData({
				type: 'FeatureCollection',
				features: pts.map((p) => ({
					type: 'Feature',
					geometry: { type: 'Point', coordinates: [p.lng, p.lat] },
					properties: {},
				})),
			});
			lastUpdated = new Date();
		} catch (e) {
			console.error('heatmap refresh failed', e);
		} finally {
			loading = false;
		}
	}
</script>

<div class="heatmap-wrap">
	<div bind:this={mapEl} class="map"></div>
	<aside class="legend">
		<strong>Where people run</strong>
		<p>
			Warmer cells = more public routes pass through here. Pan to explore;
			the layer refreshes after each move. Only routes flipped public are
			counted.
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
		height: 70vh;
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
