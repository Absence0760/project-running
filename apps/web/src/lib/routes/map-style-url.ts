/// Pure URL builder for the map style. Lives in a plain `.ts` file
/// (not `.svelte.ts`) so Node test runners can import it without
/// needing the Svelte compiler to resolve runes. The reactive
/// preference signal stays in `map-style.svelte.ts` — this module
/// is its testable arm.
///
/// See `map-style.svelte.ts` for callers; see
/// `docs/ops/protomaps_local_setup.md` + `decisions.md § 68` for why the
/// override exists.

export type MapStyle = 'streets' | 'satellite' | 'outdoors' | 'dark';

/// Every MapTiler style slug any surface in the app requests. Wider than
/// [MapStyle] on purpose: the route builder runs its own three-way switcher
/// whose satellite rung is `hybrid` (imagery with labels, which is what you
/// want while placing waypoints) rather than the bare `satellite` the
/// preference resolves to. That is a genuine difference in tiles, so it is
/// modelled here as an extra slug rather than flattened onto the preference
/// union — a fifth `MapStyle` member would be a value no preference surface
/// ever writes, and pointing the builder at `satellite` would silently change
/// the imagery it requests (§ 526 declined the swap for exactly that reason).
///
/// What the two DO share is the classification: which slugs are dark ground.
/// That question has one answer in [slugIsDark], so a surface with its own
/// slug table still cannot disagree with the palette about what it drew over.
export type MaptilerSlug =
	| 'streets-v2'
	| 'streets-v2-dark'
	| 'satellite'
	| 'hybrid'
	| 'outdoor-v2';

/// Pure env-override resolver. Returns the trimmed value of
/// [getter] when non-blank; the empty string otherwise (treated by
/// [buildMapStyleUrl] as "no override → fall back to MapTiler").
///
/// The getter is a callback rather than a direct env read so the
/// test surface doesn't need `import.meta.env`. Production passes
/// `() => env.PUBLIC_TILE_STYLE_URL` from `$env/dynamic/public`.
///
/// Whitespace-only values are treated as absent — a stray space
/// after `PUBLIC_TILE_STYLE_URL=` in `.env.local` shouldn't silently
/// disable MapTiler.
export function resolveStyleOverride(
	getter: () => string | undefined,
): string {
	const raw = getter();
	if (raw == null) return '';
	const trimmed = raw.trim();
	return trimmed;
}

/// Static fallback served from `apps/web/static/` — an OSM-raster
/// MapLibre style with no API key requirement. Used when neither
/// `PUBLIC_TILE_STYLE_URL` (local dev override) nor
/// `PUBLIC_MAPTILER_KEY` (production keyed tiles) is set, so the
/// map always renders instead of 403-ing on
/// `https://api.maptiler.com/.../style.json?key=` (empty key).
/// Matches the OSM fallback contract on mobile's `resolveTileUrl`
/// (`apps/mobile_android/lib/widgets/live_run_map.dart`).
export const OSM_FALLBACK_STYLE_URL = '/osm-fallback-style.json';

export function buildMapStyleUrl(
	chosen: MapStyle,
	key: string,
	prefersDark: boolean,
	overrideUrl: string | undefined = undefined,
): string {
	// When `PUBLIC_TILE_STYLE_URL` is set in `.env.local` (typically
	// pointing at a local Protomaps tileserver-gl), the override
	// wins outright — local dev mode runs against a single
	// self-hosted style and the user's preference is ignored.
	//
	// Whitespace-only values are treated as absent — a stray space
	// after `PUBLIC_TILE_STYLE_URL=` in `.env.local` shouldn't
	// silently break the production fallback. Matches the
	// `isNotBlank` semantics on the mobile + Wear OS sides.
	const trimmed = overrideUrl?.trim() ?? '';
	if (trimmed.length > 0) return trimmed;

	// No MapTiler key + no override → fall through to the OSM raster
	// fallback style instead of constructing
	// `https://api.maptiler.com/.../style.json?key=` (which 403s).
	// Same semantic as mobile's `resolveTileUrl` OSM fallback.
	if (key.trim().length === 0) return OSM_FALLBACK_STYLE_URL;

	return maptilerStyleUrl(maptilerSlug(chosen, prefersDark), key);
}

/// The MapTiler style-document URL for a slug. The one place the endpoint is
/// spelled, so a surface with its own slug table (the route builder) still
/// requests it the same way.
export function maptilerStyleUrl(slug: MaptilerSlug, key: string): string {
	return `https://api.maptiler.com/maps/${slug}/style.json?key=${key}`;
}

/// The MapTiler style slug a preference resolves to. Extracted so
/// [basemapIsDark] classifies the SAME slug [buildMapStyleUrl] requests —
/// two switches would let the URL and the overlay palette drift apart,
/// which is the whole defect below.
function maptilerSlug(chosen: MapStyle, prefersDark: boolean): MaptilerSlug {
	switch (chosen) {
		case 'satellite':
			return 'satellite';
		case 'outdoors':
			return 'outdoor-v2';
		case 'dark':
			return 'streets-v2-dark';
		case 'streets':
		default:
			return prefersDark ? 'streets-v2-dark' : 'streets-v2';
	}
}

/// Whether the basemap [buildMapStyleUrl] just resolved to is DARK, so map
/// overlays can pick colours that show against the ground they land on.
///
/// This is not `prefers-color-scheme`, and conflating the two is the bug it
/// exists to close: the map-style preference decouples basemap luminance
/// from the OS theme in both directions. `outdoors` is a light basemap even
/// under a dark OS, and `dark` / `satellite` are dark basemaps even under a
/// light one — so an overlay keyed on `prefersDark` paints its light-ground
/// colours on dark ground and vice versa. Twin of mobile's
/// `resolveBasemapIsDark` (`live_run_map.dart`, decisions § 491), including
/// its classification of MapTiler `satellite` as dark: imagery is not
/// enumerable, and the darker rung is the safe side of an un-enumerable
/// ground.
///
/// The keyless path is the OSM raster fallback, whose own
/// `background-color` is `#dcdcdc` under light OSM tiles — light. An
/// override is classified by its URL, the same substring test mobile uses,
/// because a self-hosted style's luminance is not otherwise knowable here.
export function basemapIsDark(
	chosen: MapStyle,
	key: string,
	prefersDark: boolean,
	overrideUrl: string | undefined = undefined,
): boolean {
	return basemapIsDarkForSlug(maptilerSlug(chosen, prefersDark), key, overrideUrl);
}

/// [basemapIsDark] for a surface that resolves its own slug rather than a
/// [MapStyle] preference — the route builder, whose three-way switcher offers
/// `hybrid` imagery and no dark rung. It keeps the override and keyless
/// precedence identical, so the only thing such a surface still owns is WHICH
/// slug it asked for; whether that slug is dark ground is not its call.
export function basemapIsDarkForSlug(
	slug: MaptilerSlug,
	key: string,
	overrideUrl: string | undefined = undefined,
): boolean {
	const trimmed = overrideUrl?.trim() ?? '';
	if (trimmed.length > 0) return trimmed.toLowerCase().includes('dark');
	if (key.trim().length === 0) return false;
	return slugIsDark(slug);
}

/// Whether a MapTiler slug renders dark ground. Exhaustive over
/// [MaptilerSlug], so adding a slug is a compile error here until it is
/// classified — which is the point: an unclassified ground is an overlay
/// palette picked by coin toss. Both imagery slugs count as dark for § 526's
/// reason (imagery is not enumerable, and the darker rung is the safe side).
export function slugIsDark(slug: MaptilerSlug): boolean {
	switch (slug) {
		case 'streets-v2-dark':
		case 'satellite':
		case 'hybrid':
			return true;
		case 'streets-v2':
		case 'outdoor-v2':
			return false;
	}
}
