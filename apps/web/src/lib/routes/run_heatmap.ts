/// Pure aggregation for the personal run-track heatmap (`/runs/heatmap`,
/// persona-hunt finding #53 — privacy / strava-migration). Flattens many
/// of the runner's own GPS tracks into weighted grid cells: repeated
/// routes accumulate weight in the same cell instead of exploding the
/// point count, so the MapLibre heatmap layer can render thousands of
/// runs without shipping every raw sample to the GPU. Kept dependency-
/// free and side-effect-free so it's unit-testable with `tsx --test` —
/// the component layer does the Storage downloads + map wiring.

export interface HeatLatLng {
	lat: number;
	lng: number;
}

export interface HeatCell {
	lat: number;
	lng: number;
	weight: number;
}

/// ~33 m at the equator. Fine enough that distinct streets stay
/// distinct, coarse enough that one route's thousands of samples
/// collapse to a manageable cell count.
export const DEFAULT_GRID_DEG = 0.0003;

/// Largest weight a single cell reports. A daily-commute cell would
/// otherwise dwarf everything else and flatten the rest of the map to
/// one colour; clamping keeps the gradient legible. The MapLibre layer
/// still interpolates over [0, MAX_CELL_WEIGHT].
export const MAX_CELL_WEIGHT = 50;

function isFinitePoint(p: HeatLatLng | null | undefined): p is HeatLatLng {
	return (
		!!p &&
		typeof p.lat === 'number' &&
		typeof p.lng === 'number' &&
		Number.isFinite(p.lat) &&
		Number.isFinite(p.lng) &&
		Math.abs(p.lat) <= 90 &&
		Math.abs(p.lng) <= 180
	);
}

/// Quantise every point of every track into a grid and sum hits per
/// cell. Each cell's coordinate is its grid-centre; weight is the
/// clamped hit count. Empty / all-invalid input yields an empty array.
export function buildHeatCells(
	tracks: ReadonlyArray<ReadonlyArray<HeatLatLng>>,
	gridDeg: number = DEFAULT_GRID_DEG,
): HeatCell[] {
	if (!(gridDeg > 0)) gridDeg = DEFAULT_GRID_DEG;
	const counts = new Map<string, number>();
	for (const track of tracks) {
		if (!track) continue;
		for (const p of track) {
			if (!isFinitePoint(p)) continue;
			const gx = Math.round(p.lng / gridDeg);
			const gy = Math.round(p.lat / gridDeg);
			const key = `${gx}:${gy}`;
			counts.set(key, (counts.get(key) ?? 0) + 1);
		}
	}
	const cells: HeatCell[] = [];
	for (const [key, count] of counts) {
		const [gx, gy] = key.split(':').map(Number);
		cells.push({
			lng: gx * gridDeg,
			lat: gy * gridDeg,
			weight: Math.min(count, MAX_CELL_WEIGHT),
		});
	}
	return cells;
}

/// Bounding box of a set of cells as MapLibre's
/// `[[west, south], [east, north]]`. Null when there's nothing to fit.
export function heatBounds(
	cells: ReadonlyArray<HeatCell>,
): [[number, number], [number, number]] | null {
	if (cells.length === 0) return null;
	let minLat = Infinity,
		minLng = Infinity,
		maxLat = -Infinity,
		maxLng = -Infinity;
	for (const c of cells) {
		if (c.lat < minLat) minLat = c.lat;
		if (c.lat > maxLat) maxLat = c.lat;
		if (c.lng < minLng) minLng = c.lng;
		if (c.lng > maxLng) maxLng = c.lng;
	}
	return [
		[minLng, minLat],
		[maxLng, maxLat],
	];
}

/// GeoJSON FeatureCollection of weighted points for a MapLibre `heatmap`
/// layer (read `weight` via `['get', 'weight']` in `heatmap-weight`).
export function toHeatGeoJSON(
	cells: ReadonlyArray<HeatCell>,
): GeoJSON.FeatureCollection<GeoJSON.Point, { weight: number }> {
	return {
		type: 'FeatureCollection',
		features: cells.map((c) => ({
			type: 'Feature',
			properties: { weight: c.weight },
			geometry: { type: 'Point', coordinates: [c.lng, c.lat] },
		})),
	};
}

/// GeoJSON FeatureCollection of LineStrings — one per track — for the
/// line layer that fades in as the heatmap fades out at high zoom
/// (Strava-style: heat cloud zoomed out, the runner's actual paths
/// zoomed in). Invalid / out-of-range points are dropped; a track left
/// with fewer than two points contributes no feature. Owner-only
/// surface, so these are the runner's own un-clipped tracks.
export function toTrackLinesGeoJSON(
	tracks: ReadonlyArray<ReadonlyArray<HeatLatLng>>,
): GeoJSON.FeatureCollection<GeoJSON.LineString> {
	const features: GeoJSON.Feature<GeoJSON.LineString>[] = [];
	for (const track of tracks) {
		if (!track) continue;
		const coordinates: [number, number][] = [];
		for (const p of track) {
			if (!isFinitePoint(p)) continue;
			coordinates.push([p.lng, p.lat]);
		}
		if (coordinates.length >= 2) {
			features.push({
				type: 'Feature',
				properties: {},
				geometry: { type: 'LineString', coordinates },
			});
		}
	}
	return { type: 'FeatureCollection', features };
}
