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
	// variables, so the hex is hardcoded. Chosen over the previous
	// generic `#3b82f6` blue so the polyline reads as "this app" at
	// thumbnail size. Width bumped from 3 to 4 so the line stays
	// legible against busy basemap content.
	const path = `fill:none|stroke:%23F2A07B|width:4|${coords}`;
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
	// Theme brand colour (`--color-primary` in dark mode, complement of
	// `--color-secondary` in light mode). Static images can't read CSS
	// variables, so the hex is hardcoded. Chosen over the previous
	// generic `#3b82f6` blue so the polyline reads as "this app" at
	// thumbnail size. Width bumped from 3 to 4 so the line stays
	// legible against busy basemap content.
	const path = `fill:none|stroke:%23F2A07B|width:4|${coords}`;
	// `@2x` scale not supported by tileserver-gl's path syntax —
	// it uses a `?scale=2` query param. Skip for now; thumbnails at
	// 220×140 look fine at 1× on a HiDPI display + the disk write
	// + transfer time at 2× isn't worth the marginal sharpness on
	// a small card.
	return `${base}/static/auto/${opts.w}x${opts.h}.png?path=${path}`;
}
