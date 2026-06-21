import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	dedupeFoods,
	lookupBarcode,
	normaliseBarcode,
	parseOffProduct,
	parseOffSearch,
	parseUsdaSearch,
	scalePortion,
	searchFoodSources,
	searchFoods,
	searchUsda,
	type Fetcher,
	type FoodSearchResult,
} from './food_search';

const sample = {
	products: [
		{
			code: '111',
			product_name: 'Rolled Oats',
			brands: 'Quaker, StoreBrand',
			nutriments: {
				'energy-kcal_100g': 389,
				proteins_100g: 16.9,
				carbohydrates_100g: 66.3,
				fat_100g: 6.9,
			},
		},
		{
			// no calories → dropped
			code: '222',
			product_name: 'Mystery Item',
			nutriments: { proteins_100g: 5 },
		},
		{
			// no name → dropped
			code: '333',
			product_name: '   ',
			nutriments: { 'energy-kcal_100g': 100 },
		},
	],
};

test('parseOffSearch maps products and drops unloggable ones', () => {
	const out = parseOffSearch(sample);
	assert.equal(out.length, 1);
	assert.equal(out[0].code, '111');
	assert.equal(out[0].name, 'Rolled Oats');
	assert.equal(out[0].brand, 'Quaker'); // first brand only
	assert.equal(out[0].per100g.calories, 389);
	assert.equal(out[0].per100g.proteinG, 16.9);
	assert.equal(out[0].source, 'off');
});

test('parseOffSearch tolerates string-typed nutriment numbers', () => {
	const out = parseOffSearch({
		products: [
			{
				code: 'c',
				product_name: 'X',
				nutriments: { 'energy-kcal_100g': '250', proteins_100g: '10' },
			},
		],
	});
	assert.equal(out[0].per100g.calories, 250);
	assert.equal(out[0].per100g.proteinG, 10);
});

test('parseOffSearch drops a product whose calorie field is a blank string', () => {
	// Open Food Facts very commonly returns "" for a nutriment it has no value
	// for. Number('') === 0, so without a blank-guard this kept the product as a
	// phantom 0-kcal entry — contradicting the "drops … no calorie figure" contract.
	const out = parseOffSearch({
		products: [
			{ code: 'a', product_name: 'Blank Energy', nutriments: { 'energy-kcal_100g': '' } },
			{ code: 'b', product_name: 'Whitespace Energy', nutriments: { 'energy-kcal_100g': '   ' } },
			// a genuine numeric 0 (e.g. water) is loggable and must be KEPT
			{ code: 'c', product_name: 'Water', nutriments: { 'energy-kcal_100g': 0 } },
		],
	});
	assert.equal(out.length, 1);
	assert.equal(out[0].code, 'c');
	assert.equal(out[0].per100g.calories, 0);
});

test('parseOffSearch returns [] on malformed input', () => {
	assert.deepEqual(parseOffSearch(null), []);
	assert.deepEqual(parseOffSearch({}), []);
	assert.deepEqual(parseOffSearch({ products: 'nope' }), []);
});

test('scalePortion scales per-100g to a gram portion, rounded', () => {
	const per100g = { calories: 389, proteinG: 16.9, carbsG: 66.3, fatG: 6.9 };
	const half = scalePortion(per100g, 50);
	assert.equal(half.calories, 195); // 389 * 0.5 = 194.5 → 195
	assert.equal(half.proteinG, 8); // 8.45 → 8
	const none = scalePortion(per100g, 0);
	assert.equal(none.calories, 0);
});

test('searchFoods returns [] for an empty query without calling the fetcher', async () => {
	let called = false;
	const fetcher: Fetcher = async () => {
		called = true;
		return new Response('{}');
	};
	const out = await searchFoods('   ', fetcher);
	assert.deepEqual(out, []);
	assert.equal(called, false);
});

test('searchFoods parses a successful response via the injected fetcher', async () => {
	const fetcher: Fetcher = async (url) => {
		assert.ok(url.includes('search_terms=oats'));
		return new Response(JSON.stringify(sample), { status: 200 });
	};
	const out = await searchFoods('oats', fetcher);
	assert.equal(out.length, 1);
	assert.equal(out[0].name, 'Rolled Oats');
});

test('searchFoods throws on a non-OK response (so the caller can show retry, not empty)', async () => {
	const bad: Fetcher = async () => new Response('', { status: 500 });
	await assert.rejects(() => searchFoods('oats', bad));
});

test('searchFoods propagates a network throw (failure is distinct from empty)', async () => {
	const thrower: Fetcher = async () => {
		throw new Error('network down');
	};
	await assert.rejects(() => searchFoods('oats', thrower), /network down/);
});

const productSample = {
	status: 1,
	product: {
		code: '737628064502',
		product_name: 'Rolled Oats',
		brands: 'Quaker, StoreBrand',
		nutriments: {
			'energy-kcal_100g': 389,
			proteins_100g: 16.9,
			carbohydrates_100g: 66.3,
			fat_100g: 6.9,
		},
	},
};

test('normaliseBarcode strips non-digits and rejects empty', () => {
	assert.equal(normaliseBarcode(' 737628064502\n'), '737628064502');
	assert.equal(normaliseBarcode('EAN 4006381333931'), '4006381333931');
	assert.equal(normaliseBarcode('abc'), null);
	assert.equal(normaliseBarcode(''), null);
});

test('parseOffProduct maps a found product', () => {
	const r = parseOffProduct(productSample);
	assert.ok(r);
	assert.equal(r?.code, '737628064502');
	assert.equal(r?.name, 'Rolled Oats');
	assert.equal(r?.brand, 'Quaker');
	assert.equal(r?.per100g.calories, 389);
});

test('parseOffProduct returns null for a missing product or unloggable one', () => {
	assert.equal(parseOffProduct({ status: 0, product: {} }), null);
	assert.equal(parseOffProduct(null), null);
	assert.equal(
		parseOffProduct({ status: 1, product: { code: 'x', product_name: 'No Energy', nutriments: {} } }),
		null,
	);
});

test('lookupBarcode returns null for a blank / non-numeric code without calling the fetcher', async () => {
	let called = false;
	const fetcher: Fetcher = async () => {
		called = true;
		return new Response('{}');
	};
	assert.equal(await lookupBarcode('  ', fetcher), null);
	assert.equal(called, false);
});

test('lookupBarcode parses a found product via the injected fetcher', async () => {
	const fetcher: Fetcher = async (url) => {
		assert.ok(url.includes('/api/v2/product/737628064502.json'));
		return new Response(JSON.stringify(productSample), { status: 200 });
	};
	const r = await lookupBarcode('737628064502', fetcher);
	assert.equal(r?.name, 'Rolled Oats');
});

test('lookupBarcode returns null on a genuine no-match (status 0)', async () => {
	const fetcher: Fetcher = async () => new Response(JSON.stringify({ status: 0 }), { status: 200 });
	assert.equal(await lookupBarcode('000000000000', fetcher), null);
});

test('lookupBarcode throws on a non-OK response (failure is distinct from no-match)', async () => {
	const bad: Fetcher = async () => new Response('', { status: 500 });
	await assert.rejects(() => lookupBarcode('737628064502', bad));
});

const usdaSample = {
	foods: [
		{
			fdcId: 555,
			description: 'Oats, raw',
			brandName: 'Generic',
			foodNutrients: [
				{ nutrientNumber: '208', value: 389 },
				{ nutrientNumber: '203', value: 16.9 },
				{ nutrientNumber: '205', value: 66.3 },
				{ nutrientNumber: '204', value: 6.9 },
			],
		},
		{
			// no energy figure → dropped (unloggable noise, like OFF)
			fdcId: 666,
			description: 'Mystery Powder',
			foodNutrients: [{ nutrientNumber: '203', value: 5 }],
		},
		{
			// no description → dropped
			fdcId: 777,
			description: '   ',
			foodNutrients: [{ nutrientNumber: '208', value: 100 }],
		},
	],
};

test('parseUsdaSearch maps foods and drops unloggable ones', () => {
	const out = parseUsdaSearch(usdaSample);
	assert.equal(out.length, 1);
	assert.equal(out[0].code, '555'); // numeric fdcId stringified
	assert.equal(out[0].source, 'usda');
	assert.equal(out[0].name, 'Oats, raw');
	assert.equal(out[0].brand, 'Generic');
	assert.equal(out[0].per100g.calories, 389);
	assert.equal(out[0].per100g.proteinG, 16.9);
	assert.equal(out[0].per100g.carbsG, 66.3);
	assert.equal(out[0].per100g.fatG, 6.9);
});

test('parseUsdaSearch tolerates the nested nutrient shape + string fdcId + brandOwner fallback', () => {
	const out = parseUsdaSearch({
		foods: [
			{
				fdcId: 'abc',
				description: 'Nested Food',
				brandOwner: 'Acme',
				foodNutrients: [
					{ nutrient: { number: '208' }, amount: 250 },
					{ nutrient: { number: '203' }, amount: 10 },
				],
			},
		],
	});
	assert.equal(out[0].code, 'abc');
	assert.equal(out[0].brand, 'Acme');
	assert.equal(out[0].per100g.calories, 250);
	assert.equal(out[0].per100g.proteinG, 10);
});

test('parseUsdaSearch ignores a non-208 energy nutrient (never mixes kJ in)', () => {
	const out = parseUsdaSearch({
		foods: [
			{
				fdcId: 1,
				description: 'KJ Only',
				// 268 = Energy in kJ; without a 208 row this food is unloggable
				foodNutrients: [{ nutrientNumber: '268', value: 1600 }],
			},
		],
	});
	assert.deepEqual(out, []);
});

test('parseUsdaSearch returns [] on malformed input', () => {
	assert.deepEqual(parseUsdaSearch(null), []);
	assert.deepEqual(parseUsdaSearch({}), []);
	assert.deepEqual(parseUsdaSearch({ foods: 'nope' }), []);
});

test('searchUsda short-circuits to [] when the API key is blank (fail-closed gate)', async () => {
	let called = false;
	const fetcher: Fetcher = async () => {
		called = true;
		return new Response('{}');
	};
	assert.deepEqual(await searchUsda('oats', '', fetcher), []);
	assert.deepEqual(await searchUsda('oats', '   ', fetcher), []);
	assert.equal(called, false);
});

test('searchUsda parses a successful response + sends the key as a query param', async () => {
	const fetcher: Fetcher = async (url) => {
		assert.ok(url.includes('query=oats'));
		assert.ok(url.includes('api_key=SECRET'));
		return new Response(JSON.stringify(usdaSample), { status: 200 });
	};
	const out = await searchUsda('oats', 'SECRET', fetcher);
	assert.equal(out.length, 1);
	assert.equal(out[0].source, 'usda');
});

test('searchUsda throws on a non-OK response', async () => {
	const bad: Fetcher = async () => new Response('', { status: 403 });
	await assert.rejects(() => searchUsda('oats', 'SECRET', bad));
});

test('searchFoodSources queries OFF only when no USDA key is set', async () => {
	const urls: string[] = [];
	const fetcher: Fetcher = async (url) => {
		urls.push(url);
		return new Response(JSON.stringify(sample), { status: 200 });
	};
	const out = await searchFoodSources('oats', { fetcher });
	assert.equal(urls.length, 1);
	assert.ok(urls[0].includes('openfoodfacts'));
	assert.equal(out.length, 1);
	assert.equal(out[0].source, 'off');
});

test('searchFoodSources merges both sources, OFF first, when a USDA key is set', async () => {
	const fetcher: Fetcher = async (url) =>
		url.includes('usda')
			? new Response(JSON.stringify(usdaSample), { status: 200 })
			: new Response(JSON.stringify(sample), { status: 200 });
	const out = await searchFoodSources('oats', { fetcher, usdaApiKey: 'SECRET' });
	assert.equal(out.length, 2);
	assert.equal(out[0].source, 'off'); // OFF listed first
	assert.equal(out[1].source, 'usda');
});

test('searchFoodSources degrades to the healthy source when one fails', async () => {
	const fetcher: Fetcher = async (url) => {
		if (url.includes('usda')) return new Response(JSON.stringify(usdaSample), { status: 200 });
		throw new Error('OFF down');
	};
	const out = await searchFoodSources('oats', { fetcher, usdaApiKey: 'SECRET' });
	assert.equal(out.length, 1);
	assert.equal(out[0].source, 'usda'); // OFF failure didn't suppress USDA
});

test('searchFoodSources throws only when every configured source fails', async () => {
	const fetcher: Fetcher = async () => {
		throw new Error('all down');
	};
	await assert.rejects(() => searchFoodSources('oats', { fetcher, usdaApiKey: 'SECRET' }), /all down/);
});

test('dedupeFoods drops case-insensitive name+brand dupes, keeping the first', () => {
	const off: FoodSearchResult = {
		code: '1',
		source: 'off',
		name: 'Rolled Oats',
		brand: 'Quaker',
		per100g: { calories: 389, proteinG: 16, carbsG: 66, fatG: 7 },
	};
	const usdaDupe: FoodSearchResult = {
		code: '2',
		source: 'usda',
		name: 'rolled oats',
		brand: 'quaker',
		per100g: { calories: 380, proteinG: 15, carbsG: 65, fatG: 6 },
	};
	const distinct: FoodSearchResult = { ...usdaDupe, code: '3', name: 'Steel Cut Oats' };
	const out = dedupeFoods([off, usdaDupe, distinct]);
	assert.equal(out.length, 2);
	assert.equal(out[0].code, '1'); // OFF kept (first wins)
	assert.equal(out[1].code, '3');
});
