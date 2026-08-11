// Locale-derived defaults for first-run settings (audit-findings
// 2026-05-30 Medium [regional]). Onboarding hard-coded `km` + Monday for
// everyone regardless of where the visitor is — wrong for a US/UK runner
// (miles) or a US user (Sunday-first week). These are pure functions over
// a BCP-47 locale string so they unit-test without a browser; callers
// pass `navigator.language`.

const FALLBACK_LOCALE = 'en-US';

export function regionOfLocale(locale: string): string {
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
	return IMPERIAL_REGIONS.has(regionOfLocale(locale)) ? 'mi' : 'km';
}

// Sunday-first-week regions where the CLDR week data isn't available.
// Europe / ISO-8601 is Monday-first; the Americas + much of East Asia +
// Israel start on Sunday.
// Regions whose CLDR week data starts the week on SUNDAY. Derived from
// Intl week data (firstDay === 7) over every assigned ISO 3166-1 alpha-2
// region, so the table and the Intl lookup above can never disagree.
//
// Kept identical to `_sundayFirstRegions` in `locale_defaults.dart`, which has
// no Intl equivalent and relies on this table alone. The hand-written 16-region
// version they shared disagreed with CLDR for 19 of them — it wrongly listed AR
// (Argentina is Monday-first) and omitted PT, TH, ID, SG, SA, DO, GT, HN, SV,
// NI, PA, PY, KE, ET, PK, BD, YE, NP and LA — so web (which consults Intl
// first) and mobile (which cannot) seeded different week starts, and
// `current_week` then bucketed the dashboard onto different seven days.
//
// Saturday-first regions (firstDay === 6: EG, JO, KW, SA-adjacent Gulf states,
// IR, AF …) are deliberately absent: the setting models only sunday | monday,
// and both platforms fall through to monday for them, which already agrees.
const SUNDAY_FIRST_REGIONS = new Set([
	'AG', 'AS', 'BD', 'BR', 'BS', 'BT', 'BW', 'BZ',
	'CA', 'CO', 'DM', 'DO', 'ET', 'GT', 'GU', 'HK',
	'HN', 'ID', 'IL', 'IN', 'IS', 'JM', 'JP', 'KE',
	'KH', 'KR', 'LA', 'MH', 'MM', 'MO', 'MT', 'MX',
	'MZ', 'NI', 'NP', 'PA', 'PE', 'PH', 'PK', 'PR',
	'PT', 'PY', 'SA', 'SG', 'SV', 'TH', 'TT', 'TW',
	'UM', 'US', 'VE', 'VI', 'WS', 'YE', 'ZA', 'ZW',
]);

export function defaultWeekStartForLocale(locale: string = FALLBACK_LOCALE): 'monday' | 'sunday' {
	const region = regionOfLocale(locale);
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
