// Unit tests for the map-style URL builder. Pin both the legacy
// MapTiler-keyed path AND the PUBLIC_TILE_STYLE_URL override that
// drives the local Protomaps tileserver-gl dev setup.
//
// Invocation:
//   npx tsx --test src/lib/map-style.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	basemapIsDark,
	basemapIsDarkForSlug,
	buildMapStyleUrl,
	maptilerStyleUrl,
	OSM_FALLBACK_STYLE_URL,
	resolveStyleOverride,
	slugIsDark,
	styleUrlForSlug,
	type MaptilerSlug,
} from './map-style-url';

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

test('empty key + no override → OSM fallback style URL', () => {
	// `PUBLIC_MAPTILER_KEY=""` is the CI default and the "no key
	// configured yet" path for a fresh self-hoster. Without the OSM
	// fallback the builder would emit
	// `https://api.maptiler.com/.../style.json?key=` which 403s — map
	// blank, every tile request burns, headless e2e times out
	// waiting for `moveend`. Pin the fallback URL so a future refactor
	// can't regress the contract.
	for (const style of ['streets', 'dark', 'satellite', 'outdoors'] as const) {
		const url = buildMapStyleUrl(style, '', false);
		assert.equal(url, OSM_FALLBACK_STYLE_URL,
			`style=${style} + empty key must fall back to the OSM style`);
	}
});

test('whitespace-only key + no override → OSM fallback style URL', () => {
	// Match the trim semantics on the override path (see test above)
	// — a stray space in `.env`s shouldn't trick the builder into
	// emitting a `key= ` MapTiler URL.
	for (const ws of [' ', '   ', '\t', '\n', ' \t\n ']) {
		const url = buildMapStyleUrl('streets', ws, false);
		assert.equal(url, OSM_FALLBACK_STYLE_URL,
			`whitespace key ${JSON.stringify(ws)} must fall back to OSM`);
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

// ---------------- the slug vocabulary ----------------

// The route builder resolves its own slugs (`hybrid` for satellite, no dark
// rung), so the shared piece is the slug -> URL template and the slug ->
// luminance classification. Both are pinned literally: § 526's whole finding
// was that a second, private answer to "is this ground dark" is how 35 of 49
// cartographic literals came to be painted on the wrong basemap.

const ALL_SLUGS: MaptilerSlug[] = [
	'streets-v2',
	'streets-v2-dark',
	'satellite',
	'hybrid',
	'outdoor-v2',
];

test('maptilerStyleUrl — one spelling of the style-document endpoint', () => {
	assert.equal(
		maptilerStyleUrl('hybrid', 'KEY'),
		'https://api.maptiler.com/maps/hybrid/style.json?key=KEY',
	);
	assert.equal(
		maptilerStyleUrl('outdoor-v2', 'KEY'),
		'https://api.maptiler.com/maps/outdoor-v2/style.json?key=KEY',
	);
});

test('buildMapStyleUrl still routes through maptilerStyleUrl for every preference', () => {
	const cases: Array<[Parameters<typeof buildMapStyleUrl>[0], boolean, MaptilerSlug]> = [
		['streets', false, 'streets-v2'],
		['streets', true, 'streets-v2-dark'],
		['dark', false, 'streets-v2-dark'],
		['satellite', false, 'satellite'],
		['outdoors', true, 'outdoor-v2'],
	];
	for (const [chosen, prefersDark, slug] of cases) {
		assert.equal(
			buildMapStyleUrl(chosen, 'KEY', prefersDark),
			maptilerStyleUrl(slug, 'KEY'),
			`${chosen} (prefersDark=${prefersDark}) must resolve to ${slug}`,
		);
	}
});

test('slugIsDark — both imagery slugs are dark, outdoor-v2 is not', () => {
	assert.deepEqual(
		ALL_SLUGS.map(slugIsDark),
		[false, true, true, true, false],
	);
});

test('slugIsDark answers for every slug (no undefined ground)', () => {
	for (const slug of ALL_SLUGS) assert.equal(typeof slugIsDark(slug), 'boolean');
});

test('basemapIsDarkForSlug — the route builder gets the same verdict basemapIsDark gives', () => {
	// The builder's three rungs against the preference that resolves to the
	// same ground. `hybrid` and `satellite` are different tiles and the SAME
	// ground, which is the distinction the two functions exist to keep.
	assert.equal(basemapIsDarkForSlug('hybrid', 'KEY'), basemapIsDark('satellite', 'KEY', false));
	assert.equal(basemapIsDarkForSlug('outdoor-v2', 'KEY'), basemapIsDark('outdoors', 'KEY', true));
	assert.equal(basemapIsDarkForSlug('streets-v2', 'KEY'), basemapIsDark('streets', 'KEY', false));
	assert.equal(
		basemapIsDarkForSlug('streets-v2-dark', 'KEY'),
		basemapIsDark('streets', 'KEY', true),
	);
});

test('basemapIsDarkForSlug — override and keyless precedence match basemapIsDark', () => {
	assert.equal(basemapIsDarkForSlug('hybrid', 'KEY', 'http://localhost:8080/dark.json'), true);
	assert.equal(basemapIsDarkForSlug('hybrid', 'KEY', 'http://localhost:8080/style.json'), false);
	// No key: the OSM raster fallback is light ground whatever slug was asked
	// for, so imagery does not carry a dark verdict into a light fallback.
	assert.equal(basemapIsDarkForSlug('hybrid', ''), false);
	assert.equal(basemapIsDarkForSlug('hybrid', '   '), false);
});

// `styleUrlForSlug` is the URL half of the same pair, and its whole reason for
// existing is the branch a private slug table skipped: the route builder built
// its three URLs from `maptilerStyleUrl` and so had no keyless fallback at all
// — a 403 and a blank canvas where every other surface rendered OSM raster,
// with no basemap credit either, because MapLibre reads the credit out of the
// style document that loaded (§ 491).

test('styleUrlForSlug — every builder slug falls back to OSM raster with no key', () => {
	// The population, not just the property: all three rungs the builder can
	// select, and the two blank spellings a missing env var produces.
	const builderSlugs: MaptilerSlug[] = ['streets-v2', 'streets-v2-dark', 'hybrid', 'outdoor-v2'];
	assert.equal(builderSlugs.length, 4, 'the builder resolves four slugs across its three rungs');
	for (const slug of builderSlugs) {
		for (const key of ['', '   ']) {
			assert.equal(
				styleUrlForSlug(slug, key),
				OSM_FALLBACK_STYLE_URL,
				`${slug} with key ${JSON.stringify(key)} must degrade to the keyless style`,
			);
		}
	}
});

test('styleUrlForSlug — the override wins over both the key and the fallback', () => {
	const override = 'http://localhost:8080/style.json';
	assert.equal(styleUrlForSlug('hybrid', 'KEY', override), override);
	assert.equal(styleUrlForSlug('hybrid', '', override), override);
	assert.equal(styleUrlForSlug('outdoor-v2', 'KEY', '  ' + override + '  '), override);
	// Blank overrides are absent, not a style URL.
	assert.equal(styleUrlForSlug('hybrid', 'KEY', '   '), maptilerStyleUrl('hybrid', 'KEY'));
	assert.equal(styleUrlForSlug('hybrid', '', ''), OSM_FALLBACK_STYLE_URL);
});

test('styleUrlForSlug and buildMapStyleUrl are one precedence, not two', () => {
	const pairs: Array<[Parameters<typeof buildMapStyleUrl>[0], boolean, MaptilerSlug]> = [
		['streets', false, 'streets-v2'],
		['streets', true, 'streets-v2-dark'],
		['dark', false, 'streets-v2-dark'],
		['satellite', false, 'satellite'],
		['outdoors', true, 'outdoor-v2'],
	];
	for (const [chosen, prefersDark, slug] of pairs) {
		for (const key of ['KEY', '']) {
			for (const override of [undefined, 'http://localhost:8080/style.json']) {
				assert.equal(
					buildMapStyleUrl(chosen, key, prefersDark, override),
					styleUrlForSlug(slug, key, override),
					`${chosen}/${key}/${override} must resolve identically through both entry points`,
				);
			}
		}
	}
});
