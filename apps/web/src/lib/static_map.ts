// Pure helpers for MapTiler Static Maps URL construction. Lives
// outside RouteTrackPreview.svelte so node:test can import it without
// loading the Svelte runtime — the .svelte file imports back from
// here.

type Waypoint = { lat: number; lng: number };

/// Downsample a polyline to at most `target` evenly-spaced points
/// before building the MapTiler static-maps URL. Two reasons:
///   - MapTiler's `path` query parameter is hard-capped at a few
///     kilobytes; a 1000-point route blows past that with every
///     thumbnail.
///   - The endpoints stay (first + last), and the visual fidelity
///     of a 144x144 thumbnail tops out around ~60 points anyway.
export function downsampleForPreview(
	pts: Waypoint[],
	target: number,
): Waypoint[] {
	if (pts.length <= target) return pts;
	const out: Waypoint[] = [];
	const step = (pts.length - 1) / (target - 1);
	for (let i = 0; i < target; i++) {
		out.push(pts[Math.min(pts.length - 1, Math.round(i * step))]);
	}
	return out;
}

/// Build a MapTiler Static Maps URL with the route polyline rendered
/// on top of a real map background — the "map preview" users expect
/// on a card view (instead of the bare SVG line on an empty backdrop).
/// Returns null when the key is missing or the route has fewer than 2
/// points so the caller can fall back to the SVG-only thumbnail.
export function buildStaticMapUrl(
	pts: Waypoint[],
	opts: { w: number; h: number; style: string; key: string },
): string | null {
	if (!opts.key || pts.length < 2) return null;
	const down = downsampleForPreview(pts, 60);
	const coords = down
		.map((p) => `${p.lng.toFixed(5)},${p.lat.toFixed(5)}`)
		.join('|');
	// Theme brand colour (`--color-primary` in dark mode, complement of
	// `--color-secondary` in light mode). Static images can't read CSS
	// variables, so the hex is hardcoded. Width bumped from 3 to 4 so
	// the line stays legible against busy basemap content.
	//
	// Fill is a fully-transparent hex8 (`#ffffff00`) rather than
	// `none` — MapTiler's static-maps path syntax doesn't recognise
	// `none`, so closed loops (first coord ≈ last coord) get the
	// default black polygon fill and a "hole" appears inside the
	// loop on the thumbnail. Caught by the May 2026 audit pass.
	const path = `fill:%23ffffff00|stroke:%23F2A07B|width:4|${coords}`;
	return `https://api.maptiler.com/maps/${opts.style}/static/auto/${opts.w}x${opts.h}@2x.png?path=${path}&key=${opts.key}`;
}

/// Local-Protomaps counterpart. `tileserver-gl` exposes a static-map
/// endpoint at `/styles/{id}/static/auto/{w}x{h}.png?path=…` with the
/// same `path=` shape as MapTiler. We derive the static base from the
/// configured `PUBLIC_TILE_STYLE_URL` (which already points at
/// `…/styles/{id}/style.json`) by swapping `/style.json` for `/static`.
/// That keeps the override single-knob — set the style URL, get both
/// the live MapLibre tiles and the static-map thumbnails from the
/// same server.
///
/// Returns null when the style URL isn't set, the URL doesn't match
/// the expected `…/style.json` shape, or the route has fewer than 2
/// points — letting the caller fall through to MapTiler or SVG.
export function buildLocalStaticMapUrl(
	pts: Waypoint[],
	opts: { w: number; h: number; styleUrl: string },
): string | null {
	if (pts.length < 2 || !opts.styleUrl) return null;
	const match = opts.styleUrl.match(/^(.*)\/style\.json(?:\?.*)?$/);
	if (!match) return null;
	const base = match[1];
	const down = downsampleForPreview(pts, 60);
	const coords = down
		.map((p) => `${p.lng.toFixed(5)},${p.lat.toFixed(5)}`)
		.join('|');
	// Same fully-transparent fill as buildStaticMapUrl above — the
	// tileserver-gl static endpoint mirrors MapTiler's path syntax,
	// so `fill:none` would produce the same closed-loop "black hole"
	// regression here too.
	const path = `fill:%23ffffff00|stroke:%23F2A07B|width:4|${coords}`;
	// `@2x` scale not supported by tileserver-gl's path syntax —
	// it uses a `?scale=2` query param. Skip for now; thumbnails at
	// 220×140 look fine at 1× on a HiDPI display + the disk write
	// + transfer time at 2× isn't worth the marginal sharpness on
	// a small card.
	return `${base}/static/auto/${opts.w}x${opts.h}.png?path=${path}`;
}

/// Build a MapTiler Static Maps URL centred on a single point with a
/// marker — used for the meetup-point thumbnail on the event detail
/// page (persona-hunt social-group #10). Returns null when the key is
/// missing or the coordinates are out of range so the caller can hide
/// the thumbnail and fall back to the text label + directions link.
export function buildStaticMarkerMapUrl(
	lat: number,
	lng: number,
	opts: { w: number; h: number; style: string; key: string; zoom?: number },
): string | null {
	if (!opts.key) return null;
	if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
	if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
	const zoom = opts.zoom ?? 14;
	// Centre + zoom in the path, marker (lon,lat order) as a query param.
	return (
		`https://api.maptiler.com/maps/${opts.style}/static/` +
		`${lng.toFixed(5)},${lat.toFixed(5)},${zoom}/${opts.w}x${opts.h}@2x.png` +
		`?markers=${lng.toFixed(5)},${lat.toFixed(5)}&key=${opts.key}`
	);
}

/// Platform-agnostic "open in maps" deep link for a meetup point.
/// `geo:` is honoured by Android (and most mobile map apps); the
/// Google Maps universal URL is the safe fallback for desktop / iOS
/// browsers. Callers pick which to use per platform.
export function mapsDirectionsUrl(lat: number, lng: number): string {
	return `https://www.google.com/maps/search/?api=1&query=${lat},${lng}`;
}

export function geoUri(lat: number, lng: number, label?: string): string {
	const q = label ? `?q=${lat},${lng}(${encodeURIComponent(label)})` : '';
	return `geo:${lat},${lng}${q}`;
}
