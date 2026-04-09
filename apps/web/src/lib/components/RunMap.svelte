<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';
	import type { TrackPoint } from '$lib/types';

	let { track = [], animatable = false }: { track: TrackPoint[]; animatable?: boolean } = $props();

	let mapContainer: HTMLDivElement;
	let map: maplibregl.Map;
	let animating = $state(false);
	let animationFrame: number;
	let animationMarker: maplibregl.Marker;

	export function startAnimation() {
		if (!map || animating) return;
		const coords: [number, number][] = track.map((p) => [p.lng, p.lat]);
		if (coords.length < 2) return;

		animating = true;
		let idx = 0;

		// Create animated dot
		const el = document.createElement('div');
		el.className = 'animated-dot';
		animationMarker = new maplibregl.Marker({ element: el })
			.setLngLat(coords[0])
			.addTo(map);

		// Animated trace source
		const animSource = map.getSource('animated-trace') as maplibregl.GeoJSONSource | undefined;
		if (animSource) {
			animSource.setData({
				type: 'Feature', properties: {},
				geometry: { type: 'LineString', coordinates: [coords[0]] }
			});
		}

		function step() {
			if (idx >= coords.length) {
				stopAnimation();
				return;
			}
			idx++;
			animationMarker.setLngLat(coords[idx - 1]);

			const animSrc = map.getSource('animated-trace') as maplibregl.GeoJSONSource | undefined;
			animSrc?.setData({
				type: 'Feature', properties: {},
				geometry: { type: 'LineString', coordinates: coords.slice(0, idx) }
			});

			animationFrame = requestAnimationFrame(step);
		}

		animationFrame = requestAnimationFrame(step);
	}

	export function stopAnimation() {
		animating = false;
		cancelAnimationFrame(animationFrame);
		animationMarker?.remove();
	}

	onMount(() => {
		const coords: [number, number][] = track.map((p) => [p.lng, p.lat]);

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

			if (bounds) {
				map.fitBounds(bounds, { padding: 50 });
			}

			map.addSource('trace', {
				type: 'geojson',
				data: {
					type: 'Feature', properties: {},
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

			// Animated trace layer (hidden until animation starts)
			if (animatable) {
				map.addSource('animated-trace', {
					type: 'geojson',
					data: { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } }
				});

				map.addLayer({
					id: 'animated-trace-line',
					type: 'line',
					source: 'animated-trace',
					paint: { 'line-color': '#f59e0b', 'line-width': 4 },
					layout: { 'line-join': 'round', 'line-cap': 'round' }
				});
			}

			new maplibregl.Marker({ color: '#22c55e' })
				.setLngLat(coords[0])
				.addTo(map);

			new maplibregl.Marker({ color: '#ef4444' })
				.setLngLat(coords[coords.length - 1])
				.addTo(map);
		});
	});

	onDestroy(() => {
		cancelAnimationFrame(animationFrame);
		map?.remove();
	});
</script>

<div class="run-map-wrapper">
	<div bind:this={mapContainer} class="run-map"></div>
	{#if animatable}
		<button class="replay-btn" onclick={() => animating ? stopAnimation() : startAnimation()}>
			<span class="material-symbols">{animating ? 'stop' : 'play_arrow'}</span>
			{animating ? 'Stop' : 'Replay'}
		</button>
	{/if}
</div>

<style>
	.run-map-wrapper {
		width: 100%;
		height: 100%;
		position: relative;
	}

	.run-map {
		width: 100%;
		height: 100%;
	}

	.replay-btn {
		position: absolute;
		bottom: 12px;
		left: 12px;
		z-index: 10;
		display: flex;
		align-items: center;
		gap: 4px;
		padding: 8px 14px;
		background: white;
		border: none;
		border-radius: 8px;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
		font-size: 0.8rem;
		font-weight: 600;
		cursor: pointer;
		color: #333;
	}

	.replay-btn:hover {
		background: #f3f4f6;
		color: #3b82f6;
	}

	.replay-btn .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}

	:global(.animated-dot) {
		width: 12px;
		height: 12px;
		border-radius: 50%;
		background: #f59e0b;
		border: 2px solid white;
		box-shadow: 0 0 0 3px rgba(245, 158, 11, 0.3), 0 1px 4px rgba(0, 0, 0, 0.3);
	}
</style>
