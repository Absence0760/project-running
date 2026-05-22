/// Pure URL builder for the map style. Lives in a plain `.ts` file
/// (not `.svelte.ts`) so Node test runners can import it without
/// needing the Svelte compiler to resolve runes. The reactive
/// preference signal stays in `map-style.svelte.ts` — this module
/// is its testable arm.
///
/// See `map-style.svelte.ts` for callers; see
/// `docs/protomaps_local_setup.md` + `decisions.md § 68` for why the
/// override exists.

export type MapStyle = 'streets' | 'satellite' | 'outdoors' | 'dark';

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
	if (overrideUrl && overrideUrl.length > 0) return overrideUrl;

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
