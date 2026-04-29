import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseRunSource, type RunSource } from './types';

test('parseRunSource — every valid RunSource passes through', () => {
	const all: RunSource[] = [
		'app',
		'watch',
		'healthkit',
		'healthconnect',
		'strava',
		'garmin',
		'parkrun',
		'race',
	];
	for (const s of all) {
		assert.equal(parseRunSource(s), s);
	}
});

test('parseRunSource — null falls back to app', () => {
	assert.equal(parseRunSource(null), 'app');
});

test('parseRunSource — undefined falls back to app', () => {
	assert.equal(parseRunSource(undefined), 'app');
});

test('parseRunSource — empty string falls back to app', () => {
	assert.equal(parseRunSource(''), 'app');
});

test('parseRunSource — unknown string falls back to app', () => {
	assert.equal(parseRunSource('zwift'), 'app');
});

test('parseRunSource — case-mismatched falls back to app', () => {
	assert.equal(parseRunSource('Watch'), 'app');
	assert.equal(parseRunSource('STRAVA'), 'app');
});
