// parkrun operates in a limited set of countries (~20 as of 2026), but
// the integrations page offered it to every signed-up user with no
// signal that there may be no events anywhere near them (audit
// regional-availability, Medium). The card stays fully functional
// everywhere — an expat with a parkrun athlete ID can still connect —
// this only gates a "may not be available in your region" hint, so an
// unknown region shows nothing rather than a false warning.
// Dart twin: apps/mobile_android/lib/parkrun_regions.dart (keep in
// lockstep).

import { regionOfLocale } from '../format/locale_defaults';

export const PARKRUN_REGIONS = new Set([
	'AU', 'AT', 'CA', 'DK', 'DE', 'FI', 'IE', 'IT', 'JP', 'LT', 'MY',
	'NA', 'NL', 'NO', 'NZ', 'PL', 'SE', 'SG', 'GB', 'US', 'ZA',
]);

export function parkrunLikelyUnavailable(locale: string): boolean {
	const region = regionOfLocale(locale);
	return region !== '' && !PARKRUN_REGIONS.has(region);
}
