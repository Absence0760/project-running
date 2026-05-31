const FALLBACK_LOCALE = 'en-US';
const FALLBACK_CURRENCY = 'USD';

const CURRENCY_BY_LOCALE: Record<string, string> = {
	GB: 'GBP',
	IE: 'EUR',
	DE: 'EUR',
	FR: 'EUR',
	ES: 'EUR',
	IT: 'EUR',
	NL: 'EUR',
	BE: 'EUR',
	PT: 'EUR',
	AT: 'EUR',
	FI: 'EUR',
	GR: 'EUR',
	LU: 'EUR',
	MT: 'EUR',
	CY: 'EUR',
	EE: 'EUR',
	LV: 'EUR',
	LT: 'EUR',
	SK: 'EUR',
	SI: 'EUR',
	HR: 'EUR',
	CA: 'CAD',
	AU: 'AUD',
	NZ: 'NZD',
	JP: 'JPY',
	CH: 'CHF',
	SE: 'SEK',
	NO: 'NOK',
	DK: 'DKK',
	PL: 'PLN',
	CZ: 'CZK',
	HU: 'HUF',
	RO: 'RON',
	BG: 'BGN',
	BR: 'BRL',
	MX: 'MXN',
	IN: 'INR',
	SG: 'SGD',
	HK: 'HKD',
	KR: 'KRW',
};

function detectLocale(): string {
	if (typeof navigator === 'undefined') return FALLBACK_LOCALE;
	return navigator.language || FALLBACK_LOCALE;
}

function regionFromLocale(locale: string): string | null {
	const parts = locale.split('-');
	if (parts.length < 2) return null;
	return parts[1]?.toUpperCase() ?? null;
}

export function detectCurrency(locale: string = detectLocale()): string {
	const region = regionFromLocale(locale);
	if (!region) return FALLBACK_CURRENCY;
	return CURRENCY_BY_LOCALE[region] ?? FALLBACK_CURRENCY;
}

export interface FormatPriceOptions {
	currency?: string;
	locale?: string;
}

export function formatPrice(usdAmount: number, opts: FormatPriceOptions = {}): string {
	const locale = opts.locale ?? detectLocale();
	const currency = opts.currency ?? detectCurrency(locale);
	try {
		return new Intl.NumberFormat(locale, {
			style: 'currency',
			currency,
			minimumFractionDigits: 2,
			maximumFractionDigits: 2,
		}).format(usdAmount);
	} catch {
		return `$${usdAmount.toFixed(2)}`;
	}
}
