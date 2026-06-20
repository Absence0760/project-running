/**
 * Pure slippy-map tile-enumeration math for offline tile packs. TS twin of
 * `apps/mobile_android/lib/tile_pack.dart` — keep the two in lockstep
 * (algorithm, edge cases, test counts).
 *
 * The actual tile fetch + disk write lives mobile-side in
 * `offline_tile_pack.dart`; this pure layer just turns a route bounding box
 * + a zoom range into the `{z,x,y}` tile coordinates that cover it, and caps
 * the count so a huge route × deep zoom can't blow up disk (decisions §167).
 * The web side exists for testability and a future "download size" preview
 * if web ever offers pack management.
 */
export interface TileBbox {
	minLat: number;
	minLng: number;
	maxLat: number;
	maxLng: number;
}

export interface TileCoord {
	z: number;
	x: number;
	y: number;
}

/// Default zoom band for a route pack (decisions §167): z12 (neighbourhood
/// overview) through z16 (street detail) — the band the live run map uses.
export const DEFAULT_MIN_ZOOM = 12;
export const DEFAULT_MAX_ZOOM = 16;
/// Per-pack hard ceiling. A route bbox spanning z12–z16 stays well under this
/// for any realistic single route; the cap guards against a pathological bbox
/// (a route accidentally spanning a continent) silently downloading gigabytes.
export const MAX_TILES_PER_PACK = 5000;

/// Web Mercator latitude limit — tiles are undefined beyond this.
const MAX_MERCATOR_LAT = 85.05112878;

/// Number of tiles a bbox would need across [minZoom, maxZoom]. Cheap O(zooms)
/// — used by the cap guard and a size preview without enumerating.
export function estimateTileCount(
	bbox: TileBbox,
	minZoom = DEFAULT_MIN_ZOOM,
	maxZoom = DEFAULT_MAX_ZOOM,
): number {
	const norm = normaliseBbox(bbox);
	let total = 0;
	for (let z = minZoom; z <= maxZoom; z++) {
		const { xMin, xMax, yMin, yMax } = tileRange(norm, z);
		total += (xMax - xMin + 1) * (yMax - yMin + 1);
	}
	return total;
}

/**
 * Enumerate every `{z,x,y}` tile covering `bbox` across the inclusive zoom
 * range. Throws when the count would exceed `maxTiles` (default
 * MAX_TILES_PER_PACK) so the caller surfaces a "too large" warning rather
 * than starting an unbounded download. A degenerate (zero-area) bbox still
 * yields the single tile its point falls in.
 */
export function tilesForBbox(
	bbox: TileBbox,
	minZoom = DEFAULT_MIN_ZOOM,
	maxZoom = DEFAULT_MAX_ZOOM,
	maxTiles = MAX_TILES_PER_PACK,
): TileCoord[] {
	if (minZoom > maxZoom) {
		throw new Error(`minZoom ${minZoom} > maxZoom ${maxZoom}`);
	}
	const norm = normaliseBbox(bbox);
	const count = estimateTileCount(norm, minZoom, maxZoom);
	if (count > maxTiles) {
		throw new Error(`tile pack would need ${count} tiles, over the ${maxTiles} cap`);
	}
	const tiles: TileCoord[] = [];
	for (let z = minZoom; z <= maxZoom; z++) {
		const { xMin, xMax, yMin, yMax } = tileRange(norm, z);
		for (let x = xMin; x <= xMax; x++) {
			for (let y = yMin; y <= yMax; y++) {
				tiles.push({ z, x, y });
			}
		}
	}
	return tiles;
}

/// Clamp + order a bbox: latitudes into the Mercator range, min/max sorted so
/// a caller passing them swapped (or an antimeridian-spanning degenerate box)
/// still yields a sane in-hemisphere range. We deliberately clamp longitude to
/// [-180, 180] rather than wrap, so a route that genuinely crosses the
/// antimeridian produces a wide-but-bounded pack instead of an empty one.
function normaliseBbox(bbox: TileBbox): TileBbox {
	const minLat = clamp(Math.min(bbox.minLat, bbox.maxLat), -MAX_MERCATOR_LAT, MAX_MERCATOR_LAT);
	const maxLat = clamp(Math.max(bbox.minLat, bbox.maxLat), -MAX_MERCATOR_LAT, MAX_MERCATOR_LAT);
	const minLng = clamp(Math.min(bbox.minLng, bbox.maxLng), -180, 180);
	const maxLng = clamp(Math.max(bbox.minLng, bbox.maxLng), -180, 180);
	return { minLat, minLng, maxLat, maxLng };
}

function tileRange(
	bbox: TileBbox,
	z: number,
): { xMin: number; xMax: number; yMin: number; yMax: number } {
	const n = 1 << z;
	const xMin = clampTile(lngToTileX(bbox.minLng, z), n);
	const xMax = clampTile(lngToTileX(bbox.maxLng, z), n);
	// y grows southward, so maxLat → smaller y.
	const yMin = clampTile(latToTileY(bbox.maxLat, z), n);
	const yMax = clampTile(latToTileY(bbox.minLat, z), n);
	return { xMin, xMax, yMin, yMax };
}

function lngToTileX(lng: number, z: number): number {
	const n = 1 << z;
	return Math.floor(((lng + 180) / 360) * n);
}

function latToTileY(lat: number, z: number): number {
	const n = 1 << z;
	const rad = (lat * Math.PI) / 180;
	return Math.floor(
		((1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2) * n,
	);
}

function clampTile(v: number, n: number): number {
	return Math.min(n - 1, Math.max(0, v));
}

function clamp(v: number, lo: number, hi: number): number {
	return Math.min(hi, Math.max(lo, v));
}
