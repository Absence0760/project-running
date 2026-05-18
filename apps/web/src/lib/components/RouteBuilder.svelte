<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';
	// Single source of truth for the OSRM endpoint — env-overridable via
	// PUBLIC_OSRM_URL so a self-hosted backend can replace the public
	// demo server without code edits.
	import { OSRM_BASE_URL } from '$lib/routing';
	import {
		DEFAULT_SCALE_FACTOR,
		generateLoopWaypoints,
		isValidTargetDistance,
		isWithinAcceptBand,
		nextScaleFactor,
	} from '$lib/route_loop';
	import { fetchElevations, sampleCoordinates, calculateElevationGain } from '$lib/elevation';
	import {
		closestPointDistanceM,
		formatWaypointRanges,
		haversineM as routingHaversineM,
		identifyFailedWaypoints,
		OSRM_SNAP_RADIUS_M,
		QUALITY_THRESHOLDS,
		qualityWarning,
		validateRouteQuality,
		type RoutedSegment,
	} from '$lib/routing_quality';
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
		onerror = (_message: string | null, _severity: 'error' | 'warning' = 'error') => {}
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
		 * Called with a non-null message when routing fails or partially
		 * fails, and with null when the next successful calculation
		 * clears the error. `severity` distinguishes hard failures (no
		 * usable route) from partial-success warnings (route is drawn
		 * but some segments are missing). The parent decides styling.
		 */
		onerror?: (message: string | null, severity?: 'error' | 'warning') => void;
	} = $props();

	let mapContainer: HTMLDivElement;
	let searchInput: HTMLInputElement = undefined!;
	let map: maplibregl.Map;
	let waypoints: TrackPoint[] = [];
	let routeCoordinates: [number, number][] = [];
	let routeElevations: number[] = [];
	let markers: maplibregl.Marker[] = [];
	/// 0-based indices of waypoints flagged by the post-routing quality
	/// pass — failed snaps, deviation outliers, or detour-segment
	/// endpoints. These markers render in red so the user can see at a
	/// glance which clicks are causing the warning text. Cleared on any
	/// waypoint mutation; repopulated after Calculate Route.
	let implicatedWaypoints = new Set<number>();
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

	function getMarkerColor(index: number, implicated: boolean): string {
		// Red wins over the green start-marker convention — the user's
		// problem is more important to surface than "this is point 1".
		if (implicated) return '#ef4444';
		if (index === 0) return '#22c55e';
		return '#3b82f6';
	}

	function createWaypointMarker(
		lngLat: { lng: number; lat: number },
		index: number,
		implicated = false,
	): maplibregl.Marker {
		const marker = new maplibregl.Marker({
			color: getMarkerColor(index, implicated),
			draggable: true,
		})
			.setLngLat([lngLat.lng, lngLat.lat])
			.addTo(map);
		// Tagged so updateMarkerStyles can detect implicated → default
		// transitions and only rebuild the markers that actually changed.
		(marker as unknown as { __implicated: boolean }).__implicated = implicated;

		// Track drag state to distinguish click from drag
		let wasDragged = false;

		marker.on('dragstart', () => {
			wasDragged = true;
		});

		marker.on('dragend', () => {
			const currentIndex = markers.indexOf(marker);
			if (currentIndex === -1) return;
			// Any waypoint mutation has to invalidate an in-flight
			// recalculateRoute so the stale result doesn't overwrite
			// the post-drag state. The bump fires at the next version
			// checkpoint inside recalculateRoute and causes it to return
			// false instead of writing routeCoordinates.
			routeVersion++;
			const pos = marker.getLngLat();
			waypoints[currentIndex] = { lat: pos.lat, lng: pos.lng };
			routeCoordinates = [];
			routeElevations = [];
			// The previous quality pass referenced the old position;
			// drop its red markers so they don't mislead the user about
			// the post-drag state. The next Calculate Route will repaint
			// any that are still problematic.
			clearImplicatedMarkers();
			updateStraightLine();
			// IMPORTANT: reset wasDragged here, not just in the click
			// handler. The browser doesn't fire a `click` event after a
			// drag (mouseup with movement skips the synthetic click),
			// so the flag would otherwise stay `true` and silently eat
			// the next legitimate click on this marker — the exact
			// "click an existing marker to back-track doesn't work
			// after dragging it" bug the audit caught. Defer one tick
			// so any synthetic click that DID fire (some browsers do
			// emit click after a no-movement drag) lands first.
			setTimeout(() => {
				wasDragged = false;
			}, 0);
		});

		// Tell the user clicking the marker does something. Replaces
		// the default `move` cursor that maplibre applies to draggable
		// markers, which gave no hint that clicking back-tracks the
		// route through this point.
		marker.getElement().style.cursor = 'pointer';

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

			// Click on any other marker = back-track through it. The
			// new waypoint is appended at the same lat/lng so OSRM has
			// to route from the current end back through this point on
			// the next Calculate. Without a tiny visual offset the new
			// pin sits exactly on top of the clicked one and looks
			// like nothing happened.
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
		// MapLibre's built-in marker can't change color after creation,
		// so we destroy + rebuild any markers whose implicated state
		// has flipped. Markers whose color is already correct are left
		// alone, preserving any in-flight drag handlers.
		for (let i = 0; i < markers.length; i++) {
			const existing = markers[i];
			const lngLat = existing.getLngLat();
			const wasImplicated =
				(existing as unknown as { __implicated?: boolean }).__implicated === true;
			const shouldBeImplicated = implicatedWaypoints.has(i);
			if (wasImplicated === shouldBeImplicated) continue;
			existing.remove();
			markers[i] = createWaypointMarker(
				{ lng: lngLat.lng, lat: lngLat.lat },
				i,
				shouldBeImplicated,
			);
		}
	}

	function clearImplicatedMarkers() {
		// Any waypoint mutation invalidates the previous quality pass.
		// Reset before the mutation; updateMarkerStyles flips reds
		// back to default colors.
		if (implicatedWaypoints.size === 0) return;
		implicatedWaypoints = new Set();
		updateMarkerStyles();
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

	async function recalculateRoute(): Promise<boolean> {
		if (waypoints.length < 2) {
			routeCoordinates = [];
			routeElevations = [];
			updateRouteLine();
			updateDistanceMarkers();
			emitUpdate();
			return false;
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
				// `radiuses=` caps how far OSRM can reach to find a road for
				// each waypoint. Default OSRM is "unlimited" — that's how a
				// click near a stream ends up snapping to a road 800m away.
				// 100m is loose enough that a click near a known path still
				// snaps but rejects the absurd cases. OSRM returns
				// `code: "NoSegment"` when no road is in range; we treat
				// that as a normal segment failure (counted in okSegments).
				const radius = OSRM_SNAP_RADIUS_M;
				const url = `${OSRM_BASE_URL}/route/v1/foot/${coords}?overview=full&geometries=geojson&radiuses=${radius};${radius}`;
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
				if (currentVersion !== routeVersion) return false;

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

			if (currentVersion !== routeVersion) return false;

			// Build per-segment results, falling back to a straight line
			// for segments OSRM couldn't snap. The old behaviour silently
			// dropped failed segments, which produced absurd-looking routes
			// (a few hundred metres of snapped path glued together by
			// invisible jumps) and meant a click on an unmapped private
			// path killed the whole save. Now every segment contributes
			// to the merged polyline — the warning banner tells the user
			// which bits are straight-line fallbacks.
			const perSegment: {
				ok: boolean;
				from: TrackPoint;
				to: TrackPoint;
				polyline: [number, number][];
				distanceM: number;
			}[] = (results as {
				code: string;
				routes?: { geometry: { coordinates: [number, number][] }; distance?: number }[];
			}[]).map((data, i) => {
				const from = segments[i].from;
				const to = segments[i].to;
				if (data.code === 'Ok' && data.routes?.[0]) {
					return {
						ok: true,
						from,
						to,
						polyline: data.routes[0].geometry.coordinates,
						distanceM: data.routes[0].distance ?? 0,
					};
				}
				return {
					ok: false,
					from,
					to,
					polyline: [
						[from.lng, from.lat],
						[to.lng, to.lat],
					],
					distanceM: routingHaversineM(from, to),
				};
			});

			if (currentVersion !== routeVersion) return false;

			const okSegments = perSegment.filter((s) => s.ok).length;
			const allCoords: [number, number][] = [];
			for (const s of perSegment) {
				if (allCoords.length > 0 && s.polyline.length > 0) {
					allCoords.push(...s.polyline.slice(1));
				} else {
					allCoords.push(...s.polyline);
				}
			}

			if (okSegments === 0) {
				throw new Error(
					'Routing service unavailable — no segments could be routed. The public OSRM demo server may be unreachable, or this region has poor pedestrian-graph coverage.'
				);
			}
			// Build the implicated-waypoint set from three diagnostics —
			// failed snaps, deviation outliers, and detour-segment
			// endpoints — then push the colour update through
			// updateMarkerStyles() so the user sees red pins for the
			// markers the warning text is naming.
			const implicated = new Set<number>();
			for (const oneBasedIdx of identifyFailedWaypoints(perSegment)) {
				implicated.add(oneBasedIdx - 1);
			}
			// Deviation: per-waypoint distance to the merged polyline.
			// Reuses the qualityWarning threshold (60m) so the marker
			// colour and the banner text refer to the same set of
			// outliers.
			for (let i = 0; i < waypoints.length; i++) {
				const d = closestPointDistanceM(waypoints[i], allCoords);
				if (d > QUALITY_THRESHOLDS.deviationWarnM) implicated.add(i);
			}
			// Detour: paint both endpoints of any segment that took a
			// > 2.5x route between its clicks. Straight-line-fallback
			// segments have ratio exactly 1, so they don't trip this.
			perSegment.forEach((s, i) => {
				const straightLine = routingHaversineM(s.from, s.to);
				if (straightLine < 1) return;
				const ratio = s.distanceM / straightLine;
				if (ratio > QUALITY_THRESHOLDS.detourWarnRatio) {
					implicated.add(i);
					implicated.add(i + 1);
				}
			});

			if (okSegments < perSegment.length) {
				// Partial success — identify the specific waypoints that
				// couldn't snap, fall back to straight lines through them,
				// and tell the user which markers to nudge if they want a
				// snapped route.
				const failedWaypoints = identifyFailedWaypoints(perSegment);
				const failedSegments = perSegment.length - okSegments;
				const wpList = formatWaypointRanges(failedWaypoints);
				const wpClause =
					failedWaypoints.length > 0
						? ` Waypoint${failedWaypoints.length === 1 ? '' : 's'} ${wpList} couldn't snap to a path within ${OSRM_SNAP_RADIUS_M}m — using direct lines through those points.`
						: ` ${failedSegments} segment${failedSegments === 1 ? '' : 's'} couldn't snap — using direct lines for those.`;
				onerror(
					`Routed ${okSegments} of ${perSegment.length} segments.${wpClause} Drag the red markers closer to a road for a snapped route, or accept the direct lines.`,
					'warning',
				);
			} else {
				// Every segment came back. Now check whether the route
				// actually sticks close to the user's clicks — radiuses=
				// caps the snap at the endpoints but doesn't stop OSRM
				// from routing via a wild detour BETWEEN waypoints.
				const routedSegments: RoutedSegment[] = perSegment.map((s) => ({
					from: s.from,
					to: s.to,
					polyline: s.polyline,
					distanceM: s.distanceM,
				}));
				const quality = validateRouteQuality(routedSegments);
				const warn = qualityWarning(quality);
				if (warn) {
					onerror(
						`${warn} (Red markers highlight the implicated waypoints.)`,
						'warning',
					);
				}
			}

			implicatedWaypoints = implicated;
			updateMarkerStyles();

			routeCoordinates = allCoords;

			const { sampled } = sampleCoordinates(routeCoordinates, 100);
			const elevations = await fetchElevations(sampled);

			if (currentVersion !== routeVersion) return false;

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
			return true;
		} catch (err) {
			if (currentVersion === routeVersion) {
				console.error('Routing failed:', err);
				onerror(
					err instanceof Error
						? err.message
						: 'Routing failed — the routing service is unreachable.',
					'error'
				);
				// Clear the stale in-flight route so the UI doesn't show a
				// partial or empty line.
				routeCoordinates = [];
				routeElevations = [];
				updateRouteLine();
				emitUpdate();
			}
			return false;
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

	// Any waypoint mutation after a Calculate Route makes the snapped
	// polyline stale — the user added a back-track / inserted a
	// mid-route point / deleted one, and OSRM hasn't been re-run.
	// Mirror dragend: drop the snapped state so the map reverts to
	// the straight-line preview that includes the new waypoint, and
	// emitUpdate carries the empty `coordinates` array back to the
	// parent so its `routed` flag (gated on coordinates.length >= 2)
	// disables Save until the user recalculates.
	function invalidateCalculatedRoute() {
		// Bump BEFORE the early-return: even when the polyline is
		// already empty, an in-flight recalculateRoute might be a few
		// microseconds away from writing into it. Bumping the version
		// is the only safe signal that "the world changed under you,
		// drop your result."
		routeVersion++;
		if (routeCoordinates.length === 0 && routeElevations.length === 0) return;
		routeCoordinates = [];
		routeElevations = [];
		distanceMarkers.forEach((m) => m.remove());
		distanceMarkers = [];
		updateRouteLine();
	}

	export function addWaypoint(lngLat: { lng: number; lat: number }) {
		if (nearStart && waypoints.length >= 3) {
			lngLat = { lng: waypoints[0].lng, lat: waypoints[0].lat };
		}

		invalidateCalculatedRoute();
		clearImplicatedMarkers();
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
		invalidateCalculatedRoute();
		clearImplicatedMarkers();
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
		invalidateCalculatedRoute();
		clearImplicatedMarkers();
		waypoints.splice(index, 1);
		const marker = markers.splice(index, 1)[0];
		marker?.remove();
		updateMarkerStyles();
		updateStraightLine();
	}

	export function undoWaypoint() {
		if (waypoints.length === 0) return;
		// Invalidate any in-flight recalculateRoute — see invalidateCalculatedRoute.
		routeVersion++;
		clearImplicatedMarkers();
		waypoints.pop();
		const marker = markers.pop();
		marker?.remove();
		updateMarkerStyles();
		clearPreviewLine();
		updateStraightLine();
	}

	export function clearWaypoints() {
		// Invalidate any in-flight recalculateRoute — Esc during a slow
		// OSRM batch must not let the late result repopulate the polyline.
		routeVersion++;
		waypoints = [];
		routeCoordinates = [];
		routeElevations = [];
		implicatedWaypoints = new Set();
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
	 * Saves a snapshot of waypoints for undo. Returns true only when
	 * a usable route was produced (>= 1 OSRM segment succeeded). The
	 * parent uses this to gate the Save button — a stale `routed`
	 * flag after a failed call let the user "save" an empty route.
	 */
	export async function calculateRoute(): Promise<boolean> {
		// Reject re-entry while a calculation is already running. The
		// public OSRM demo is slow enough that a user impatient-clicking
		// "Calculate Route" twice would otherwise fire two parallel
		// batches that trample each other's state.
		if (isRouting) return false;
		preRouteWaypoints = waypoints.map((w) => ({ ...w }));
		return await recalculateRoute();
	}

	/**
	 * Undo route calculation — restore waypoints from before calculate was called.
	 */
	export function undoCalculate() {
		if (preRouteWaypoints.length === 0) return;
		// Invalidate any in-flight recalculateRoute — see invalidateCalculatedRoute.
		routeVersion++;

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
		// Invalidate any in-flight recalculateRoute — see invalidateCalculatedRoute.
		routeVersion++;

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
	): Promise<boolean> {
		// Refuse re-entry. generateLoop overwrites waypoints + markers on
		// every iteration; a second concurrent call would have its state
		// trampled by the first call's next iteration mid-flight.
		if (isRouting) return false;
		// Refuse before-map-ready. The fallback below reads map.getCenter()
		// directly and would crash on undefined.
		if (!map) return false;
		// Reject garbage targets — NaN / Infinity / non-positive — so a
		// caller bug can't push the iteration into an infinite or
		// degenerate scaleFactor chase. The slider in /routes/new
		// already clamps to [1, 42] km but this is the API boundary.
		if (!isValidTargetDistance(targetDistanceM)) return false;

		const start: { lat: number; lng: number } = startFrom
			? { lat: startFrom.lat, lng: startFrom.lng }
			: (() => { const c = map.getCenter(); return { lat: c.lat, lng: c.lng }; })();

		let scaleFactor = DEFAULT_SCALE_FACTOR;
		// Deterministic per-call seed so the three attempts all radiate
		// from the same orientation — comparing actual vs target distance
		// across runs with a re-randomised pattern would chase noise.
		const radialSeedRad = Math.random() * Math.PI * 2;
		const maxAttempts = 3;

		for (let attempt = 0; attempt < maxAttempts; attempt++) {
			// Capture before the iteration's mutations so we can detect a
			// non-gated interruption (Esc / drag / right-click / Ctrl+Z)
			// that fired during the awaited recalculateRoute. Those paths
			// bump routeVersion via invalidateCalculatedRoute or directly;
			// recalculateRoute bumps it exactly once. So a healthy
			// iteration ends with routeVersion === beforeIter + 1. Anything
			// greater means someone else mutated mid-flight — bail
			// instead of overwriting their state on the next iteration.
			const beforeIter = routeVersion;

			const newWaypoints = generateLoopWaypoints({
				start,
				end: endAt,
				targetDistanceM,
				scaleFactor,
				radialSeedRad,
			});

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

			if (routeVersion !== beforeIter + 1) return false;

			if (routeCoordinates.length < 2) break;

			let actualDistance = 0;
			for (let i = 1; i < routeCoordinates.length; i++) {
				actualDistance += haversine(routeCoordinates[i - 1], routeCoordinates[i]);
			}

			if (isWithinAcceptBand(targetDistanceM, actualDistance)) break;
			// nextScaleFactor clamps the per-step adjustment and the
			// absolute output so a degenerate first attempt (waypoints
			// clumped near start → tiny actualDistance → huge raw ratio)
			// can't push the next attempt's waypoints off the map. This
			// is the bug a user reported when they set start ≈ end and
			// the generator drew a route 2km north of both pins.
			scaleFactor = nextScaleFactor(scaleFactor, targetDistanceM, actualDistance);
		}

		updateStraightLine();
		return routeCoordinates.length >= 2;
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
