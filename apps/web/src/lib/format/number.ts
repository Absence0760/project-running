// Locale-aware number formatting (i18n-readiness W-15). The unit
// formatters in units.svelte.ts previously used `.toFixed(N)`, which
// always emits a period decimal separator and never groups thousands —
// wrong for the comma-decimal locales (de/es/fr/pt-BR: `5,21 km`) and the
// space/locale grouping ones (fr: `1 234`). These pure helpers wrap
// Intl.NumberFormat so the same value renders correctly per locale.
//
// Kept pure (plain .ts, explicit `locale` arg) so it unit-tests under
// `tsx --test`; the reactive caller (units.svelte.ts) passes the active
// UI locale from the i18n runtime. Intl.NumberFormat construction is
// relatively expensive, so instances are memoised by (locale, digits) —
// the responsiveness guard, since these run on every distance/pace cell.
//
// Pace ("m:ss") is deliberately NOT routed through here: it is athletic
// notation, intentionally locale-neutral (see units.svelte.ts).

const cache = new Map<string, Intl.NumberFormat>();

function formatter(locale: string | undefined, min: number, max: number): Intl.NumberFormat {
	const key = `${locale ?? ''}|${min}|${max}`;
	let nf = cache.get(key);
	if (!nf) {
		nf = new Intl.NumberFormat(locale, {
			minimumFractionDigits: min,
			maximumFractionDigits: max,
		});
		cache.set(key, nf);
	}
	return nf;
}

/// Fixed-fraction decimal (the locale-aware replacement for `toFixed`):
/// `formatDecimal(5.21, 2, 'de')` → `'5,21'`, `(1234.5, 1, 'en')` →
/// `'1,234.5'`. `digits` pins both the minimum and maximum fraction
/// digits so the width matches the old `toFixed(digits)` exactly.
export function formatDecimal(value: number, digits: number, locale?: string): string {
	return formatter(locale, digits, digits).format(value);
}

/// Grouped integer: `formatInteger(1234, 'de')` → `'1.234'`,
/// `(1234, 'fr')` → `'1 234'`. Used for whole-unit labels (metres, yards,
/// feet) where the old code emitted an ungrouped `Math.round` string.
export function formatInteger(value: number, locale?: string): string {
	return formatter(locale, 0, 0).format(value);
}
