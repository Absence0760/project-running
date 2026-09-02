// Unit tests for scripts/check_watch_ios_source.mjs.
//
// That guard makes five claims about a tier this repo compiles in exactly one
// job, on a runner nobody here has. Every failure it exists to catch is silent
// on the platform: a localization key with no catalog entry renders English and
// throws nothing, an entitlement nothing claims builds and links fine and is
// refused months later by App Review, and two copies of one formatter drifting
// apart leaves the Swift suite green because it links only one of them. So the
// guard cannot be measured by "does the app work" — it is measured the same way
// `check_xcstrings_parity.test.mjs` measures its sibling: by mutating a copy of
// the real tree into each shape the guard exists to refuse, with the unmutated
// copy as the positive control. Without that control every rejection below
// could be an accident of the copy rather than of the mutation.
//
// Run: node --test scripts/check_watch_ios_source.test.mjs
// CI:  the `watch-ios-locale-parity` job in .github/workflows/ci.yml.

import { cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

import {
	check,
	functionBody,
	normalizeKey,
	parseFlatPlist,
	stripSwiftComments,
} from './check_watch_ios_source.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const WATCH_IOS = join(REPO_ROOT, 'apps', 'watch_ios');

const CATALOG = join('WatchApp', 'Localizable.xcstrings');
const PLIST = join('WatchApp', 'Info.plist');
const ENTS = join('WatchApp', 'WatchApp.entitlements');
const BRIDGE = join('WatchApp', 'ActiveRunBridge.swift');
const COPY = join('Complications', 'ActiveRunComplication.swift');
const ORIGIN = join('WatchApp', 'RunFormat.swift');
const README = join('Complications', 'README.md');

/** Copy only the files the guard reads into a throwaway tree. */
function stage() {
	const dir = mkdtempSync(join(tmpdir(), 'watch-ios-source-'));
	const rels = [CATALOG, PLIST, ENTS, README];
	for (const sub of ['WatchApp', 'Complications']) {
		for (const name of readdirSync(join(WATCH_IOS, sub))) {
			if (name.endsWith('.swift')) rels.push(join(sub, name));
		}
	}
	for (const rel of rels) {
		mkdirSync(join(dir, dirname(rel)), { recursive: true });
		cpSync(join(WATCH_IOS, rel), join(dir, rel));
	}
	return dir;
}

/**
 * Stage, mutate, check, clean up.
 * @param {(dir: string) => void} mutate
 */
function runMutated(mutate) {
	const dir = stage();
	try {
		mutate(dir);
		return check(dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

/** @param {string} dir @param {string} rel @param {(s: string) => string} f */
function edit(dir, rel, f) {
	const p = join(dir, rel);
	const before = readFileSync(p, 'utf8');
	const after = f(before);
	assert.notEqual(after, before, `the mutation of ${rel} matched nothing`);
	writeFileSync(p, after);
}

/** @param {string} dir */
const readCatalog = (dir) => JSON.parse(readFileSync(join(dir, CATALOG), 'utf8'));
/** @param {string} dir @param {unknown} cat */
const writeCatalog = (dir, cat) => writeFileSync(join(dir, CATALOG), JSON.stringify(cat, null, 2));

/** @param {string[]} errors @param {RegExp} re */
const matched = (errors, re) => errors.filter((e) => re.test(e));

// --- the positive control ---------------------------------------------------

test('the shipped apps/watch_ios tree satisfies every claim', () => {
	const { errors, ok } = check(WATCH_IOS);
	assert.deepEqual(errors, []);
	assert.ok(ok.length >= 12, `only ${ok.length} claims were exercised`);
});

// --- claim 1: a localizing literal with no catalog entry --------------------

test('a Text literal with no String Catalog entry is refused', () => {
	// The quiet one. LocalizedStringKey falls back to the key, so every locale
	// renders the English literal and nothing throws.
	const { errors } = runMutated((dir) => {
		edit(dir, COPY, (s) => s.replace('Text("RUNNING")', 'Text("Still going")'));
	});
	assert.equal(matched(errors, /Text\("Still going"\).*no.*String Catalog entry/s).length, 1, errors.join('\n'));
});

test('an accessibility hint with no catalog entry is refused too', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, join('WatchApp', 'ContentView.swift'), (s) =>
			s.replace('.accessibilityHint("Resumes the paused recording")', '.accessibilityHint("Unwritten")'),
		);
	});
	assert.equal(matched(errors, /accessibilityHint\("Unwritten"\)/).length, 1, errors.join('\n'));
});

test('Text(verbatim:) is not a localization key and needs no catalog entry', () => {
	// This is the shape the two complication stat lines were fixed into: a
	// literal that only stitches already-formatted values together. If the
	// guard demanded a catalog entry for it, the fix it recommends would fail
	// the guard that recommends it.
	const { errors } = runMutated((dir) => {
		edit(dir, COPY, (s) =>
			s.replace('Text("RUNNING")', 'Text("RUNNING")\n                    Text(verbatim: "Still going")'),
		);
	});
	assert.deepEqual(errors, []);
});

test('a literal that only appears inside a comment is not treated as a key', () => {
	// A naive scanner reports every `Text("…")` it can see, comments included,
	// and then the fix is to translate a string the app never renders.
	const { errors } = runMutated((dir) => {
		edit(dir, COPY, (s) => `// Text("A commented example")\n${s}`);
	});
	assert.deepEqual(errors, []);
});

test('an interpolated literal matches its catalog key through the format specifier', () => {
	// `Text("\(n) run queued to sync")` is stored as `%lld run queued to sync`.
	// Both sides normalise to the same shape, so the live tree passes claim 1
	// — asserted here so a normaliser regression cannot hide behind "no
	// interpolated literal is checked anyway".
	const { errors } = runMutated((dir) => {
		const cat = readCatalog(dir);
		delete cat.strings['%lld run queued to sync'];
		writeCatalog(dir, cat);
	});
	assert.equal(matched(errors, /run queued to sync.*no.*String Catalog entry/s).length, 1, errors.join('\n'));
});

// --- claim 2: an orphaned catalog entry -------------------------------------

test('a String Catalog entry no Swift literal references is refused', () => {
	const { errors } = runMutated((dir) => {
		const cat = readCatalog(dir);
		cat.strings['A screen that was deleted'] = {
			localizations: { de: { stringUnit: { state: 'translated', value: 'x' } } },
		};
		writeCatalog(dir, cat);
	});
	assert.equal(matched(errors, /"A screen that was deleted".*no Swift/s).length, 1, errors.join('\n'));
});

test('a key reached only through String(localized:) is not reported as orphaned', () => {
	// The sync-status strings are the ones that are not SwiftUI `Text`. Claim 2
	// searches every string literal rather than only the localizing-API call
	// sites precisely so an unlisted API cannot manufacture a dead key.
	const { errors, ok } = check(WATCH_IOS);
	assert.deepEqual(matched(errors, /no Swift/), []);
	assert.ok(ok.some((o) => /String Catalog entries are still referenced/.test(o)));
});

// --- claim 3: declarations, both directions ---------------------------------

test('a purpose string removed while the call that needs it stays is refused', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, PLIST, (s) =>
			s.replace(/\t<key>NSHealthShareUsageDescription<\/key>\n\t<string>[^<]*<\/string>\n/, ''),
		);
	});
	assert.equal(matched(errors, /missing a usable `NSHealthShareUsageDescription`/).length, 1, errors.join('\n'));
});

test('a purpose string no call claims is refused as an over-claim', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, PLIST, (s) =>
			s.replace(
				'\t<key>WKApplication</key>',
				'\t<key>NSCameraUsageDescription</key>\n\t<string>Unclaimed.</string>\n\t<key>WKApplication</key>',
			),
		);
	});
	assert.equal(matched(errors, /declares `NSCameraUsageDescription` and no code/).length, 1, errors.join('\n'));
});

test('a background mode removed while the call that needs it stays is refused', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, PLIST, (s) => s.replace('\t\t<string>workout-processing</string>\n', ''));
	});
	assert.equal(matched(errors, /WKBackgroundModes is missing `workout-processing`/).length, 1, errors.join('\n'));
});

test('a background mode no call claims is refused', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, PLIST, (s) => s.replace('\t\t<string>location</string>', '\t\t<string>location</string>\n\t\t<string>audio</string>'));
	});
	assert.equal(matched(errors, /declares the `audio` background mode/).length, 1, errors.join('\n'));
});

test('the HealthKit entitlement removed while HKHealthStore stays is refused', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, ENTS, (s) => s.replace('\t<key>com.apple.developer.healthkit</key>\n\t<true/>\n', ''));
	});
	assert.equal(matched(errors, /missing `com\.apple\.developer\.healthkit`/).length, 1, errors.join('\n'));
});

test('an entitlement no call claims is refused — the health background-delivery case', () => {
	// The live defect this guard was written against: the tree declared
	// `com.apple.developer.healthkit.background-delivery` and nothing anywhere
	// called `enableBackgroundDelivery`. It is a health capability, so an
	// unexercised one over-claims what the watch collects as well as inviting
	// a rejection.
	const { errors } = runMutated((dir) => {
		edit(dir, ENTS, (s) =>
			s.replace(
				'\t<key>com.apple.security.application-groups</key>',
				'\t<key>com.apple.developer.healthkit.background-delivery</key>\n\t<true/>\n\t<key>com.apple.security.application-groups</key>',
			),
		);
	});
	assert.equal(
		matched(errors, /declares `com\.apple\.developer\.healthkit\.background-delivery` and no code/).length,
		1,
		errors.join('\n'),
	);
});

test('an App Group entitlement present but empty is refused as unusable', () => {
	// `UserDefaults(suiteName:)` binds against a named group. An entitlement
	// key with no group in it is the same silence as no key at all, so
	// "declared" is not the claim — "declared with a group" is.
	const { errors } = runMutated((dir) => {
		edit(dir, ENTS, (s) =>
			s.replace(/<key>com\.apple\.security\.application-groups<\/key>\n\t<array>[\s\S]*?<\/array>/, '<key>com.apple.security.application-groups</key>\n\t<array/>'),
		);
	});
	assert.equal(matched(errors, /application-groups` with an unusable value/).length, 1, errors.join('\n'));
});

// --- claim 4: the duplicated complication formatters ------------------------

test('a complication formatter that drifts from its RunFormat copy is refused', () => {
	// The failure no Swift test can see: ActiveRunComplication.swift is in no
	// target, so ComplicationFormatterTests links the RunFormat copy and stays
	// green while the widget rounds differently.
	const { errors } = runMutated((dir) => {
		edit(dir, COPY, (s) => s.replace('func formatElapsed(_ seconds: Int) -> String {\n    let s = max(seconds, 0)', 'func formatElapsed(_ seconds: Int) -> String {\n    let s = seconds'));
	});
	assert.equal(matched(errors, /`formatElapsed` differs between/).length, 1, errors.join('\n'));
});

test('a complication formatter deleted outright is refused, not silently skipped', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, ORIGIN, (s) => s.replace('func formatDistanceKm(', 'func formatDistanceKmOld('));
	});
	assert.equal(matched(errors, /`formatDistanceKm` is missing from/).length, 1, errors.join('\n'));
});

// --- claim 5: the App Group identifier, stated twice ------------------------

test('renaming the App Group in Swift without following it in the README is refused', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, BRIDGE, (s) => s.replace('group.com.threkir.app.activerun', 'group.com.threkir.app.run'));
	});
	assert.equal(matched(errors, /never names/).length, 1, errors.join('\n'));
});

// --- vacuity ----------------------------------------------------------------

test('a tree with no Swift sources fails loudly rather than passing vacuously', () => {
	const dir = mkdtempSync(join(tmpdir(), 'watch-ios-empty-'));
	try {
		mkdirSync(join(dir, 'WatchApp'), { recursive: true });
		mkdirSync(join(dir, 'Complications'), { recursive: true });
		const { errors } = check(dir);
		assert.equal(matched(errors, /pass vacuously/).length, 1, errors.join('\n'));
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('an empty String Catalog fails loudly rather than passing vacuously', () => {
	const { errors } = runMutated((dir) => {
		writeCatalog(dir, { sourceLanguage: 'en', strings: {} });
	});
	assert.ok(matched(errors, /zero entries/).length === 1, errors.join('\n'));
});

// --- the pure helpers -------------------------------------------------------

test('comment stripping does not eat the scheme separator inside a URL literal', () => {
	// SupabaseService.swift holds `http://127.0.0.1:54321`. A `//`-to-EOL strip
	// that ignores string literals deletes the rest of that line, and with it
	// any localizing call sharing it.
	const out = stripSwiftComments('let url = "http://127.0.0.1:54321" // trailing\nlet x = 1\n');
	assert.match(out, /"http:\/\/127\.0\.0\.1:54321"/);
	assert.doesNotMatch(out, /trailing/);
});

test('comment stripping handles nested block comments', () => {
	const out = stripSwiftComments('a /* outer /* inner */ still */ b');
	assert.match(out, /a\s+b/);
});

test('normalizeKey balances nested interpolation rather than stopping at the first paren', () => {
	// `Label("\(Int(bpm.rounded())) bpm")` against the key `%lld bpm`. A
	// non-greedy `\\(.*?\\)` stops at the inner `)`, leaves `) bpm` behind, and
	// reports a live, correct call site as a missing key — which is exactly
	// what the first by-hand measurement of this did.
	assert.equal(
		normalizeKey('\\(Int(bpm.rounded())) bpm'),
		normalizeKey('%lld bpm'),
	);
});

test('normalizeKey collapses positional specifiers to the same shape as plain ones', () => {
	assert.equal(normalizeKey('Recover unsaved run from %1$@, %2$@, %3$@?'), normalizeKey('Recover unsaved run from %@, %@, %@?'));
});

test('normalizeKey does not collapse two different sentences onto one shape', () => {
	assert.notEqual(normalizeKey('%@ to go'), normalizeKey('%@ to stop'));
});

test('parseFlatPlist reads the four value shapes these files use', () => {
	const m = parseFlatPlist(
		'<plist version="1.0"><dict>' +
			'<key>Flag</key><true/>' +
			'<key>Off</key><false/>' +
			'<key>Word</key><string>hello</string>' +
			'<key>Empty</key><array/>' +
			'<key>List</key><array><string>a</string><string>b</string></array>' +
			'</dict></plist>',
	);
	assert.equal(m.get('Flag'), true);
	assert.equal(m.get('Off'), false);
	assert.equal(m.get('Word'), 'hello');
	assert.deepEqual(m.get('Empty'), []);
	assert.deepEqual(m.get('List'), ['a', 'b']);
});

test('parseFlatPlist agrees with the real files it is pointed at', () => {
	// The hand-rolled reader exists so this runs under a bare node on Linux.
	// It is only worth having if it answers the same as a real plist parser on
	// the two files it actually reads, so both are re-read here and their key
	// sets asserted rather than assumed.
	const info = parseFlatPlist(readFileSync(join(WATCH_IOS, PLIST), 'utf8'));
	assert.equal(info.get('WKApplication'), true);
	assert.deepEqual(info.get('WKBackgroundModes'), ['location', 'workout-processing']);
	assert.equal(typeof info.get('NSHealthShareUsageDescription'), 'string');
	assert.deepEqual(info.get('CFBundleLocalizations'), ['en', 'de', 'fr', 'es', 'ja', 'pt-BR', 'pt-PT']);

	const ents = parseFlatPlist(readFileSync(join(WATCH_IOS, ENTS), 'utf8'));
	assert.equal(ents.get('com.apple.developer.healthkit'), true);
	assert.deepEqual(ents.get('com.apple.developer.healthkit.access'), []);
	assert.deepEqual(ents.get('com.apple.security.application-groups'), ['group.com.threkir.app.activerun']);
});

test('functionBody balances braces rather than stopping at the first close', () => {
	const src = 'func f() -> Int {\n    if true {\n        return 1\n    }\n    return 0\n}\nfunc g() {}\n';
	const body = functionBody(src, 'f');
	assert.ok(body?.endsWith('return 0\n}'), body ?? 'null');
	assert.doesNotMatch(body ?? '', /func g/);
	assert.equal(functionBody(src, 'missing'), null);
});
