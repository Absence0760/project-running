<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';
	import { fetchFullRoute } from '$lib/routing';
	import { fetchElevations, sampleCoordinates, calculateElevationGain } from '$lib/elevation';
	import type { TrackPoint } from '$lib/types';

	let {
		mode = 'road',
		onupdate = (_data: {
			waypoints: number;
			distance: number;
			elevation: number;
			elevations: number[];
			coordinates: [number, number][];
		}) => {}
	}: {
		mode?: 'road' | 'trail';
		onupdate?: (data: {
			waypoints: number;
			distance: number;
			elevation: number;
			elevations: number[];
			coordinates: [number, number][];
		}) => void;
	} = $props();

	let mapContainer: HTMLDivElement;
	let searchInput: HTMLInputElement = undefined!;
	let map: maplibregl.Map;
	let waypoints: TrackPoint[] = [];
	let routeCoordinates: [number, number][] = [];
	let routeElevations: number[] = [];
	let markers: maplibregl.Marker[] = [];
	let isRouting = false;
	let searchQuery = $state('');
	let searchResults = $state<{ name: string; lng: number; lat: number }[]>([]);
	let showResults = $state(false);
	let searchTimeout: ReturnType<typeof setTimeout>;

	async function handleSearch(query: string) {
		if (query.length < 2) {
			searchResults = [];
			showResults = false;
			return;
		}

		const url = `https://api.maptiler.com/geocoding/${encodeURIComponent(query)}.json?key=${PUBLIC_MAPTILER_KEY}&limit=5`;
		const res = await fetch(url);
		if (!res.ok) return;

		const data = await res.json();
		searchResults = data.features.map((f: { place_name: string; center: [number, number] }) => ({
			name: f.place_name,
			lng: f.center[0],
			lat: f.center[1]
		}));
		showResults = searchResults.length > 0;
	}

	function onSearchInput() {
		clearTimeout(searchTimeout);
		searchTimeout = setTimeout(() => handleSearch(searchQuery), 300);
	}

	function selectSearchResult(result: { name: string; lng: number; lat: number }) {
		map.flyTo({ center: [result.lng, result.lat], zoom: 14 });
		searchQuery = '';
		searchResults = [];
		showResults = false;
		searchInput.blur();
	}

	function createWaypointMarker(lngLat: { lng: number; lat: number }, index: number): maplibregl.Marker {
		const el = document.createElement('div');
		el.className = 'route-waypoint';
		el.dataset.index = String(index);

		// Style based on position
		if (index === 0) {
			el.classList.add('route-waypoint-start');
		}

		const marker = new maplibregl.Marker({ element: el, draggable: true })
			.setLngLat([lngLat.lng, lngLat.lat])
			.addTo(map);

		marker.on('dragend', () => {
			const pos = marker.getLngLat();
			waypoints[index] = { lat: pos.lat, lng: pos.lng };
			recalculateRoute();
		});

		return marker;
	}

	function updateMarkerStyles() {
		markers.forEach((marker, i) => {
			const el = marker.getElement();
			el.className = 'route-waypoint';
			el.dataset.index = String(i);
			if (i === 0) el.classList.add('route-waypoint-start');
			if (i === waypoints.length - 1 && waypoints.length > 1) el.classList.add('route-waypoint-end');
		});
	}

	async function recalculateRoute() {
		if (waypoints.length < 2) {
			routeCoordinates = [];
			routeElevations = [];
			updateRouteLine();
			emitUpdate();
			return;
		}

		isRouting = true;
		const profile = mode === 'trail' ? 'foot' : 'car';

		try {
			const result = await fetchFullRoute(waypoints, profile);
			routeCoordinates = result.coordinates;

			// Fetch elevation for sampled points
			const { sampled } = sampleCoordinates(routeCoordinates, 100);
			const elevations = await fetchElevations(sampled);

			// Interpolate elevations back to full coordinate set if sampled
			if (sampled.length < routeCoordinates.length) {
				routeElevations = interpolateElevations(elevations, sampled.length, routeCoordinates.length);
			} else {
				routeElevations = elevations;
			}

			updateRouteLine();
			emitUpdate();
		} catch (err) {
			console.error('Routing failed:', err);
		} finally {
			isRouting = false;
		}
	}

	function interpolateElevations(sampled: number[], sampledCount: number, totalCount: number): number[] {
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
		const source = map.getSource('route') as maplibregl.GeoJSONSource | undefined;
		if (!source) return;

		source.setData({
			type: 'Feature',
			properties: {},
			geometry: {
				type: 'LineString',
				coordinates: routeCoordinates
			}
		});
	}

	function emitUpdate() {
		const gain = calculateElevationGain(routeElevations);
		// Calculate total distance from coordinates using haversine
		let distance = 0;
		for (let i = 1; i < routeCoordinates.length; i++) {
			distance += haversine(routeCoordinates[i - 1], routeCoordinates[i]);
		}

		onupdate({
			waypoints: waypoints.length,
			distance,
			elevation: gain,
			elevations: routeElevations,
			coordinates: routeCoordinates
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

	export function addWaypoint(lngLat: { lng: number; lat: number }) {
		const point: TrackPoint = { lat: lngLat.lat, lng: lngLat.lng };
		waypoints.push(point);

		const marker = createWaypointMarker(lngLat, waypoints.length - 1);
		markers.push(marker);
		updateMarkerStyles();

		recalculateRoute();
	}

	export function undoWaypoint() {
		if (waypoints.length === 0) return;

		waypoints.pop();
		const marker = markers.pop();
		marker?.remove();
		updateMarkerStyles();

		recalculateRoute();
	}

	export function clearWaypoints() {
		waypoints = [];
		routeCoordinates = [];
		routeElevations = [];
		markers.forEach((m) => m.remove());
		markers = [];

		updateRouteLine();
		emitUpdate();
	}

	export function getRouteData() {
		return {
			waypoints: [...waypoints],
			coordinates: [...routeCoordinates],
			elevations: [...routeElevations]
		};
	}

	onMount(() => {
		map = new maplibregl.Map({
			container: mapContainer,
			style: `https://api.maptiler.com/maps/streets-v2/style.json?key=${PUBLIC_MAPTILER_KEY}`,
			center: [144.9631, -37.8136],
			zoom: 13
		});

		map.addControl(new maplibregl.NavigationControl(), 'top-right');

		const geolocate = new maplibregl.GeolocateControl({
			positionOptions: { enableHighAccuracy: true },
			trackUserLocation: false
		});
		map.addControl(geolocate, 'top-right');

		// Auto-center on user's location when map loads
		map.on('load', () => {
			geolocate.trigger();
		});

		map.on('load', () => {
			// Add route line source and layer
			map.addSource('route', {
				type: 'geojson',
				data: {
					type: 'Feature',
					properties: {},
					geometry: { type: 'LineString', coordinates: [] }
				}
			});

			// Route casing (outline)
			map.addLayer({
				id: 'route-casing',
				type: 'line',
				source: 'route',
				paint: {
					'line-color': '#1d4ed8',
					'line-width': 8,
					'line-opacity': 0.3
				},
				layout: {
					'line-join': 'round',
					'line-cap': 'round'
				}
			});

			// Route line
			map.addLayer({
				id: 'route-line',
				type: 'line',
				source: 'route',
				paint: {
					'line-color': '#3b82f6',
					'line-width': 4
				},
				layout: {
					'line-join': 'round',
					'line-cap': 'round'
				}
			});
		});

		// Click to place waypoints
		map.on('click', (e: maplibregl.MapMouseEvent) => {
			if (isRouting) return;
			addWaypoint(e.lngLat);
		});

		// Change cursor on hover over map
		map.getCanvas().style.cursor = 'crosshair';
	});

	onDestroy(() => {
		markers.forEach((m) => m.remove());
		map?.remove();
	});

	// Re-route when mode changes
	$effect(() => {
		// Access mode to register the dependency
		const _mode = mode;
		if (waypoints.length >= 2) {
			recalculateRoute();
		}
	});
</script>

<div class="map-wrapper">
	<div class="search-box">
		<input
			bind:this={searchInput}
			bind:value={searchQuery}
			oninput={onSearchInput}
			onfocusout={() => setTimeout(() => (showResults = false), 200)}
			onfocusin={() => { if (searchResults.length > 0) showResults = true; }}
			type="text"
			placeholder="Search for a place..."
		/>
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
	<div bind:this={mapContainer} class="map-container"></div>
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

	.search-box {
		position: absolute;
		top: 12px;
		left: 12px;
		z-index: 10;
		width: 320px;
	}

	.search-box input {
		width: 100%;
		padding: 10px 14px;
		border: none;
		border-radius: 8px;
		font-size: 0.9rem;
		background: white;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
	}

	.search-box input:focus {
		outline: none;
		box-shadow: 0 2px 12px rgba(0, 0, 0, 0.25);
	}

	.search-results {
		list-style: none;
		margin: 4px 0 0;
		padding: 0;
		background: white;
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
		text-align: left;
		font-size: 0.85rem;
		cursor: pointer;
		color: #333;
	}

	.search-results li button:hover {
		background: #f3f4f6;
	}

	.search-results li + li {
		border-top: 1px solid #e5e7eb;
	}

	:global(.route-waypoint) {
		width: 16px;
		height: 16px;
		border-radius: 50%;
		background: #3b82f6;
		border: 2.5px solid white;
		box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
		cursor: grab;
	}

	:global(.route-waypoint:active) {
		cursor: grabbing;
	}

	:global(.route-waypoint-start) {
		background: #22c55e;
		width: 18px;
		height: 18px;
	}

	:global(.route-waypoint-end) {
		background: #ef4444;
		width: 18px;
		height: 18px;
	}
</style>
