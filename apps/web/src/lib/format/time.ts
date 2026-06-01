// Pure time/date formatting helpers shared across web surfaces.
// No runes here (plain `.ts`) so the helpers are unit-testable via `tsx --test`.

// The active UI locale, pushed in by the i18n runtime (store.svelte.ts
// calls setActiveFormatLocale on every locale change). Date helpers
// default to it, and call sites that format inline pass activeFormatLocale()
// to toLocaleDateString instead of `undefined` — so dates follow the
// picker, not just the browser locale (i18n-readiness W-12). Kept a plain
// module variable rather than a rune so time.ts stays tsx-testable and
// importable from non-Svelte code; the trade-off is that dates rendered
// via these helpers re-localise on the next render/navigation rather than
// the instant of an in-place switch (the relative-time call sites pass
// currentLocale() directly for live reactivity). `undefined` until the
// runtime sets it (SSR/prerender + tests), which means the host default —
// the prior behaviour.
let activeLocale: string | undefined;

export function setActiveFormatLocale(locale: string | undefined): void {
	activeLocale = locale;
}

export function activeFormatLocale(): string | undefined {
	return activeLocale;
}

// Memoised Intl.RelativeTimeFormat instances (construction is relatively
// expensive and these run per feed/notification row). Keyed by
// locale + numeric mode.
const rtfCache = new Map<string, Intl.RelativeTimeFormat>();
function rtf(locale: string | undefined, numeric: 'always' | 'auto'): Intl.RelativeTimeFormat {
	const key = `${locale ?? ''}|${numeric}`;
	let f = rtfCache.get(key);
	if (!f) {
		f = new Intl.RelativeTimeFormat(locale, { numeric, style: 'narrow' });
		rtfCache.set(key, f);
	}
	return f;
}

/**
 * Relative-time label for a feed/comment/notification timestamp:
 * the locale's "now"/`Nm ago`/`Nh ago`/`Nd ago` (under 30 days), otherwise
 * a localized `Mon D, YYYY` date. (i18n-readiness W-7: the labels used to
 * be hard-coded English.)
 *
 * `narrow` style reproduces the prior compact en form ("5m ago", "3h ago")
 * while localising automatically (de "vor 5 m", ja "5分前"). `numeric:'auto'`
 * is used only for the sub-minute case so it reads "now"/"jetzt"/"今";
 * the N-ago branches use `numeric:'always'` to keep the strict "Nd ago"
 * shape rather than auto's "yesterday".
 *
 * `now` is injectable so the relative branches are deterministic in tests;
 * `locale` defaults to the runtime default — callers that follow the i18n
 * picker pass `currentLocale()`.
 */
export function formatRelativeTime(
	iso: string,
	now: number = Date.now(),
	locale: string | undefined = activeLocale,
): string {
	const date = new Date(iso);
	const ms = now - date.getTime();
	const mins = Math.floor(ms / 60_000);
	if (mins < 1) return rtf(locale, 'auto').format(0, 'second');
	const ago = rtf(locale, 'always');
	if (mins < 60) return ago.format(-mins, 'minute');
	const hrs = Math.floor(mins / 60);
	if (hrs < 24) return ago.format(-hrs, 'hour');
	const days = Math.floor(hrs / 24);
	if (days < 30) return ago.format(-days, 'day');
	return date.toLocaleDateString(locale, {
		month: 'short',
		day: 'numeric',
		year: 'numeric',
	});
}

/** Duration as `H:MM:SS` (>= 1h) or `M:SS`. */
export function formatDuration(seconds: number): string {
	const h = Math.floor(seconds / 3600);
	const m = Math.floor((seconds % 3600) / 60);
	const s = seconds % 60;
	if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
	return `${m}:${String(s).padStart(2, '0')}`;
}

/** Localized `D Mon YYYY` date in the active UI locale (W-12). */
export function formatDate(iso: string, locale: string | undefined = activeLocale): string {
	return new Date(iso).toLocaleDateString(locale, {
		day: 'numeric',
		month: 'short',
		year: 'numeric',
	});
}

/** Localized `D Mon` date, no year, in the active UI locale (W-12). */
export function formatDateShort(iso: string, locale: string | undefined = activeLocale): string {
	return new Date(iso).toLocaleDateString(locale, {
		day: 'numeric',
		month: 'short',
	});
}
