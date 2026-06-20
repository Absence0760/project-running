/**
 * Open Food Facts food search for nutrition logging.
 *
 * Logging is search → tap → confirm portion, never blank macro entry
 * (multi_modal.md § Nutrition). Open Food Facts is free, open-data, and
 * needs no API key (`world.openfoodfacts.org`).
 *
 * The HTTP call is isolated behind an injectable `fetcher` (the seam, like
 * `routing.ts`) so the parse + portion-scaling logic is unit-testable
 * without network. The Dart twin (`food_search.dart`, G8) mirrors the parse
 * + scale behaviour.
 */

export interface FoodMacros {
	calories: number;
	proteinG: number;
	carbsG: number;
	fatG: number;
}

export interface FoodSearchResult {
	/// Open Food Facts barcode — stable id, used for the `off:<code>`
	/// external_id namespace on logged entries.
	code: string;
	name: string;
	brand: string | null;
	/// Macros per 100 g (Open Food Facts' canonical basis).
	per100g: FoodMacros;
}

export type Fetcher = (url: string) => Promise<Response>;

const SEARCH_URL = 'https://world.openfoodfacts.org/cgi/search.pl';
const PRODUCT_URL = 'https://world.openfoodfacts.org/api/v2/product';

/// Keep only the digits of a scanned EAN/UPC. A barcode scanner can hand back
/// a trailing newline or a symbology label; Open Food Facts keys products by
/// the bare digit string. Returns null when nothing usable remains. Mobile
/// owns the camera-scan surface (multi_modal.md); this stays in lockstep with
/// the Dart twin's `normaliseBarcode`.
export function normaliseBarcode(raw: string): string | null {
	const digits = raw.replace(/[^0-9]/g, '');
	return digits === '' ? null : digits;
}

function num(v: unknown): number | null {
	// Number('') and Number('   ') both coerce to 0, so a blank Open Food Facts
	// nutriment field (very common upstream) would otherwise read as a real 0 —
	// keeping an unloggable product as a phantom 0-kcal row. Treat blank as missing,
	// matching the Dart twin's double.tryParse('') === null.
	let n: number;
	if (typeof v === 'string') {
		if (v.trim() === '') return null;
		n = Number(v);
	} else if (typeof v === 'number') {
		n = v;
	} else {
		return null;
	}
	return Number.isFinite(n) && n >= 0 ? n : null;
}

/// Map a raw Open Food Facts search response into our result shape. Pure.
/// Drops products with no name or no calorie figure (unloggable noise).
export function parseOffSearch(json: unknown): FoodSearchResult[] {
	const products = (json as { products?: unknown[] } | null)?.products;
	if (!Array.isArray(products)) return [];
	const out: FoodSearchResult[] = [];
	for (const p of products) {
		const prod = p as Record<string, unknown>;
		const name = typeof prod.product_name === 'string' ? prod.product_name.trim() : '';
		const code = typeof prod.code === 'string' ? prod.code : '';
		const n = (prod.nutriments ?? {}) as Record<string, unknown>;
		const calories = num(n['energy-kcal_100g']);
		if (!name || !code || calories == null) continue;
		const brandRaw = typeof prod.brands === 'string' ? prod.brands.split(',')[0].trim() : '';
		out.push({
			code,
			name,
			brand: brandRaw || null,
			per100g: {
				calories,
				proteinG: num(n.proteins_100g) ?? 0,
				carbsG: num(n.carbohydrates_100g) ?? 0,
				fatG: num(n.fat_100g) ?? 0,
			},
		});
	}
	return out;
}

/// Map a raw Open Food Facts `/api/v2/product/{barcode}` response into a
/// single result. Pure. The product-by-barcode endpoint returns
/// `{status, product}` (one object, not the `products` array the search
/// endpoint returns), so it can't reuse `parseOffSearch`. Returns null when
/// the product is missing (`status != 1`) or unloggable (no name / no calorie
/// figure) — the caller treats null as "no match, fall back to search".
export function parseOffProduct(json: unknown): FoodSearchResult | null {
	const map = json as { status?: unknown; product?: unknown } | null;
	if (!map || map.status !== 1) return null;
	const p = map.product as Record<string, unknown> | undefined;
	if (!p || typeof p !== 'object') return null;
	const name = typeof p.product_name === 'string' ? p.product_name.trim() : '';
	const code = typeof p.code === 'string' ? p.code : '';
	const n = (p.nutriments ?? {}) as Record<string, unknown>;
	const calories = num(n['energy-kcal_100g']);
	if (!name || !code || calories == null) return null;
	const brandRaw = typeof p.brands === 'string' ? p.brands.split(',')[0].trim() : '';
	return {
		code,
		name,
		brand: brandRaw || null,
		per100g: {
			calories,
			proteinG: num(n.proteins_100g) ?? 0,
			carbsG: num(n.carbohydrates_100g) ?? 0,
			fatG: num(n.fat_100g) ?? 0,
		},
	};
}

/// Scale a per-100 g result to a portion in grams, rounded to whole units.
export function scalePortion(per100g: FoodMacros, grams: number): FoodMacros {
	const f = grams > 0 ? grams / 100 : 0;
	return {
		calories: Math.round(per100g.calories * f),
		proteinG: Math.round(per100g.proteinG * f),
		carbsG: Math.round(per100g.carbsG * f),
		fatG: Math.round(per100g.fatG * f),
	};
}

/// Search Open Food Facts. Returns [] only for a genuinely empty result
/// set; THROWS on a network / non-2xx / parse failure so the caller can
/// tell "no matches" apart from "search failed" and offer a retry instead
/// of a misleading empty state. (An empty query short-circuits to [].)
export async function searchFoods(
	query: string,
	fetcher: Fetcher = (u) => fetch(u),
	limit = 20,
): Promise<FoodSearchResult[]> {
	const q = query.trim();
	if (!q) return [];
	const params = new URLSearchParams({
		search_terms: q,
		search_simple: '1',
		action: 'process',
		json: '1',
		page_size: String(limit),
		fields: 'code,product_name,brands,nutriments',
	});
	const res = await fetcher(`${SEARCH_URL}?${params.toString()}`);
	if (!res.ok) throw new Error(`Open Food Facts search failed: ${res.status}`);
	return parseOffSearch(await res.json());
}

/// Look up a single product by scanned EAN/UPC barcode (the v1.1 camera
/// fast-path on the same Open Food Facts lookup; mobile owns the camera-scan
/// surface). Returns null for a blank / non-numeric code or a genuine
/// no-match (`status != 1` / unloggable product); THROWS on a network /
/// non-2xx / parse failure so the caller can tell "not in the database" apart
/// from "lookup failed". Kept for parity with the Dart twin's `lookupBarcode`.
export async function lookupBarcode(
	barcode: string,
	fetcher: Fetcher = (u) => fetch(u),
): Promise<FoodSearchResult | null> {
	const code = normaliseBarcode(barcode);
	if (code == null) return null;
	const params = new URLSearchParams({ fields: 'code,product_name,brands,nutriments' });
	const res = await fetcher(`${PRODUCT_URL}/${code}.json?${params.toString()}`);
	if (!res.ok) throw new Error(`Open Food Facts product lookup failed: ${res.status}`);
	return parseOffProduct(await res.json());
}
