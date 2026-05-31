/// Theme toggle state. Three-way: `light`, `dark`, `auto`. The last
/// follows the OS via `prefers-color-scheme` and is the default.
///
/// The explicit value is mirrored to `html[data-theme="..."]` so CSS
/// can override the media query when the user has a strong preference,
/// and persisted to `localStorage` so it survives a reload.

export type Theme = 'light' | 'dark' | 'auto';

const STORAGE_KEY = 'run_app.theme';

export function loadTheme(): Theme {
	if (typeof localStorage === 'undefined') return 'auto';
	const raw = localStorage.getItem(STORAGE_KEY);
	if (raw === 'light' || raw === 'dark' || raw === 'auto') return raw;
	return 'auto';
}

export function applyTheme(theme: Theme): void {
	if (typeof document === 'undefined') return;
	document.documentElement.dataset.theme = theme;
	try {
		localStorage.setItem(STORAGE_KEY, theme);
	} catch (_) {
		// quota / SSR — applying the attribute is the important bit
	}
}

/// Initialise from persisted state. Safe to call multiple times — the
/// root layout triggers it on mount.
export function initTheme(): Theme {
	const t = loadTheme();
	applyTheme(t);
	return t;
}
