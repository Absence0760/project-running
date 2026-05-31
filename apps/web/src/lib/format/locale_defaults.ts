// Locale-derived defaults for first-run settings (audit-findings
// 2026-05-30 Medium [regional]). Onboarding hard-coded `km` + Monday for
// everyone regardless of where the visitor is — wrong for a US/UK runner
// (miles) or a US user (Sunday-first week). These are pure functions over
// a BCP-47 locale string so they unit-test without a browser; callers
// pass `navigator.language`.

const FALLBACK_LOCALE = 'en-US';

function regionOf(locale: string): string {
	try {
		return (new Intl.Locale(locale).region ?? '').toUpperCase();
	} catch {
		return '';
	}
}

// Regions that use imperial distance for everyday + running use. Matches
// the audit's list: United States, United Kingdom, Liberia, Myanmar.
const IMPERIAL_REGIONS = new Set(['US', 'GB', 'LR', 'MM']);

export function defaultUnitForLocale(locale: string = FALLBACK_LOCALE): 'km' | 'mi' {
	return IMPERIAL_REGIONS.has(regionOf(locale)) ? 'mi' : 'km';
}

// Sunday-first-week regions where the CLDR week data isn't available.
// Europe / ISO-8601 is Monday-first; the Americas + much of East Asia +
// Israel start on Sunday.
const SUNDAY_FIRST_REGIONS = new Set([
	'US', 'CA', 'JP', 'IL', 'KR', 'TW', 'HK', 'IN', 'PH', 'BR', 'MX', 'ZA', 'CO', 'AR', 'PE', 'VE',
]);

export function defaultWeekStartForLocale(locale: string = FALLBACK_LOCALE): 'monday' | 'sunday' {
	const region = regionOf(locale);
	// Region-less locales ('en', '') stay on the neutral ISO/Monday
	// default (mirrors the km default for `defaultUnitForLocale`) rather
	// than letting Intl maximize 'en' → en-US → Sunday.
	if (!region) return 'monday';
	// With an explicit region, prefer the CLDR week data exposed via Intl
	// (Chromium 99+ / modern Node) — it's authoritative per-region.
	try {
		const loc = new Intl.Locale(locale) as Intl.Locale & {
			weekInfo?: { firstDay?: number };
			getWeekInfo?: () => { firstDay?: number };
		};
		const wi = loc.getWeekInfo?.() ?? loc.weekInfo;
		// firstDay: 1 = Monday … 7 = Sunday (ISO numbering).
		if (wi?.firstDay === 7) return 'sunday';
		if (wi?.firstDay === 1) return 'monday';
	} catch {
		// fall through to the region heuristic
	}
	return SUNDAY_FIRST_REGIONS.has(region) ? 'sunday' : 'monday';
}
