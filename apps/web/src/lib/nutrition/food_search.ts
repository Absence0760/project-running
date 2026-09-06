/**
 * Food search for nutrition logging — two sources behind one shape.
 *
 * Logging is search → tap → confirm portion, never blank macro entry
 * (multi_modal.md § Nutrition). Open Food Facts is free, open-data, and
 * needs no API key (`world.openfoodfacts.org`) — it also backs the camera
 * barcode fast-path (`lookupBarcode`). USDA FoodData Central is a second
 * source (`api.nal.usda.gov`) and DOES require an API key — it is gated
 * fail-closed: with no key the USDA source is simply absent (OFF still
 * works), no error, no broken UI.
 *
 * The HTTP call is isolated behind an injectable `fetcher` (the seam, like
 * `routing.ts`) so the parse + portion-scaling logic is unit-testable
 * without network. The Dart twin (`food_search.dart`, G8) mirrors the parse
 * + scale behaviour for both sources.
 */

import { fold } from '../segments/catalogue_browse';

export interface FoodMacros {
	calories: number;
	proteinG: number;
	carbsG: number;
	fatG: number;
	// Extended nutrients (issue #492). Optional + nullable: both food sources
	// carry these unevenly, so a missing value stays null (never a phantom 0),
	// and consumers that only need the headline macros ignore them. Grams for
	// fibre / sugar / saturated fat; milligrams for sodium / cholesterol.
	fiberG?: number | null;
	sugarG?: number | null;
	sodiumMg?: number | null;
	saturatedFatG?: number | null;
	cholesterolMg?: number | null;
}

/// Which database a result came from. Drives the source label in the
/// composer and the `<source>:<code>` external_id namespace on logged
/// entries (`off:` / `usda:`).
export type FoodSource = 'off' | 'usda';

export interface FoodSearchResult {
	/// Stable id within its source — an Open Food Facts barcode (`off`) or a
	/// USDA FDC id (`usda`). Combined with `source` it forms the
	/// `<source>:<code>` external_id namespace on logged entries.
	code: string;
	source: FoodSource;
	name: string;
	brand: string | null;
	/// Macros per 100 g (both sources' canonical basis).
	per100g: FoodMacros;
}

export type Fetcher = (url: string) => Promise<Response>;

const SEARCH_URL = 'https://world.openfoodfacts.org/cgi/search.pl';
const PRODUCT_URL = 'https://world.openfoodfacts.org/api/v2/product';
const USDA_SEARCH_URL = 'https://api.nal.usda.gov/fdc/v1/foods/search';

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

/// Open Food Facts normalises every mass nutriment in a `_100g` field to GRAMS
/// (sodium 0.5 → 0.5 g, cholesterol 0.02 → 0.02 g), but the food_log columns
/// store sodium + cholesterol in milligrams. Scale grams → mg; a missing value
/// stays null (never a phantom 0). Note the issue text only called out sodium,
/// but cholesterol_100g is grams too, so both need the ×1000.
function offGToMg(v: unknown): number | null {
	const n = num(v);
	return n == null ? null : n * 1000;
}

/// Extended nutrients (issue #492) from an Open Food Facts `nutriments` object.
/// Every field is optional upstream, so a missing one stays null, never 0.
function offExtended(n: Record<string, unknown>): Pick<
	FoodMacros,
	'fiberG' | 'sugarG' | 'sodiumMg' | 'saturatedFatG' | 'cholesterolMg'
> {
	return {
		fiberG: num(n.fiber_100g),
		sugarG: num(n.sugars_100g),
		sodiumMg: offGToMg(n.sodium_100g),
		saturatedFatG: num(n['saturated-fat_100g']),
		cholesterolMg: offGToMg(n.cholesterol_100g),
	};
}

/// Normalise a BCP-47 locale/tag to an Open Food Facts language code (`lc`) —
/// the primary subtag, lowercased (`pt-BR` → `pt`, `en` → `en`). Blank/unknown
/// falls back to English. Kept in lockstep with the Dart twin's `offLang`.
export function offLang(locale?: string | null): string {
	if (!locale) return 'en';
	const base = locale.split('-')[0].trim().toLowerCase();
	return base || 'en';
}

/// The best display name for an Open Food Facts product in language `lc`.
/// Open Food Facts is a global, community-contributed database: `product_name`
/// holds whatever language the contributor typed (Nordic contributors are very
/// active, so unfiltered it skews non-English), while `product_name_<lc>` holds
/// the per-language name where one exists. Prefer the localized field, fall
/// back to the generic name. Kept in lockstep with the Dart twin.
function offProductName(prod: Record<string, unknown>, lc: string): string {
	const localizedRaw = prod[`product_name_${lc}`];
	const localized = typeof localizedRaw === 'string' ? localizedRaw.trim() : '';
	if (localized) return localized;
	return typeof prod.product_name === 'string' ? prod.product_name.trim() : '';
}

/// Map a raw Open Food Facts search response into our result shape. Pure.
/// Drops products with no name or no calorie figure (unloggable noise).
/// `lang` picks which `product_name_<lc>` to prefer (see `offProductName`).
export function parseOffSearch(json: unknown, lang = 'en'): FoodSearchResult[] {
	const products = (json as { products?: unknown[] } | null)?.products;
	if (!Array.isArray(products)) return [];
	const lc = offLang(lang);
	const out: FoodSearchResult[] = [];
	for (const p of products) {
		const prod = p as Record<string, unknown>;
		const name = offProductName(prod, lc);
		const code = typeof prod.code === 'string' ? prod.code : '';
		const n = (prod.nutriments ?? {}) as Record<string, unknown>;
		const calories = num(n['energy-kcal_100g']);
		if (!name || !code || calories == null) continue;
		const brandRaw = typeof prod.brands === 'string' ? prod.brands.split(',')[0].trim() : '';
		out.push({
			code,
			source: 'off',
			name,
			brand: brandRaw || null,
			per100g: {
				calories,
				proteinG: num(n.proteins_100g) ?? 0,
				carbsG: num(n.carbohydrates_100g) ?? 0,
				fatG: num(n.fat_100g) ?? 0,
				...offExtended(n),
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
export function parseOffProduct(json: unknown, lang = 'en'): FoodSearchResult | null {
	const map = json as { status?: unknown; product?: unknown } | null;
	if (!map || map.status !== 1) return null;
	const p = map.product as Record<string, unknown> | undefined;
	if (!p || typeof p !== 'object') return null;
	const name = offProductName(p, offLang(lang));
	const code = typeof p.code === 'string' ? p.code : '';
	const n = (p.nutriments ?? {}) as Record<string, unknown>;
	const calories = num(n['energy-kcal_100g']);
	if (!name || !code || calories == null) return null;
	const brandRaw = typeof p.brands === 'string' ? p.brands.split(',')[0].trim() : '';
	return {
		code,
		source: 'off',
		name,
		brand: brandRaw || null,
		per100g: {
			calories,
			proteinG: num(n.proteins_100g) ?? 0,
			carbsG: num(n.carbohydrates_100g) ?? 0,
			fatG: num(n.fat_100g) ?? 0,
			...offExtended(n),
		},
	};
}

/// Scale a per-100 g result to a portion in grams, rounded to whole units. The
/// extended nutrients (issue #492) are nullable: a null (absent upstream) stays
/// null through the scale, never becoming a phantom 0.
export function scalePortion(per100g: FoodMacros, grams: number): FoodMacros {
	const f = grams > 0 ? grams / 100 : 0;
	const scale = (v: number | null | undefined): number | null =>
		v == null ? null : Math.round(v * f);
	return {
		calories: Math.round(per100g.calories * f),
		proteinG: Math.round(per100g.proteinG * f),
		carbsG: Math.round(per100g.carbsG * f),
		fatG: Math.round(per100g.fatG * f),
		fiberG: scale(per100g.fiberG),
		sugarG: scale(per100g.sugarG),
		sodiumMg: scale(per100g.sodiumMg),
		saturatedFatG: scale(per100g.saturatedFatG),
		cholesterolMg: scale(per100g.cholesterolMg),
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
	lang = 'en',
): Promise<FoodSearchResult[]> {
	const q = query.trim();
	if (!q) return [];
	const lc = offLang(lang);
	const params = new URLSearchParams({
		search_terms: q,
		search_simple: '1',
		action: 'process',
		json: '1',
		lc,
		page_size: String(limit),
		fields: `code,product_name,product_name_${lc},brands,nutriments`,
	});
	const res = await fetcher(`${SEARCH_URL}?${params.toString()}`);
	if (!res.ok) throw new Error(`Open Food Facts search failed: ${res.status}`);
	return parseOffSearch(await res.json(), lc);
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
	lang = 'en',
): Promise<FoodSearchResult | null> {
	const code = normaliseBarcode(barcode);
	if (code == null) return null;
	const lc = offLang(lang);
	const params = new URLSearchParams({
		lc,
		fields: `code,product_name,product_name_${lc},brands,nutriments`,
	});
	const res = await fetcher(`${PRODUCT_URL}/${code}.json?${params.toString()}`);
	if (!res.ok) throw new Error(`Open Food Facts product lookup failed: ${res.status}`);
	return parseOffProduct(await res.json(), lc);
}

/// USDA FDC nutrient numbers (`nutrientNumber`, the stable identifier) for the
/// four macros we log. Energy in kcal is 208 on legacy/SR-Legacy/Survey rows;
/// some rows additionally carry 957 (Energy, Atwater general). We key only on
/// 208 to match Open Food Facts' kcal basis and never mix kJ in.
const USDA_ENERGY_KCAL = '208';
const USDA_PROTEIN = '203';
const USDA_CARBS = '205';
const USDA_FAT = '204';
// Extended nutrients (issue #492). USDA already reports sodium (307) and
// cholesterol (601) in mg and fibre/sugar/saturated-fat in g — the exact units
// the food_log columns store — so no conversion is needed on the USDA side.
const USDA_FIBER = '291';
const USDA_SUGAR = '269';
const USDA_SODIUM = '307';
const USDA_SAT_FAT = '606';
const USDA_CHOLESTEROL = '601';

function usdaNutrient(nutrients: unknown, nutrientNumber: string): number | null {
	if (!Array.isArray(nutrients)) return null;
	for (const item of nutrients) {
		const fn = item as Record<string, unknown>;
		// The /v1/foods/search shape flattens the nutrient onto the array item
		// (`nutrientNumber` + `value`), unlike /v1/food/{id} which nests under
		// `nutrient`. Read the flat shape; fall back to the nested one defensively.
		const numberRaw =
			fn.nutrientNumber ?? (fn.nutrient as Record<string, unknown> | undefined)?.number;
		const number = typeof numberRaw === 'string' ? numberRaw : String(numberRaw ?? '');
		if (number !== nutrientNumber) continue;
		const value = fn.value ?? fn.amount;
		const n = num(value);
		if (n != null) return n;
	}
	return null;
}

/// Map a raw USDA FoodData Central `/v1/foods/search` response into our result
/// shape. Pure. Drops foods with no description or no calorie figure (the same
/// unloggable-noise filter Open Food Facts gets), so a USDA row slots into the
/// identical confirm-portion flow. USDA macros are already per 100 g.
export function parseUsdaSearch(json: unknown): FoodSearchResult[] {
	const foods = (json as { foods?: unknown[] } | null)?.foods;
	if (!Array.isArray(foods)) return [];
	const out: FoodSearchResult[] = [];
	for (const f of foods) {
		const food = f as Record<string, unknown>;
		const name = typeof food.description === 'string' ? food.description.trim() : '';
		const fdcId = food.fdcId;
		const code = typeof fdcId === 'number' ? String(fdcId) : typeof fdcId === 'string' ? fdcId : '';
		const calories = usdaNutrient(food.foodNutrients, USDA_ENERGY_KCAL);
		if (!name || !code || calories == null) continue;
		const brandRaw =
			typeof food.brandName === 'string'
				? food.brandName.trim()
				: typeof food.brandOwner === 'string'
					? food.brandOwner.trim()
					: '';
		out.push({
			code,
			source: 'usda',
			name,
			brand: brandRaw || null,
			per100g: {
				calories,
				proteinG: usdaNutrient(food.foodNutrients, USDA_PROTEIN) ?? 0,
				carbsG: usdaNutrient(food.foodNutrients, USDA_CARBS) ?? 0,
				fatG: usdaNutrient(food.foodNutrients, USDA_FAT) ?? 0,
				fiberG: usdaNutrient(food.foodNutrients, USDA_FIBER),
				sugarG: usdaNutrient(food.foodNutrients, USDA_SUGAR),
				sodiumMg: usdaNutrient(food.foodNutrients, USDA_SODIUM),
				saturatedFatG: usdaNutrient(food.foodNutrients, USDA_SAT_FAT),
				cholesterolMg: usdaNutrient(food.foodNutrients, USDA_CHOLESTEROL),
			},
		});
	}
	return out;
}

/// Search USDA FoodData Central. Returns [] for a blank query OR a blank API
/// key (the fail-closed gate — no key means no USDA source, never an error).
/// Otherwise THROWS on a network / non-2xx / parse failure, mirroring
/// `searchFoods`, so the merge caller can tell a failed source apart from an
/// empty one. The key travels as a query param per the FDC API contract.
export async function searchUsda(
	query: string,
	apiKey: string,
	fetcher: Fetcher = (u) => fetch(u),
	limit = 20,
): Promise<FoodSearchResult[]> {
	const q = query.trim();
	if (!q || !apiKey.trim()) return [];
	const params = new URLSearchParams({
		query: q,
		pageSize: String(limit),
		api_key: apiKey.trim(),
	});
	const res = await fetcher(`${USDA_SEARCH_URL}?${params.toString()}`);
	if (!res.ok) throw new Error(`USDA FoodData Central search failed: ${res.status}`);
	return parseUsdaSearch(await res.json());
}

/// Merge results from Open Food Facts and (when a key is provided) USDA into
/// one labelled, deduped list. Each source is queried in parallel; a failure
/// or absence of one source NEVER suppresses the other — a thrown OFF search
/// with a healthy USDA search still returns the USDA rows, and vice versa.
/// Only when BOTH configured sources fail does this throw, so the caller's
/// retry-vs-empty distinction still holds.
///
/// `usdaApiKey` empty/unset → USDA is simply not queried (the fail-closed
/// gate). Dedupe is by case-insensitive name+brand, keeping the first
/// occurrence; OFF is listed first so a barcoded branded product wins over the
/// looser USDA generic of the same name.
export async function searchFoodSources(
	query: string,
	opts: { fetcher?: Fetcher; usdaApiKey?: string; limit?: number; lang?: string } = {},
): Promise<FoodSearchResult[]> {
	const q = query.trim();
	if (!q) return [];
	const fetcher = opts.fetcher ?? ((u) => fetch(u));
	const limit = opts.limit ?? 20;
	const usdaKey = (opts.usdaApiKey ?? '').trim();
	const lang = opts.lang ?? 'en';

	const sources: Promise<FoodSearchResult[]>[] = [searchFoods(q, fetcher, limit, lang)];
	if (usdaKey) sources.push(searchUsda(q, usdaKey, fetcher, limit));

	const settled = await Promise.allSettled(sources);
	const fulfilled = settled.filter((s) => s.status === 'fulfilled');
	// Every configured source failed → surface the failure (retry, not a
	// misleading empty). A partial failure degrades to the healthy source.
	if (fulfilled.length === 0) {
		const first = settled[0] as PromiseRejectedResult;
		throw first.reason instanceof Error ? first.reason : new Error('Food search failed');
	}

	const merged: FoodSearchResult[] = [];
	for (const s of fulfilled) merged.push(...(s as PromiseFulfilledResult<FoodSearchResult[]>).value);
	return dedupeFoods(merged);
}

/// Drop duplicate foods by case- and accent-insensitive name+brand, keeping
/// the first occurrence (so the source order passed in decides the winner).
/// Pure.
///
/// The key folds through `catalogue_browse`'s generated table rather than the
/// runtime's own `toLowerCase`, for the reason the Dart twin exists at all:
/// the two runtimes' lower-case disagree at 466 code points (decisions § 854),
/// so a Turkish product name collapsed two rows into one on the phone and left
/// two on the web from the same two searches. Folding the accents too is the
/// point of the dedupe and not a side effect — the two sources spell the same
/// product differently, and `Café Latte` from Open Food Facts beside
/// `Cafe Latte` from USDA is one product listed twice.
export function dedupeFoods(results: FoodSearchResult[]): FoodSearchResult[] {
	const seen = new Set<string>();
	const out: FoodSearchResult[] = [];
	for (const r of results) {
		const key = `${fold(r.name.trim())} ${fold((r.brand ?? '').trim())}`;
		if (seen.has(key)) continue;
		seen.add(key);
		out.push(r);
	}
	return out;
}
