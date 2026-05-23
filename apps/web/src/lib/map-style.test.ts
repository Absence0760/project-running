// Unit tests for the map-style URL builder. Pin both the legacy
// MapTiler-keyed path AND the PUBLIC_TILE_STYLE_URL override that
// drives the local Protomaps tileserver-gl dev setup.
//
// Invocation:
//   npx tsx --test src/lib/map-style.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildMapStyleUrl, resolveStyleOverride } from './map-style-url';

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

// Parses a URL string and returns its host (so test assertions can
// compare exact hosts instead of doing a sloppy substring match —
// satisfies CodeQL js/incomplete-url-substring-sanitization).
function hostOf(url: string): string {
	return new URL(url).host;
}

test('empty-string override is treated as absent', () => {
	const url = buildMapStyleUrl('streets', 'KEY', false, '');
	assert.equal(hostOf(url), 'api.maptiler.com');
});

test('undefined override falls back to MapTiler', () => {
	const url = buildMapStyleUrl('streets', 'KEY', false, undefined);
	assert.equal(hostOf(url), 'api.maptiler.com');
});

test('whitespace-only override falls back to MapTiler (no silent breakage)',
	() => {
		// A stray space after `PUBLIC_TILE_STYLE_URL=` in .env.local
		// is a really common copy/paste mistake. Treating it as a
		// valid override would silently break MapTiler at runtime.
		// Pin the trim-then-check behaviour.
		for (const ws of [' ', '   ', '\t', '\n', ' \t\n ']) {
			const url = buildMapStyleUrl('streets', 'KEY', false, ws);
			assert.equal(
				hostOf(url),
				'api.maptiler.com',
				`whitespace value ${JSON.stringify(ws)} must fall through`,
			);
		}
	});

test('override with surrounding whitespace is trimmed', () => {
	const url = buildMapStyleUrl(
		'streets',
		'KEY',
		false,
		'  http://localhost:8080/styles/basic/style.json\n',
	);
	assert.equal(url, 'http://localhost:8080/styles/basic/style.json');
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

test('override with query params round-trips intact', () => {
	const url = buildMapStyleUrl(
		'streets',
		'KEY',
		false,
		'http://localhost:8080/styles/basic/style.json?token=abc',
	);
	assert.equal(url,
		'http://localhost:8080/styles/basic/style.json?token=abc');
});

// ---- resolveStyleOverride (env-reading test seam) -----------------------

test('resolveStyleOverride: getter returning undefined → empty string', () => {
	assert.equal(resolveStyleOverride(() => undefined), '');
});

test('resolveStyleOverride: getter returning null is handled (typed undefined-only but defensive)',
	() => {
		// The signature is `() => string | undefined` but a real
		// `import.meta.env.X` value can be `null` at runtime in
		// some edge configurations. Make sure the helper handles
		// it without throwing.
		assert.equal(
			resolveStyleOverride(() => null as unknown as undefined),
			'',
		);
	});

test('resolveStyleOverride: empty string → empty string', () => {
	assert.equal(resolveStyleOverride(() => ''), '');
});

test('resolveStyleOverride: whitespace-only → empty string', () => {
	for (const ws of [' ', '   ', '\t', '\n', ' \t\n ']) {
		assert.equal(resolveStyleOverride(() => ws), '',
			`whitespace ${JSON.stringify(ws)} must resolve to empty`);
	}
});

test('resolveStyleOverride: non-empty value passes through trimmed', () => {
	assert.equal(
		resolveStyleOverride(() => 'http://localhost:8080/style.json'),
		'http://localhost:8080/style.json',
	);
});

test('resolveStyleOverride: surrounding whitespace is trimmed', () => {
	assert.equal(
		resolveStyleOverride(() => '  http://localhost:8080/style.json\n'),
		'http://localhost:8080/style.json',
	);
});

test('resolveStyleOverride: getter is invoked at call time (not memoised)',
	() => {
		// Sanity check: a different value across calls produces a
		// different return. Defends against a future refactor that
		// caches the getter result.
		let nextValue = 'http://first.local/s';
		const getter = () => nextValue;
		assert.equal(resolveStyleOverride(getter), 'http://first.local/s');
		nextValue = 'http://second.local/s';
		assert.equal(resolveStyleOverride(getter), 'http://second.local/s');
	});
