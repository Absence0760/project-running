/// Map style preference signal.
///
/// Mirrors the pattern used by `units.svelte.ts`: a module-level reactive
/// signal that any view (notably `RunMap`) can read with `getMapStyle()`
/// to re-render automatically when the user flips the setting on
/// `/settings/preferences`. The preferences page calls `setMapStyle(...)`
/// when saving, and the root layout calls it once on mount with the
/// effective value from the settings bag.

export type MapStyle = 'streets' | 'satellite' | 'outdoors' | 'dark';

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

/// Resolve the user's chosen style into a MapTiler style URL. Falls back
/// to streets (or streets-dark, if the OS is dark) when no preference is
/// set yet — matches the legacy hardcoded behaviour of `RunMap`.
export function mapStyleUrl(key: string, prefersDark: boolean): string {
	const chosen = style.value ?? (prefersDark ? 'dark' : 'streets');
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
