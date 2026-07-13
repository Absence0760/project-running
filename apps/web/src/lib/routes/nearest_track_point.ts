/**
 * Nearest-track-vertex search for map tap-to-select.
 *
 * A plain linear haversine scan is fine for a normal run (a few
 * thousand points) but an ultra track is 150-300k points, where a
 * synchronous per-tap O(n) scan visibly lags. `buildTrackIndex`
 * precomputes a uniform lng/lat grid once when the track loads;
 * `nearestIndex` then answers each tap by expanding rings outward from
 * the tapped cell, with an exact cutoff so the result is identical to
 * the brute-force scan. Below `LINEAR_SCAN_MAX` points the grid is
 * skipped entirely and the scan runs linearly — a normal-sized run
 * keeps its exact, unchanged behaviour.
 *
 * Web-only (the mobile LiveRunMap has no tap-to-select surface), so no
 * Dart twin.
 */

const EARTH_RADIUS_M = 6371000;
const M_PER_DEG_LAT = 111320;

/** Runs at or below this point count use a plain linear scan. */
const LINEAR_SCAN_MAX = 20000;
/** Grid resolution cap per axis, so a tap far from the track can't
 *  expand rings unboundedly — worst-case cell visits stay O(GRID_AXIS²)
 *  regardless of track length. */
const GRID_AXIS = 128;

export function haversineMetres(a: [number, number], b: [number, number]): number {
	const toRad = (d: number) => (d * Math.PI) / 180;
	const dLat = toRad(b[1] - a[1]);
	const dLng = toRad(b[0] - a[0]);
	const sinLat = Math.sin(dLat / 2);
	const sinLng = Math.sin(dLng / 2);
	const h = sinLat * sinLat + Math.cos(toRad(a[1])) * Math.cos(toRad(b[1])) * sinLng * sinLng;
	return EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

interface Grid {
	cells: Map<number, number[]>;
	cols: number;
	rows: number;
	minLng: number;
	minLat: number;
	cellLng: number;
	cellLat: number;
	/** Conservative smallest cell side in metres — the per-ring lower
	 *  bound that lets the ring search terminate exactly. */
	minCellMetres: number;
}

export interface TrackIndex {
	coords: readonly [number, number][];
	grid: Grid | null;
}

export function buildTrackIndex(coords: readonly [number, number][]): TrackIndex {
	if (coords.length <= LINEAR_SCAN_MAX) return { coords, grid: null };

	let minLng = Infinity;
	let maxLng = -Infinity;
	let minLat = Infinity;
	let maxLat = -Infinity;
	for (const [lng, lat] of coords) {
		if (lng < minLng) minLng = lng;
		if (lng > maxLng) maxLng = lng;
		if (lat < minLat) minLat = lat;
		if (lat > maxLat) maxLat = lat;
	}

	const lngSpan = maxLng - minLng;
	const latSpan = maxLat - minLat;
	const cols = lngSpan > 0 ? GRID_AXIS : 1;
	const rows = latSpan > 0 ? GRID_AXIS : 1;
	const cellLng = lngSpan > 0 ? lngSpan / cols : 1;
	const cellLat = latSpan > 0 ? latSpan / rows : 1;

	const maxAbsLat = Math.max(Math.abs(minLat), Math.abs(maxLat));
	const lngMetresPerDeg = M_PER_DEG_LAT * Math.cos((maxAbsLat * Math.PI) / 180);
	// Ignore a degenerate (zero-span) axis when picking the ring bound;
	// only a real cell side constrains how far the next ring can be.
	const sides: number[] = [];
	if (latSpan > 0) sides.push(cellLat * M_PER_DEG_LAT);
	if (lngSpan > 0) sides.push(cellLng * lngMetresPerDeg);
	const minCellMetres = sides.length > 0 ? Math.min(...sides) : 0;

	// A collinear track (both spans effectively zero, or cos→0 at a
	// pole) leaves no usable ring bound; fall back to a linear scan.
	if (!(minCellMetres > 0)) return { coords, grid: null };

	const cells = new Map<number, number[]>();
	for (let i = 0; i < coords.length; i++) {
		const key = cellKey(coords[i][0], coords[i][1], minLng, minLat, cellLng, cellLat, cols, rows);
		const bucket = cells.get(key);
		if (bucket) bucket.push(i);
		else cells.set(key, [i]);
	}

	return {
		coords,
		grid: { cells, cols, rows, minLng, minLat, cellLng, cellLat, minCellMetres },
	};
}

function clamp(v: number, lo: number, hi: number): number {
	return v < lo ? lo : v > hi ? hi : v;
}

function cellKey(
	lng: number,
	lat: number,
	minLng: number,
	minLat: number,
	cellLng: number,
	cellLat: number,
	cols: number,
	rows: number
): number {
	const cx = clamp(Math.floor((lng - minLng) / cellLng), 0, cols - 1);
	const cy = clamp(Math.floor((lat - minLat) / cellLat), 0, rows - 1);
	return cy * cols + cx;
}

/**
 * Nearest track index to a tapped lng/lat. Identical result to a
 * brute-force linear scan (ties broken by lowest index, matching the
 * scan — GPS floats effectively never tie). Bounded per-tap cost once
 * the track exceeds `LINEAR_SCAN_MAX`.
 */
export function nearestIndex(index: TrackIndex, lng: number, lat: number): number {
	const { coords, grid } = index;
	if (coords.length === 0) return 0;
	if (!grid) return linearNearest(coords, lng, lat);

	const q: [number, number] = [lng, lat];
	const { cells, cols, rows, minLng, minLat, cellLng, cellLat, minCellMetres } = grid;
	const cx = clamp(Math.floor((lng - minLng) / cellLng), 0, cols - 1);
	const cy = clamp(Math.floor((lat - minLat) / cellLat), 0, rows - 1);

	let bestIdx = -1;
	let bestD = Infinity;
	const scanCell = (gx: number, gy: number) => {
		if (gx < 0 || gy < 0 || gx >= cols || gy >= rows) return;
		const bucket = cells.get(gy * cols + gx);
		if (!bucket) return;
		for (const i of bucket) {
			const d = haversineMetres(q, coords[i]);
			if (d < bestD) {
				bestD = d;
				bestIdx = i;
			}
		}
	};

	const maxRing = Math.max(cols, rows);
	for (let r = 0; r <= maxRing; r++) {
		if (r === 0) {
			scanCell(cx, cy);
		} else {
			const x0 = cx - r;
			const x1 = cx + r;
			const y0 = cy - r;
			const y1 = cy + r;
			for (let gx = x0; gx <= x1; gx++) {
				scanCell(gx, y0);
				scanCell(gx, y1);
			}
			for (let gy = y0 + 1; gy <= y1 - 1; gy++) {
				scanCell(x0, gy);
				scanCell(x1, gy);
			}
		}
		// Every unsearched cell (ring r+1 and beyond) is at least
		// r cell-widths from the tap, so once the best match is within
		// that bound nothing further can beat it.
		if (bestIdx >= 0 && bestD <= r * minCellMetres) break;
	}

	return bestIdx >= 0 ? bestIdx : 0;
}

function linearNearest(coords: readonly [number, number][], lng: number, lat: number): number {
	let bestIdx = 0;
	let bestD = Infinity;
	const q: [number, number] = [lng, lat];
	for (let i = 0; i < coords.length; i++) {
		const d = haversineMetres(q, coords[i]);
		if (d < bestD) {
			bestD = d;
			bestIdx = i;
		}
	}
	return bestIdx;
}
