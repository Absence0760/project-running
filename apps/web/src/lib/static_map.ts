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
	const path = `fill:none|stroke:%233b82f6|width:3|${coords}`;
	return `https://api.maptiler.com/maps/${opts.style}/static/auto/${opts.w}x${opts.h}@2x.png?path=${path}&key=${opts.key}`;
}
