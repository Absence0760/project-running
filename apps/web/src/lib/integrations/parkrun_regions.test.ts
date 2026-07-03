import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { parkrunLikelyUnavailable, PARKRUN_REGIONS } from './parkrun_regions';

test('parkrun regions show no hint', () => {
	assert.equal(parkrunLikelyUnavailable('en-US'), false);
	assert.equal(parkrunLikelyUnavailable('en-GB'), false);
	assert.equal(parkrunLikelyUnavailable('de-DE'), false);
	assert.equal(parkrunLikelyUnavailable('ja-JP'), false);
	assert.equal(parkrunLikelyUnavailable('en-AU'), false);
	assert.equal(parkrunLikelyUnavailable('af-ZA'), false);
});

test('regions outside the parkrun footprint show the hint', () => {
	assert.equal(parkrunLikelyUnavailable('es-ES'), true);
	assert.equal(parkrunLikelyUnavailable('fr-FR'), true);
	assert.equal(parkrunLikelyUnavailable('pt-BR'), true);
	assert.equal(parkrunLikelyUnavailable('id-ID'), true);
	assert.equal(parkrunLikelyUnavailable('zh-Hant-TW'), true);
});

test('an unknown or region-less locale shows no hint (no false warning)', () => {
	assert.equal(parkrunLikelyUnavailable('en'), false);
	assert.equal(parkrunLikelyUnavailable(''), false);
	assert.equal(parkrunLikelyUnavailable('not-a-locale!!'), false);
});

test('region codes are two-letter uppercase', () => {
	for (const r of PARKRUN_REGIONS) {
		assert.match(r, /^[A-Z]{2}$/);
	}
});
