// Unit tests for the icon extractor, and the repo invariant it exists for: the
// subset font that ships carries every icon apps/web names.
//
// The invariant is checked by re-running the generator's SELECTION step — the
// same `selectIcons` over the same sources and the same committed vocabulary —
// and comparing it with the manifest the generator wrote beside the font. That
// makes the failure mode of a new icon loud: adding `<span
// class="material-symbols">rocket_launch</span>` fails here with the name in
// the message, instead of shipping a 1.25em box with the word `rocket_launch`
// clipped inside it. The font work itself is not repeated (it needs fontTools);
// what pins the manifest to the bytes on disk is the digest below, which the
// generator wrote in the same run.
//
// CI: the `build-web` job in .github/workflows/ci.yml, which is in the
//     `CI gate` aggregator's `needs:` list.

import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

import {
	MANIFEST,
	PINNED_AXES,
	REPO_ROOT,
	SUBSET_FONT,
	UPSTREAM_FONT,
	VOCABULARY_FILE,
	WEB_SRC,
	collectSources,
	parseVocabulary,
	selectIcons,
	sha256Bytes,
} from './web_icon_font.mjs';

const vocabulary = parseVocabulary(readFileSync(VOCABULARY_FILE, 'utf8'));
const manifest = JSON.parse(readFileSync(MANIFEST, 'utf8'));

/** @param {string} path @param {string} text */
const source = (path, text) => [{ path, text }];

test('an icon written as element text is taken from the render site', () => {
	const { icons, unrenderable, unreadable } = selectIcons(
		source('a.svelte', '<span class="material-symbols">arrow_back</span>'),
		new Set(['arrow_back']),
	);
	assert.deepEqual(icons, ['arrow_back']);
	assert.deepEqual(unrenderable, []);
	assert.deepEqual(unreadable, []);
});

test('an attribute expression between the class and the tag end does not hide the icon', () => {
	// The one site rendering `push_pin` writes `title={m('…')}` after the class,
	// which a class-anchored match that stopped at the first `{` used to drop.
	const { icons } = selectIcons(
		source(
			'a.svelte',
			'<span class="pin material-symbols" title={m(\'routeHeatmap.keptOnMap\')}>push_pin</span>',
		),
		new Set(['push_pin']),
	);
	assert.deepEqual(icons, ['push_pin']);
});

test('an icon that arrives through an expression is found where its name is written', () => {
	// `{item.icon}` names nothing at the render site. The literal that feeds it
	// is somewhere else entirely, which is why the second rule scans every
	// quoted token in every file rather than only the render sites.
	const { icons, unreadable } = selectIcons(
		[
			{ path: 'nav.ts', text: "const items = [{ icon: 'directions_run' }];" },
			{ path: 'a.svelte', text: '<span class="nav-icon material-symbols">{item.icon}</span>' },
		],
		new Set(['directions_run']),
	);
	assert.deepEqual(icons, ['directions_run']);
	assert.deepEqual(unreadable, [], 'an expression is a shape the extractor reads, not one it cannot');
});

test('a quoted token the font cannot render is not an icon', () => {
	const { icons } = selectIcons(
		source('a.ts', "const label = 'not_a_material_symbol';"),
		new Set(['directions_run']),
	);
	assert.deepEqual(icons, []);
});

test('element text the font has no ligature for is an error, not a filtered candidate', () => {
	// This name is rendered today and would render as text; excluding it
	// silently would hide a broken icon rather than report one.
	const { icons, unrenderable } = selectIcons(
		source('a.svelte', '<span class="material-symbols">rocket_lunch</span>'),
		new Set(['rocket_launch']),
	);
	assert.deepEqual(icons, []);
	assert.deepEqual(unrenderable, [{ name: 'rocket_lunch', path: 'a.svelte' }]);
});

test('a dynamic class is reported rather than read as carrying no icons', () => {
	const { icons, unreadable } = selectIcons(
		source('a.svelte', '<span class={`material-symbols ${extra}`}>arrow_back</span>'),
		new Set(['arrow_back']),
	);
	assert.deepEqual(icons, [], 'the name is still found by the literal rule only if quoted');
	assert.equal(unreadable.length, 1);
	assert.match(unreadable[0].name, /material-symbols/);
});

test('an icon span with no content renders no icon and is not an unreadable shape', () => {
	const { icons, unreadable } = selectIcons(
		source('a.svelte', '<span class="material-symbols" title={seg.role}></span>'),
		new Set(['arrow_back']),
	);
	assert.deepEqual(icons, []);
	assert.deepEqual(unreadable, []);
});

test('the vocabulary is the font\'s, not the package\'s type declaration', () => {
	// `material-symbols/index.d.ts` lists 3899 names and omits every alias whose
	// ligature resolves to a differently-named glyph. These five are rendered by
	// apps/web and are absent from it; a guard built on that list would have
	// dropped them.
	for (const alias of ['terrain', 'expand_more', 'emoji_events', 'place', 'loop']) {
		assert.ok(vocabulary.has(alias), `${alias} must be in the committed vocabulary`);
	}
	assert.equal(vocabulary.size, manifest.upstream.ligatures);
});

test('every icon apps/web names is in the shipped subset', () => {
	const { icons, unrenderable, unreadable } = selectIcons(collectSources(WEB_SRC), vocabulary);
	assert.deepEqual(
		unreadable.map((u) => `${u.path}: ${u.name}`),
		[],
		'an icon class on an element whose content the extractor cannot read — extend ' +
			'CLASS_ATTRIBUTE / ELEMENT_TEXT in scripts/web_icon_font.mjs',
	);
	assert.deepEqual(
		unrenderable.map((u) => `${u.path}: ${u.name}`),
		[],
		'element text with no ligature in the upstream font — that icon does not render',
	);
	assert.deepEqual(
		icons.filter((name) => !manifest.icons.includes(name)),
		[],
		'apps/web names icons the subset does not carry. Re-run ' +
			'`node scripts/gen_web_icon_font.mjs` and commit the font + manifest.',
	);
	assert.deepEqual(
		manifest.icons.filter((/** @type {string} */ name) => !icons.includes(name)),
		[],
		'the subset carries icons apps/web no longer names. Re-run ' +
			'`node scripts/gen_web_icon_font.mjs` and commit the font + manifest.',
	);
});

test('the manifest describes the font that is actually committed', () => {
	const font = readFileSync(SUBSET_FONT);
	assert.equal(font.length, manifest.subset.bytes);
	assert.equal(sha256Bytes(font), manifest.subset.sha256);
	assert.deepEqual(manifest.pinnedAxes, PINNED_AXES);
	assert.deepEqual(manifest.variableAxes, ['FILL', 'wght']);
});

test('app.css serves the subset and nothing imports the unsubsetted package stylesheet', () => {
	const css = readFileSync(join(WEB_SRC, 'app.css'), 'utf8');
	assert.match(
		css,
		/src:\s*url\('\.\/lib\/assets\/material-symbols-subset\.woff2'\)/,
		'the @font-face must point at the committed subset',
	);
	assert.match(css, /font-display:\s*block;/);

	const offenders = collectSources(WEB_SRC)
		.filter((s) => /['"]material-symbols\/[\w.-]+\.css['"]/.test(s.text))
		.map((s) => s.path);
	assert.deepEqual(
		offenders,
		[],
		"importing the package's own stylesheet @font-face's the complete 3866 KB " +
			'font again, on the root layout, in front of every reader',
	);
});

test('the upstream font the subset was cut from is the one installed', {
	skip: existsSync(UPSTREAM_FONT) ? false : 'material-symbols is not installed',
}, () => {
	const upstream = readFileSync(UPSTREAM_FONT);
	assert.equal(
		sha256Bytes(upstream),
		manifest.upstream.sha256,
		`the installed ${manifest.upstream.file} is not the one the subset was cut ` +
			'from. Re-run `node scripts/gen_web_icon_font.mjs` after a version bump — ' +
			'the vocabulary moves with the font, and a stale one cannot see a new icon.',
	);
	const version = JSON.parse(
		readFileSync(join(REPO_ROOT, 'node_modules', 'material-symbols', 'package.json'), 'utf8'),
	).version;
	assert.equal(manifest.upstream.package, `material-symbols@${version}`);
});
