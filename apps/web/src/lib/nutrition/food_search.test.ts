import assert from 'node:assert/strict';
import { test } from 'node:test';

import { parseOffSearch, scalePortion, searchFoods, type Fetcher } from './food_search';

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
