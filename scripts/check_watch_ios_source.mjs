// Source-level claims about `apps/watch_ios` that no compiler in this repo's
// Linux CI can make.
//
// The watchOS tier is the least verifiable thing in the monorepo. Exactly one
// job compiles it — `test-watch-ios`, on a macOS runner — and every other
// claim about it rests on reading. `apps/watch_ios/scripts/check_xcstrings_parity.sh`
// already holds the String Catalog against its two locale-declaration sites
// (decisions § 761 / § 795). This guard holds the five *other* things about
// the tier that a bare `node` on Linux can honestly measure, each of which
// fails in a way no Swift test and no `xcodebuild` run would report:
//
//   (1) Every string literal handed to a localizing SwiftUI / Foundation API
//       has a String Catalog entry. A literal with no entry is NOT a build
//       error and NOT a crash: `LocalizedStringKey` falls back to the key, so
//       the watch renders English in every locale and everything passes. The
//       cost lands later and elsewhere — the next Xcode build extracts the
//       literal into the catalog as a new untranslated key, and *then* the
//       parity guard fails a PR that never touched localization.
//
//   (2) Every String Catalog entry is still referenced by some Swift literal.
//       A key orphaned by a UI change is six translations nobody will delete,
//       and it makes the catalog's size a lie about the app's surface.
//
//   (3) Every capability the Swift exercises is declared in `Info.plist` /
//       `WatchApp.entitlements`, and every declaration is claimed by code —
//       both directions, mirroring `check_ios_native_declarations.mjs`, which
//       does exactly this for the phone and reads nothing under
//       `apps/watch_ios`. A missing purpose string makes watchOS deny the
//       permission silently; an over-declared capability is an App Review
//       rejection and a privacy over-claim.
//
//   (4) The three pure formatters the complication duplicates are byte-for-byte
//       the copies in `RunFormat.swift`. Both files say "keep the two in
//       lockstep" in a comment and nothing enforced it. `ComplicationFormatterTests`
//       cannot: `Complications/ActiveRunComplication.swift` is in no target, so
//       the suite links the `RunFormat.swift` copy and passing proves nothing
//       about the copy the widget will actually run.
//
//   (5) The App Group identifier in `ActiveRunBridge.swift` matches the one
//       `Complications/README.md` instructs an operator to type into Xcode. A
//       mismatch there is a shared container that silently never binds.
//
// WHAT THIS GUARD DOES NOT PROVE. It parses text. It does not compile Swift,
// does not run it, and cannot see anything a type-checker would: claim (1)
// matches a catalog key on the SHAPE of its interpolation, not on the type of
// what is interpolated, so swapping `\(anInt)` for `\(aString)` under a `%lld`
// key reads as unchanged here. Nothing in this file is evidence that the app
// builds. See docs/custom_watch/quality_standards.md for the rungs.
//
// Run: node scripts/check_watch_ios_source.mjs
// CI:  the `watch-ios-locale-parity` job in .github/workflows/ci.yml.

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** Swift source directories, relative to the `apps/watch_ios` root. */
export const SWIFT_DIRS = ['WatchApp', 'Complications'];

/**
 * APIs whose FIRST positional string literal is a `LocalizedStringKey` (or a
 * `String(localized:)` lookup) and therefore must exist in the catalog.
 *
 * A literal reaching a localizing API through some call this list does not
 * name is simply not required to be in the catalog — the omission is a false
 * negative, never a false alarm. Claim (2) below deliberately does NOT use
 * this list: it looks for the key text among ALL string literals, so a key
 * consumed through an unlisted API is not reported as dead.
 */
export const LOCALIZING_APIS = [
	'Text',
	'Button',
	'Label',
	'Toggle',
	'TextField',
	'Picker',
	'Section',
	'LabeledContent',
	'NavigationLink',
	'LocalizedStringKey',
	'widgetLabel',
	'accessibilityLabel',
	'accessibilityHint',
	'accessibilityValue',
	'navigationTitle',
	'confirmationDialog',
	'alert',
	'configurationDisplayName',
	'description',
];

/**
 * `WKBackgroundModes` entries, each derived from the call that needs it.
 * The reverse direction is an error for the same reason it is on the phone:
 * App Review rejects a binary declaring a background capability it never
 * exercises.
 * @type {{ mode: string, pattern: RegExp, needed_by: string, why: string }[]}
 */
export const BACKGROUND_MODES = [
	{
		mode: 'location',
		pattern: /allowsBackgroundLocationUpdates\s*=\s*true/,
		needed_by: 'CoreLocation is asked to keep delivering fixes with the display asleep',
		why:
			'CLLocationManager.allowsBackgroundLocationUpdates throws unless the ' +
			'`location` background mode is declared, which takes the recorder down ' +
			'rather than degrading it.',
	},
	{
		mode: 'workout-processing',
		pattern: /HKWorkoutSession\s*\(/,
		needed_by: 'the run holds an HKWorkoutSession for heart rate',
		why:
			'`workout-processing` is what lets the session — and the ' +
			'HKLiveWorkoutBuilder collecting from it — keep running once the wrist ' +
			'drops. Without it heart rate stops the moment the screen sleeps, which ' +
			'is most of a long run.',
	},
];

/** A background mode allowed to stand with no rule claiming it. */
/** @type {string[]} */
export const UNCLAIMED_BACKGROUND_MODES = [];

/**
 * Purpose strings watchOS demands before it grants the permission. A missing
 * one is not a build error — the OS denies the request and the feature returns
 * nothing.
 * @type {{ key: string, pattern: RegExp, needed_by: string }[]}
 */
export const PURPOSE_STRINGS = [
	{
		key: 'NSLocationWhenInUseUsageDescription',
		pattern: /requestWhenInUseAuthorization\s*\(/,
		needed_by: 'WorkoutManager asks for foreground location at start()',
	},
	{
		// Derived from the same call the phone guard derives it from, not from
		// requestAlwaysAuthorization (which this app never makes): asking
		// CoreLocation to run backgrounded is what puts the app in front of the
		// grant this string explains.
		key: 'NSLocationAlwaysAndWhenInUseUsageDescription',
		pattern: /allowsBackgroundLocationUpdates\s*=\s*true/,
		needed_by: 'the recorder keeps GPS running with the display asleep',
	},
	{
		key: 'NSHealthShareUsageDescription',
		pattern: /requestAuthorization\s*\(\s*toShare:[^)]*read:/,
		needed_by: 'HealthKitManager reads heart rate',
	},
	{
		key: 'NSHealthUpdateUsageDescription',
		pattern: /requestAuthorization\s*\(\s*toShare:/,
		needed_by: 'HealthKitManager writes the workout back to Health',
	},
];

/**
 * `WatchApp.entitlements` keys, each derived from the code that needs it.
 * @type {{ key: string, pattern: RegExp, needed_by: string, accepts: (v: unknown) => boolean, shape: string, why: string }[]}
 */
export const ENTITLEMENTS = [
	{
		key: 'com.apple.developer.healthkit',
		pattern: /HKHealthStore\s*\(/,
		needed_by: 'HealthKitManager instantiates an HKHealthStore',
		accepts: (v) => v === true,
		shape: '<true/>',
		why: 'The first HealthKit call on a device without the entitlement fails outright.',
	},
	{
		key: 'com.apple.developer.healthkit.access',
		pattern: /HKHealthStore\s*\(/,
		needed_by: 'the HealthKit grant is scoped by this array',
		accepts: (v) => Array.isArray(v),
		shape: '<array/> (empty = no clinical-record types)',
		why:
			'Xcode writes this alongside the HealthKit capability. Empty is the ' +
			'correct value: it claims none of the clinical-record types, which this ' +
			'app does not read.',
	},
	{
		key: 'com.apple.security.application-groups',
		pattern: /UserDefaults\s*\(\s*suiteName:/,
		needed_by: 'ActiveRunBridge writes the complication snapshot to a shared container',
		accepts: (v) => Array.isArray(v) && v.length > 0,
		shape: '<array><string>group.…</string></array>',
		why:
			'`UserDefaults(suiteName:)` for a group the target is not entitled to ' +
			'yields no shared store, so every publishComplicationSnapshot() writes ' +
			'nowhere — and ActiveRunBridge.write fails closed, so nothing is thrown ' +
			'and nothing is logged.',
	},
];

/** Entitlement keys allowed to stand with no rule claiming them. */
/** @type {string[]} */
export const UNCLAIMED_ENTITLEMENTS = [];

/**
 * Functions the complication carries a second copy of, because its Widget
 * Extension target cannot link `RunFormat.swift`. Both copies must be
 * byte-identical or the watch face and the run screen round the same run
 * differently.
 */
export const DUPLICATED_FORMATTERS = ['formatElapsed', 'formatDistanceKm', 'formatPaceSecPerKm'];

export const FORMATTER_ORIGIN = join('WatchApp', 'RunFormat.swift');
export const FORMATTER_COPY = join('Complications', 'ActiveRunComplication.swift');
export const BRIDGE = join('WatchApp', 'ActiveRunBridge.swift');
export const COMPLICATION_README = join('Complications', 'README.md');

// --- text utilities ---------------------------------------------------------

/**
 * Strip Swift comments without touching string literals. A naive `//` strip
 * eats the scheme separator out of a URL, and `SupabaseService.swift` holds
 * one. Nested block comments are Swift-legal, so the depth is counted.
 * @param {string} src
 */
export function stripSwiftComments(src) {
	let out = '';
	let i = 0;
	let block = 0;
	while (i < src.length) {
		const two = src.slice(i, i + 2);
		if (block > 0) {
			if (two === '/*') {
				block += 1;
				i += 2;
				continue;
			}
			if (two === '*/') {
				block -= 1;
				i += 2;
				continue;
			}
			out += src[i] === '\n' ? '\n' : ' ';
			i += 1;
			continue;
		}
		if (two === '/*') {
			block = 1;
			i += 2;
			continue;
		}
		if (two === '//') {
			while (i < src.length && src[i] !== '\n') i += 1;
			continue;
		}
		if (src[i] === '"') {
			out += src[i];
			i += 1;
			while (i < src.length) {
				if (src[i] === '\\') {
					out += src.slice(i, i + 2);
					i += 2;
					continue;
				}
				out += src[i];
				i += 1;
				if (src[i - 1] === '"') break;
			}
			continue;
		}
		out += src[i];
		i += 1;
	}
	return out;
}

/**
 * Collapse every printf conversion and every interpolation to one placeholder,
 * so a source literal and the catalog key Xcode extracted from it compare
 * equal. Interpolations nest (`Int(bpm.rounded())` inside one), so the closing
 * paren is found by balancing rather than by a non-greedy match — the shape
 * that silently mis-read two literals when this was first measured by hand.
 * @param {string} s
 */
export function normalizeKey(s) {
	const noSpecs = s.replace(
		/%(?:\d+\$)?[-+ #0]*[\d*]*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@dioruxXeEfgGacsp]/g,
		'•',
	);
	let out = '';
	let i = 0;
	while (i < noSpecs.length) {
		if (noSpecs[i] === '\\' && noSpecs[i + 1] === '(') {
			let depth = 0;
			let j = i + 1;
			for (; j < noSpecs.length; j += 1) {
				if (noSpecs[j] === '(') depth += 1;
				else if (noSpecs[j] === ')') {
					depth -= 1;
					if (depth === 0) break;
				}
			}
			out += '•';
			i = j + 1;
			continue;
		}
		out += noSpecs[i];
		i += 1;
	}
	return out;
}

/** Every double-quoted literal in the (comment-stripped) source. @param {string} src */
export function allStringLiterals(src) {
	return [...src.matchAll(/"((?:[^"\\\n]|\\.)*)"/g)].map((m) => m[1]);
}

/**
 * Literals in the first positional slot of a localizing API.
 * @param {string} src
 * @param {string} file
 */
export function localizingLiterals(src, file) {
	const alt = LOCALIZING_APIS.map((a) => a.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|');
	const re = new RegExp(`\\b(${alt})\\s*\\(\\s*"((?:[^"\\\\\\n]|\\\\.)*)"`, 'g');
	const stringLocalized = /\bString\s*\(\s*localized:\s*"((?:[^"\\\n]|\\.)*)"/g;
	/** @type {{ api: string, literal: string, line: number, file: string }[]} */
	const out = [];
	/** @param {number} index */
	const lineOf = (index) => src.slice(0, index).split('\n').length;
	let m;
	while ((m = re.exec(src)) !== null) {
		out.push({ api: m[1], literal: m[2], line: lineOf(m.index), file });
	}
	while ((m = stringLocalized.exec(src)) !== null) {
		out.push({ api: 'String(localized:)', literal: m[1], line: lineOf(m.index), file });
	}
	return out;
}

// --- minimal plist reader ---------------------------------------------------

/**
 * Parse a FLAT plist dict into key -> value. Handles the four value shapes
 * these two files use (`<true/>`, `<false/>`, `<string>`, `<array>` of
 * strings) and returns `undefined` for anything else, which the callers treat
 * as unusable rather than as absent. Deliberately not a real plist parser:
 * this has to run under a bare `node` on a Linux runner with nothing
 * installed.
 * @param {string} xml
 * @returns {Map<string, true | false | string | string[] | undefined>}
 */
export function parseFlatPlist(xml) {
	const body = xml.replace(/<!DOCTYPE[\s\S]*?>/, '');
	const open = body.indexOf('<dict>');
	const close = body.lastIndexOf('</dict>');
	/** @type {Map<string, true | false | string | string[] | undefined>} */
	const out = new Map();
	if (open === -1 || close === -1) return out;
	const inner = body.slice(open + '<dict>'.length, close);
	const re =
		/<key>([^<]*)<\/key>\s*(<true\s*\/>|<false\s*\/>|<string>([\s\S]*?)<\/string>|<array\s*\/>|<array>([\s\S]*?)<\/array>|<[a-z]+)/g;
	let m;
	while ((m = re.exec(inner)) !== null) {
		const key = m[1];
		if (/^<true/.test(m[2])) out.set(key, true);
		else if (/^<false/.test(m[2])) out.set(key, false);
		else if (m[3] !== undefined) out.set(key, m[3]);
		else if (/^<array\s*\/>/.test(m[2])) out.set(key, []);
		else if (m[4] !== undefined)
			out.set(
				key,
				[...m[4].matchAll(/<string>([\s\S]*?)<\/string>/g)].map((s) => s[1]),
			);
		else out.set(key, undefined);
	}
	return out;
}

/**
 * The text of a top-level `func <name>(` through its matching close brace,
 * signature line included. Returns null when the function is not in this
 * source.
 * @param {string} src
 * @param {string} name
 */
export function functionBody(src, name) {
	const start = src.search(new RegExp(`^func\\s+${name}\\s*\\(`, 'm'));
	if (start === -1) return null;
	const open = src.indexOf('{', start);
	if (open === -1) return null;
	let depth = 0;
	for (let i = open; i < src.length; i += 1) {
		if (src[i] === '{') depth += 1;
		else if (src[i] === '}') {
			depth -= 1;
			if (depth === 0) return src.slice(start, i + 1);
		}
	}
	return null;
}

// --- the checks -------------------------------------------------------------

/**
 * @param {string} watchRoot absolute path to an `apps/watch_ios` tree
 * @returns {{ errors: string[], ok: string[] }}
 */
export function check(watchRoot) {
	/** @type {string[]} */ const errors = [];
	/** @type {string[]} */ const ok = [];
	/** @param {string} rel */
	const read = (rel) => readFileSync(join(watchRoot, rel), 'utf8');

	/** @type {{ rel: string, src: string }[]} */
	const swift = [];
	for (const dir of SWIFT_DIRS) {
		for (const name of readdirSync(join(watchRoot, dir)).sort()) {
			if (!name.endsWith('.swift')) continue;
			swift.push({ rel: join(dir, name), src: stripSwiftComments(read(join(dir, name))) });
		}
	}
	if (swift.length === 0) {
		errors.push('No Swift sources found — every claim below would pass vacuously.');
		return { errors, ok };
	}
	const allSwift = swift.map((f) => f.src).join('\n');

	// (1) + (2) String Catalog coverage, both directions.
	const catalog = JSON.parse(read(join('WatchApp', 'Localizable.xcstrings')));
	const keys = Object.keys(catalog.strings ?? {});
	if (keys.length === 0) {
		errors.push('The String Catalog parsed to zero entries — claims (1) and (2) would pass vacuously.');
	}
	/** @type {Map<string, string[]>} */
	const byShape = new Map();
	for (const k of keys) {
		const n = normalizeKey(k);
		byShape.set(n, [...(byShape.get(n) ?? []), k]);
	}

	let missing = 0;
	for (const file of swift) {
		for (const use of localizingLiterals(file.src, file.rel)) {
			if (byShape.has(normalizeKey(use.literal))) continue;
			missing += 1;
			errors.push(
				`${use.file}:${use.line}: ${use.api}("${use.literal}") is a localization key with no ` +
					'String Catalog entry, so every locale renders the English literal.\n' +
					'    Fix: add the key to WatchApp/Localizable.xcstrings with all six translations, ' +
					'or — when the literal only stitches already-formatted values together and there is ' +
					'nothing to translate — pass it as Text(verbatim:) so it is not a key at all.',
			);
		}
	}
	if (missing === 0) {
		ok.push(`every localizing literal across ${swift.length} Swift file(s) has a catalog entry`);
	}

	const literalShapes = new Set(allStringLiterals(allSwift).map(normalizeKey));
	let orphans = 0;
	for (const [shape, ks] of byShape) {
		if (literalShapes.has(shape)) continue;
		orphans += 1;
		errors.push(
			`String Catalog entry ${ks.map((k) => JSON.stringify(k)).join(' / ')} appears in no Swift ` +
				'string literal. Either the surface that used it was removed — delete the entry and its ' +
				'translations — or it is reached by a spelling this guard reads as a different string.',
		);
	}
	if (orphans === 0) ok.push(`all ${keys.length} String Catalog entries are still referenced`);

	// (3) Declarations, both directions.
	const info = parseFlatPlist(read(join('WatchApp', 'Info.plist')));
	const ents = parseFlatPlist(read(join('WatchApp', 'WatchApp.entitlements')));

	const declaredModes = info.get('WKBackgroundModes');
	if (!Array.isArray(declaredModes)) {
		errors.push('Info.plist has no usable WKBackgroundModes array.');
	} else {
		for (const rule of BACKGROUND_MODES) {
			if (!rule.pattern.test(allSwift)) continue;
			if (declaredModes.includes(rule.mode)) {
				ok.push(`WKBackgroundModes contains \`${rule.mode}\` (${rule.needed_by})`);
				continue;
			}
			errors.push(
				`Info.plist's WKBackgroundModes is missing \`${rule.mode}\`, but ${rule.needed_by}.\n    ${rule.why}`,
			);
		}
		for (const mode of declaredModes) {
			if (BACKGROUND_MODES.some((r) => r.mode === mode && r.pattern.test(allSwift))) continue;
			if (UNCLAIMED_BACKGROUND_MODES.includes(mode)) continue;
			errors.push(
				`Info.plist declares the \`${mode}\` background mode and no code in apps/watch_ios claims ` +
					'it. App Review rejects a binary declaring a background capability it does not ' +
					'exercise. Either delete it, or add a rule to BACKGROUND_MODES naming the call that ' +
					'needs it.',
			);
		}
	}

	for (const rule of PURPOSE_STRINGS) {
		if (!rule.pattern.test(allSwift)) continue;
		const value = info.get(rule.key);
		if (typeof value === 'string' && value.trim() !== '') {
			ok.push(`Info.plist carries \`${rule.key}\` (${rule.needed_by})`);
			continue;
		}
		errors.push(
			`Info.plist is missing a usable \`${rule.key}\`, but ${rule.needed_by}. watchOS denies the ` +
				'permission outright when the purpose string is absent, and the denial is silent — the ' +
				'feature just returns nothing.',
		);
	}
	for (const key of info.keys()) {
		if (!key.endsWith('UsageDescription')) continue;
		if (PURPOSE_STRINGS.some((r) => r.key === key && r.pattern.test(allSwift))) continue;
		errors.push(
			`Info.plist declares \`${key}\` and no code in apps/watch_ios claims it. A purpose string for ` +
				'a permission the app never asks for is an App Store privacy over-claim. Either delete ' +
				'it, or add a rule to PURPOSE_STRINGS naming the call that needs it.',
		);
	}

	for (const rule of ENTITLEMENTS) {
		if (!rule.pattern.test(allSwift)) continue;
		if (!ents.has(rule.key)) {
			errors.push(
				`WatchApp.entitlements is missing \`${rule.key}\`, but ${rule.needed_by}.\n    ` +
					`${rule.why}\n    Fix: add <key>${rule.key}</key> ${rule.shape}.`,
			);
			continue;
		}
		if (!rule.accepts(ents.get(rule.key))) {
			errors.push(
				`WatchApp.entitlements declares \`${rule.key}\` with an unusable value; expected ${rule.shape}.`,
			);
			continue;
		}
		ok.push(`entitlement \`${rule.key}\` (${rule.needed_by})`);
	}
	for (const key of ents.keys()) {
		if (ENTITLEMENTS.some((r) => r.key === key && r.pattern.test(allSwift))) continue;
		if (UNCLAIMED_ENTITLEMENTS.includes(key)) continue;
		errors.push(
			`WatchApp.entitlements declares \`${key}\` and no code in apps/watch_ios claims it. An ` +
				'entitlement is a capability the binary asks the store to grant; one nothing exercises is ' +
				'a rejection and, for a health capability, an over-claim about what the watch collects. ' +
				'Either delete it, or add a rule to ENTITLEMENTS naming the call that needs it.',
		);
	}

	// (4) The duplicated complication formatters.
	const originSrc = read(FORMATTER_ORIGIN);
	const copySrc = read(FORMATTER_COPY);
	let diverged = 0;
	for (const name of DUPLICATED_FORMATTERS) {
		const a = functionBody(originSrc, name);
		const b = functionBody(copySrc, name);
		if (a === null || b === null) {
			diverged += 1;
			errors.push(
				`\`${name}\` is missing from ${a === null ? FORMATTER_ORIGIN : FORMATTER_COPY}. Both ` +
					'copies must exist: the complication builds in a Widget Extension target that cannot ' +
					`link ${FORMATTER_ORIGIN}, and ComplicationFormatterTests links the other one.`,
			);
			continue;
		}
		if (a === b) continue;
		diverged += 1;
		errors.push(
			`\`${name}\` differs between ${FORMATTER_ORIGIN} and ${FORMATTER_COPY}. The two are a ` +
				'hand-maintained duplicate — the widget runs the second copy and the Swift suite tests ' +
				'the first, so a divergence means the watch face and the run screen round the same run ' +
				'differently and every test still passes.',
		);
	}
	if (diverged === 0) {
		ok.push(`${DUPLICATED_FORMATTERS.length} duplicated complication formatters are byte-identical`);
	}

	// (5) The App Group identifier, stated twice.
	const declared = /appGroup\s*=\s*"([^"]+)"/.exec(read(BRIDGE));
	if (declared === null) {
		errors.push(`${BRIDGE} declares no \`appGroup\` identifier.`);
	} else if (read(COMPLICATION_README).includes(declared[1])) {
		ok.push(`App Group \`${declared[1]}\` matches the Xcode wiring in ${COMPLICATION_README}`);
	} else {
		errors.push(
			`ActiveRunBridge.appGroup is \`${declared[1]}\`, which ${COMPLICATION_README} never names. ` +
				'That README is the only instruction an operator has for typing the identifier into two ' +
				'Xcode capability panes, and a shared container bound under a different name never ' +
				'yields a store — silently.',
		);
	}

	return { errors, ok };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	const root = process.argv[2] ?? join(REPO_ROOT, 'apps', 'watch_ios');
	const { errors, ok } = check(root);
	for (const line of ok) console.log(`  ok: ${line}`);
	if (errors.length > 0) {
		console.error(`\nFAIL: ${errors.length} problem(s) in apps/watch_ios:`);
		for (const e of errors) console.error(`  - ${e}`);
		process.exit(1);
	}
	console.log(`\nOK: ${ok.length} claim(s) hold across apps/watch_ios (read, not compiled).`);
}
