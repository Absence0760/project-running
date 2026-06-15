import assert from 'node:assert/strict';
import { test } from 'node:test';

import { parseOffSearch, scalePortion, searchFoods, type Fetcher } from './food_search';

test('parseOffSearch — keeps multiple loggable products in source order', () => {
	const out = parseOffSearch({
		products: [
			{ code: 'a', product_name: 'Apple', nutriments: { 'energy-kcal_100g': 52 } },
			{ code: 'b', product_name: 'Banana', nutriments: { 'energy-kcal_100g': 89 } },
		],
	});
	assert.deepEqual(
		out.map((p) => p.name),
		['Apple', 'Banana'],
	);
});

test('parseOffSearch — drops a product missing its barcode (code)', () => {
	const out = parseOffSearch({
		products: [{ product_name: 'No Code', nutriments: { 'energy-kcal_100g': 100 } }],
	});
	assert.equal(out.length, 0);
});

test('parseOffSearch — a negative nutriment is rejected (treated as missing → 0)', () => {
	// num() rejects negatives; the calorie field being negative drops the whole
	// product, while a negative macro falls back to 0.
	const dropped = parseOffSearch({
		products: [{ code: 'x', product_name: 'Bad', nutriments: { 'energy-kcal_100g': -5 } }],
	});
	assert.equal(dropped.length, 0);

	const macroZeroed = parseOffSearch({
		products: [
			{
				code: 'y',
				product_name: 'Negative Protein',
				nutriments: { 'energy-kcal_100g': 100, proteins_100g: -3 },
			},
		],
	});
	assert.equal(macroZeroed[0].per100g.proteinG, 0);
});

test('parseOffSearch — a NaN-ish nutriment string falls back rather than poisoning macros', () => {
	const out = parseOffSearch({
		products: [
			{
				code: 'z',
				product_name: 'Weird',
				nutriments: { 'energy-kcal_100g': 100, carbohydrates_100g: 'abc' },
			},
		],
	});
	assert.equal(out.length, 1);
	assert.equal(out[0].per100g.carbsG, 0);
});

test('parseOffSearch — a brand with surrounding whitespace is trimmed; empty brand → null', () => {
	const out = parseOffSearch({
		products: [
			{ code: 'a', product_name: 'A', brands: '  Acme , Other', nutriments: { 'energy-kcal_100g': 1 } },
			{ code: 'b', product_name: 'B', brands: '   ', nutriments: { 'energy-kcal_100g': 1 } },
			{ code: 'c', product_name: 'C', nutriments: { 'energy-kcal_100g': 1 } },
		],
	});
	assert.equal(out[0].brand, 'Acme');
	assert.equal(out[1].brand, null); // whitespace-only → null
	assert.equal(out[2].brand, null); // absent → null
});

test('scalePortion — scales up past 100 g linearly', () => {
	const per100g = { calories: 200, proteinG: 10, carbsG: 20, fatG: 5 };
	const big = scalePortion(per100g, 250);
	assert.equal(big.calories, 500);
	assert.equal(big.proteinG, 25);
	assert.equal(big.carbsG, 50);
	assert.equal(big.fatG, 13); // 12.5 → 13
});

test('scalePortion — a negative gram amount yields all zeros (never negative macros)', () => {
	const per100g = { calories: 200, proteinG: 10, carbsG: 20, fatG: 5 };
	assert.deepEqual(scalePortion(per100g, -50), {
		calories: 0,
		proteinG: 0,
		carbsG: 0,
		fatG: 0,
	});
});

test('searchFoods — encodes the page_size limit into the request URL', async () => {
	let seen = '';
	const fetcher: Fetcher = async (url) => {
		seen = url;
		return new Response(JSON.stringify({ products: [] }), { status: 200 });
	};
	await searchFoods('oats', fetcher, 7);
	assert.ok(seen.includes('page_size=7'));
	assert.ok(seen.includes('json=1'));
	assert.ok(seen.includes('search_simple=1'));
});

test('searchFoods — trims the query before sending it', async () => {
	let seen = '';
	const fetcher: Fetcher = async (url) => {
		seen = url;
		return new Response(JSON.stringify({ products: [] }), { status: 200 });
	};
	await searchFoods('  greek yogurt  ', fetcher);
	assert.ok(seen.includes('search_terms=greek+yogurt'));
	assert.ok(!seen.includes('search_terms=++'));
});

test('searchFoods — a 200 response with malformed JSON throws (a garbage body is a failure, not "no matches")', async () => {
	const fetcher: Fetcher = async () => new Response('not json', { status: 200 });
	await assert.rejects(() => searchFoods('oats', fetcher));
});

test('searchFoods — a 200 response with valid JSON but no products is genuinely empty (returns [])', async () => {
	const fetcher: Fetcher = async () => new Response(JSON.stringify({ products: [] }), { status: 200 });
	assert.deepEqual(await searchFoods('oats', fetcher), []);
});
