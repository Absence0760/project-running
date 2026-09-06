// Unit tests for scripts/check_watch_ios_source.mjs.
//
// That guard makes ten claims about a tier this repo compiles in exactly one
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
	DIRECT_ONLY_FIELDS,
	buildSettingsBlocks,
	INGEST,
	ROUTE_BRIDGE,
	UNGUARDED_DESTRUCTIVE,
	check,
	confirmationDialogSpans,
	dartInvokeKeys,
	destructiveButtons,
	methodBody,
	functionBody,
	normalizeKey,
	parseFlatPlist,
	phoneEnvelopeKeys,
	stripSwiftComments,
	swiftPayloadKeys,
	swiftStructFields,
	watchEnvelopeKeys,
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
const SYNC = join('WatchApp', 'ContentView.swift');
const INGEST_ABS = join(REPO_ROOT, INGEST);
const ROUTE_BRIDGE_ABS = join(REPO_ROOT, ROUTE_BRIDGE);
/** Where `stage()` parks a copy of the phone's half of the envelope. */
const STAGED_INGEST = 'WatchIngestBridge.swift';
/** …and of the Dart end of the route-push envelope. */
const STAGED_ROUTE_BRIDGE = 'apple_watch_route_bridge.dart';
const ARMED = join('WatchApp', 'ArmedRoute.swift');
const DIRECT = join('WatchApp', 'SupabaseService.swift');
const PBX = join('WatchApp.xcodeproj', 'project.pbxproj');

/** Copy only the files the guard reads into a throwaway tree. */
function stage() {
	const dir = mkdtempSync(join(tmpdir(), 'watch-ios-source-'));
	const rels = [CATALOG, PLIST, ENTS, README, PBX];
	for (const sub of ['WatchApp', 'Complications']) {
		for (const name of readdirSync(join(WATCH_IOS, sub))) {
			if (name.endsWith('.swift')) rels.push(join(sub, name));
		}
	}
	for (const rel of rels) {
		mkdirSync(join(dir, dirname(rel)), { recursive: true });
		cpSync(join(WATCH_IOS, rel), join(dir, rel));
	}
	cpSync(INGEST_ABS, join(dir, STAGED_INGEST));
	cpSync(ROUTE_BRIDGE_ABS, join(dir, STAGED_ROUTE_BRIDGE));
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
		return check(dir, join(dir, STAGED_INGEST), join(dir, STAGED_ROUTE_BRIDGE));
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
	const { errors, ok } = check(WATCH_IOS, INGEST_ABS, ROUTE_BRIDGE_ABS);
	assert.deepEqual(errors, []);
	assert.ok(ok.length >= 13, `only ${ok.length} claims were exercised`);
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
	const { errors, ok } = check(WATCH_IOS, INGEST_ABS, ROUTE_BRIDGE_ABS);
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

// --- claim 6: the run hand-off envelope, read from both ends ----------------

test('a metadata key the watch sends and the phone never lifts is refused', () => {
	// The already-happened failure. Nothing throws: the file transfers, the
	// row is inserted, and one column is simply absent.
	const { errors } = runMutated((dir) => {
		edit(dir, SYNC, (s) => s.replace('"source": "watch",', '"source": "watch",\n                "cadence_spm": 0,'));
	});
	assert.equal(matched(errors, /`cadence_spm`.*never\s+lifts it out/s).length, 1, errors.join('\n'));
});

test('a metadata key the phone reads and the watch never sends is refused', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, STAGED_INGEST, (s) =>
			s.replace('if let v = metadata["avg_bpm"]', 'if let v = metadata["laps"] { payload["laps"] = v }\n        if let v = metadata["avg_bpm"]'),
		);
	});
	assert.equal(matched(errors, /reads `laps`.*never puts it there/s).length, 1, errors.join('\n'));
});

test('an unparseable envelope on either end fails loudly rather than vacuously', () => {
	// Both extractors read a hand-written literal. If either shape changes,
	// the honest answer is "this claim can no longer be made", not silence.
	// TWO claims read this literal — (6) against the phone lift and (9)
	// against the DEBUG direct writer — and both must say so, because a claim
	// that quietly stopped reading is the failure mode the whole file is
	// written against.
	const { errors } = runMutated((dir) => {
		edit(dir, SYNC, (s) => s.replace('var metadata: [String: Any] = [', 'var metadata = buildMetadata(['));
	});
	assert.equal(matched(errors, /pass vacuously/).length, 2, errors.join('\n'));
	assert.equal(matched(errors, /claim \(6\) would pass vacuously/).length, 1, errors.join('\n'));
	assert.equal(matched(errors, /claim \(9\) would pass vacuously/).length, 1, errors.join('\n'));
});

test('claims 6 and 7 are skipped, not faked, when no phone half is available', () => {
	const { errors, ok } = check(WATCH_IOS);
	assert.deepEqual(errors, []);
	assert.deepEqual(ok.filter((o) => /run hand-off metadata keys/.test(o)), []);
	assert.deepEqual(ok.filter((o) => /route-push keys/.test(o)), []);
});

test('claim 7 is skipped when the Dart rail alone is unavailable', () => {
	// The route envelope has three ends. Two of them agreeing is not the claim,
	// so a caller holding only the two Swift ones must be told nothing rather
	// than told half of it.
	const { errors, ok } = check(WATCH_IOS, INGEST_ABS);
	assert.deepEqual(errors, []);
	assert.ok(ok.some((o) => /run hand-off metadata keys/.test(o)));
	assert.deepEqual(ok.filter((o) => /route-push keys/.test(o)), []);
});

// --- claim 7: the route-push envelope, three rails --------------------------

test('the three route-push rails agree on the shipped tree', () => {
	const { errors, ok } = check(WATCH_IOS, INGEST_ABS, ROUTE_BRIDGE_ABS);
	assert.deepEqual(matched(errors, /route/), []);
	assert.ok(ok.some((o) => /^all 5 route-push keys agree/.test(o)));
});

test('a key renamed on the Dart rail alone is refused', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, STAGED_ROUTE_BRIDGE, (s) => s.replace("'route_lng':", "'route_lon':"));
	});
	assert.ok(matched(errors, /`route_lon` is on .*apple_watch_route_bridge\.dart/).length >= 1, errors.join('\n'));
	assert.ok(matched(errors, /`route_lng` is on .*WatchIngestBridge\.swift/).length >= 1, errors.join('\n'));
});

test('a key renamed on the phone repack alone is refused', () => {
	// The failure this claim exists for: the phone reads `route_name` off the
	// channel and forwards it under a different key, so `ArmedRoute.decode`
	// rejects the payload, the whole push is dropped, and the runner was
	// already told the route was armed.
	const { errors } = runMutated((dir) => {
		edit(dir, STAGED_INGEST, (s) => s.replace('"route_name": name,', '"routeName": name,'));
	});
	assert.ok(matched(errors, /`routeName` is on .*WatchIngestBridge\.swift/).length >= 1, errors.join('\n'));
});

test('a key renamed on the watch decode alone is refused', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, ARMED, (s) => s.replace('payload["route_distance_m"]', 'payload["route_distance"]'));
	});
	assert.ok(matched(errors, /`route_distance` is on .*ArmedRoute\.swift/).length >= 1, errors.join('\n'));
});

test('a route push whose Dart call site changed shape fails vacuity rather than passing', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, STAGED_ROUTE_BRIDGE, (s) => s.replace("invokeMethod<void>('push'", "invokeMethod<void>('pushRoute'"));
	});
	assert.equal(matched(errors, /Parsed no route-push keys/).length, 1, errors.join('\n'));
});

test('a decode that stops subscripting the payload fails vacuity rather than passing', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, ARMED, (s) => s.replace(/payload\[/g, 'input['));
	});
	assert.equal(matched(errors, /Parsed no route-push keys/).length, 1, errors.join('\n'));
});

test('swiftPayloadKeys reads both the subscripts and the repacked literal', () => {
	// The phone rail does both in one function, and a key it reads but does not
	// forward is a field dropped between two lines of it.
	const body = 'guard let a = args["k"] as? String else { return nil }\nreturn ["k": a, "extra": 1]\n';
	assert.deepEqual([...(swiftPayloadKeys(body, 'args') ?? [])].sort(), ['extra', 'k']);
	assert.equal(swiftPayloadKeys('return ["k": 1]', 'args'), null);
});

test('dartInvokeKeys spans the nested collection literals in the map it reads', () => {
	// `route_lat` / `route_lng` are `[for (…) …]` comprehensions, so a scan
	// that stopped at the first `]` would lose everything after the first one.
	const src = "await _c.invokeMethod<void>('push', {\n  'a': 1,\n  'b': [for (final p in ps) p.x],\n  'c': 2,\n});";
	assert.deepEqual([...(dartInvokeKeys(src, 'push') ?? [])].sort(), ['a', 'b', 'c']);
	assert.equal(dartInvokeKeys(src, 'nope'), null);
});

test('methodBody finds an indented method with modifiers in front of func', () => {
	const src = 'struct S {\n    private static func decode(_ p: [String: Any]) -> S? {\n        return nil\n    }\n}\n';
	assert.match(methodBody(src, 'decode') ?? '', /return nil/);
	assert.equal(methodBody(src, 'encode'), null);
});

test('watchEnvelopeKeys reads the dictionary literal and the conditional assignment', () => {
	const keys = watchEnvelopeKeys(
		'var metadata: [String: Any] = [\n  "id": run.id,\n  "nested": ["a": 1],\n]\nif x { metadata["avg_bpm"] = bpm }\n',
	);
	assert.deepEqual([...(keys ?? [])].sort(), ['a', 'avg_bpm', 'id', 'nested']);
});

test('watchEnvelopeKeys returns null when the dictionary literal is not there to read', () => {
	assert.equal(watchEnvelopeKeys('var metadata = buildMetadata([\n  "id": run.id,\n])\n'), null);
});

test('watchEnvelopeKeys balances the nested array rather than stopping at its close bracket', () => {
	// A non-balancing scan ends the dictionary at the inner `]` and loses every
	// key after it — which on the live file is `last_modified_at`, the one the
	// phone delta-fetch filters on.
	const keys = watchEnvelopeKeys('var metadata: [String: Any] = [\n  "a": [1, 2],\n  "z": 3,\n]\n');
	assert.ok(keys?.has('z'), [...(keys ?? [])].join(','));
});

test('phoneEnvelopeKeys reads the required-field loop and the individual reads', () => {
	const keys = phoneEnvelopeKeys(
		'for key in ["id", "source"] {\n  if let v = metadata[key] { payload[key] = v }\n}\n' +
			'if let v = metadata["avg_bpm"] { payload["avg_bpm"] = v }\n',
	);
	assert.deepEqual([...keys].sort(), ['avg_bpm', 'id', 'source']);
});

test('phoneEnvelopeKeys ignores an array literal that has nothing to do with the envelope', () => {
	assert.deepEqual([...phoneEnvelopeKeys('for x in ["unrelated"] { print(x) }\n')], []);
});

// --- (8) destructive controls -----------------------------------------------

test('destructiveButtons reads the label and body of a destructive Button only', () => {
	const src =
		'Button("Keep", role: .cancel) { keep() }\n' +
		'Button("Discard", role: .destructive) {\n    armed = true\n}\n';
	const found = destructiveButtons(src);
	assert.equal(found.length, 1);
	assert.equal(found[0].label, 'Discard');
	assert.equal(found[0].body?.trim(), 'armed = true');
});

test('destructiveButtons is not unbalanced by a paren inside a label', () => {
	// `Button("Delete (all)", role: .destructive)` closes at the wrong paren
	// under a matcher that does not skip string literals, and the role is then
	// outside the args it reads — so the button vanishes from the claim.
	const found = destructiveButtons('Button("Delete (all)", role: .destructive) { go() }\n');
	assert.equal(found.length, 1);
	assert.equal(found[0].label, 'Delete (all)');
});

test('confirmationDialogSpans covers the trailing actions and message closures', () => {
	const src =
		'.confirmationDialog(\n  "Discard this run?",\n  isPresented: $flag\n) {\n' +
		'    Button("Discard", role: .destructive) { onDiscard() }\n' +
		'} message: {\n    Text("Not saved anywhere else")\n}\n';
	const spans = confirmationDialogSpans(src);
	assert.equal(spans.length, 1);
	const button = src.indexOf('Button("Discard"');
	assert.ok(button > spans[0][0] && button < spans[0][1], 'the action must fall inside the span');
	// And the span must END — a walker that runs to EOF would swallow every
	// later Button in the file and pass them all as "the dialog's action".
	assert.equal(spans[0][1], src.length - 1);
});

test('claim (8) fails when a destructive Button acts on the tap', () => {
	const { errors } = runMutated((dir) => {
		const f = join(dir, SYNC);
		writeFileSync(
			f,
			readFileSync(f, 'utf8').replace('confirmingDiscard = true', 'onDiscard()'),
		);
	});
	assert.ok(
		errors.some((e) => e.includes('acts on the tap instead of arming a confirmation')),
		errors.join('\n'),
	);
});

test('claim (8) fails when the armed flag is presented by no dialog', () => {
	const { errors } = runMutated((dir) => {
		const f = join(dir, SYNC);
		writeFileSync(
			f,
			readFileSync(f, 'utf8').replace(/isPresented: \$confirmingDiscard/g, 'isPresented: $other'),
		);
	});
	assert.ok(
		errors.some((e) => e.includes('and no confirmationDialog is presented on it')),
		errors.join('\n'),
	);
});

test('claim (8) fails when every confirmationDialog is deleted', () => {
	const { errors } = runMutated((dir) => {
		const f = join(dir, SYNC);
		writeFileSync(f, readFileSync(f, 'utf8').replaceAll('.confirmationDialog(', '.ignored('));
	});
	assert.ok(
		errors.some((e) => e.includes('destructive Button(s) and no confirmationDialog')),
		errors.join('\n'),
	);
});

test('claim (8) fails on an exemption for a button that no longer exists', () => {
	assert.ok(
		Object.keys(UNGUARDED_DESTRUCTIVE).length > 0,
		'the register is empty, so the staleness test below proves nothing',
	);
	const { errors } = runMutated((dir) => {
		const f = join(dir, SYNC);
		writeFileSync(
			f,
			readFileSync(f, 'utf8').replace('Button("Stop", role: .destructive)', 'Button("Halt", role: .destructive)'),
		);
	});
	assert.ok(
		errors.some((e) => e.includes('UNGUARDED_DESTRUCTIVE exempts a destructive Button')),
		errors.join('\n'),
	);
});

// --- claim 9: the two run-write paths send the same run ---------------------

test('claim (9) fails when the DEBUG direct path drops a field the envelope sends', () => {
	// The shape it shipped in: `RunPayload.metadata` was `[String: String]`, so
	// the two numeric heart-rate keys had nowhere to go and the row simply
	// arrived short. Nothing failed — which is why this is a guard.
	const { errors } = runMutated((dir) => {
		edit(dir, DIRECT, (s) => s.replace('        let hr_coverage: Double?\n', ''));
	});
	assert.ok(
		errors.some((e) => e.includes('`hr_coverage`') && e.includes('sends it on neither')),
		errors.join('\n'),
	);
});

test('claim (9) fails when the direct path grows a field the envelope has no idea about', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, DIRECT, (s) =>
			s.replace('        let hr_coverage: Double?', '        let hr_coverage: Double?\n        let cadence_spm: Double?'),
		);
	});
	assert.ok(
		errors.some((e) => e.includes('`cadence_spm`') && e.includes('DIRECT_ONLY_FIELDS')),
		errors.join('\n'),
	);
});

test('claim (9) fails on an exemption for a field the direct path no longer sends', () => {
	assert.ok(
		Object.keys(DIRECT_ONLY_FIELDS).length > 0,
		'the register is empty, so the staleness test below proves nothing',
	);
	const { errors } = runMutated((dir) => {
		edit(dir, DIRECT, (s) => s.replaceAll('track_url', 'object_path'));
	});
	assert.ok(
		errors.some((e) => e.includes('DIRECT_ONLY_FIELDS exempts `track_url`')),
		errors.join('\n'),
	);
});

test('claim (9) refuses to pass vacuously when the payload struct is renamed', () => {
	// A renamed struct parses to null, not to an empty field set: reporting
	// that a payload nobody sends agrees with the envelope is the failure this
	// whole guard exists to avoid.
	const { errors } = runMutated((dir) => {
		edit(dir, DIRECT, (s) => s.replace('private struct RunMetadata: Encodable', 'private struct RowMetadata: Encodable'));
	});
	assert.ok(
		errors.some((e) => e.includes('claim (9) would pass vacuously')),
		errors.join('\n'),
	);
});

test('claim (9) refuses to pass vacuously when RunPayload stops carrying the bag', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, DIRECT, (s) => s.replace('        let metadata: RunMetadata', '        let extra: RunMetadata'));
	});
	assert.ok(
		errors.some((e) => e.includes('claim (9) would pass vacuously')),
		errors.join('\n'),
	);
});

test('swiftStructFields reads stored properties and not computed ones', () => {
	const src = [
		'private struct Thing: Encodable {',
		'    let a: String',
		'    var b: Double?',
		'    var c: Int { 3 }',
		'    func d(x: Int) -> Int {',
		'        let local: Int = x',
		'        return local',
		'    }',
		'}',
	].join('\n');
	assert.deepEqual(swiftStructFields(src, 'Thing'), ['a', 'b']);
	assert.equal(swiftStructFields(src, 'Absent'), null);
});

// --- claim 10: the Info.plist owns its own keys --------------------------

test('claim (10) refuses an INFOPLIST_KEY_* on a target that does not generate its plist', () => {
	// The shape it shipped in: INFOPLIST_KEY_CFBundleDisplayName = "Threkir" on
	// both configurations, GENERATE_INFOPLIST_FILE = NO, and no
	// CFBundleDisplayName in the file — so the watch app was named `WatchApp`
	// while a build setting sitting right there said otherwise.
	const { errors } = runMutated((dir) => {
		edit(dir, PBX, (s) =>
			s.replace('\t\t\t\tGENERATE_INFOPLIST_FILE = NO;\n', '\t\t\t\tGENERATE_INFOPLIST_FILE = NO;\n\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Threkir";\n'),
		);
	});
	assert.ok(
		errors.some((e) => e.includes('INFOPLIST_KEY_CFBundleDisplayName') && e.includes('inert')),
		errors.join('\n'),
	);
});

test('claim (10) refuses a watch app with no display name of its own', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, PLIST, (s) => s.replace('\t<key>CFBundleDisplayName</key>\n\t<string>Threkir</string>\n', ''));
	});
	assert.ok(
		errors.some((e) => e.includes('declares no `CFBundleDisplayName`')),
		errors.join('\n'),
	);
});

test('claim (10) refuses WKWatchOnly and a companion bundle id together', () => {
	// Apple documents them as mutually exclusive. This is the mistake a session
	// resolving the companion question is most likely to make: adding the
	// companion key without removing the watch-only claim.
	const { errors } = runMutated((dir) => {
		edit(dir, PLIST, (s) =>
			s.replace(
				'\t<key>WKWatchOnly</key>',
				'\t<key>WKCompanionAppBundleIdentifier</key>\n\t<string>com.threkir.app</string>\n\t<key>WKWatchOnly</key>',
			),
		);
	});
	assert.ok(
		errors.some((e) => e.includes('mutually exclusive')),
		errors.join('\n'),
	);
});

test('claim (10) reports rather than passes when no target uses a manual plist', () => {
	const { errors } = runMutated((dir) => {
		edit(dir, PBX, (s) => s.replaceAll('GENERATE_INFOPLIST_FILE = NO;', 'GENERATE_INFOPLIST_FILE = YES;'));
	});
	assert.ok(
		errors.some((e) => e.includes("claim (10)'s first half read nothing")),
		errors.join('\n'),
	);
});

test('buildSettingsBlocks brace-matches rather than running to the next block', () => {
	const src = [
		'\t\t\tbuildSettings = {',
		'\t\t\t\tA = 1;',
		'\t\t\t\tPATHS = (',
		'\t\t\t\t\t"$(inherited)",',
		'\t\t\t\t);',
		'\t\t\t};',
		'\t\t\tbuildSettings = {',
		'\t\t\t\tB = 2;',
		'\t\t\t};',
	].join('\n');
	const blocks = buildSettingsBlocks(src);
	assert.equal(blocks.length, 2);
	assert.ok(blocks[0].includes('A = 1') && !blocks[0].includes('B = 2'));
	assert.deepEqual(buildSettingsBlocks('nothing here'), []);
});
