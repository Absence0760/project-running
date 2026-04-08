<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';
	import type { TrackPoint } from '$lib/types';

	let { track = [] }: { track: TrackPoint[] } = $props();

	let mapContainer: HTMLDivElement;
	let map: maplibregl.Map;

	onMount(() => {
		const coords: [number, number][] = track.map((p) => [p.lng, p.lat]);

		// Calculate bounds
		let bounds: maplibregl.LngLatBoundsLike | undefined;
		if (coords.length > 0) {
			const lngs = coords.map((c) => c[0]);
			const lats = coords.map((c) => c[1]);
			bounds = [
				[Math.min(...lngs), Math.min(...lats)],
				[Math.max(...lngs), Math.max(...lats)]
			];
		}

		map = new maplibregl.Map({
			container: mapContainer,
			style: `https://api.maptiler.com/maps/streets-v2/style.json?key=${PUBLIC_MAPTILER_KEY}`,
			center: coords.length > 0 ? coords[Math.floor(coords.length / 2)] : [0, 20],
			zoom: 13
		});

		map.addControl(new maplibregl.NavigationControl(), 'top-right');

		map.on('load', () => {
			if (coords.length < 2) return;

			// Fit to bounds
			if (bounds) {
				map.fitBounds(bounds, { padding: 50 });
			}

			// GPS trace line
			map.addSource('trace', {
				type: 'geojson',
				data: {
					type: 'Feature',
					properties: {},
					geometry: { type: 'LineString', coordinates: coords }
				}
			});

			map.addLayer({
				id: 'trace-casing',
				type: 'line',
				source: 'trace',
				paint: { 'line-color': '#1d4ed8', 'line-width': 7, 'line-opacity': 0.25 },
				layout: { 'line-join': 'round', 'line-cap': 'round' }
			});

			map.addLayer({
				id: 'trace-line',
				type: 'line',
				source: 'trace',
				paint: { 'line-color': '#3b82f6', 'line-width': 3.5 },
				layout: { 'line-join': 'round', 'line-cap': 'round' }
			});

			// Direction arrows
			map.addLayer({
				id: 'trace-arrows',
				type: 'symbol',
				source: 'trace',
				layout: {
					'symbol-placement': 'line',
					'symbol-spacing': 100,
					'text-field': '▶',
					'text-size': 10,
					'text-rotation-alignment': 'map',
					'text-keep-upright': false
				},
				paint: { 'text-color': '#1d4ed8' }
			});

			// Start marker
			new maplibregl.Marker({ color: '#22c55e' })
				.setLngLat(coords[0])
				.addTo(map);

			// End marker
			new maplibregl.Marker({ color: '#ef4444' })
				.setLngLat(coords[coords.length - 1])
				.addTo(map);
		});
	});

	onDestroy(() => {
		map?.remove();
	});
</script>

<div bind:this={mapContainer} class="run-map"></div>

<style>
	.run-map {
		width: 100%;
		height: 100%;
	}
</style>
