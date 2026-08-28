import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
	ASSET_EXEMPTIONS,
	CATALOGUE_SOURCE,
	MAX_ASSET_KB,
	MAX_CATALOGUE_KB,
	MAX_CODE_KB,
	MAX_LARGEST_CHUNK_KB,
	catalogueChunks,
	checkBudgets,
	collectEmitted,
	gzipKb,
	isCodeFile,
	localeTags,
	renderSummary,
} from './check_web_bundle_budget.mjs';

/// The ceiling this guard replaces: one number over every emitted file, which
/// is what let a language move it and a dep hide under it. Both fixtures below
/// are scored against it as well as against the new rule, because "the new rule
/// is better" is a claim about a disagreement, and a test that only ran the new
/// rule could not show one.
const RETIRED_TOTAL_KB = 2700;
/// The retired walk matched `*.js` and `*.css`, so it is scored over those —
/// which is also the hole the asset ceiling closes: the 3866 KB font below was
/// invisible to that total as well as to the three ceilings that replaced it.
/** @param {readonly {path: string, kb: number}[]} files */
const retiredTotalPasses = (files) =>
	files.filter((f) => isCodeFile(f.path)).reduce((sum, f) => sum + f.kb, 0) <=
	RETIRED_TOTAL_KB;

/// apps/web as measured on 2026-08-28: 1934 KB of code in 403 files (largest
/// chunk 245 KB) plus six lazily-imported catalogues. Collapsed to a handful of
/// entries whose sizes add up to the real ones — the arithmetic under test is
/// the partition, not the file count.
const CATALOGUE_KB = { de: 88, es: 85, fr: 88, ja: 91, 'pt-BR': 85, 'pt-PT': 85 };
const LOCALES = ['de', 'en', 'es', 'fr', 'ja', 'pt-BR', 'pt-PT'];

/// The non-JS/CSS half of the same build: 33 files, 4058 KB gzipped, collapsed
/// to the nine that carry all but a kilobyte of it. The font is the whole
/// reason this population exists — 3866 KB, 1.8x the code ceiling, and outside
/// every metric until it was measured.
const ASSET_KB = [
	{ path: '_app/immutable/assets/material-symbols-outlined.CqIkmgaP.woff2', kb: 3866 },
	{ path: 'icon-512.png', kb: 68 },
	{ path: 'og-default.png', kb: 20 },
	{ path: 'icon-192.png', kb: 11 },
	{ path: 'apple-touch-icon.png', kb: 10 },
	{ path: 'learn/couch-to-5k.html', kb: 5 },
	{ path: 'learn.html', kb: 5 },
	{ path: 'learn/category/gear.html', kb: 4 },
	{ path: 'index.html', kb: 2 },
];

/**
 * @param {{
 *   extraCatalogues?: Record<string, number>,
 *   extraCode?: {path: string, kb: number}[],
 *   assets?: {path: string, kb: number}[],
 * }} [opts]
 */
function fixture({ extraCatalogues = {}, extraCode = [], assets = ASSET_KB } = {}) {
	/** @type {Map<string, string>} */
	const catalogues = new Map();
	const files = [
		{ path: '_app/immutable/chunks/largest.js', kb: 245 },
		// The English catalogue is inside this one: store.svelte.ts imports it
		// statically as the fallback dict, so it is never its own chunk.
		{ path: '_app/immutable/chunks/store.js', kb: 80 },
	];
	// The remaining 1609 KB of code, spread so no single chunk is the largest.
	for (let i = 0; i < 7; i++) {
		files.push({ path: `_app/immutable/nodes/${i}.js`, kb: i === 6 ? 229 : 230 });
	}
	for (const [locale, kb] of Object.entries({ ...CATALOGUE_KB, ...extraCatalogues })) {
		const path = `_app/immutable/chunks/${locale}.js`;
		catalogues.set(locale, path);
		files.push({ path, kb });
	}
	files.push(...extraCode, ...assets);
	const locales = [...new Set([...LOCALES, ...Object.keys(extraCatalogues)])].sort();
	return { files, catalogues, locales };
}

test('the shipped ceilings pass against the measured build', () => {
	const { errors, summary } = checkBudgets(fixture());
	assert.deepEqual(errors, []);
	assert.equal(summary.codeKb, 1934);
	assert.equal(summary.catalogueKb, 522);
	assert.equal(summary.catalogueFiles.length, 6);
	assert.equal(summary.largest.kb, 245);
	assert.equal(summary.assetFileCount, 9);
	assert.equal(summary.assetKb, 3991);
	assert.equal(summary.largestAsset.kb, 3866);
});

test('three more languages move no budget, where the retired total ceiling fails', () => {
	const grown = fixture({ extraCatalogues: { it: 88, nl: 88, ko: 91 } });

	assert.equal(
		retiredTotalPasses(grown.files),
		false,
		'the retired rule summed catalogues, so the tenth language alone pushed ' +
			'2456 KB past 2700 and forced another bump',
	);

	const { errors, summary } = checkBudgets(grown);
	assert.deepEqual(errors, [], 'nine catalogues cost a reader exactly what six did');
	assert.equal(summary.codeKb, 1934, 'the code budget does not know a language was added');
	assert.equal(summary.catalogueFiles.length, 9);
});

test('a rogue dep the retired total ceiling had room for trips the code budget', () => {
	const rogue = fixture({
		extraCode: [{ path: '_app/immutable/chunks/rogue-dep.js', kb: 200 }],
	});

	assert.equal(
		retiredTotalPasses(rogue.files),
		true,
		'2456 + 200 = 2656 sat under 2700 — the 522 KB of catalogues in that total ' +
			'were the cover the dep hid behind',
	);

	const { errors } = checkBudgets(rogue);
	assert.equal(errors.length, 1);
	assert.equal(errors[0].budget, 'code');
	assert.match(errors[0].message, /code is 2134 KB gzipped, over the 2120 KB ceiling by 14 KB/);
	assert.match(
		errors[0].message,
		/a new locale cannot have caused it/,
		'the diagnosis has to point at the population that actually moved',
	);
});

test('an oversized catalogue names its own locale and its own budget', () => {
	const { errors } = checkBudgets(fixture({ extraCatalogues: { ja: 140 } }));
	assert.equal(errors.length, 1);
	assert.equal(errors[0].budget, 'catalogue');
	assert.match(errors[0].message, /the ja catalogue is 140 KB/);
	assert.match(errors[0].message, /over the 100 KB per-catalogue ceiling by 40 KB/);
	assert.match(errors[0].message, /adding a language cannot trip it/);
});

test('a catalogue is not measured against the largest-code-chunk ceiling', () => {
	const { errors } = checkBudgets(fixture({ extraCatalogues: { ja: 400 } }));
	assert.deepEqual(
		errors.map((e) => e.budget),
		['catalogue'],
		'400 KB is over MAX_LARGEST_CHUNK_KB too, but a catalogue is already a lazy ' +
			'chunk and cannot be split — one budget owns it, and it is not that one',
	);
});

test('an oversized code chunk trips the largest-chunk budget alone', () => {
	const big = fixture();
	big.files = big.files.map((f) =>
		f.path.endsWith('largest.js') ? { ...f, kb: 380 } : f,
	);
	const { errors } = checkBudgets(big);
	assert.deepEqual(errors.map((e) => e.budget), ['largest-chunk']);
	assert.match(errors[0].message, /380 KB gzipped, over the 350 KB ceiling by 30 KB/);
	assert.match(errors[0].message, /largest\.js/);
});

test('a catalogue the manifest names but the build lacks fails classification', () => {
	const f = fixture();
	f.files = f.files.filter((x) => !x.path.endsWith('/ja.js'));
	const { errors } = checkBudgets(f);
	assert.deepEqual(errors.map((e) => e.budget), ['classification']);
	assert.match(errors[0].message, /locale ja to _app\/immutable\/chunks\/ja\.js/);
	assert.match(errors[0].message, /no ceiling below means anything/);
});

test('a second statically-bundled catalogue is named, not absorbed into code', () => {
	const f = fixture();
	// What a catalogue merging into a shared chunk looks like from here: it
	// leaves the manifest, so its bytes land in the code budget under a message
	// about deps unless the count is checked.
	f.catalogues.delete('ja');
	f.files = f.files.map((x) =>
		x.path.endsWith('/ja.js') ? { ...x, path: '_app/immutable/chunks/store.js' } : x,
	);
	const { errors } = checkBudgets(f);
	const classification = errors.filter((e) => e.budget === 'classification');
	assert.equal(classification.length, 1);
	assert.match(classification[0].message, /found 2 — en, ja/);
});

test('every catalogue going lazy is a classification failure too', () => {
	const f = fixture({ extraCatalogues: { en: 80 } });
	const { errors } = checkBudgets(f);
	assert.deepEqual(errors.map((e) => e.budget), ['classification']);
	assert.match(errors[0].message, /found 0\./);
});

test('catalogueChunks reads hyphenated tags and ignores everything else', () => {
	const chunks = catalogueChunks({
		'src/lib/i18n/locales/pt-BR.ts': { file: 'chunks/a.js' },
		'src/lib/i18n/locales/de.ts': { file: 'chunks/b.js' },
		'src/lib/i18n/locale.ts': { file: 'chunks/c.js' },
		'src/lib/i18n/locales/nested/de.ts': { file: 'chunks/d.js' },
		'src/routes/+page.svelte': { file: 'chunks/e.js' },
		'src/lib/i18n/locales/fr.ts': {},
	});
	assert.deepEqual([...chunks], [
		['pt-BR', 'chunks/a.js'],
		['de', 'chunks/b.js'],
	]);
	assert.equal(CATALOGUE_SOURCE.test('src/lib/i18n/locales/en.ts'), true);
});

test('localeTags reads the catalogue directory and skips its tests', () => {
	const dir = mkdtempSync(join(tmpdir(), 'budget-locales-'));
	try {
		for (const f of ['en.ts', 'pt-BR.ts', 'de.ts', 'messages.test.ts', 'README.md']) {
			writeFileSync(join(dir, f), '');
		}
		assert.deepEqual(localeTags(dir), ['de', 'en', 'pt-BR']);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('collectEmitted walks nested output and returns every emitted file', () => {
	// It used to return JS and CSS only, which is how a font twice the size of
	// the whole code budget sat outside all three ceilings. Classification is
	// checkBudgets' job; the walk's job is to miss nothing.
	const dir = mkdtempSync(join(tmpdir(), 'budget-build-'));
	try {
		mkdirSync(join(dir, '_app', 'immutable', 'chunks'), { recursive: true });
		writeFileSync(join(dir, '_app', 'immutable', 'chunks', 'a.js'), 'x'.repeat(4096));
		writeFileSync(join(dir, '_app', 'b.css'), 'y'.repeat(4096));
		writeFileSync(join(dir, '_app', 'font.woff2'), 'w'.repeat(4096));
		writeFileSync(join(dir, 'index.html'), 'z'.repeat(4096));
		const files = collectEmitted(dir);
		assert.deepEqual(files.map((f) => f.path), [
			'_app/b.css',
			'_app/font.woff2',
			'_app/immutable/chunks/a.js',
			'index.html',
		]);
		for (const f of files) assert.equal(f.kb, 1, 'a compressible 4 KiB file ceils to 1 KB');
		assert.deepEqual(files.filter((f) => !isCodeFile(f.path)).map((f) => f.path), [
			'_app/font.woff2',
			'index.html',
		]);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('gzipKb rounds a part-kilobyte up', () => {
	assert.equal(gzipKb(Buffer.alloc(0)), 1);
});

test('the summary states the catalogue total without gating on it', () => {
	const text = renderSummary(checkBudgets(fixture()).summary);
	assert.match(text, /Code \(every reader, any language\) \| 1934 KB across 9 files \| 2120 KB/);
	assert.match(text, /Largest message catalogue \(ja\) \| 91 KB \| 100 KB, per catalogue/);
	assert.match(text, /ungated in total \(522 KB across 6, one fetched per reader\)/);
	assert.match(text, /Largest single asset[^|]*\| 3866 KB \| 100 KB, per asset/);
	assert.match(text, /ungated in total too \(3991 KB across 9/);
});

test('the shipped ceilings are the ones this suite reasons about', () => {
	assert.equal(MAX_CODE_KB, 2120);
	assert.equal(MAX_CATALOGUE_KB, 100);
	assert.equal(MAX_LARGEST_CHUNK_KB, 350);
	assert.equal(MAX_ASSET_KB, 100);
	assert.equal(ASSET_EXEMPTIONS.length, 1);
});

test('an oversized asset the exemptions do not name is reported', () => {
	const { errors } = checkBudgets(
		fixture({ assets: [...ASSET_KB, { path: 'hero-photo.png', kb: 240 }] }),
	);
	assert.deepEqual(errors.map((e) => e.budget), ['asset']);
	assert.match(errors[0].message, /hero-photo\.png is 240 KB gzipped, over the 100 KB/);
	assert.match(errors[0].message, /never summed/);
});

test('prerendering /learn once per language moves no ceiling', () => {
	// The question this population was added for. Eight guides plus a category
	// index across six more languages is 54 more prerendered pages and ~250 KB
	// of HTML nobody downloads together, because a reader loads ONE page.
	const perLocale = [];
	for (const tag of ['de', 'es', 'fr', 'ja', 'pt-BR', 'pt-PT']) {
		for (let i = 0; i < 9; i++) perLocale.push({ path: `${tag}/learn/guide-${i}.html`, kb: 5 });
	}
	const grown = fixture({ assets: [...ASSET_KB, ...perLocale] });
	const { errors, summary } = checkBudgets(grown);
	assert.deepEqual(errors, []);
	assert.equal(summary.assetFileCount, 63);
	assert.equal(summary.assetKb, 4261);
	assert.equal(summary.largestAsset.kb, 3866, 'the largest asset is still the font');
});

test('the exempt font is held to its own ceiling, and a version bump keeps it', () => {
	const font = ASSET_KB[0];
	const rehashed = { path: font.path.replace('CqIkmgaP', 'Zq7Kb2Lm'), kb: 3870 };
	assert.deepEqual(
		checkBudgets(fixture({ assets: [rehashed, ...ASSET_KB.slice(1)] })).errors,
		[],
		'vite content-hashes the asset, so the exemption must survive a font update',
	);

	const grown = { path: font.path, kb: 4100 };
	const { errors } = checkBudgets(fixture({ assets: [grown, ...ASSET_KB.slice(1)] }));
	assert.deepEqual(errors.map((e) => e.budget), ['asset-exemption']);
	assert.match(errors[0].message, /over its own 3900 KB exemption ceiling by 200 KB/);
});

test('an exemption that names nothing in the build is reported', () => {
	const { errors } = checkBudgets(fixture({ assets: ASSET_KB.slice(1) }));
	assert.deepEqual(errors.map((e) => e.budget), ['asset-exemption']);
	assert.match(errors[0].message, /emits no such file/);
});

test('an exempt asset that has shrunk under the ceiling loses its exemption', () => {
	// Subsetting the font to the glyphs actually used is the fix; when it lands,
	// the entry carrying it has to go rather than sit there covering nothing.
	const subset = { path: ASSET_KB[0].path, kb: 42 };
	const { errors } = checkBudgets(fixture({ assets: [subset, ...ASSET_KB.slice(1)] }));
	assert.deepEqual(errors.map((e) => e.budget), ['asset-exemption']);
	assert.match(errors[0].message, /no longer needs the exemption/);
});

test('assets are outside the code and largest-chunk budgets, not silently inside them', () => {
	// The font is 1.8x MAX_CODE_KB on its own. If the widened walk let it into
	// the code population, the code ceiling would fail on the first run and the
	// largest-chunk one would name a woff2.
	const { errors, summary } = checkBudgets(fixture());
	assert.deepEqual(errors, []);
	assert.equal(summary.codeKb, 1934);
	assert.match(summary.largest.path, /\.js$/);
	assert.ok(summary.largestAsset.kb > MAX_CODE_KB, 'the font outweighs the entire code ceiling');
});
