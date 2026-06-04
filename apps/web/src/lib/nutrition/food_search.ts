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

function num(v: unknown): number | null {
	const n = typeof v === 'string' ? Number(v) : typeof v === 'number' ? v : NaN;
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

/// Search Open Food Facts. Returns [] on a network/parse failure (the caller
/// falls back to manual entry — never blocks logging on the DB being up).
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
	try {
		const res = await fetcher(`${SEARCH_URL}?${params.toString()}`);
		if (!res.ok) return [];
		return parseOffSearch(await res.json());
	} catch (e) {
		console.warn('searchFoods failed', e);
		return [];
	}
}
