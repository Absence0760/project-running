// Pure locale negotiation + direction helpers for the web i18n runtime.
// No Svelte runtime, no message catalogue — kept side-effect-free so it
// unit-tests under `tsx --test` without a browser. The reactive runtime
// (the locale signal + message lookup) lives in store.svelte.ts; the
// message catalogues live in locales/.
//
// The web app is statically prerendered (adapter-static, no per-request
// SSR), so locale is negotiated client-side from navigator.language + a
// stored preference rather than from an Accept-Language header on the
// server. See decisions.md § "web i18n is client-side". The negotiation
// here is still written to accept a full Accept-Language-style q-list so
// the same parser works if a server surface (e.g. the coach Lambda) ever
// needs it.

export const SUPPORTED_LOCALES = ['en', 'de', 'fr', 'es', 'ja', 'pt-BR'] as const;
export type Locale = (typeof SUPPORTED_LOCALES)[number];
export const DEFAULT_LOCALE: Locale = 'en';

// Endonyms (the language's own name) for the locale picker — never
// translated, always shown in the target language's own script.
export const LOCALE_LABELS: Record<Locale, string> = {
	en: 'English',
	de: 'Deutsch',
	fr: 'Français',
	es: 'Español',
	ja: '日本語',
	'pt-BR': 'Português (Brasil)',
};

// Case-insensitive exact-tag map. Keys are lowercased; values are the
// canonical-cased Locale we actually use (`pt-BR`, not `pt-br`).
const EXACT: Record<string, Locale> = {
	en: 'en',
	de: 'de',
	fr: 'fr',
	es: 'es',
	ja: 'ja',
	'pt-br': 'pt-BR',
};

// Base-language fallback: a tag we don't carry exactly (fr-CA, pt-PT,
// de-AT) still resolves to the one variant we ship for that language.
const BASE_TO_LOCALE: Record<string, Locale> = {
	en: 'en',
	de: 'de',
	fr: 'fr',
	es: 'es',
	ja: 'ja',
	pt: 'pt-BR',
};

// RTL base languages. None of the current starter set is RTL, but the
// switch-point exists so dropping in an Arabic/Hebrew catalogue later
// flips <html dir> with no further plumbing (the web shell already uses
// CSS logical properties — see app.css).
const RTL_BASES = new Set(['ar', 'he', 'fa', 'ur']);

export function isSupportedLocale(value: string | null | undefined): value is Locale {
	return value != null && (SUPPORTED_LOCALES as readonly string[]).includes(value);
}

export function dirForLocale(locale: string): 'ltr' | 'rtl' {
	const base = locale.toLowerCase().split('-')[0];
	return RTL_BASES.has(base) ? 'rtl' : 'ltr';
}

function exactMatch(tag: string): Locale | null {
	return EXACT[tag.toLowerCase()] ?? null;
}

function baseMatch(tag: string): Locale | null {
	const base = tag.toLowerCase().split('-')[0];
	return BASE_TO_LOCALE[base] ?? null;
}

// Parse an Accept-Language-style header (or a single navigator.language
// tag) into the list of tags ordered by descending q-weight. `*` and
// empty tags are dropped.
export function parseAcceptLanguage(header: string): string[] {
	return header
		.split(',')
		.map((part) => {
			const [rawTag, ...params] = part.trim().split(';');
			let q = 1;
			for (const p of params) {
				const m = p.trim().match(/^q=([0-9.]+)$/);
				if (m) q = Number.parseFloat(m[1]);
			}
			return { tag: rawTag.trim(), q: Number.isFinite(q) ? q : 0 };
		})
		.filter((x) => x.tag.length > 0 && x.tag !== '*')
		.sort((a, b) => b.q - a.q)
		.map((x) => x.tag);
}

// Resolve the best supported locale. A stored preference (our own
// canonical value, written by setLocale) wins outright; otherwise the
// ordered Accept-Language / navigator.language tags are matched exact
// first, then by base language; falling back to DEFAULT_LOCALE.
export function negotiateLocale(
	acceptLanguage: string | null | undefined,
	stored?: string | null,
): Locale {
	if (isSupportedLocale(stored)) return stored;
	if (stored) {
		const m = exactMatch(stored) ?? baseMatch(stored);
		if (m) return m;
	}
	if (!acceptLanguage) return DEFAULT_LOCALE;
	const tags = parseAcceptLanguage(acceptLanguage);
	for (const tag of tags) {
		const m = exactMatch(tag);
		if (m) return m;
	}
	for (const tag of tags) {
		const m = baseMatch(tag);
		if (m) return m;
	}
	return DEFAULT_LOCALE;
}
