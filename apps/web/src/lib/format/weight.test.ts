// `npx tsx --test src/lib/format/weight.test.ts`
//
// Pure kg <-> lbs conversion + display/parse contract for the
// `weight_unit` preference. The reactive signal lives in units.svelte.ts
// (runes, not tsx-testable); this pins the pure math the signal delegates
// to and is mirrored by the mobile Dart twin.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	parseWeightUnit,
	kgToDisplay,
	displayToKg,
	roundWeight,
	formatWeightKg,
	parseWeightToKg,
} from './weight.js';

test('parseWeightUnit: only "lbs" maps to lbs, everything else to kg', () => {
	assert.equal(parseWeightUnit('lbs'), 'lbs');
	assert.equal(parseWeightUnit('kg'), 'kg');
	assert.equal(parseWeightUnit(null), 'kg');
	assert.equal(parseWeightUnit(undefined), 'kg');
	assert.equal(parseWeightUnit('pounds'), 'kg');
});

test('kg is identity in kg, scaled in lbs', () => {
	assert.equal(kgToDisplay(60, 'kg'), 60);
	assert.ok(Math.abs(kgToDisplay(60, 'lbs') - 132.277) < 0.01);
	assert.equal(displayToKg(60, 'kg'), 60);
	assert.ok(Math.abs(displayToKg(132.277, 'lbs') - 60) < 0.001);
});

test('kg -> display -> kg round-trips within float tolerance', () => {
	for (const kg of [0, 2.5, 20, 42.5, 100, 227.5]) {
		for (const unit of ['kg', 'lbs'] as const) {
			const back = displayToKg(kgToDisplay(kg, unit), unit);
			assert.ok(
				Math.abs(back - kg) < 1e-9,
				`round-trip ${kg}kg via ${unit} -> ${back}`,
			);
		}
	}
});

test('lbs -> kg -> lbs round-trips a user-typed value', () => {
	for (const lbs of [45, 135, 225, 315]) {
		const kg = displayToKg(lbs, 'lbs');
		const back = roundWeight(kgToDisplay(kg, 'lbs'));
		assert.ok(Math.abs(back - lbs) < 0.05, `${lbs}lbs round-trip -> ${back}`);
	}
});

test('formatWeightKg: integer values drop the trailing .0; suffix baked in', () => {
	assert.equal(formatWeightKg(60, 'kg'), '60 kg');
	assert.equal(formatWeightKg(62.5, 'kg'), '62.5 kg');
	assert.equal(formatWeightKg(60, 'lbs'), '132.3 lbs');
});

test('formatWeightKg: null / NaN render as an em dash', () => {
	assert.equal(formatWeightKg(null, 'kg'), '—');
	assert.equal(formatWeightKg(undefined, 'lbs'), '—');
	assert.equal(formatWeightKg(NaN, 'kg'), '—');
});

test('parseWeightToKg: interprets the typed value in the active unit', () => {
	assert.equal(parseWeightToKg('60', 'kg'), 60);
	const fromLbs = parseWeightToKg('132.277', 'lbs');
	assert.ok(fromLbs != null && Math.abs(fromLbs - 60) < 0.001);
});

test('parseWeightToKg: tolerates a comma decimal separator', () => {
	assert.equal(parseWeightToKg('62,5', 'kg'), 62.5);
});

test('parseWeightToKg: empty / non-numeric / negative -> null', () => {
	assert.equal(parseWeightToKg('', 'kg'), null);
	assert.equal(parseWeightToKg('   ', 'kg'), null);
	assert.equal(parseWeightToKg('abc', 'kg'), null);
	assert.equal(parseWeightToKg('-5', 'kg'), null);
	assert.equal(parseWeightToKg(null, 'lbs'), null);
});
