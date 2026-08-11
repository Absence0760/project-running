import assert from 'node:assert/strict';
import { test } from 'node:test';

import { sameInstant, selectEffectivePricing } from './event_instance';

// The exact pair that made every per-instance override unreachable: PostgREST's
// rendering of a timestamptz vs the client's Date#toISOString of the same
// instant.
const FROM_DB: string = '2026-06-01T18:00:00+00:00';
const FROM_CLIENT: string = '2026-06-01T18:00:00.000Z';

test('sameInstant matches the PostgREST and toISOString renderings', () => {
	assert.equal(FROM_DB === FROM_CLIENT, false, 'precondition: they differ as strings');
	assert.equal(sameInstant(FROM_DB, FROM_CLIENT), true);
	assert.equal(sameInstant(FROM_CLIENT, FROM_DB), true);
});

test('sameInstant matches across offsets naming the same moment', () => {
	assert.equal(sameInstant('2026-06-01T20:00:00+02:00', FROM_CLIENT), true);
});

test('sameInstant separates different instants', () => {
	assert.equal(sameInstant('2026-06-08T18:00:00+00:00', FROM_CLIENT), false);
	assert.equal(sameInstant('2026-06-01T18:00:01+00:00', FROM_CLIENT), false);
});

test('sameInstant treats an unknown side as not equal, never as a match', () => {
	assert.equal(sameInstant(null, FROM_CLIENT), false);
	assert.equal(sameInstant(FROM_CLIENT, null), false);
	assert.equal(sameInstant(undefined, undefined), false);
	assert.equal(sameInstant(null, null), false);
	assert.equal(sameInstant('not a date', FROM_CLIENT), false);
	assert.equal(sameInstant(FROM_CLIENT, ''), false);
});

test('selectEffectivePricing prefers the override for that instant', () => {
	const rows = [
		{ instance_start: null, price_cents: 2200 },
		{ instance_start: FROM_DB, price_cents: 4400 }
	];
	assert.equal(selectEffectivePricing(rows, FROM_CLIENT)?.price_cents, 4400);
});

test('selectEffectivePricing falls back to the series default', () => {
	const rows = [
		{ instance_start: null, price_cents: 2200 },
		{ instance_start: '2026-06-08T18:00:00+00:00', price_cents: 4400 }
	];
	assert.equal(selectEffectivePricing(rows, FROM_CLIENT)?.price_cents, 2200);
});

test('selectEffectivePricing returns the series row when no instance is asked for', () => {
	const rows = [{ instance_start: null, price_cents: 2200 }];
	assert.equal(selectEffectivePricing(rows, null)?.price_cents, 2200);
	assert.equal(selectEffectivePricing(rows, undefined)?.price_cents, 2200);
});

test('selectEffectivePricing returns null when the event is unpriced', () => {
	assert.equal(selectEffectivePricing([], FROM_CLIENT), null);
	assert.equal(
		selectEffectivePricing([{ instance_start: '2026-06-08T18:00:00+00:00' }], FROM_CLIENT),
		null,
		'an override for a DIFFERENT instance is not a series default'
	);
});
