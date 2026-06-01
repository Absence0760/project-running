import { browser } from '$app/environment';
import { en } from './locales/en';
import { CATALOGUE_LOADERS } from './catalogues';
import { interpolate } from './interpolate';
import { setActiveFormatLocale } from '$lib/format/time';
import type { Messages, MessageKey } from './messages';
import {
	DEFAULT_LOCALE,
	dirForLocale,
	isSupportedLocale,
	negotiateLocale,
	type Locale,
} from './locale';

let locale = $state<Locale>(DEFAULT_LOCALE);
let dict = $state<Messages>(en);

export function currentLocale(): Locale {
	return locale;
}

// Reactive message lookup. Reading `dict` here makes every call site
// (template / $derived) re-render when the active locale changes. Falls
// back to the English string, then the raw key, so a not-yet-translated
// key degrades gracefully rather than rendering blank.
export function m(key: MessageKey, params?: Record<string, string | number>): string {
	const value: string = dict[key] ?? en[key] ?? key;
	return interpolate(value, params);
}

function applyDocumentLocale(next: Locale): void {
	// Keep the pure date/time formatters (time.ts) in sync with the active
	// locale (W-12). The FORMAT locale is the full browser locale when it is
	// a regional variant of the active catalogue locale (e.g. catalogue 'en'
	// + browser 'en-GB' → format with 'en-GB' so dates read "20 Jun 2026",
	// not the US "Jun 20, 2026"); otherwise the catalogue locale itself (an
	// explicit picker choice like 'de' wins over an unrelated browser tag).
	// Done outside the browser gate so it tracks even in non-DOM contexts.
	let formatLocale: string = next;
	if (browser && typeof navigator !== 'undefined' && navigator.language) {
		const nav = navigator.language;
		if (nav.toLowerCase().split('-')[0] === next) formatLocale = nav;
	}
	setActiveFormatLocale(formatLocale);
	if (!browser) return;
	try {
		localStorage.setItem('locale', next);
	} catch {
		/* storage may be unavailable (private mode / quota) — non-fatal */
	}
	document.documentElement.lang = next;
	document.documentElement.dir = dirForLocale(next);
}

// Switch the active locale. English swaps synchronously; other locales
// load their chunk first and keep the current dict on failure (layered
// resilience — a failed locale fetch must not blank the UI).
export async function setLocale(next: Locale): Promise<void> {
	if (next === 'en') {
		dict = en;
		locale = 'en';
		applyDocumentLocale('en');
		return;
	}
	try {
		dict = await CATALOGUE_LOADERS[next]();
		locale = next;
		applyDocumentLocale(next);
	} catch {
		/* keep the current locale + dict */
	}
}

// Detect the visitor's locale on first client mount: a stored choice
// wins, else navigator.language(s). Called once from +layout.svelte.
export function initLocale(): void {
	if (!browser) return;
	let stored: string | null = null;
	try {
		stored = localStorage.getItem('locale');
	} catch {
		/* ignore */
	}
	const navLangs =
		typeof navigator !== 'undefined'
			? (navigator.languages?.join(',') ?? navigator.language ?? null)
			: null;
	const next = negotiateLocale(navLangs, stored);
	void setLocale(next);
}

export { isSupportedLocale };
export type { Locale };
