// Unit tests for the map-style URL builder. Pin both the legacy
// MapTiler-keyed path AND the PUBLIC_TILE_STYLE_URL override that
// drives the local Protomaps tileserver-gl dev setup.
//
// Invocation:
//   npx tsx --test src/lib/map-style.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildMapStyleUrl } from './map-style-url';

test('no override + light mode → MapTiler streets-v2', () => {
	const url = buildMapStyleUrl('streets', 'KEY', false);
	assert.equal(
		url,
		'https://api.maptiler.com/maps/streets-v2/style.json?key=KEY',
	);
});

test('no override + dark mode → MapTiler streets-v2-dark', () => {
	const url = buildMapStyleUrl('streets', 'KEY', true);
	assert.equal(
		url,
		'https://api.maptiler.com/maps/streets-v2-dark/style.json?key=KEY',
	);
});

test('satellite + dark → MapTiler satellite slug', () => {
	const url = buildMapStyleUrl('satellite', 'KEY', true);
	assert.equal(
		url,
		'https://api.maptiler.com/maps/satellite/style.json?key=KEY',
	);
});

test('outdoors + light → MapTiler outdoor-v2 slug', () => {
	const url = buildMapStyleUrl('outdoors', 'KEY', false);
	assert.equal(
		url,
		'https://api.maptiler.com/maps/outdoor-v2/style.json?key=KEY',
	);
});

test('explicit dark style overrides prefersDark=false', () => {
	const url = buildMapStyleUrl('dark', 'KEY', false);
	assert.equal(
		url,
		'https://api.maptiler.com/maps/streets-v2-dark/style.json?key=KEY',
	);
});

test('empty-string override is treated as absent', () => {
	const url = buildMapStyleUrl('streets', 'KEY', false, '');
	assert.ok(url.includes('api.maptiler.com'));
});

test('undefined override falls back to MapTiler', () => {
	const url = buildMapStyleUrl('streets', 'KEY', false, undefined);
	assert.ok(url.includes('api.maptiler.com'));
});

test('non-empty override wins outright — local dev path', () => {
	const url = buildMapStyleUrl(
		'streets',
		'KEY',
		false,
		'http://localhost:8080/styles/basic/style.json',
	);
	assert.equal(url, 'http://localhost:8080/styles/basic/style.json');
});

test('override wins even when the API key is empty (no-key local dev)', () => {
	// The local Protomaps tileserver-gl doesn't require an API key.
	// Passing '' for the key alongside a populated override must not
	// produce a URL with a trailing `?key=` that some CDNs reject.
	const url = buildMapStyleUrl(
		'streets',
		'',
		false,
		'http://localhost:8080/styles/basic/style.json',
	);
	assert.equal(url, 'http://localhost:8080/styles/basic/style.json');
	assert.ok(!url.includes('?key='),
		'override path must not append the key parameter');
});

test('override wins regardless of the chosen style preference', () => {
	const override = 'http://10.0.2.2:8080/styles/basic/style.json';
	for (const style of ['streets', 'dark', 'satellite', 'outdoors'] as const) {
		const url = buildMapStyleUrl(style, 'KEY', false, override);
		assert.equal(url, override,
			`style=${style} must not bypass the override`);
	}
});

test('IPv6 override URL round-trips intact', () => {
	const url = buildMapStyleUrl(
		'streets',
		'KEY',
		false,
		'http://[::1]:8080/styles/basic/style.json',
	);
	assert.equal(url, 'http://[::1]:8080/styles/basic/style.json');
});
