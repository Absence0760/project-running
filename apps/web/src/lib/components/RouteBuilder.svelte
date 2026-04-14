<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';
	// routing.ts still available for individual segment calls if needed
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
		}) => {},
		onmapclick = (_lngLat: { lng: number; lat: number }): boolean => false,
		onerror = (_message: string | null) => {}
	}: {
		mode?: 'road' | 'trail';
		onupdate?: (data: {
			waypoints: number;
			distance: number;
			elevation: number;
			elevations: number[];
			coordinates: [number, number][];
		}) => void;
		onmapclick?: (lngLat: { lng: number; lat: number }) => boolean;
		/**
		 * Called with a non-null message when routing fails (upstream
		 * unreachable, all segments returned errors, etc.), and with null
		 * when the next successful calculation clears the error.
		 */
		onerror?: (message: string | null) => void;
	} = $props();

	let mapContainer: HTMLDivElement;
	let searchInput: HTMLInputElement = undefined!;
	let map: maplibregl.Map;
	let waypoints: TrackPoint[] = [];
	let routeCoordinates: [number, number][] = [];
	let routeElevations: number[] = [];
	let markers: maplibregl.Marker[] = [];
	let distanceMarkers: maplibregl.Marker[] = [];
	let isRouting = $state(false);
	let mapStyle = $state<'streets' | 'satellite' | 'terrain'>('streets');
	let nearStart = false;
	let routeVersion = 0;
	let preRouteWaypoints: TrackPoint[] = []; // snapshot for undo-recalculate
	let searchQuery = $state('');
	let searchResults = $state<{ name: string; lng: number; lat: number }[]>([]);
	let showResults = $state(false);
	let searchTimeout: ReturnType<typeof setTimeout>;
	let keyHandler: (e: KeyboardEvent) => void;
	let geoWatchId: number | null = null;

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;

	const MAP_STYLES: Record<string, string> = {
		streets: `https://api.maptiler.com/maps/${prefersDark ? 'streets-v2-dark' : 'streets-v2'}/style.json?key=${PUBLIC_MAPTILER_KEY}`,
		satellite: `https://api.maptiler.com/maps/hybrid/style.json?key=${PUBLIC_MAPTILER_KEY}`,
		terrain: `https://api.maptiler.com/maps/outdoor-v2/style.json?key=${PUBLIC_MAPTILER_KEY}`,
	};

	const SNAP_DISTANCE_PX = 25;
	const KM_MARKER_INTERVAL = 1000; // metres

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
			name: f.place_name, lng: f.center[0], lat: f.center[1]
		}));
		showResults = searchResults.length > 0;
	}

	function onSearchInput() {
		clearTimeout(searchTimeout);
		searchTimeout = setTimeout(() => handleSearch(searchQuery), 300);
	}

	function selectSearchResult(result: { name: string; lng: number; lat: number }) {
		map.flyTo({ center: [result.lng, result.lat], zoom: 15 });
		searchQuery = '';
		searchResults = [];
		showResults = false;
		searchInput.blur();
	}

	// --- Waypoint markers ---

	function getMarkerColor(index: number): string {
		if (index === 0) return '#22c55e';
		return '#3b82f6';
	}

	function createWaypointMarker(lngLat: { lng: number; lat: number }, index: number): maplibregl.Marker {
		const marker = new maplibregl.Marker({ color: getMarkerColor(index), draggable: true })
			.setLngLat([lngLat.lng, lngLat.lat])
			.addTo(map);

		// Track drag state to distinguish click from drag
		let wasDragged = false;

		marker.on('dragstart', () => {
			wasDragged = true;
		});

		marker.on('dragend', () => {
			const currentIndex = markers.indexOf(marker);
			if (currentIndex === -1) return;
			const pos = marker.getLngLat();
			waypoints[currentIndex] = { lat: pos.lat, lng: pos.lng };
			routeCoordinates = [];
			routeElevations = [];
			updateStraightLine();
		});

		// Click on marker without dragging
		marker.getElement().addEventListener('click', (e: MouseEvent) => {
			if (wasDragged) {
				wasDragged = false;
				return;
			}
			e.stopPropagation();
			const currentIndex = markers.indexOf(marker);

			// Click on start marker with 3+ waypoints = close the loop
			if (currentIndex === 0 && waypoints.length >= 3) {
				addWaypoint({ lng: waypoints[0].lng, lat: waypoints[0].lat });
				return;
			}

			// Click on any other marker = add new waypoint at same position (for overlaps)
			const pos = marker.getLngLat();
			addWaypoint({ lng: pos.lng, lat: pos.lat });
		});

		// Right-click to delete
		marker.getElement().addEventListener('contextmenu', (e: MouseEvent) => {
			e.preventDefault();
			e.stopPropagation();
			const currentIndex = markers.indexOf(marker);
			if (currentIndex !== -1) removeWaypoint(currentIndex);
		});

		return marker;
	}

	function updateMarkerStyles() {
		// Built-in markers can't change color after creation.
		// Colors are set at creation time: green for first, blue for rest.
	}


	// --- Km distance markers ---

	function updateDistanceMarkers() {
		// Remove old markers
		distanceMarkers.forEach((m) => m.remove());
		distanceMarkers = [];

		if (routeCoordinates.length < 2) return;

		let accumulated = 0;
		let nextKm = KM_MARKER_INTERVAL;

		for (let i = 1; i < routeCoordinates.length; i++) {
			const segDist = haversine(routeCoordinates[i - 1], routeCoordinates[i]);
			accumulated += segDist;

			if (accumulated >= nextKm) {
				const el = document.createElement('div');
				el.className = 'km-marker';
				el.textContent = `${Math.round(nextKm / 1000)}`;

				const marker = new maplibregl.Marker({ element: el })
					.setLngLat(routeCoordinates[i])
					.addTo(map);
				distanceMarkers.push(marker);

				nextKm += KM_MARKER_INTERVAL;
			}
		}
	}

	// --- Routing ---

	async function recalculateRoute() {
		if (waypoints.length < 2) {
			routeCoordinates = [];
			routeElevations = [];
			updateRouteLine();
			updateDistanceMarkers();
			emitUpdate();
			return;
		}

		isRouting = true;
		routeVersion++;
		const currentVersion = routeVersion;
		// Clear any stale error from a previous failed attempt.
		onerror(null);

		try {
			// Route each segment — batched in groups of 3 to avoid OSRM rate limits
			const BATCH_SIZE = 3;
			// Per-fetch timeout. The public OSRM demo server is frequently
			// overloaded and can hang for 30s+ before returning a 504; we
			// bail out aggressively so the spinner never lasts longer than
			// (FETCH_TIMEOUT_MS * retries * segments) in the worst case.
			const FETCH_TIMEOUT_MS = 8000;
			const segments: { from: TrackPoint; to: TrackPoint }[] = [];
			for (let i = 0; i < waypoints.length - 1; i++) {
				segments.push({ from: waypoints[i], to: waypoints[i + 1] });
			}

			async function fetchSegment(from: TrackPoint, to: TrackPoint, retries = 2): Promise<unknown> {
				const coords = `${from.lng},${from.lat};${to.lng},${to.lat}`;
				const url = `https://router.project-osrm.org/route/v1/foot/${coords}?overview=full&geometries=geojson`;
				for (let attempt = 0; attempt <= retries; attempt++) {
					try {
						const res = await fetch(url, {
							signal: AbortSignal.timeout(FETCH_TIMEOUT_MS)
						});
						if (res.ok) return res.json();
						if (attempt < retries) await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
					} catch {
						// Timeouts land here as AbortError; network errors too.
						if (attempt < retries) await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
					}
				}
				return { code: 'Error' };
			}

			const results: unknown[] = [];
			for (let b = 0; b < segments.length; b += BATCH_SIZE) {
				if (currentVersion !== routeVersion) return;

				const batch = segments.slice(b, b + BATCH_SIZE);
				const batchResults = await Promise.all(
					batch.map(({ from, to }) => fetchSegment(from, to))
				);
				results.push(...batchResults);

				// Small delay between batches to avoid rate limiting
				if (b + BATCH_SIZE < segments.length) {
					await new Promise((r) => setTimeout(r, 200));
				}
			}

			if (currentVersion !== routeVersion) return;

			// Stitch segments together. Count how many succeeded so we can
			// surface an error when the upstream is completely unreachable.
			const allCoords: [number, number][] = [];
			let okSegments = 0;
			for (const data of results as { code: string; routes?: { geometry: { coordinates: [number, number][] } }[] }[]) {
				if (data.code !== 'Ok' || !data.routes?.[0]) continue;
				okSegments++;
				const segCoords = data.routes[0].geometry.coordinates;
				if (allCoords.length > 0 && segCoords.length > 0) {
					allCoords.push(...segCoords.slice(1));
				} else {
					allCoords.push(...segCoords);
				}
			}

			if (currentVersion !== routeVersion) return;

			if (okSegments === 0) {
				throw new Error(
					'Routing service unavailable — all segment requests timed out or failed. The public OSRM demo server is unreliable; see docs/roadmap.md.'
				);
			}
			if (okSegments < segments.length) {
				// Partial success — show a softer warning but keep the route.
				onerror(
					`Routed ${okSegments} of ${segments.length} segments — some requests failed. The line is incomplete.`
				);
			}

			routeCoordinates = allCoords;

			const { sampled } = sampleCoordinates(routeCoordinates, 100);
			const elevations = await fetchElevations(sampled);

			if (currentVersion !== routeVersion) return;

			if (sampled.length < routeCoordinates.length) {
				routeElevations = interpolateElevations(elevations, sampled.length, routeCoordinates.length);
			} else {
				routeElevations = elevations;
			}

			updateRouteLine();
			clearPreviewLine();
			// Clear the straight-line preview now that we have the real route
			const wpSrc = map.getSource('waypoint-lines') as maplibregl.GeoJSONSource | undefined;
			wpSrc?.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
			updateDistanceMarkers();
			emitUpdate();
		} catch (err) {
			if (currentVersion === routeVersion) {
				console.error('Routing failed:', err);
				onerror(
					err instanceof Error
						? err.message
						: 'Routing failed — the routing service is unreachable.'
				);
				// Clear the stale in-flight route so the UI doesn't show a
				// partial or empty line.
				routeCoordinates = [];
				routeElevations = [];
				updateRouteLine();
				emitUpdate();
			}
		} finally {
			if (currentVersion === routeVersion) {
				isRouting = false;
			}
		}
	}

	function interpolateElevations(sampled: number[], sampledCount: number, totalCount: number): number[] {
		if (sampledCount === 0) return Array(totalCount).fill(0);
		if (sampledCount === 1) return Array(totalCount).fill(sampled[0]);
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
		const routeSource = map.getSource('route') as maplibregl.GeoJSONSource | undefined;
		const overlapSource = map.getSource('route-overlap') as maplibregl.GeoJSONSource | undefined;
		if (!routeSource || !overlapSource) return;

		// Render the full route as a single line — no overlap splitting
		routeSource.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: routeCoordinates } });
		overlapSource.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
	}

	// --- Preview line ---

	function updatePreviewLine(lngLat: { lng: number; lat: number }) {
		const source = map.getSource('preview-line') as maplibregl.GeoJSONSource | undefined;
		if (!source || waypoints.length === 0) return;
		// Don't show cursor preview if route is already calculated
		if (routeCoordinates.length > 0) return;
		const last = waypoints[waypoints.length - 1];
		source.setData({
			type: 'Feature', properties: {},
			geometry: { type: 'LineString', coordinates: [[last.lng, last.lat], [lngLat.lng, lngLat.lat]] }
		});
	}

	function clearPreviewLine() {
		const source = map.getSource('preview-line') as maplibregl.GeoJSONSource | undefined;
		if (!source) return;
		source.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
	}

	// --- Snap to start detection ---

	function checkSnapToStart(e: maplibregl.MapMouseEvent): boolean {
		if (waypoints.length < 3) { nearStart = false; return false; }
		const startPx = map.project([waypoints[0].lng, waypoints[0].lat]);
		const cursorPx = e.point;
		const dist = Math.sqrt((startPx.x - cursorPx.x) ** 2 + (startPx.y - cursorPx.y) ** 2);
		nearStart = dist < SNAP_DISTANCE_PX;
		updateStartMarkerPulse();
		return nearStart;
	}

	function updateStartMarkerPulse() {
		// With built-in markers, we just rely on the cursor change to indicate snap-to-start
	}

	// --- Click on route to insert waypoint ---

	function findInsertIndex(lngLat: maplibregl.LngLat): number {
		if (waypoints.length < 2) return waypoints.length;

		let bestIdx = waypoints.length;
		let bestDist = Infinity;

		for (let i = 0; i < waypoints.length - 1; i++) {
			const a = waypoints[i];
			const b = waypoints[i + 1];
			// Distance from click to the midpoint of segment a-b
			const mid: [number, number] = [(a.lng + b.lng) / 2, (a.lat + b.lat) / 2];
			const d = haversine([lngLat.lng, lngLat.lat], mid);
			if (d < bestDist) {
				bestDist = d;
				bestIdx = i + 1;
			}
		}
		return bestIdx;
	}

	function isClickOnRoute(e: maplibregl.MapMouseEvent): boolean {
		if (routeCoordinates.length < 2) return false;
		// Check if click is within 12px of the route line
		const features = map.queryRenderedFeatures(
			[[e.point.x - 12, e.point.y - 12], [e.point.x + 12, e.point.y + 12]],
			{ layers: ['route-line', 'route-overlap-line'] }
		);
		return features.length > 0;
	}

	// --- Stats ---

	function emitUpdate() {
		const gain = calculateElevationGain(routeElevations);
		let distance = 0;
		for (let i = 1; i < routeCoordinates.length; i++) {
			distance += haversine(routeCoordinates[i - 1], routeCoordinates[i]);
		}
		onupdate({
			waypoints: waypoints.length, distance, elevation: gain,
			elevations: routeElevations, coordinates: routeCoordinates
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
		updateStraightLine();
	}

	export function insertWaypoint(lngLat: { lng: number; lat: number }, atIndex: number) {
		const point: TrackPoint = { lat: lngLat.lat, lng: lngLat.lng };
		waypoints.splice(atIndex, 0, point);

		const marker = createWaypointMarker(lngLat, atIndex);
		markers.splice(atIndex, 0, marker);
		updateMarkerStyles();
		updateStraightLine();
	}

	export function removeWaypoint(index: number) {
		if (waypoints.length <= 1 && index === 0) {
			clearWaypoints();
			return;
		}
		waypoints.splice(index, 1);
		const marker = markers.splice(index, 1)[0];
		marker?.remove();
		updateMarkerStyles();
		updateStraightLine();
	}

	export function undoWaypoint() {
		if (waypoints.length === 0) return;
		waypoints.pop();
		const marker = markers.pop();
		marker?.remove();
		updateMarkerStyles();
		clearPreviewLine();
		updateStraightLine();
	}

	export function clearWaypoints() {
		waypoints = [];
		routeCoordinates = [];
		routeElevations = [];
		markers.forEach((m) => m.remove());
		markers = [];
		distanceMarkers.forEach((m) => m.remove());
		distanceMarkers = [];
		nearStart = false;
		isRouting = false;
		clearPreviewLine();
		updateRouteLine();
		updateStraightLine();
		emitUpdate();
	}

	/**
	 * Calculate the road-snapped route through all waypoints.
	 * Saves a snapshot of waypoints for undo.
	 */
	export async function calculateRoute() {
		preRouteWaypoints = waypoints.map((w) => ({ ...w }));
		await recalculateRoute();
	}

	/**
	 * Undo route calculation — restore waypoints from before calculate was called.
	 */
	export function undoCalculate() {
		if (preRouteWaypoints.length === 0) return;

		// Clear existing
		markers.forEach((m) => m.remove());
		markers = [];
		routeCoordinates = [];
		routeElevations = [];
		distanceMarkers.forEach((m) => m.remove());
		distanceMarkers = [];

		// Restore waypoints
		waypoints = preRouteWaypoints.map((w) => ({ ...w }));
		preRouteWaypoints = [];

		// Recreate markers
		for (let i = 0; i < waypoints.length; i++) {
			const marker = createWaypointMarker({ lng: waypoints[i].lng, lat: waypoints[i].lat }, i);
			markers.push(marker);
		}
		updateMarkerStyles();
		updateRouteLine();
		updateStraightLine();
	}

	/**
	 * Duplicate the route in reverse to create an out-and-back.
	 */
	export function outAndBack() {
		if (waypoints.length < 2) return;

		// Add waypoints in reverse (skip the last since it's the turnaround point)
		const reversed = waypoints.slice(0, -1).reverse();
		for (const wp of reversed) {
			const lngLat = { lng: wp.lng, lat: wp.lat };
			const point: TrackPoint = { lat: lngLat.lat, lng: lngLat.lng };
			waypoints.push(point);

			const marker = createWaypointMarker(lngLat, waypoints.length - 1);
			markers.push(marker);
		}
		updateMarkerStyles();

		// Clear any calculated route — user needs to recalculate
		routeCoordinates = [];
		routeElevations = [];
		updateStraightLine();
	}

	/**
	 * Switch map style between streets, satellite, and terrain.
	 */
	export function setMapStyle(style: 'streets' | 'satellite' | 'terrain') {
		if (!map || mapStyle === style) return;
		mapStyle = style;
		map.setStyle(MAP_STYLES[style]);

		// Re-add sources and layers after style change
		map.once('style.load', () => {
			addMapSourcesAndLayers();
			// Redraw existing route or straight lines
			if (routeCoordinates.length > 0) {
				updateRouteLine();
			} else {
				updateStraightLine();
			}
		});
	}

	/**
	 * Generate a loop route of approximately the target distance from the start point.
	 */
	export async function generateLoop(
		targetDistanceM: number,
		startFrom?: { lat: number; lng: number },
		endAt?: { lat: number; lng: number }
	) {
		const start: TrackPoint = startFrom
			? { lat: startFrom.lat, lng: startFrom.lng }
			: (() => { const c = map.getCenter(); return { lat: c.lat, lng: c.lng }; })();

		const end: TrackPoint = endAt
			? { lat: endAt.lat, lng: endAt.lng }
			: { ...start };

		const isLoop = !endAt;
		let scaleFactor = 0.30;
		const numPoints = 6;
		const maxAttempts = 3;

		for (let attempt = 0; attempt < maxAttempts; attempt++) {
			let newWaypoints: TrackPoint[];

			if (isLoop) {
				const radiusM = (targetDistanceM * scaleFactor) / (2 * Math.PI);
				const radiusDeg = radiusM / 111320;
				const cosLat = Math.cos(start.lat * Math.PI / 180);
				const randomOffset = Math.random() * Math.PI * 2;

				newWaypoints = [start];
				for (let i = 1; i <= numPoints; i++) {
					const angle = randomOffset + (i / numPoints) * Math.PI * 2;
					newWaypoints.push({
						lat: start.lat + Math.sin(angle) * radiusDeg,
						lng: start.lng + Math.cos(angle) * radiusDeg / cosLat,
					});
				}
				newWaypoints.push({ ...start });
			} else {
				// Point-to-point: curve the path to hit target distance
				const directDist = haversine([start.lng, start.lat], [end.lng, end.lat]);
				const curveAmount = Math.max(0, (targetDistanceM * scaleFactor - directDist) / Math.max(directDist, 1));
				const dLat = end.lat - start.lat;
				const dLng = end.lng - start.lng;
				// Perpendicular offset
				const perpLat = -dLng * curveAmount * 0.4;
				const perpLng = dLat * curveAmount * 0.4;

				newWaypoints = [start];
				for (let i = 1; i <= numPoints; i++) {
					const t = i / (numPoints + 1);
					const curveFactor = Math.sin(t * Math.PI);
					newWaypoints.push({
						lat: start.lat + dLat * t + perpLat * curveFactor,
						lng: start.lng + dLng * t + perpLng * curveFactor,
					});
				}
				newWaypoints.push(end);
			}

			markers.forEach((m) => m.remove());
			markers = [];
			waypoints = newWaypoints;
			for (let i = 0; i < waypoints.length; i++) {
				const marker = createWaypointMarker({ lng: waypoints[i].lng, lat: waypoints[i].lat }, i);
				markers.push(marker);
			}
			updateMarkerStyles();
			routeCoordinates = [];
			routeElevations = [];

			await recalculateRoute();

			if (routeCoordinates.length < 2) break;

			let actualDistance = 0;
			for (let i = 1; i < routeCoordinates.length; i++) {
				actualDistance += haversine(routeCoordinates[i - 1], routeCoordinates[i]);
			}

			const ratio = targetDistanceM / actualDistance;
			if (ratio > 0.85 && ratio < 1.15) break;
			scaleFactor *= ratio;
		}

		updateStraightLine();
	}

	export function getMapStyle() { return mapStyle; }
	export function getMapCenter() { return map ? map.getCenter() : null; }

	/**
	 * Show straight dashed lines between waypoints as a preview before routing.
	 */
	function updateStraightLine() {
		const wpSource = map.getSource('waypoint-lines') as maplibregl.GeoJSONSource | undefined;
		if (!wpSource) return;

		// If we have a calculated route, hide the straight-line preview
		if (routeCoordinates.length > 0) {
			wpSource.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
			return;
		}

		// No calculated route — clear route/overlap and show straight-line preview
		const routeSource = map.getSource('route') as maplibregl.GeoJSONSource | undefined;
		const overlapSource = map.getSource('route-overlap') as maplibregl.GeoJSONSource | undefined;
		if (routeSource) {
			routeSource.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
		}
		if (overlapSource) {
			overlapSource.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
		}

		if (waypoints.length < 2) {
			wpSource.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } });
			emitUpdate();
			return;
		}

		// Draw dashed straight lines between waypoints
		const coords: [number, number][] = waypoints.map((w) => [w.lng, w.lat]);
		wpSource.setData({
			type: 'Feature', properties: {},
			geometry: { type: 'LineString', coordinates: coords }
		});

		// Emit basic distance estimate from straight lines
		let distance = 0;
		for (let i = 1; i < coords.length; i++) {
			distance += haversine(coords[i - 1], coords[i]);
		}
		onupdate({
			waypoints: waypoints.length, distance, elevation: 0,
			elevations: [], coordinates: coords
		});
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
				style: MAP_STYLES.streets,
				center, zoom
			});
			setupMap();
		}

		navigator.geolocation.getCurrentPosition(
			(pos) => initMap([pos.coords.longitude, pos.coords.latitude], 16),
			() => initMap(defaultCenter, defaultZoom),
			{ timeout: 3000 }
		);

		// Keyboard shortcuts
		keyHandler = (e: KeyboardEvent) => {
			// Don't trigger shortcuts when typing in search
			if (e.target instanceof HTMLInputElement) return;

			if ((e.metaKey || e.ctrlKey) && e.key === 'z') {
				e.preventDefault();
				undoWaypoint();
			}
			if (e.key === 'Escape') {
				clearWaypoints();
			}
		};
		document.addEventListener('keydown', keyHandler);
	});

	function goToMyLocation() {
		navigator.geolocation.getCurrentPosition(
			(pos) => map.flyTo({ center: [pos.coords.longitude, pos.coords.latitude], zoom: 17 }),
			() => {},
			{ timeout: 5000 }
		);
	}

	function addMapSourcesAndLayers() {
		const empty = { type: 'Feature' as const, properties: {}, geometry: { type: 'LineString' as const, coordinates: [] as [number, number][] } };
		map.addSource('route', { type: 'geojson', data: empty });
		map.addSource('route-overlap', { type: 'geojson', data: empty });
		map.addSource('preview-line', { type: 'geojson', data: empty });
		map.addSource('waypoint-lines', { type: 'geojson', data: empty });

		map.addLayer({
			id: 'route-casing', type: 'line', source: 'route',
			paint: { 'line-color': '#1d4ed8', 'line-width': 8, 'line-opacity': 0.25 },
			layout: { 'line-join': 'round', 'line-cap': 'round' }
		});
		map.addLayer({
			id: 'route-line', type: 'line', source: 'route',
			paint: { 'line-color': '#3b82f6', 'line-width': 4 },
			layout: { 'line-join': 'round', 'line-cap': 'round' }
		});
		map.addLayer({
			id: 'route-overlap-casing', type: 'line', source: 'route-overlap',
			paint: { 'line-color': '#9333ea', 'line-width': 8, 'line-opacity': 0.25 },
			layout: { 'line-join': 'round', 'line-cap': 'round' }
		});
		map.addLayer({
			id: 'route-overlap-line', type: 'line', source: 'route-overlap',
			paint: { 'line-color': '#a855f7', 'line-width': 4 },
			layout: { 'line-join': 'round', 'line-cap': 'round' }
		});
		map.addLayer({
			id: 'route-arrows', type: 'symbol', source: 'route',
			layout: {
				'symbol-placement': 'line', 'symbol-spacing': 80,
				'text-field': '▶', 'text-size': 12,
				'text-rotation-alignment': 'map', 'text-keep-upright': false
			},
			paint: { 'text-color': '#1d4ed8' }
		});
		map.addLayer({
			id: 'waypoint-lines', type: 'line', source: 'waypoint-lines',
			paint: { 'line-color': '#3b82f6', 'line-width': 2.5, 'line-dasharray': [6, 4], 'line-opacity': 0.6 },
			layout: { 'line-join': 'round', 'line-cap': 'round' }
		});
		map.addLayer({
			id: 'preview-line', type: 'line', source: 'preview-line',
			paint: { 'line-color': '#94a3b8', 'line-width': 2, 'line-dasharray': [4, 4] }
		});
	}

	function setupMap() {
		map.addControl(new maplibregl.NavigationControl(), 'top-right');

		// Single load handler for all map setup
		let locationMarker: maplibregl.Marker | null = null;

		map.on('load', () => {
			// User location dot (non-interactive, clicks pass through)
			geoWatchId = navigator.geolocation.watchPosition(
				(pos) => {
					const lngLat: [number, number] = [pos.coords.longitude, pos.coords.latitude];
					if (!locationMarker) {
						const el = document.createElement('div');
						el.className = 'user-location-dot';
						locationMarker = new maplibregl.Marker({ element: el }).setLngLat(lngLat).addTo(map);
					} else {
						locationMarker.setLngLat(lngLat);
					}
				},
				() => {},
				{ enableHighAccuracy: true }
			);
			addMapSourcesAndLayers();
		});

		// Click handler — let parent intercept first, then insert mid-route or append
		map.on('click', (e: maplibregl.MapMouseEvent) => {
			if (isRouting) return;

			// Let parent handle the click (e.g. for picking start/end point)
			if (onmapclick(e.lngLat)) return;

			// Only consider mid-route insertion if:
			// 1. Clicking on the route line
			// 2. There are 3+ waypoints (need at least a "middle")
			// 3. The click is NOT near the last waypoint (user is extending, not inserting)
			if (isClickOnRoute(e) && waypoints.length >= 3) {
				const lastWp = waypoints[waypoints.length - 1];
				const distToLast = haversine(
					[e.lngLat.lng, e.lngLat.lat],
					[lastWp.lng, lastWp.lat]
				);
				// If click is more than 100m from the last waypoint, it's a mid-route insert
				if (distToLast > 100) {
					const idx = findInsertIndex(e.lngLat);
					// Only insert if it's not at the end
					if (idx < waypoints.length) {
						insertWaypoint(e.lngLat, idx);
						return;
					}
				}
			}
			addWaypoint(e.lngLat);
		});

		// Mouse move: preview line + snap detection + cursor changes
		map.on('mousemove', (e: maplibregl.MapMouseEvent) => {
			if (waypoints.length > 0) {
				updatePreviewLine(e.lngLat);
			}
			checkSnapToStart(e);

			// Change cursor when hovering mid-route (not near end)
			let showInsertCursor = false;
			if (routeCoordinates.length >= 2 && waypoints.length >= 3 && isClickOnRoute(e)) {
				const lastWp = waypoints[waypoints.length - 1];
				const distToLast = haversine([e.lngLat.lng, e.lngLat.lat], [lastWp.lng, lastWp.lat]);
				showInsertCursor = distToLast > 100;
			}

			if (showInsertCursor) {
				map.getCanvas().style.cursor = 'copy';
			} else if (nearStart) {
				map.getCanvas().style.cursor = 'pointer';
			} else {
				map.getCanvas().style.cursor = 'crosshair';
			}
		});

		map.on('mouseout', () => {
			clearPreviewLine();
			nearStart = false;
			updateStartMarkerPulse();
			map.getCanvas().style.cursor = 'crosshair';
		});

		// Disable context menu on map
		map.getCanvas().addEventListener('contextmenu', (e) => e.preventDefault());
	}

	onDestroy(() => {
		clearTimeout(searchTimeout);
		if (geoWatchId !== null) navigator.geolocation.clearWatch(geoWatchId);
		markers.forEach((m) => m.remove());
		distanceMarkers.forEach((m) => m.remove());
		map?.remove();
		if (keyHandler) document.removeEventListener('keydown', keyHandler);
	});

	// When mode changes, clear any calculated route so user re-calculates
	$effect(() => {
		const _mode = mode;
		if (routeCoordinates.length > 0) {
			routeCoordinates = [];
			routeElevations = [];
			updateStraightLine();
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

	{#if isRouting}
		<div class="routing-indicator">
			<div class="routing-spinner"></div>
			Calculating route...
		</div>
	{/if}

	<div class="shortcuts-hint">
		<span><kbd>Ctrl</kbd>+<kbd>Z</kbd> Undo</span>
		<span><kbd>Esc</kbd> Clear</span>
		<span>Right-click marker to delete</span>
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

	/* Search */
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
		background: var(--color-surface);
		color: var(--color-text);
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
		background: var(--color-surface);
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
		cursor: pointer;
		color: var(--color-text);
		flex-shrink: 0;
	}

	.locate-btn:hover {
		background: var(--color-bg-tertiary);
		color: var(--color-primary);
	}

	.locate-btn .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.2rem;
	}

	.search-results {
		list-style: none;
		margin: 4px 0 0;
		padding: 0;
		background: var(--color-surface);
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
		color: var(--color-text);
	}

	.search-results li button:hover {
		background: var(--color-bg-tertiary);
	}

	.search-results li + li {
		border-top: 1px solid var(--color-border);
	}

	/* Routing indicator */
	.routing-indicator {
		position: absolute;
		top: 12px;
		left: 50%;
		transform: translateX(-50%);
		z-index: 10;
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 8px 16px;
		background: var(--color-surface);
		border-radius: 20px;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
		font-size: 0.8rem;
		font-weight: 500;
		color: var(--color-primary);
	}

	.routing-spinner {
		width: 14px;
		height: 14px;
		border: 2px solid var(--color-border);
		border-top-color: var(--color-primary);
		border-radius: 50%;
		animation: spin 0.6s linear infinite;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	/* Keyboard shortcuts hint */
	.shortcuts-hint {
		position: absolute;
		bottom: 12px;
		left: 12px;
		z-index: 10;
		display: flex;
		gap: 12px;
		padding: 6px 12px;
		background: rgba(0, 0, 0, 0.6);
		border-radius: 6px;
		font-size: 0.7rem;
		color: rgba(255, 255, 255, 0.8);
	}

	.shortcuts-hint kbd {
		background: rgba(255, 255, 255, 0.15);
		padding: 1px 4px;
		border-radius: 3px;
		font-family: inherit;
		font-size: 0.65rem;
	}

	/* Km markers */
	:global(.km-marker) {
		width: 20px;
		height: 20px;
		border-radius: 50%;
		background: var(--color-surface);
		border: 2px solid var(--color-primary);
		font-size: 8px;
		font-weight: 700;
		color: var(--color-primary);
		display: flex;
		align-items: center;
		justify-content: center;
		pointer-events: none;
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
	}

	/* User location dot */
	:global(.user-location-dot) {
		width: 14px;
		height: 14px;
		border-radius: 50%;
		background: #4285f4;
		border: 2.5px solid white;
		box-shadow: 0 0 0 3px rgba(66, 133, 244, 0.3);
		pointer-events: none;
	}
</style>
