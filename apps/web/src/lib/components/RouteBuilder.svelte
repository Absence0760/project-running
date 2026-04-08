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
	let nearStart = false;
	let searchQuery = $state('');
	let searchResults = $state<{ name: string; lng: number; lat: number }[]>([]);
	let showResults = $state(false);
	let searchTimeout: ReturnType<typeof setTimeout>;

	const SNAP_DISTANCE_PX = 25;
	const OVERLAP_THRESHOLD_M = 30;

	// --- Search ---

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

	// --- Waypoint markers ---

	function createWaypointMarker(lngLat: { lng: number; lat: number }, index: number): maplibregl.Marker {
		const el = document.createElement('div');
		el.className = 'route-waypoint';
		el.dataset.index = String(index);

		if (index === 0) {
			el.classList.add('route-waypoint-start');
		}

		// Number label
		const label = document.createElement('span');
		label.className = 'route-waypoint-label';
		label.textContent = String(index + 1);
		el.appendChild(label);

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

			// Update label
			let label = el.querySelector('.route-waypoint-label') as HTMLSpanElement;
			if (!label) {
				label = document.createElement('span');
				label.className = 'route-waypoint-label';
				el.appendChild(label);
			}
			label.textContent = String(i + 1);
		});
	}

	// --- Routing ---

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

			const { sampled } = sampleCoordinates(routeCoordinates, 100);
			const elevations = await fetchElevations(sampled);

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

	// --- Overlap detection ---

	/**
	 * Split route coordinates into primary and overlap segments.
	 * A coordinate is "overlapping" if it's within OVERLAP_THRESHOLD_M
	 * of any earlier part of the route.
	 */
	function splitOverlaps(coords: [number, number][]): {
		primary: [number, number][];
		overlap: [number, number][];
	} {
		if (coords.length < 10) return { primary: coords, overlap: [] };

		const primary: [number, number][] = [];
		const overlap: [number, number][] = [];

		// Build a grid index for fast proximity lookup
		const visited: [number, number][] = [];
		const checkInterval = Math.max(1, Math.floor(coords.length / 500)); // sample for perf

		for (let i = 0; i < coords.length; i++) {
			const pt = coords[i];
			let isOverlap = false;

			// Only check against points well before this one (skip nearby indices)
			if (i > 20) {
				const searchEnd = i - 15;
				for (let j = 0; j < searchEnd; j += checkInterval) {
					if (haversine(pt, visited[j] || coords[j]) < OVERLAP_THRESHOLD_M) {
						isOverlap = true;
						break;
					}
				}
			}

			if (isOverlap) {
				// Ensure continuity: add bridge point from primary
				if (overlap.length === 0 && primary.length > 0) {
					overlap.push(primary[primary.length - 1]);
				}
				overlap.push(pt);
			} else {
				// Bridge back from overlap
				if (overlap.length > 0 && primary.length > 0) {
					primary.push(overlap[overlap.length - 1]);
				}
				primary.push(pt);
			}

			visited.push(pt);
		}

		return { primary, overlap };
	}

	function updateRouteLine() {
		const routeSource = map.getSource('route') as maplibregl.GeoJSONSource | undefined;
		const overlapSource = map.getSource('route-overlap') as maplibregl.GeoJSONSource | undefined;
		if (!routeSource || !overlapSource) return;

		const { primary, overlap } = splitOverlaps(routeCoordinates);

		routeSource.setData({
			type: 'Feature',
			properties: {},
			geometry: { type: 'LineString', coordinates: primary }
		});

		overlapSource.setData({
			type: 'Feature',
			properties: {},
			geometry: { type: 'LineString', coordinates: overlap }
		});
	}

	// --- Preview line (cursor to last waypoint) ---

	function updatePreviewLine(lngLat: { lng: number; lat: number }) {
		const source = map.getSource('preview-line') as maplibregl.GeoJSONSource | undefined;
		if (!source || waypoints.length === 0) return;

		const last = waypoints[waypoints.length - 1];
		source.setData({
			type: 'Feature',
			properties: {},
			geometry: {
				type: 'LineString',
				coordinates: [
					[last.lng, last.lat],
					[lngLat.lng, lngLat.lat]
				]
			}
		});
	}

	function clearPreviewLine() {
		const source = map.getSource('preview-line') as maplibregl.GeoJSONSource | undefined;
		if (!source) return;
		source.setData({
			type: 'Feature',
			properties: {},
			geometry: { type: 'LineString', coordinates: [] }
		});
	}

	// --- Snap to start detection ---

	function checkSnapToStart(e: maplibregl.MapMouseEvent): boolean {
		if (waypoints.length < 3) {
			nearStart = false;
			return false;
		}

		const startPx = map.project([waypoints[0].lng, waypoints[0].lat]);
		const cursorPx = e.point;
		const dist = Math.sqrt(
			(startPx.x - cursorPx.x) ** 2 + (startPx.y - cursorPx.y) ** 2
		);

		nearStart = dist < SNAP_DISTANCE_PX;
		updateStartMarkerPulse();
		return nearStart;
	}

	function updateStartMarkerPulse() {
		if (markers.length === 0) return;
		const el = markers[0].getElement();
		if (nearStart) {
			el.classList.add('route-waypoint-pulse');
		} else {
			el.classList.remove('route-waypoint-pulse');
		}
	}

	// --- Stats ---

	function emitUpdate() {
		const gain = calculateElevationGain(routeElevations);
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

	// --- Public API ---

	export function addWaypoint(lngLat: { lng: number; lat: number }) {
		// Snap to start if near enough (closing the loop)
		if (nearStart && waypoints.length >= 3) {
			lngLat = { lng: waypoints[0].lng, lat: waypoints[0].lat };
		}

		const point: TrackPoint = { lat: lngLat.lat, lng: lngLat.lng };
		waypoints.push(point);

		const marker = createWaypointMarker(lngLat, waypoints.length - 1);
		markers.push(marker);
		updateMarkerStyles();
		nearStart = false;
		updateStartMarkerPulse();

		recalculateRoute();
	}

	export function undoWaypoint() {
		if (waypoints.length === 0) return;

		waypoints.pop();
		const marker = markers.pop();
		marker?.remove();
		updateMarkerStyles();
		clearPreviewLine();

		recalculateRoute();
	}

	export function clearWaypoints() {
		waypoints = [];
		routeCoordinates = [];
		routeElevations = [];
		markers.forEach((m) => m.remove());
		markers = [];
		nearStart = false;
		clearPreviewLine();

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

	// --- Map setup ---

	onMount(() => {
		const defaultCenter: [number, number] = [0, 20];
		const defaultZoom = 2;

		function initMap(center: [number, number], zoom: number) {
			map = new maplibregl.Map({
				container: mapContainer,
				style: `https://api.maptiler.com/maps/streets-v2/style.json?key=${PUBLIC_MAPTILER_KEY}`,
				center,
				zoom
			});
			setupMap();
		}

		navigator.geolocation.getCurrentPosition(
			(pos) => initMap([pos.coords.longitude, pos.coords.latitude], 14),
			() => initMap(defaultCenter, defaultZoom),
			{ timeout: 3000 }
		);
	});

	function goToMyLocation() {
		navigator.geolocation.getCurrentPosition(
			(pos) => map.flyTo({ center: [pos.coords.longitude, pos.coords.latitude], zoom: 14 }),
			() => {},
			{ timeout: 5000 }
		);
	}

	function setupMap() {
		map.addControl(new maplibregl.NavigationControl(), 'top-right');

		const geolocate = new maplibregl.GeolocateControl({
			positionOptions: { enableHighAccuracy: true },
			trackUserLocation: true,
			showUserLocation: true
		});
		map.addControl(geolocate, 'top-right');

		// Show the blue dot once the map loads
		map.on('load', () => {
			geolocate.trigger();
		});

		map.on('load', () => {
			// Primary route line
			map.addSource('route', {
				type: 'geojson',
				data: { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } }
			});

			// Overlap route line (different color for out-and-back/loop overlap)
			map.addSource('route-overlap', {
				type: 'geojson',
				data: { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } }
			});

			// Preview line (cursor to last waypoint)
			map.addSource('preview-line', {
				type: 'geojson',
				data: { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } }
			});

			// Route casing
			map.addLayer({
				id: 'route-casing',
				type: 'line',
				source: 'route',
				paint: { 'line-color': '#1d4ed8', 'line-width': 8, 'line-opacity': 0.25 },
				layout: { 'line-join': 'round', 'line-cap': 'round' }
			});

			// Primary route line
			map.addLayer({
				id: 'route-line',
				type: 'line',
				source: 'route',
				paint: { 'line-color': '#3b82f6', 'line-width': 4 },
				layout: { 'line-join': 'round', 'line-cap': 'round' }
			});

			// Overlap casing
			map.addLayer({
				id: 'route-overlap-casing',
				type: 'line',
				source: 'route-overlap',
				paint: { 'line-color': '#9333ea', 'line-width': 8, 'line-opacity': 0.25 },
				layout: { 'line-join': 'round', 'line-cap': 'round' }
			});

			// Overlap line (purple)
			map.addLayer({
				id: 'route-overlap-line',
				type: 'line',
				source: 'route-overlap',
				paint: { 'line-color': '#a855f7', 'line-width': 4 },
				layout: { 'line-join': 'round', 'line-cap': 'round' }
			});

			// Direction arrows on the primary route
			map.addLayer({
				id: 'route-arrows',
				type: 'symbol',
				source: 'route',
				layout: {
					'symbol-placement': 'line',
					'symbol-spacing': 80,
					'text-field': '▶',
					'text-size': 12,
					'text-rotation-alignment': 'map',
					'text-keep-upright': false
				},
				paint: {
					'text-color': '#1d4ed8'
				}
			});

			// Preview line (dashed)
			map.addLayer({
				id: 'preview-line',
				type: 'line',
				source: 'preview-line',
				paint: {
					'line-color': '#94a3b8',
					'line-width': 2,
					'line-dasharray': [4, 4]
				}
			});
		});

		// Click to place waypoints
		map.on('click', (e: maplibregl.MapMouseEvent) => {
			if (isRouting) return;
			addWaypoint(e.lngLat);
		});

		// Mouse move: preview line + snap detection
		map.on('mousemove', (e: maplibregl.MapMouseEvent) => {
			if (waypoints.length > 0) {
				updatePreviewLine(e.lngLat);
			}
			checkSnapToStart(e);
		});

		// Clear preview when mouse leaves map
		map.on('mouseout', () => {
			clearPreviewLine();
			nearStart = false;
			updateStartMarkerPulse();
		});

		map.getCanvas().style.cursor = 'crosshair';
	}

	onDestroy(() => {
		markers.forEach((m) => m.remove());
		map?.remove();
	});

	// Re-route when mode changes
	$effect(() => {
		const _mode = mode;
		if (waypoints.length >= 2) {
			recalculateRoute();
		}
	});
</script>

<div class="map-wrapper">
	<div class="search-box">
		<div class="search-row">
			<input
				bind:this={searchInput}
				bind:value={searchQuery}
				oninput={onSearchInput}
				onfocusout={() => setTimeout(() => (showResults = false), 200)}
				onfocusin={() => { if (searchResults.length > 0) showResults = true; }}
				type="text"
				placeholder="Search for a place..."
			/>
			<button class="locate-btn" onclick={goToMyLocation} title="Go to my location">
				<span class="material-symbols">my_location</span>
			</button>
		</div>
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

	.search-row {
		display: flex;
		gap: 6px;
	}

	.search-box input {
		flex: 1;
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

	.locate-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 40px;
		height: 40px;
		border: none;
		border-radius: 8px;
		background: white;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
		cursor: pointer;
		color: #333;
		flex-shrink: 0;
	}

	.locate-btn:hover {
		background: #f3f4f6;
		color: #3b82f6;
	}

	.locate-btn .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.2rem;
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

	/* Waypoint markers */
	:global(.route-waypoint) {
		width: 22px;
		height: 22px;
		border-radius: 50%;
		background: #3b82f6;
		border: 2.5px solid white;
		box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
		cursor: grab;
		display: flex;
		align-items: center;
		justify-content: center;
		position: relative;
	}

	:global(.route-waypoint:active) {
		cursor: grabbing;
	}

	:global(.route-waypoint-label) {
		font-size: 9px;
		font-weight: 700;
		color: white;
		line-height: 1;
		pointer-events: none;
		user-select: none;
	}

	:global(.route-waypoint-start) {
		background: #22c55e;
		width: 26px;
		height: 26px;
	}

	:global(.route-waypoint-end) {
		background: #ef4444;
		width: 24px;
		height: 24px;
	}

	/* Pulse animation for snap-to-start hint */
	:global(.route-waypoint-pulse) {
		animation: pulse-ring 1s ease-out infinite;
	}

	@keyframes pulse-ring {
		0% {
			box-shadow: 0 0 0 0 rgba(34, 197, 94, 0.6);
		}
		100% {
			box-shadow: 0 0 0 14px rgba(34, 197, 94, 0);
		}
	}
</style>
