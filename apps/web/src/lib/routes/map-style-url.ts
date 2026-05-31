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

	const slug = (() => {
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
	})();
	return `https://api.maptiler.com/maps/${slug}/style.json?key=${key}`;
}
