// Unit tests for apps/watch_ios/scripts/check_xcstrings_parity.sh.
//
// That guard is the ONLY thing between a half-declared watchOS locale and
// the App Store, and until now it had no test of its own. It cannot be
// replaced by a Swift test: the failure it exists to catch is not a
// compile error and not a runtime crash — an undeclared locale is simply
// never loaded, so the watch shows English, nothing throws, and the Mac
// job that builds and runs the Swift suite passes. Nor can this repo run
// a Swift test at all outside the one macOS job.
//
// So the guard is measured the only way a guard can honestly be measured:
// by mutating a copy of the real tree in each of the ways a locale ships
// half-declared and asserting it refuses. The unmutated copy is the
// positive control — without it every rejection below could be an
// accident of the copy rather than of the mutation.
//
// Run: node --test scripts/check_xcstrings_parity.test.mjs
// CI:  the `watch-ios-locale-parity` job in .github/workflows/ci.yml.

import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const WATCH_IOS = join(REPO_ROOT, 'apps', 'watch_ios');
const CATALOG = join('WatchApp', 'Localizable.xcstrings');
const PLIST = join('WatchApp', 'Info.plist');
const PBXPROJ = join('WatchApp.xcodeproj', 'project.pbxproj');
const SCRIPT = join('scripts', 'check_xcstrings_parity.sh');

/** Copy the four files the guard reads into a throwaway tree. */
function stage() {
	const dir = mkdtempSync(join(tmpdir(), 'xcstrings-'));
	for (const rel of [CATALOG, PLIST, PBXPROJ, SCRIPT]) {
		mkdirSync(join(dir, dirname(rel)), { recursive: true });
		cpSync(join(WATCH_IOS, rel), join(dir, rel));
	}
	return dir;
}

/** @param {string} dir */
function run(dir) {
	const r = spawnSync('bash', [join(dir, SCRIPT)], { encoding: 'utf8' });
	return { status: r.status, out: `${r.stdout}${r.stderr}` };
}

/**
 * Stage, mutate, run, clean up.
 * @param {(dir: string) => void} mutate
 */
function runMutated(mutate) {
	const dir = stage();
	try {
		mutate(dir);
		return run(dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

/** @param {string} dir */
const readCatalog = (dir) => JSON.parse(readFileSync(join(dir, CATALOG), 'utf8'));
/** @param {string} dir @param {unknown} cat */
const writeCatalog = (dir, cat) =>
	writeFileSync(join(dir, CATALOG), JSON.stringify(cat, null, 2));

test('the shipped watchOS catalog, Info.plist and knownRegions agree', () => {
	const { status, out } = runMutated(() => {});
	assert.equal(status, 0, out);
	assert.match(out, /^OK: \d+ string\(s\)/, out);
});

test('a locale translated but missing from CFBundleLocalizations is refused', () => {
	// The quiet one. iOS never loads a locale the bundle does not declare,
	// so the watch shows English and nothing fails.
	const { status, out } = runMutated((dir) => {
		const p = join(dir, PLIST);
		writeFileSync(
			p,
			readFileSync(p, 'utf8').replace('<string>pt-PT</string>', ''),
		);
	});
	assert.equal(status, 1, out);
	assert.match(out, /CFBundleLocalizations/);
});

test('a locale translated but missing from knownRegions is refused', () => {
	const { status, out } = runMutated((dir) => {
		const p = join(dir, PBXPROJ);
		const src = readFileSync(p, 'utf8');
		const cut = src.replace(/^\s*"?pt-PT"?,?\s*$\n/m, '');
		assert.notEqual(cut, src, 'the pbxproj mutation matched nothing');
		writeFileSync(p, cut);
	});
	assert.equal(status, 1, out);
	assert.match(out, /knownRegions/);
});

test('an entry that never translated one of the shipped locales is refused', () => {
	const { status, out } = runMutated((dir) => {
		const cat = readCatalog(dir);
		const key = Object.keys(cat.strings).find((k) => cat.strings[k].localizations?.de);
		assert.ok(key, 'no entry carries a de localization to remove');
		delete cat.strings[key].localizations.de;
		writeCatalog(dir, cat);
	});
	assert.equal(status, 1, out);
	assert.match(out, /de: missing translation/);
});

test('an empty translation value is refused rather than shipped blank', () => {
	const { status, out } = runMutated((dir) => {
		const cat = readCatalog(dir);
		const key = Object.keys(cat.strings).find(
			(k) => cat.strings[k].localizations?.fr?.stringUnit,
		);
		assert.ok(key, 'no entry carries a plain fr stringUnit');
		cat.strings[key].localizations.fr.stringUnit.value = '   ';
		writeCatalog(dir, cat);
	});
	assert.equal(status, 1, out);
	assert.match(out, /fr: empty value/);
});

test('a plural entry missing its singular category is refused', () => {
	const { status, out } = runMutated((dir) => {
		const cat = readCatalog(dir);
		const key = Object.keys(cat.strings).find(
			(k) => cat.strings[k].localizations?.de?.variations?.plural?.one,
		);
		assert.ok(key, 'no entry carries a de plural with a "one" category');
		delete cat.strings[key].localizations.de.variations.plural.one;
		writeCatalog(dir, cat);
	});
	assert.equal(status, 1, out);
	assert.match(out, /de: missing\/empty plural 'one'/);
});

test('ja keeps its exemption from the singular category', () => {
	// Japanese has no singular/plural distinction, so the catalog declares
	// only "other" for it. If the exemption were dropped the guard would
	// fail on the shipped tree — which the first case already covers — but
	// if it were WIDENED to every locale the guard would stop seeing a
	// German plural entry that lost its singular. Asserted here so the
	// exemption cannot quietly grow.
	const dir = stage();
	try {
		const cat = readCatalog(dir);
		const jaPlurals = Object.entries(cat.strings).filter(
			([, e]) => e.localizations?.ja?.variations?.plural,
		);
		assert.ok(jaPlurals.length > 0, 'no ja plural entry to reason about');
		for (const [key, entry] of jaPlurals) {
			assert.equal(
				entry.localizations.ja.variations.plural.one,
				undefined,
				`${key} declares a ja singular, so the exemption is not what is passing the guard`,
			);
		}
		assert.equal(run(dir).status, 0);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('a locale added to one entry only fails everywhere it is not declared', () => {
	// The locale set is DERIVED from the catalog, so half-adding a seventh
	// one must not read as "nothing to check". Every other entry is then
	// short of the derived set, and both declaration sites disagree with it.
	const { status, out } = runMutated((dir) => {
		const cat = readCatalog(dir);
		const key = Object.keys(cat.strings).find(
			(k) => cat.strings[k].localizations?.de?.stringUnit,
		);
		assert.ok(key, 'no entry carries a plain de stringUnit');
		cat.strings[key].localizations.it = { stringUnit: { state: 'translated', value: 'Ciao' } };
		writeCatalog(dir, cat);
	});
	assert.equal(status, 1, out);
	assert.match(out, /it: missing translation/);
	assert.match(out, /CFBundleLocalizations/);
	assert.match(out, /knownRegions/);
});

test('a catalog with no entries fails loudly rather than passing vacuously', () => {
	const { status, out } = runMutated((dir) => {
		writeCatalog(dir, { sourceLanguage: 'en', strings: {} });
	});
	assert.equal(status, 1, out);
	assert.match(out, /no string entries parsed/);
});

test('an Info.plist with no CFBundleLocalizations array at all is refused', () => {
	const { status, out } = runMutated((dir) => {
		const p = join(dir, PLIST);
		writeFileSync(
			p,
			readFileSync(p, 'utf8').replace('CFBundleLocalizations', 'CFBundleLocalizationsWas'),
		);
	});
	assert.equal(status, 1, out);
	assert.match(out, /declares no CFBundleLocalizations array/);
});
