<script lang="ts">
	import { onMount, onDestroy, untrack } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	import { getUnit } from '$lib/format/units.svelte';
	import { getMapStyle, mapStyleUrlFromEnv as mapStyleUrl } from '$lib/routes/map-style.svelte';
	import { watchMapResize } from '$lib/routes/map_resize';
	import { minMax } from '$lib/util/min_max';
	import type { TrackPoint } from '$lib/types';
	import {
		buildPaceSegments,
		hasTrackTimestamps,
		type ActivityKind,
	} from '$lib/segments/pace_segments';
	import { snapToPolyline } from '$lib/routes/route_snap';
	import {
		haversineMetres as haversine,
		buildTrackIndex,
		nearestIndex,
		type TrackIndex,
	} from '$lib/routes/nearest_track_point';

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

	/// A course marker to paint on the map. `color` is the shared hex from
	/// ROUTE_MARKER_KINDS so a pin matches the schedule list + the mobile twin.
	export interface MapMarkerPin {
		id: string;
		label: string;
		color: string;
		lat: number;
		lng: number;
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
		/// When `true`, the component will NOT instantiate maplibregl
		/// until the user explicitly accepts loading the map. Anonymous
		/// public pages (/share/run/[id], /share/route/[id]) pass true
		/// per audit/cookie-consent (2026-05-25): MapTiler logs the
		/// requester IP per tile fetch, so we cannot auto-initialise
		/// before the visitor has consented. Authenticated surfaces
		/// leave this false — those callers reach the component via a
		/// signed-in session where consent is implicit.
		requireExplicitConsent?: boolean;
		/// Course markers (aid stations, cutoffs, …) to paint along the
		/// route line as coloured pins with a label. Each carries its own
		/// shared hex `color` (from ROUTE_MARKER_KINDS). Empty / absent =
		/// no marker layer. Updates reactively as the editor adds/removes.
		markers?: MapMarkerPin[];
		/// When true, a map click reports its lng/lat up via `onMarkerPlace`
		/// (the marker-editor "click to drop a pin" mode) instead of doing
		/// segment selection.
		markerEditable?: boolean;
		onMarkerPlace?: (lngLat: { lng: number; lat: number }) => void;
		onMarkerClick?: (id: string) => void;
		/// When true, the pins in `markers` render as draggable DOM markers
		/// (owner edit affordance) rather than the static GeoJSON circle
		/// layer: grab a pin to reposition it, click to open it. The route
		/// owner gets this; everyone else keeps the lightweight circle layer.
		draggablePins?: boolean;
		/// Fired when an existing pin's drag ends, with its new (possibly
		/// snapped) position. The host persists it.
		onMarkerDrag?: (id: string, lngLat: { lng: number; lat: number }) => void;
		/// The marker being added / edited, rendered as a single distinct
		/// pulsing draggable pin separate from the saved `markers`. Dragging
		/// it (or clicking the map) reports up via `onMarkerPlace`. Null =
		/// nothing in flight.
		draftMarker?: MapMarkerPin | null;
		/// When true, placement clicks + pin drags snap to the nearest point
		/// on the route line so a course marker sticks to the course. The
		/// snap is purely the rendered lng/lat; `position_m` is still derived
		/// server-side from routes.geom.
		snapToRoute?: boolean;
	}
	let {
		track = [],
		animatable = false,
		onSegmentSelect,
		totalDistanceM,
		activity,
		hoverIdx = null,
		previewLngLat = null,
		requireExplicitConsent = false,
		markers = [],
		markerEditable = false,
		onMarkerPlace,
		onMarkerClick,
		draggablePins = false,
		onMarkerDrag,
		draftMarker = null,
		snapToRoute = false,
	}: Props = $props();

	import { hasAcceptedConsent } from '$lib/settings/consent.svelte';
	// Drives the placeholder ↔ map swap. MapTiler logs the requester IP
	// per tile fetch, so we never auto-instantiate maplibregl before the
	// user has accepted the cookie banner — on authenticated surfaces too
	// (audit/gdpr May 2026 High: "implicit consent" for signed-in users
	// is not a lawful basis under ePrivacy Art 5(3)). Anon callers
	// (`requireExplicitConsent`) always start gated; authed callers start
	// gated unless consent is already on record this session.
	let mapConsented = $state(untrack(() => (requireExplicitConsent ? false : hasAcceptedConsent())));

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;

	const METRES_PER_MILE = 1609.344;

	function buildMarkerFeatures(
		pins: MapMarkerPin[]
	): GeoJSON.FeatureCollection<GeoJSON.Point, { id: string; label: string; color: string }> {
		return {
			type: 'FeatureCollection',
			features: pins.map((m) => ({
				type: 'Feature',
				properties: { id: m.id, label: m.label, color: m.color },
				geometry: { type: 'Point', coordinates: [m.lng, m.lat] }
			}))
		};
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

	let mapContainer = $state<HTMLDivElement>();
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
		// If the track row carries non-finite or missing lat/lng,
		// MapLibre projects it to (0,0) and the marker sticks to the
		// map div's top-left corner. Bail before `setLngLat` so the
		// marker is cleanly absent rather than stuck in the corner.
		if (
			!p ||
			!Number.isFinite(p.lng) ||
			!Number.isFinite(p.lat)
		) {
			hoverMarker?.remove();
			hoverMarker = undefined;
			return;
		}
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
	/// MapLibre instance. Positioned via the standard MapLibre
	/// `Marker`, which keeps the dot pinned to the route line through
	/// any pan/zoom for free. Twin of the `previewPosition` marker on
	/// Flutter's `LiveRunMap`.
	let previewMarker: maplibregl.Marker | undefined;

	function renderPreviewMarker(lngLat: [number, number] | null): void {
		if (!map) return;
		// A null / non-finite position projects to (0,0) and pins the
		// dot to the map's top-left corner — drop it instead.
		if (
			lngLat == null ||
			!Number.isFinite(lngLat[0]) ||
			!Number.isFinite(lngLat[1])
		) {
			previewMarker?.remove();
			previewMarker = undefined;
			return;
		}
		if (!previewMarker) {
			const el = document.createElement('div');
			el.className = 'hover-marker';
			el.setAttribute('data-testid', 'route-preview-runner');
			previewMarker = new maplibregl.Marker({ element: el }).setLngLat(lngLat).addTo(map);
		} else {
			previewMarker.setLngLat(lngLat);
		}
	}

	$effect(() => {
		renderPreviewMarker(previewLngLat);
	});

	/// Cumulative distance from start to each track index, in metres.
	/// Computed once when the track is mounted.
	let cumulativeM: number[] = [];

	function buildCumulative(coords: [number, number][]): number[] {
		const out = new Array(coords.length).fill(0);
		for (let i = 1; i < coords.length; i++) {
			out[i] = out[i - 1] + haversine(coords[i - 1], coords[i]);
		}
		return out;
	}

	/// Spatial index over the track for tap-to-select. Built once with
	/// `cumulativeM` when the track mounts so per-tap nearest-point
	/// lookup stays bounded on a 150k+-point ultra track (a plain linear
	/// scan visibly lagged); small tracks fall through to an exact
	/// linear scan inside `nearestIndex`.
	let trackIndex: TrackIndex = { coords: [], grid: null };

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

		const distanceMarkers = computeDistanceMarkers(coords);
		if (distanceMarkers.features.length > 0) {
			map.addSource('distance-markers', {
				type: 'geojson',
				data: distanceMarkers,
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

		// Course markers (aid stations, cutoffs, …). Coloured pins above the
		// trace with an optional label; updated reactively by the $effect
		// below as the editor adds / removes them.
		map.addSource('route-markers', {
			type: 'geojson',
			data: buildMarkerFeatures(markers),
		});
		map.addLayer({
			id: 'route-marker-bg',
			type: 'circle',
			source: 'route-markers',
			paint: {
				'circle-radius': 8,
				'circle-color': ['get', 'color'],
				'circle-stroke-color': '#FFFFFF',
				'circle-stroke-width': 2,
			},
		});
		map.addLayer({
			id: 'route-marker-label',
			type: 'symbol',
			source: 'route-markers',
			layout: {
				'text-field': ['get', 'label'],
				'text-size': 11,
				'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
				'text-offset': [0, 1.1],
				'text-anchor': 'top',
				'text-optional': true,
			},
			paint: {
				'text-color': prefersDark ? '#F1F5F9' : '#1E293B',
				'text-halo-color': prefersDark ? '#0F172A' : '#FFFFFF',
				'text-halo-width': 1.5,
			},
		});

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
		// Honour the global banner choice on every surface: if the user
		// has already accepted the cookie banner, auto-init the map
		// (consent is on record) and skip the per-view "Load map" tap.
		if (hasAcceptedConsent()) mapConsented = true;
		trackCoords = track.map((p) => [p.lng, p.lat]);

		if (trackCoords.length > 0) {
			// Reduce, don't spread: `Math.min(...lngs)` throws RangeError past
			// ~110k args and an ultra track is ~180k points.
			const lng = minMax(trackCoords.map((c) => c[0]));
			const lat = minMax(trackCoords.map((c) => c[1]));
			if (lng && lat) {
				trackBounds = [
					[lng.min, lat.min],
					[lng.max, lat.max]
				];
			}
		}

		if (!mapConsented) return; // Wait for the user to tap "Load map".
		initMap();
	});

	function loadMapNow() {
		mapConsented = true;
		// $effect below would normally pick this up, but the map
		// container only mounts when `mapConsented` flips, so wait one
		// microtask for the DOM to render before initialising.
		queueMicrotask(initMap);
	}

	function initMap() {
		if (map || !mapContainer) return;
		map = new maplibregl.Map({
			container: mapContainer,
			style: mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark),
			center: trackCoords.length > 0 ? trackCoords[Math.floor(trackCoords.length / 2)] : [0, 20],
			zoom: 13
		});
		// Resize-on-container-change wiring — catches the
		// flex-mismeasure-at-mount + SplitPane-drag bugs. See
		// `$lib/routes/map_resize`.
		stopResizeWatch = watchMapResize(mapContainer, map);

		map.addControl(new maplibregl.NavigationControl(), 'top-right');

		cumulativeM = buildCumulative(trackCoords);
		trackIndex = buildTrackIndex(trackCoords);

		map.on('load', () => addOverlays(trackCoords, trackBounds, true));
		// The entrance fitBounds (inside the load handler above) animates the
		// camera, so a pin's screen position keeps moving for a beat after it
		// first renders. `idle` fires only once tiles are loaded AND no camera
		// animation is in flight — stamp it on the container so pointer-driven
		// tests (marker drag) can wait for a settled map instead of racing the
		// animation. Registered before `load` can fire; `idle` cannot precede
		// it because fitBounds is called synchronously inside the load handler.
		map.once('idle', () => mapContainer?.setAttribute('data-map-idle', 'true'));

		// Segment-detail click handler. Snaps to the nearest track point,
		// builds a ±150 m window, and reports stats up to the host.
		// Repeat clicks update the highlight; clicking outside the
		// trace area still snaps to whatever's closest, which matches
		// the runner's likely intent ("show me the bit near here").
		if (onSegmentSelect || onMarkerPlace) {
			map.on('click', (e) => {
				// Marker-editor mode: a click either selects an existing pin
				// (so the host can edit / delete it) or drops a new one.
				// Takes priority over segment selection while editing.
				if (markerEditable && onMarkerPlace) {
					const hits = map.queryRenderedFeatures(e.point, { layers: ['route-marker-bg'] });
					if (hits.length > 0) {
						const id = hits[0].properties?.id;
						if (id && onMarkerClick) onMarkerClick(String(id));
						return;
					}
					onMarkerPlace(maybeSnap(e.lngLat.lng, e.lngLat.lat));
					return;
				}
				if (!onSegmentSelect) return;
				if (trackCoords.length < 2) return;
				const idx = nearestIndex(trackIndex, e.lngLat.lng, e.lngLat.lat);
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
	}

	// ─────────────────── Draggable course-marker pins ───────────────────
	// In owner edit mode the saved pins + the in-flight draft render as
	// real DOM markers (draggable, clickable) instead of the static GeoJSON
	// circle layer, so the owner can drag a pin to reposition it and the
	// drop snaps to the route line. Read-only viewers keep the lightweight
	// circle layer (cheaper, no per-pin DOM).

	/// Snap a free lng/lat to the route line when snapping is on and there
	/// is a line to snap to; otherwise pass it through untouched.
	function maybeSnap(lng: number, lat: number): { lng: number; lat: number } {
		if (snapToRoute && trackCoords.length >= 2) {
			const s = snapToPolyline({ lng, lat }, trackCoords);
			if (s) return { lng: s.lng, lat: s.lat };
		}
		return { lng, lat };
	}

	function buildPinElement(color: string, label: string, draft: boolean): HTMLDivElement {
		const el = document.createElement('div');
		el.className = draft ? 'course-pin draft' : 'course-pin';
		const dot = document.createElement('span');
		dot.className = 'course-pin-dot';
		dot.style.background = color;
		el.appendChild(dot);
		const text = document.createElement('span');
		text.className = 'course-pin-label';
		text.textContent = label;
		el.appendChild(text);
		el.title = label;
		return el;
	}

	function updatePinElement(el: HTMLElement, color: string, label: string): void {
		const dot = el.querySelector('.course-pin-dot') as HTMLElement | null;
		if (dot) dot.style.background = color;
		const text = el.querySelector('.course-pin-label') as HTMLElement | null;
		if (text) text.textContent = label;
		el.title = label;
	}

	const pinMarkers = new Map<string, maplibregl.Marker>();

	function wirePinEvents(mk: maplibregl.Marker, id: string, el: HTMLElement): void {
		let dragged = false;
		mk.on('dragstart', () => {
			dragged = true;
			el.classList.add('dragging');
		});
		mk.on('dragend', () => {
			el.classList.remove('dragging');
			const ll = mk.getLngLat();
			const snapped = maybeSnap(ll.lng, ll.lat);
			mk.setLngLat([snapped.lng, snapped.lat]);
			onMarkerDrag?.(id, snapped);
			// Let the post-drag synthetic click pass before re-enabling
			// click-to-edit, so a drag never also opens the editor.
			setTimeout(() => {
				dragged = false;
			}, 0);
		});
		el.addEventListener('click', (ev) => {
			ev.stopPropagation();
			if (dragged) return;
			onMarkerClick?.(id);
		});
	}

	function syncPinMarkers(pins: MapMarkerPin[]): void {
		if (!map) return;
		const seen = new Set<string>();
		for (const pin of pins) {
			seen.add(pin.id);
			let mk = pinMarkers.get(pin.id);
			if (!mk) {
				const el = buildPinElement(pin.color, pin.label, false);
				mk = new maplibregl.Marker({ element: el, draggable: true, anchor: 'center' });
				mk.setLngLat([pin.lng, pin.lat]).addTo(map);
				wirePinEvents(mk, pin.id, el);
				pinMarkers.set(pin.id, mk);
			} else {
				mk.setLngLat([pin.lng, pin.lat]);
				updatePinElement(mk.getElement(), pin.color, pin.label);
			}
		}
		for (const [id, mk] of pinMarkers) {
			if (!seen.has(id)) {
				mk.remove();
				pinMarkers.delete(id);
			}
		}
	}

	let draftMk: maplibregl.Marker | undefined;

	function renderDraftMarker(pin: MapMarkerPin | null): void {
		if (!map) return;
		if (!pin || !Number.isFinite(pin.lng) || !Number.isFinite(pin.lat)) {
			draftMk?.remove();
			draftMk = undefined;
			return;
		}
		if (!draftMk) {
			const el = buildPinElement(pin.color, pin.label, true);
			draftMk = new maplibregl.Marker({ element: el, draggable: true, anchor: 'center' });
			draftMk.setLngLat([pin.lng, pin.lat]).addTo(map);
			draftMk.on('dragend', () => {
				const ll = draftMk!.getLngLat();
				const s = maybeSnap(ll.lng, ll.lat);
				draftMk!.setLngLat([s.lng, s.lat]);
				onMarkerPlace?.(s);
			});
		} else {
			draftMk.setLngLat([pin.lng, pin.lat]);
			updatePinElement(draftMk.getElement(), pin.color, pin.label);
		}
	}

	// Keep the route-markers layer in sync as the editor adds / moves /
	// removes pins. Owner edit mode (draggablePins) renders the saved pins
	// as DOM markers and empties the circle layer; read-only viewers keep
	// the circle layer. Reads `markers` + `draggablePins` so it re-runs on
	// any change.
	$effect(() => {
		if (!map) return;
		const circleData = buildMarkerFeatures(draggablePins ? [] : markers);
		const src = map.getSource('route-markers') as maplibregl.GeoJSONSource | undefined;
		src?.setData(circleData);
		syncPinMarkers(draggablePins ? markers : []);
	});

	$effect(() => {
		renderDraftMarker(draftMarker);
	});

	// Cursor hint while placing: a crosshair signals "click the map to drop
	// the pin". Route detail has no segment-select handler so this never
	// fights the trace-line pointer cursor.
	$effect(() => {
		if (!map) return;
		map.getCanvas().style.cursor = markerEditable ? 'crosshair' : '';
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
		previewMarker?.remove();
		previewMarker = undefined;
		for (const mk of pinMarkers.values()) mk.remove();
		pinMarkers.clear();
		draftMk?.remove();
		draftMk = undefined;
		map?.remove();
	});
</script>

<!--
	audit/accessibility (May 2026) Medium — WCAG 1.1.1 + EAA. The
	map canvas was an unlabelled <div>; screen readers had no way
	to identify the region. role="region" + aria-label makes it a
	named landmark so AT users can skip past or into it. The
	companion text alternative for the map's actual data — runs
	list on /runs, segment leaderboards on /routes/[id] — lives on
	the same page already, so a "view as table" toggle here would
	be redundant.
-->
<div class="run-map-wrapper" role="region" aria-label={m('runMap.regionLabel')}>
	{#if mapConsented}
		<div bind:this={mapContainer} class="run-map" aria-hidden="true"></div>
		{#if animatable}
			<button class="replay-btn" onclick={() => animating ? stopAnimation() : startAnimation()}>
				<span class="material-symbols">{animating ? 'stop' : 'play_arrow'}</span>
				{animating ? m('runMap.stop') : m('runMap.replay')}
			</button>
		{/if}
	{:else}
		<!--
			audit/cookie-consent (2026-05-25): MapTiler logs the
			requester IP per tile fetch. Anonymous visitors must opt
			in explicitly before the map mounts. "Load map" satisfies
			the affirmative-act requirement under ePrivacy + GDPR.
		-->
		<div class="run-map-consent">
			<div class="run-map-consent-card">
				<h2>{m('runMap.consentTitle')}</h2>
				<p>
					{m('runMap.consentPrefix')}<strong>MapTiler</strong>{m('runMap.consentMiddle')}<strong>{m('runMap.loadMap')}</strong>{m('runMap.consentBeforeLink')}<a href="/cookie-notice">{m('runMap.cookieNotice')}</a>{m('runMap.consentSuffix')}
				</p>
				<button type="button" class="btn btn-primary" onclick={loadMapNow}>
					{m('runMap.loadMap')}
				</button>
			</div>
		</div>
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
	.run-map-consent {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 100%;
		height: 100%;
		background: var(--color-bg);
		padding: var(--space-md);
	}
	.run-map-consent-card {
		max-width: 30rem;
		padding: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-md);
		text-align: start;
	}
	.run-map-consent-card h2 { margin: 0 0 var(--space-sm); font-size: 1.1rem; }
	.run-map-consent-card p {
		margin: 0 0 var(--space-md);
		color: var(--color-text-secondary);
		line-height: 1.5;
		font-size: 0.92rem;
	}

	.replay-btn {
		position: absolute;
		bottom: 12px;
		inset-inline-start: 12px;
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

	/* Linked-cursor marker (chart hover → map) + route-preview scrubber
	   dot. Same accent as the segment pin so the visual language stays
	   consistent, but slightly smaller + pulsing so the user can tell
	   it's a cursor, not a manually-selected segment.

	   The pulse animates `box-shadow`, NOT `transform`: MapLibre's
	   Marker positions this element by writing `transform: translate(...)`
	   onto it, and a CSS animation on `transform` outranks that inline
	   style in the cascade — which collapsed the dot to the map's
	   top-left corner. Pulsing the ring keeps the positioning transform
	   untouched. */
	:global(.hover-marker) {
		width: 12px;
		height: 12px;
		border-radius: 50%;
		background: var(--color-primary, #3b82f6);
		border: 2px solid white;
		box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.35), 0 1px 4px rgba(0, 0, 0, 0.3);
		pointer-events: none;
		animation: hover-marker-pulse 1.6s ease-in-out infinite;
	}
	@keyframes hover-marker-pulse {
		0%, 100% { box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.35), 0 1px 4px rgba(0, 0, 0, 0.3); }
		50% { box-shadow: 0 0 0 7px rgba(59, 130, 246, 0.12), 0 1px 4px rgba(0, 0, 0, 0.3); }
	}

	/* Draggable course-marker pins (owner edit mode). A coloured dot that
	   matches the read-only circle layer, plus a label chip under it. The
	   element wraps both so MapLibre's positioning transform stays on the
	   wrapper and the grab cursor covers the whole hit area. */
	/* The element's layout box is just the dot, so MapLibre's `anchor:
	   center` lands the dot exactly on the coordinate (= on the route
	   line). The label floats below via absolute positioning so it never
	   shifts the dot. MapLibre owns the root element's inline `transform`,
	   so the dot's hover-scale lives on the inner dot, not here. */
	:global(.course-pin) {
		position: relative;
		width: 1rem;
		height: 1rem;
		cursor: grab;
	}
	:global(.course-pin.dragging),
	:global(.course-pin:active) {
		cursor: grabbing;
	}
	:global(.course-pin-dot) {
		display: block;
		width: 100%;
		height: 100%;
		border-radius: 50%;
		border: 2px solid #ffffff;
		box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.15), 0 2px 6px rgba(0, 0, 0, 0.35);
		transition: transform 0.12s ease;
	}
	:global(.course-pin:hover .course-pin-dot) {
		transform: scale(1.2);
	}
	:global(.course-pin-label) {
		position: absolute;
		top: calc(100% + 2px);
		left: 50%;
		transform: translateX(-50%);
		max-width: 9rem;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: 0.7rem;
		font-weight: 700;
		color: #1e293b;
		text-shadow:
			0 0 2px #ffffff, 0 0 2px #ffffff, 0 0 3px #ffffff, 0 0 4px #ffffff;
		pointer-events: none;
	}
	:global(.course-pin.draft .course-pin-dot) {
		animation: course-pin-pulse 1.5s ease-in-out infinite;
	}
	@keyframes course-pin-pulse {
		0%, 100% {
			box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.45), 0 2px 6px rgba(0, 0, 0, 0.35);
		}
		50% {
			box-shadow: 0 0 0 7px rgba(59, 130, 246, 0.12), 0 2px 6px rgba(0, 0, 0, 0.35);
		}
	}
	@media (prefers-color-scheme: dark) {
		:global(.course-pin-label) {
			color: #f1f5f9;
			text-shadow:
				0 0 2px #0f172a, 0 0 2px #0f172a, 0 0 3px #0f172a, 0 0 4px #0f172a;
		}
	}
</style>
