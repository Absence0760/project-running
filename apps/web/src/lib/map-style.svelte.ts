/// Map style preference signal.
///
/// Mirrors the pattern used by `units.svelte.ts`: a module-level reactive
/// signal that any view (notably `RunMap`) can read with `getMapStyle()`
/// to re-render automatically when the user flips the setting on
/// `/settings/preferences`. The preferences page calls `setMapStyle(...)`
/// when saving, and the root layout calls it once on mount with the
/// effective value from the settings bag.

import {
	buildMapStyleUrl,
	resolveStyleOverride,
	type MapStyle,
} from './map-style-url';
export type { MapStyle };

const style = $state<{ value: MapStyle | null }>({ value: null });

export function getMapStyle(): MapStyle | null {
	return style.value;
}

export function setMapStyle(s: MapStyle | null | undefined): void {
	if (s === 'streets' || s === 'satellite' || s === 'outdoors' || s === 'dark') {
		style.value = s;
	} else {
		style.value = null;
	}
}

/// Resolve the user's chosen style into a MapLibre style URL. Falls back
/// to streets (or streets-dark, if the OS is dark) when no preference is
/// set yet — matches the legacy hardcoded behaviour of `RunMap`.
///
/// When [overrideUrl] is non-empty (typically `PUBLIC_TILE_STYLE_URL` from
/// `.env.local` pointing at a local Protomaps tileserver), the override
/// wins outright and the user's style preference is ignored — local
/// dev mode runs the whole app against a single self-hosted style. See
/// `docs/protomaps_local_setup.md` + `decisions.md § 68` for why.
///
/// Tests pass `overrideUrl` directly; production reads from
/// `import.meta.env.PUBLIC_TILE_STYLE_URL` at the call site (see
/// `mapStyleUrlFromEnv`).
export function mapStyleUrl(
	key: string,
	prefersDark: boolean,
	overrideUrl: string | undefined = undefined,
): string {
	const chosen = style.value ?? (prefersDark ? 'dark' : 'streets');
	return buildMapStyleUrl(chosen, key, prefersDark, overrideUrl);
}

/// Convenience used by every map-rendering component: reads the dev
/// override from `import.meta.env.PUBLIC_TILE_STYLE_URL` and threads
/// it through [mapStyleUrl]. Always returns a usable URL — falls
/// back to MapTiler when the override is missing.
///
/// The [envGetter] parameter exists for test injection — production
/// callers omit it, tests pass a stub that returns a known value.
/// `import.meta.env` isn't available outside Vite, so Node test
/// runners would otherwise have to set up the Vite plugin chain
/// just to exercise this two-liner.
export function mapStyleUrlFromEnv(
	key: string,
	prefersDark: boolean,
	envGetter: () => string | undefined = () =>
		import.meta.env.PUBLIC_TILE_STYLE_URL as string | undefined,
): string {
	return mapStyleUrl(key, prefersDark, resolveStyleOverride(envGetter));
}
