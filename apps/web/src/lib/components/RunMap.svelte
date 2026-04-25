<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';
	import { getUnit } from '$lib/units.svelte';
	import type { TrackPoint } from '$lib/types';

	let { track = [], animatable = false }: { track: TrackPoint[]; animatable?: boolean } = $props();

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;

	const METRES_PER_MILE = 1609.344;

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

	/// Walk the polyline and emit a GeoJSON FeatureCollection of point
	/// markers — one at every kilometre (or mile, depending on the user
	/// preference). Each feature's `label` property carries the digit
	/// rendered in the marker pin (1, 2, 3, …). Markers near the start
	/// and end are skipped since the green / red caps cover those.
	function computeDistanceMarkers(coords: [number, number][]): GeoJSON.FeatureCollection<GeoJSON.Point, { label: string }> {
		const features: GeoJSON.Feature<GeoJSON.Point, { label: string }>[] = [];
		if (coords.length < 2) return { type: 'FeatureCollection', features };
		const unit = getUnit();
		const stepM = unit === 'mi' ? METRES_PER_MILE : 1000;

		let cumulative = 0;
		let nextMarker = stepM;
		for (let i = 1; i < coords.length; i++) {
			const segmentM = haversine(coords[i - 1], coords[i]);
			while (cumulative + segmentM >= nextMarker && segmentM > 0) {
				const t = (nextMarker - cumulative) / segmentM;
				const lng = coords[i - 1][0] + (coords[i][0] - coords[i - 1][0]) * t;
				const lat = coords[i - 1][1] + (coords[i][1] - coords[i - 1][1]) * t;
				const idx = Math.round(nextMarker / stepM);
				features.push({
					type: 'Feature',
					geometry: { type: 'Point', coordinates: [lng, lat] },
					properties: { label: String(idx) },
				});
				nextMarker += stepM;
			}
			cumulative += segmentM;
		}
		return { type: 'FeatureCollection', features };
	}

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
			style: `https://api.maptiler.com/maps/${prefersDark ? 'streets-v2-dark' : 'streets-v2'}/style.json?key=${PUBLIC_MAPTILER_KEY}`,
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
				paint: { 'line-color': prefersDark ? '#818CF8' : '#4F46E5', 'line-width': 3.5 },
				layout: { 'line-join': 'round', 'line-cap': 'round' }
			});

			// Direction arrows along the line. Larger + more frequent than
			// the previous spacing so overlapping out-and-backs are easy
			// to disambiguate; the white halo (`text-halo-*`) keeps them
			// readable when the polyline doubles back on itself.
			map.addLayer({
				id: 'trace-arrows',
				type: 'symbol',
				source: 'trace',
				layout: {
					'symbol-placement': 'line',
					'symbol-spacing': 60,
					'text-field': '▶',
					'text-size': 14,
					'text-rotation-alignment': 'map',
					'text-keep-upright': false,
					'text-allow-overlap': true,
				},
				paint: {
					'text-color': prefersDark ? '#FFFFFF' : '#1d4ed8',
					'text-halo-color': prefersDark ? '#1d4ed8' : '#FFFFFF',
					'text-halo-width': 1.5,
				},
			});

			// Distance markers at every 1 km / 1 mi (matches user pref).
			// Drops a numbered pin where the cumulative haversine distance
			// crosses each unit boundary; lets the user eyeball pace and
			// orient when the route is long enough to cover ground.
			const markers = computeDistanceMarkers(coords);
			if (markers.features.length > 0) {
				map.addSource('distance-markers', {
					type: 'geojson',
					data: markers,
				});
				map.addLayer({
					id: 'distance-marker-bg',
					type: 'circle',
					source: 'distance-markers',
					paint: {
						'circle-radius': 11,
						'circle-color': prefersDark ? '#1E293B' : '#FFFFFF',
						'circle-stroke-color': prefersDark ? '#818CF8' : '#4F46E5',
						'circle-stroke-width': 2,
					},
				});
				map.addLayer({
					id: 'distance-marker-text',
					type: 'symbol',
					source: 'distance-markers',
					layout: {
						'text-field': ['get', 'label'],
						'text-size': 11,
						'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
						'text-allow-overlap': true,
					},
					paint: {
						'text-color': prefersDark ? '#F1F5F9' : '#1E293B',
					},
				});
			}

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
		background: var(--color-surface);
		border: none;
		border-radius: 8px;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
		font-size: 0.8rem;
		font-weight: 600;
		cursor: pointer;
		color: var(--color-text);
	}

	.replay-btn:hover {
		background: var(--color-bg-tertiary);
		color: var(--color-primary);
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
