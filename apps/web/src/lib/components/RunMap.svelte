<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	import { getUnit } from '$lib/units.svelte';
	import { getMapStyle, mapStyleUrlFromEnv as mapStyleUrl } from '$lib/map-style.svelte';
	import { watchMapResize } from '$lib/map_resize';
	import type { TrackPoint } from '$lib/types';
	import {
		buildPaceSegments,
		hasTrackTimestamps,
		type ActivityKind,
	} from '$lib/pace_segments';

	/// Segment-detail callback. When set, clicks anywhere on the map
	/// snap to the nearest track point, compute a small window (±150 m
	/// of cumulative track distance) around it, and fire `onSegmentSelect`
	/// with stats for that window. The host page renders the popup. Set
	/// to `null` from the host to clear the highlight.
	export interface SelectedSegment {
		startIdx: number;
		endIdx: number;
		clickIdx: number;
		distance_m: number;
		duration_s: number | null;
		avg_pace_sec_per_km: number | null;
		avg_bpm: number | null;
		ele_gain_m: number;
		ele_loss_m: number;
		mid: TrackPoint;
	}

	interface Props {
		track: TrackPoint[];
		animatable?: boolean;
		onSegmentSelect?: (seg: SelectedSegment | null) => void;
		/// When provided AND the polyline distance is shorter than the
		/// authoritative route distance, scale the marker positions so
		/// the count matches reality. Routes saved with sparse user
		/// clicks (legacy + seed data) draw a polyline that under-
		/// represents the real route length; without scaling, a 6.34mi
		/// route can render with only one mile-marker because the
		/// straight-line polyline is just 1.5mi long.
		totalDistanceM?: number;
		/// When set (and the track carries per-point timestamps), the
		/// trace renders as a per-segment NRC-style pace heatmap instead
		/// of the single indigo line. Activity scales the speed
		/// breakpoints so a 5:00/km run and a 25 km/h ride both land
		/// mid-ramp. Routes (which never carry timestamps) and
		/// imports without `ts` fall through to the legacy single-line
		/// render.
		activity?: ActivityKind;
		/// Linked-cursor index (Nike/Strava-style). When non-null AND in
		/// range of `track`, paint a small pulsing marker at that point
		/// on the polyline. Driven by the elevation/pace chart's
		/// pointer hover via the parent. Null = no marker.
		hoverIdx?: number | null;
		/// Free-form "runner" position for the route-detail scrubber.
		/// When non-null, paints a pulsing marker at this [lng, lat].
		/// Independent of `hoverIdx` — that's an index into `track`,
		/// this is a free position interpolated along an arbitrary
		/// polyline (via `interpolateAlongRoute` in `route_geometry.ts`).
		/// Twin of the `previewPosition` prop on Flutter's
		/// `LiveRunMap`. Null = no marker.
		previewLngLat?: [number, number] | null;
	}
	let {
		track = [],
		animatable = false,
		onSegmentSelect,
		totalDistanceM,
		activity,
		hoverIdx = null,
		previewLngLat = null,
	}: Props = $props();

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

		// Total polyline length — used both as the iteration bound and
		// as the denominator for the legacy-sparse-waypoints rescale
		// path below.
		let polylineTotal = 0;
		for (let i = 1; i < coords.length; i++) {
			polylineTotal += haversine(coords[i - 1], coords[i]);
		}

		// When the authoritative route distance is meaningfully greater
		// than what the polyline measures (sparse user clicks / seed
		// data), scale every marker's *along-the-polyline* position by
		// `polyline / real`. The marker count then reflects the real
		// distance even though the rendered geometry is a coarse
		// approximation.
		const realTotal = totalDistanceM && totalDistanceM > polylineTotal * 1.1
			? totalDistanceM
			: polylineTotal;
		const scale = polylineTotal > 0 ? polylineTotal / realTotal : 1;

		let cumulative = 0;
		let nextMarker = stepM * scale;
		const maxAlongPolyline = polylineTotal;
		for (let i = 1; i < coords.length; i++) {
			const segmentM = haversine(coords[i - 1], coords[i]);
			while (
				cumulative + segmentM >= nextMarker &&
				segmentM > 0 &&
				nextMarker <= maxAlongPolyline + 0.5
			) {
				const t = (nextMarker - cumulative) / segmentM;
				const lng = coords[i - 1][0] + (coords[i][0] - coords[i - 1][0]) * t;
				const lat = coords[i - 1][1] + (coords[i][1] - coords[i - 1][1]) * t;
				const realPos = nextMarker / scale;
				const idx = Math.round(realPos / stepM);
				features.push({
					type: 'Feature',
					geometry: { type: 'Point', coordinates: [lng, lat] },
					properties: { label: String(idx) },
				});
				nextMarker += stepM * scale;
			}
			cumulative += segmentM;
		}
		return { type: 'FeatureCollection', features };
	}

	let mapContainer: HTMLDivElement;
	let map: maplibregl.Map;
	let stopResizeWatch: (() => void) | null = null;
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

	let startMarker: maplibregl.Marker | undefined;
	let endMarker: maplibregl.Marker | undefined;
	let segmentMarker: maplibregl.Marker | undefined;
	/// Marker rendered at track[hoverIdx] when hoverIdx is in range —
	/// the chart-driven half of the linked-cursor pattern. Held as an
	/// instance handle so we mutate position rather than rebuild on
	/// every pointermove tick.
	let hoverMarker: maplibregl.Marker | undefined;

	/// Render or update the hover-marker. Called from a $effect so any
	/// change to `hoverIdx` or `track` re-paints it. `track[i]` is the
	/// authoritative position; the chart's idx-space is identical to
	/// the track's because /runs/[id] derives elevations 1:1 from the
	/// same baseTrack.
	function renderHoverMarker(idx: number | null): void {
		if (!map) return;
		if (idx == null || idx < 0 || idx >= track.length) {
			hoverMarker?.remove();
			hoverMarker = undefined;
			return;
		}
		const p = track[idx];
		// Defensive (same reasoning as renderPreviewMarker): if the
		// track row carries non-finite or missing lat/lng, MapLibre's
		// `translate3d` projector silently collapses to (0,0) and the
		// marker sticks to the map div's top-left corner. Bail before
		// `setLngLat` so the marker is cleanly absent rather than
		// stuck in the corner.
		if (
			!p ||
			!Number.isFinite(p.lng) ||
			!Number.isFinite(p.lat)
		) {
			hoverMarker?.remove();
			hoverMarker = undefined;
			return;
		}
		// Same defensive resize as renderPreviewMarker — see comment
		// there for the stale-projection rationale.
		map.resize();
		const at: [number, number] = [p.lng, p.lat];
		if (!hoverMarker) {
			const el = document.createElement('div');
			el.className = 'hover-marker';
			el.setAttribute('data-testid', 'chart-hover-marker');
			hoverMarker = new maplibregl.Marker({ element: el }).setLngLat(at).addTo(map);
		} else {
			hoverMarker.setLngLat(at);
		}
	}

	$effect(() => {
		renderHoverMarker(hoverIdx);
	});

	/// Separate handle for the scrubber preview marker so it can
	/// coexist with the hover-marker without one stealing the other's
	/// MapLibre instance.
	let previewMarker: maplibregl.Marker | undefined;

	function renderPreviewMarker(lngLat: [number, number] | null): void {
		if (!map) return;
		// Filter NaN / non-finite coordinates defensively. MapLibre's
		// translate3d projector silently collapses non-finite values to
		// the marker container's origin (top-left of the map div) —
		// caught when the scrubber appeared to "place the marker at
		// the top-left of the map". Treat invalid as "no marker".
		if (
			lngLat == null ||
			!Number.isFinite(lngLat[0]) ||
			!Number.isFinite(lngLat[1])
		) {
			previewMarker?.remove();
			previewMarker = undefined;
			return;
		}
		// Force MapLibre to resync its internal projection with the
		// current container size BEFORE projecting the marker. The
		// user reported the marker stuck at the top-left of the map
		// even after the NaN guard was in place — root cause is a
		// stale transform (the map's projection is computed against
		// an older container size, so projecting the lat/lng to
		// pixel coords produces a value that lands at the corner of
		// the visible canvas). `.resize()` is cheap (no actual
		// re-render unless the size differs) and idempotent.
		map.resize();
		if (!previewMarker) {
			const el = document.createElement('div');
			el.className = 'hover-marker';
			el.setAttribute('data-testid', 'route-preview-runner');
			previewMarker = new maplibregl.Marker({ element: el })
				.setLngLat(lngLat)
				.addTo(map);
		} else {
			previewMarker.setLngLat(lngLat);
		}
	}

	$effect(() => {
		renderPreviewMarker(previewLngLat);
	});

	/// Cumulative distance from start to each track index, in metres.
	/// Computed once when the track is mounted; lookups are O(log n) by
	/// linear scan since tracks are typically <2k points.
	let cumulativeM: number[] = [];

	function buildCumulative(coords: [number, number][]): number[] {
		const out = new Array(coords.length).fill(0);
		for (let i = 1; i < coords.length; i++) {
			out[i] = out[i - 1] + haversine(coords[i - 1], coords[i]);
		}
		return out;
	}

	/// Find the nearest track index to a click point. Linear scan — the
	/// runs we render top out around 2k points, well below the cost of
	/// building a spatial index.
	function nearestTrackIdx(lng: number, lat: number, coords: [number, number][]): number {
		let bestIdx = 0;
		let bestDist = Infinity;
		for (let i = 0; i < coords.length; i++) {
			const d = haversine([lng, lat], coords[i]);
			if (d < bestDist) {
				bestDist = d;
				bestIdx = i;
			}
		}
		return bestIdx;
	}

	/// Build a segment of the track centred on `clickIdx`, expanding
	/// outwards until the distance window (±150 m of cumulative track
	/// length) is reached. Computes pace + HR + elevation deltas.
	const SEGMENT_RADIUS_M = 150;

	function buildSegment(clickIdx: number): SelectedSegment | null {
		if (track.length < 2 || cumulativeM.length !== track.length) return null;
		const target = cumulativeM[clickIdx];
		let startIdx = clickIdx;
		while (startIdx > 0 && cumulativeM[startIdx - 1] >= target - SEGMENT_RADIUS_M) startIdx--;
		let endIdx = clickIdx;
		while (
			endIdx < cumulativeM.length - 1 &&
			cumulativeM[endIdx + 1] <= target + SEGMENT_RADIUS_M
		)
			endIdx++;
		if (startIdx === endIdx) {
			// Edge of the track — widen by one neighbour so we have a real
			// segment rather than a single-point degenerate.
			if (endIdx < cumulativeM.length - 1) endIdx++;
			else if (startIdx > 0) startIdx--;
		}

		const distance_m = cumulativeM[endIdx] - cumulativeM[startIdx];

		// Duration + pace come from per-point timestamps when present.
		const startTs = track[startIdx]?.ts;
		const endTs = track[endIdx]?.ts;
		let duration_s: number | null = null;
		let avg_pace_sec_per_km: number | null = null;
		if (startTs && endTs) {
			const dt = (Date.parse(endTs) - Date.parse(startTs)) / 1000;
			if (Number.isFinite(dt) && dt > 0) {
				duration_s = Math.round(dt);
				if (distance_m > 10) {
					avg_pace_sec_per_km = Math.round(dt / (distance_m / 1000));
				}
			}
		}

		// HR + elevation deltas walk only the segment slice.
		let bpmSum = 0;
		let bpmCount = 0;
		let eleGain = 0;
		let eleLoss = 0;
		for (let i = startIdx; i <= endIdx; i++) {
			const b = track[i]?.bpm;
			if (typeof b === 'number' && b >= 30 && b <= 230) {
				bpmSum += b;
				bpmCount++;
			}
			if (i > startIdx) {
				const prev = track[i - 1]?.ele;
				const cur = track[i]?.ele;
				if (typeof prev === 'number' && typeof cur === 'number') {
					const delta = cur - prev;
					if (delta > 0) eleGain += delta;
					else eleLoss += -delta;
				}
			}
		}

		return {
			startIdx,
			endIdx,
			clickIdx,
			distance_m,
			duration_s,
			avg_pace_sec_per_km,
			avg_bpm: bpmCount > 0 ? Math.round(bpmSum / bpmCount) : null,
			ele_gain_m: Math.round(eleGain),
			ele_loss_m: Math.round(eleLoss),
			mid: track[clickIdx],
		};
	}

	/// Update / re-create the highlighted segment overlay on the map.
	/// Idempotent — safe to call repeatedly with different segments.
	function renderSegmentHighlight(seg: SelectedSegment | null) {
		if (!map) return;
		const src = map.getSource('selected-segment') as maplibregl.GeoJSONSource | undefined;
		if (!seg) {
			src?.setData({ type: 'FeatureCollection', features: [] });
			segmentMarker?.remove();
			segmentMarker = undefined;
			return;
		}
		const slice = trackCoords.slice(seg.startIdx, seg.endIdx + 1);
		src?.setData({
			type: 'Feature',
			properties: {},
			geometry: { type: 'LineString', coordinates: slice },
		});
		const at: [number, number] = [seg.mid.lng, seg.mid.lat];
		if (!segmentMarker) {
			const el = document.createElement('div');
			el.className = 'segment-pin';
			segmentMarker = new maplibregl.Marker({ element: el }).setLngLat(at).addTo(map);
		} else {
			segmentMarker.setLngLat(at);
		}
	}

	// Re-add every custom source/layer/marker the component owns. Called
	// after the initial style load and again whenever the user picks a
	// new map style (setStyle wipes user layers but leaves DOM markers).
	function addOverlays(coords: [number, number][], bounds: maplibregl.LngLatBoundsLike | undefined, fit: boolean) {
		if (coords.length < 2) return;
		if (fit && bounds) map.fitBounds(bounds, { padding: 50 });

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

		// Pace heatmap when the host knows the activity AND the track
		// carries per-point timestamps; otherwise fall back to the
		// single indigo line. Mirrors the mobile behaviour
		// (`apps/mobile_android/lib/widgets/live_run_map.dart`) so a
		// run looks the same on web and on mobile.
		const heatmap = activity && hasTrackTimestamps(track)
			? buildPaceSegments(track, activity)
			: [];
		if (heatmap.length > 0) {
			map.addSource('trace-pace', {
				type: 'geojson',
				data: {
					type: 'FeatureCollection',
					features: heatmap.map((s) => ({
						type: 'Feature',
						properties: { color: s.color },
						geometry: { type: 'LineString', coordinates: s.coords },
					})),
				},
			});
			map.addLayer({
				id: 'trace-line',
				type: 'line',
				source: 'trace-pace',
				paint: { 'line-color': ['get', 'color'], 'line-width': 4 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
		} else {
			map.addLayer({
				id: 'trace-line',
				type: 'line',
				source: 'trace',
				paint: { 'line-color': prefersDark ? '#818CF8' : '#4F46E5', 'line-width': 3.5 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
		}

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

		if (!startMarker) {
			startMarker = new maplibregl.Marker({ color: '#22c55e' }).setLngLat(coords[0]).addTo(map);
		}
		if (!endMarker) {
			endMarker = new maplibregl.Marker({ color: '#ef4444' }).setLngLat(coords[coords.length - 1]).addTo(map);
		}

		// Empty selected-segment source + layers; populated when the user
		// clicks. Rendered above the base trace so the highlight reads
		// clearly against the underlying line.
		if (onSegmentSelect) {
			map.addSource('selected-segment', {
				type: 'geojson',
				data: { type: 'FeatureCollection', features: [] },
			});
			map.addLayer({
				id: 'selected-segment-casing',
				type: 'line',
				source: 'selected-segment',
				paint: { 'line-color': '#f59e0b', 'line-width': 9, 'line-opacity': 0.35 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
			map.addLayer({
				id: 'selected-segment-line',
				type: 'line',
				source: 'selected-segment',
				paint: { 'line-color': '#f59e0b', 'line-width': 5 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
		}
	}

	let trackCoords: [number, number][] = [];
	let trackBounds: maplibregl.LngLatBoundsLike | undefined;

	onMount(() => {
		trackCoords = track.map((p) => [p.lng, p.lat]);

		if (trackCoords.length > 0) {
			const lngs = trackCoords.map((c) => c[0]);
			const lats = trackCoords.map((c) => c[1]);
			trackBounds = [
				[Math.min(...lngs), Math.min(...lats)],
				[Math.max(...lngs), Math.max(...lats)]
			];
		}

		map = new maplibregl.Map({
			container: mapContainer,
			style: mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark),
			center: trackCoords.length > 0 ? trackCoords[Math.floor(trackCoords.length / 2)] : [0, 20],
			zoom: 13
		});
		// Resize-on-container-change wiring — catches the
		// flex-mismeasure-at-mount + SplitPane-drag bugs. See
		// `$lib/map_resize`.
		stopResizeWatch = watchMapResize(mapContainer, map);

		map.addControl(new maplibregl.NavigationControl(), 'top-right');

		cumulativeM = buildCumulative(trackCoords);

		map.on('load', () => addOverlays(trackCoords, trackBounds, true));

		// Segment-detail click handler. Snaps to the nearest track point,
		// builds a ±150 m window, and reports stats up to the host.
		// Repeat clicks update the highlight; clicking outside the
		// trace area still snaps to whatever's closest, which matches
		// the runner's likely intent ("show me the bit near here").
		if (onSegmentSelect) {
			map.on('click', (e) => {
				if (trackCoords.length < 2) return;
				const idx = nearestTrackIdx(e.lngLat.lng, e.lngLat.lat, trackCoords);
				const seg = buildSegment(idx);
				renderSegmentHighlight(seg);
				onSegmentSelect(seg);
			});
			// Cursor hint: turn into a pointer over the trace so users know
			// it's clickable. Falls back gracefully if either layer hasn't
			// mounted yet.
			map.on('mouseenter', 'trace-line', () => {
				map.getCanvas().style.cursor = 'pointer';
			});
			map.on('mouseleave', 'trace-line', () => {
				map.getCanvas().style.cursor = '';
			});
		}
	});

	// Reactive map-style swap. The first run after `map` is created is
	// a no-op (the style URL already matches); subsequent runs swap the
	// basemap and re-attach the trace + markers once the new style loads.
	let currentStyle: ReturnType<typeof getMapStyle> = getMapStyle();
	$effect(() => {
		const next = getMapStyle();
		if (!map || next === currentStyle) return;
		currentStyle = next;
		map.setStyle(mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark));
		map.once('style.load', () => addOverlays(trackCoords, trackBounds, false));
	});

	onDestroy(() => {
		cancelAnimationFrame(animationFrame);
		stopResizeWatch?.();
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

	:global(.segment-pin) {
		width: 14px;
		height: 14px;
		border-radius: 50%;
		background: #f59e0b;
		border: 3px solid white;
		box-shadow: 0 0 0 2px rgba(245, 158, 11, 0.4), 0 2px 6px rgba(0, 0, 0, 0.35);
	}

	/* Linked-cursor marker (chart hover → map). Same accent as the
	   segment pin so the visual language stays consistent, but slightly
	   smaller + pulsing so the user can tell it's the chart's pointer,
	   not a manually-selected segment. */
	:global(.hover-marker) {
		width: 12px;
		height: 12px;
		border-radius: 50%;
		background: var(--color-primary, #3b82f6);
		border: 2px solid white;
		box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.3), 0 1px 4px rgba(0, 0, 0, 0.3);
		pointer-events: none;
		animation: hover-marker-pulse 1.6s ease-in-out infinite;
	}
	@keyframes hover-marker-pulse {
		0%, 100% { transform: scale(1); }
		50% { transform: scale(1.25); }
	}
</style>
