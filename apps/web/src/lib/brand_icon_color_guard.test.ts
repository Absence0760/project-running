// Source-level guards for the single brand icon colour (issue #483).
//
// The app icon renders in many places — web favicon / PWA manifest,
// Android + iOS launcher icons, and the Android status-bar notification
// icon — and every one derives from ONE master, assets/icon.svg, whose
// ember→magenta gradient is #FE5932 → #A01E77. This test pins that
// canonical pair across every machine-readable brand-colour surface so a
// future edit to one of them can't silently drift the icon colour out of
// sync on a single platform (which is exactly what #483 reported).
//
// The binary PNG launcher icons are regenerated from the master by
// assets/gen-icons.sh and can't be asserted as text; this guard covers
// the config + vector + SVG surfaces, which is where drift creeps in.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const EMBER = '#FE5932';
const MAGENTA = '#A01E77';

// cwd is apps/web (see `test:unit` in package.json). Repo root is two up.
function readWeb(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}
function readRepo(...parts: string[]): string {
	return readFileSync(resolve('..', '..', ...parts), 'utf-8');
}

test('master icon.svg carries the canonical ember→magenta gradient', () => {
	const svg = readRepo('assets', 'icon.svg');
	assert.match(svg, new RegExp(`stop-color="${EMBER}"`), 'master must start ember');
	assert.match(svg, new RegExp(`stop-color="${MAGENTA}"`), 'master must end magenta');
});

test('PWA manifest theme/background colours match the master gradient stops', () => {
	const manifest = JSON.parse(readWeb('static', 'manifest.webmanifest'));
	assert.equal(manifest.theme_color, EMBER, 'theme_color must be the ember stop');
	assert.equal(manifest.background_color, MAGENTA, 'background_color must be the magenta stop');
});

test('app.html meta theme-color matches the manifest theme_color', () => {
	const html = readWeb('src', 'app.html');
	assert.match(
		html,
		new RegExp(`<meta name="theme-color" content="${EMBER}"`),
		'the browser chrome colour must be the ember brand colour'
	);
});

test('web logo-mark + wordmark SVGs reuse the same gradient stops', () => {
	for (const file of ['logo-mark.svg', 'wordmark.svg', 'wordmark-light.svg', 'bimi-logo.svg']) {
		const svg = readWeb('static', file);
		assert.match(svg, new RegExp(`stop-color="${EMBER}"`), `${file} must start ember`);
		assert.match(svg, new RegExp(`stop-color="${MAGENTA}"`), `${file} must end magenta`);
	}
});

test('Android brand_ember colour resource matches the master ember stop', () => {
	// Android colours are #AARRGGBB; the ember stop is fully opaque.
	const colors = readRepo(
		'apps',
		'mobile_android',
		'android',
		'app',
		'src',
		'main',
		'res',
		'values',
		'colors.xml'
	);
	assert.match(
		colors,
		/<color name="brand_ember">#FFFE5932<\/color>/,
		'brand_ember must be opaque #FE5932 so the notification accent matches the icon'
	);
});

test('Android notification icon is a monochrome vector of the master glyph, not the full-colour launcher', () => {
	const drawable = readRepo(
		'apps',
		'mobile_android',
		'android',
		'app',
		'src',
		'main',
		'res',
		'drawable',
		'ic_stat_threkir.xml'
	);
	// A status-bar small icon is masked to its alpha silhouette, so it
	// must be a white glyph on transparency — a full-colour opaque icon
	// renders as a solid square (the #483 bug).
	assert.match(drawable, /android:fillColor="#FFFFFFFF"/, 'glyph must be white');
	assert.match(
		drawable,
		/M30 10 H44 V90 H30 Z/,
		'glyph path must be the master þ lettermark'
	);

	const bridge = readRepo(
		'apps',
		'mobile_android',
		'android',
		'app',
		'src',
		'main',
		'kotlin',
		'com',
		'threkir',
		'app',
		'RunNotificationBridge.kt'
	);
	assert.match(
		bridge,
		/setSmallIcon\(R\.drawable\.ic_stat_threkir\)/,
		'notification must use the monochrome drawable'
	);
	assert.doesNotMatch(
		bridge,
		/setSmallIcon\(R\.mipmap\.ic_launcher\)/,
		'notification must NOT use the full-colour launcher mipmap as its small icon'
	);
});
