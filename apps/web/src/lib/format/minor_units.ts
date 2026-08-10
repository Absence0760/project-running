/// Stripe stores an amount in the currency's MINOR unit, and for a
/// zero-decimal currency the minor unit IS the base unit — a ¥1,000 donation
/// arrives as 1000, not 100000. A blanket `/ 100` understates those
/// currencies a hundredfold; a blanket `* 100` overstates them the same way
/// on the write side.
const ZERO_DECIMAL_CURRENCIES = new Set([
	'BIF',
	'CLP',
	'DJF',
	'GNF',
	'ISK',
	'JPY',
	'KMF',
	'KRW',
	'MGA',
	'PYG',
	'RWF',
	'UGX',
	'VND',
	'VUV',
	'XAF',
	'XOF',
	'XPF'
]);

const THREE_DECIMAL_CURRENCIES = new Set(['BHD', 'JOD', 'KWD', 'OMR', 'TND']);

const DEFAULT_FRACTION_DIGITS = 2;

export function currencyFractionDigits(currency: string): number {
	const code = currency.trim().toUpperCase();
	try {
		const digits = new Intl.NumberFormat('en-US', {
			style: 'currency',
			currency: code
		}).resolvedOptions().maximumFractionDigits;
		if (typeof digits === 'number' && Number.isInteger(digits)) return digits;
	} catch {
		// An unknown code, or a runtime built without currency data. The tables
		// below carry Stripe's documented non-two-decimal currencies.
	}
	if (ZERO_DECIMAL_CURRENCIES.has(code)) return 0;
	if (THREE_DECIMAL_CURRENCIES.has(code)) return 3;
	return DEFAULT_FRACTION_DIGITS;
}

export function fromMinorUnits(amountMinor: number, currency: string): number {
	return amountMinor / 10 ** currencyFractionDigits(currency);
}

export function toMinorUnits(amountMajor: number, currency: string): number {
	const digits = currencyFractionDigits(currency);
	const minor = Math.round(amountMajor * 10 ** digits);
	// Stripe rejects a three-decimal amount that is not a multiple of 10.
	return digits === 3 ? Math.round(minor / 10) * 10 : minor;
}
