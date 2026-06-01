import { browser } from '$app/environment';
import { en } from './locales/en';
import type { Messages, MessageKey } from './messages';
import {
	DEFAULT_LOCALE,
	dirForLocale,
	isSupportedLocale,
	negotiateLocale,
	type Locale,
} from './locale';

// Lazy loaders for every non-default locale. English is statically
// bundled (it is the fallback dict and the prerender default); the rest
// are split into their own chunks so a single-locale visitor only ever
// downloads their own strings — the i18n layer adds ~nothing to the
// initial payload. See the responsiveness rationale in decisions.md.
const LOADERS: Record<Exclude<Locale, 'en'>, () => Promise<{ messages: Messages }>> = {
	de: () => import('./locales/de'),
	fr: () => import('./locales/fr'),
	es: () => import('./locales/es'),
	ja: () => import('./locales/ja'),
	'pt-BR': () => import('./locales/pt-BR'),
};

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
	let value: string = dict[key] ?? en[key] ?? key;
	if (params) {
		for (const [k, v] of Object.entries(params)) {
			value = value.replaceAll(`{${k}}`, String(v));
		}
	}
	return value;
}

function applyDocumentLocale(next: Locale): void {
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
		const mod = await LOADERS[next]();
		dict = mod.messages;
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
