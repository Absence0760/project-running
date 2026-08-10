import { currencyFractionDigits } from './minor_units';

const FALLBACK_LOCALE = 'en-US';
const FALLBACK_CURRENCY = 'USD';

function detectLocale(): string {
	if (typeof navigator === 'undefined') return FALLBACK_LOCALE;
	return navigator.language || FALLBACK_LOCALE;
}

export interface FormatPriceOptions {
	currency?: string;
	locale?: string;
}

/// `amount` is in the currency's MAJOR unit. A figure that came out of Stripe
/// is in minor units — put it through `fromMinorUnits` first, never `/ 100`.
export function formatPrice(amount: number, opts: FormatPriceOptions = {}): string {
	const locale = opts.locale ?? detectLocale();
	// The amount is a raw USD figure we do NOT FX-convert. Rendering a
	// localized currency symbol over it (e.g. € on a de-DE locale) would
	// misrepresent the price the user is actually charged — an EU Omnibus /
	// consumer-protection problem. So default to USD (the real charge
	// currency, shown with the locale's number formatting); a caller that
	// has a genuine localized store price (RevenueCat) passes `currency`
	// explicitly. audit-findings 2026-05-30 Medium [regional].
	const currency = opts.currency ?? FALLBACK_CURRENCY;
	try {
		// No fraction-digit override: a currency's own convention is the right
		// one. Forcing two renders ¥1,000 as ¥1,000.00 and KWD 1.500 as KWD 1.50.
		return new Intl.NumberFormat(locale, {
			style: 'currency',
			currency,
		}).format(amount);
	} catch {
		return `${amount.toFixed(currencyFractionDigits(currency))} ${currency.toUpperCase()}`;
	}
}
