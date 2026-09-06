// Source-level claims about `apps/watch_ios` that no compiler in this repo's
// Linux CI can make.
//
// The watchOS tier is the least verifiable thing in the monorepo. Exactly one
// job compiles it — `test-watch-ios`, on a macOS runner — and every other
// claim about it rests on reading. `apps/watch_ios/scripts/check_xcstrings_parity.sh`
// already holds the String Catalog against its two locale-declaration sites
// (decisions § 761 / § 850). This guard holds the seven *other* things about
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
//   (6) Every key the watch packs into the `WCSession.transferFile` metadata
//       envelope is lifted back out by the phone's `WatchIngestBridge.swift`,
//       and vice versa. Both ends are hand-written key lists in two different
//       apps, and the drift has already happened once: the Apr 2026
//       cross-client audit found Apple-Watch runs landing on the phone with no
//       `activity_type`. Nothing fails when a key is dropped — the run syncs,
//       one column short.
//
//   (7) The same, for the envelope going the OTHER way on the same session:
//       the route the phone arms on the wrist. Three hand-written key lists in
//       three languages and three apps — `apple_watch_route_bridge.dart` names
//       them as method-channel arguments, `WatchIngestBridge.routeUserInfo`
//       lifts those out and repacks them for `transferUserInfo`, and
//       `ArmedRoute.decode` reads them back on the watch. Every rejection in
//       that chain drops the WHOLE push (a partly-decoded polyline is worse
//       than none), so a key renamed on one rail is a route the runner arms on
//       the phone that silently never reaches the wrist — with a success
//       reported at the point they armed it.
//
//   (8) No destructive control in `ContentView.swift` destroys a run on one
//       tap. Both "Discard" buttons end a run that exists nowhere else — the
//       crash-recovery checkpoint, and a finished run WCSession has not been
//       handed — and neither the compiler nor any Swift test can see that one
//       of them lost its confirmation, because a `Button` that calls its
//       closure directly is the same program as one that arms a dialog first.
//       Each destructive `Button` must therefore either ARM a confirmation
//       (`<flag> = true`, bound to some `confirmationDialog(isPresented:)`) or
//       BE the confirming action inside one.
//
//   (9) The DEBUG direct-to-Supabase path sends every field the WCSession
//       envelope sends. Two transports, one run, two hand-written field lists
//       — the § 1254 shape — and the DEBUG one is the path a watch-sim-alone
//       developer watches a row land on, so a field missing there sends them
//       to debug the wrong tier. It stayed missing because `RunPayload.metadata`
//       was typed `[String: String]`, which made the two numeric keys
//       unsendable rather than merely unsent; nothing failed, the row just
//       arrived short.
//
//  (10) The watch target's Info.plist is the only place its Info.plist keys
//       live. `GENERATE_INFOPLIST_FILE = NO` means Xcode uses the committed
//       file AS IS rather than merging the `INFOPLIST_KEY_*` build settings
//       into it, so every such setting on that target is INERT while reading
//       exactly like a declaration — which is how this app shipped with
//       `INFOPLIST_KEY_CFBundleDisplayName = "Threkir"` set on both
//       configurations and no `CFBundleDisplayName` in the plist at all,
//       leaving the watch app named by its target (`WatchApp`) on the wrist.
//       The same claim carries Apple's documented mutual exclusivity:
//       `WKWatchOnly` says the app has no iOS companion and cannot coexist
//       with `WKCompanionAppBundleIdentifier`, so a session resolving the
//       companion question must remove one while adding the other.
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
export const SYNC_SITE = join('WatchApp', 'ContentView.swift');

/**
 * The phone half of the run hand-off. Outside `apps/watch_ios` on purpose:
 * the envelope has two ends and a guard that reads only the watch's end
 * cannot see the drift.
 */
export const INGEST = join('apps', 'mobile_ios', 'ios', 'Runner', 'WatchIngestBridge.swift');

/// The watch end of the route-push envelope.
export const ARMED_ROUTE = join('WatchApp', 'ArmedRoute.swift');

/**
 * The Dart end of it — the third rail, and the one that starts the chain. Under
 * `apps/mobile_android/lib` because that tree is the byte-identical twin's
 * canonical copy (decisions § 39); the iOS twin is a mirror of it, so reading
 * one reads both.
 */
export const ROUTE_BRIDGE = join(
	'apps',
	'mobile_android',
	'lib',
	'apple_watch_route_bridge.dart',
);

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
 * The keys the watch packs into the `WCSession.transferFile(_:metadata:)`
 * envelope: the literal keys of the `metadata` dictionary, plus every key
 * assigned into it afterwards (`avg_bpm` is conditional on the run having a
 * heart-rate average).
 *
 * Returns null when the dictionary literal is not there to read. That is the
 * honest answer rather than "no keys": the whole claim rests on finding it,
 * and a shape change that silently yielded an empty set would turn the check
 * into a report that the phone reads eight keys nobody sends.
 * @param {string} src comment-stripped `ContentView.swift`
 * @returns {Set<string> | null}
 */
export function watchEnvelopeKeys(src) {
	const decl = /var\s+metadata\s*:\s*\[String\s*:\s*Any\]\s*=\s*\[/.exec(src);
	if (decl === null) return null;
	/** @type {Set<string>} */
	const keys = new Set();
	{
		const open = decl.index + decl[0].length - 1;
		let depth = 0;
		let end = open;
		for (let i = open; i < src.length; i += 1) {
			if (src[i] === '[') depth += 1;
			else if (src[i] === ']') {
				depth -= 1;
				if (depth === 0) {
					end = i;
					break;
				}
			}
		}
		for (const m of src.slice(open, end).matchAll(/"([^"\\\n]+)"\s*:/g)) keys.add(m[1]);
	}
	for (const m of src.matchAll(/\bmetadata\s*\[\s*"([^"\\\n]+)"\s*\]\s*=/g)) keys.add(m[1]);
	return keys;
}

/**
 * The keys the phone lifts back out of that envelope — the required-field
 * loop's array literal plus every individual `metadata["…"]` read.
 * @param {string} src comment-stripped `WatchIngestBridge.swift`
 */
export function phoneEnvelopeKeys(src) {
	/** @type {Set<string>} */
	const keys = new Set();
	for (const loop of src.matchAll(/for\s+\w+\s+in\s+\[([^\]]*)\]/g)) {
		if (!/metadata\s*\[/.test(src.slice(loop.index, loop.index + 400))) continue;
		for (const m of loop[1].matchAll(/"([^"\\\n]+)"/g)) keys.add(m[1]);
	}
	for (const m of src.matchAll(/\bmetadata\s*\[\s*"([^"\\\n]+)"\s*\]/g)) keys.add(m[1]);
	return keys;
}

/** The heart-rate session owner, claim (11)'s rail. */
export const HEALTHKIT = 'WatchApp/HealthKitManager.swift';

/**
 * Claim (11)'s delegate gates: `[signature marker, identity check, the first
 * thing the method writes]`. The third element is what makes the claim a
 * question about ORDER rather than about the presence of a line — a gate below
 * the mutation it is supposed to gate is no gate.
 * @type {[string, string, string][]}
 */
export const DELEGATE_IDENTITY_GATES = [
	['didFailWithError', 'workoutSession === session', 'handleSessionFailure('],
	['didCollectDataOf', 'workoutBuilder === builder', 'coverage.noteSample('],
];

/** The watch target's Xcode project, claim (10)'s second rail. */
export const PBXPROJ = join('WatchApp.xcodeproj', 'project.pbxproj');

/** The watch app's committed Info.plist, read by claims (3) and (10). */
export const WATCH_PLIST = join('WatchApp', 'Info.plist');

/**
 * Every `buildSettings { … }` block in a pbxproj, as raw text.
 *
 * Returns an empty array when none parse, which claim (10) treats as an error
 * rather than as a clean tree.
 * @param {string} src
 * @returns {string[]}
 */
export function buildSettingsBlocks(src) {
	/** @type {string[]} */
	const out = [];
	const re = /buildSettings\s*=\s*\{/g;
	let m;
	while ((m = re.exec(src)) !== null) {
		const open = m.index + m[0].length - 1;
		let depth = 0;
		for (let i = open; i < src.length; i += 1) {
			if (src[i] === '{') depth += 1;
			else if (src[i] === '}') {
				depth -= 1;
				if (depth === 0) {
					out.push(src.slice(open, i + 1));
					break;
				}
			}
		}
	}
	return out;
}

/** The DEBUG-only direct-to-Supabase writer, claim (9)'s other rail. */
export const DIRECT_SITE = join('WatchApp', 'SupabaseService.swift');

/**
 * Fields the DEBUG direct path sends that the WCSession envelope does not, and
 * why each is one-sided. Both are supplied BY THE PHONE on the envelope path,
 * so the watch has no business putting them in the hand-off: `user_id` comes
 * from the phone's authenticated session and `track_url` from the phone's own
 * Storage upload. An entry matching no field FAILS, for the reason
 * `UNGUARDED_DESTRUCTIVE` does: the next field to take that name inherits the
 * exemption.
 * @type {Record<string, string>}
 */
export const DIRECT_ONLY_FIELDS = {
	user_id: "the phone supplies it from its own session on the WCSession path",
	track_url: 'the phone uploads the track and owns the object path',
};

/**
 * The stored-property names of a Swift `struct <name>: …` declaration, in
 * order. Used to read the DEBUG payload's two field lists without compiling
 * Swift.
 *
 * Returns null when the declaration is not there to read — the honest answer
 * rather than "no fields", because an empty set would let claim (9) report
 * that a payload nobody sends agrees with the envelope.
 * @param {string} src comment-stripped Swift
 * @param {string} name
 * @returns {string[] | null}
 */
export function swiftStructFields(src, name) {
	const at = src.search(new RegExp(`\\bstruct\\s+${name}\\b`));
	if (at === -1) return null;
	const open = src.indexOf('{', at);
	if (open === -1) return null;
	let depth = 0;
	let end = -1;
	for (let i = open; i < src.length; i += 1) {
		if (src[i] === '{') depth += 1;
		else if (src[i] === '}') {
			depth -= 1;
			if (depth === 0) {
				end = i;
				break;
			}
		}
	}
	if (end === -1) return null;
	/** @type {string[]} */
	const fields = [];
	// Walk the body line by line tracking brace depth, and take `let <name>:` /
	// `var <name>:` only at the struct's OWN level. Depth is what excludes a
	// local inside a method; the "no brace on the line" test is what excludes a
	// computed property, which is a getter rather than a field on the wire.
	// Both exclusions can only ever UNDER-count, and an under-count reports a
	// field as missing rather than passing a missing one.
	let inner = 0;
	for (const line of src.slice(open + 1, end).split('\n')) {
		const decl = /^\s*(?:let|var)\s+([A-Za-z_]\w*)\s*:/.exec(line);
		if (decl !== null && inner === 0 && !line.includes('{')) fields.push(decl[1]);
		for (const ch of line) {
			if (ch === '{') inner += 1;
			else if (ch === '}') inner -= 1;
		}
	}
	return fields.length === 0 ? null : fields;
}

/**
 * The brace-matched body of `func <name>(`, wherever it sits — a method inside
 * a type, with any access modifiers in front. `functionBody` below anchors at
 * column zero, which the three route-envelope functions are not.
 * @param {string} src @param {string} name @returns {string | null}
 */
export function methodBody(src, name) {
	const at = src.search(new RegExp(`\\bfunc\\s+${name}\\s*\\(`));
	if (at === -1) return null;
	const open = src.indexOf('{', at);
	if (open === -1) return null;
	let depth = 0;
	for (let i = open; i < src.length; i += 1) {
		if (src[i] === '{') depth += 1;
		else if (src[i] === '}') {
			depth -= 1;
			if (depth === 0) return src.slice(open, i + 1);
		}
	}
	return null;
}

/**
 * The body of the method whose signature contains `marker`, `{` through the
 * matching `}`. Selected by an argument label rather than by name because
 * `HealthKitManager` has two delegate methods called `workoutSession`.
 * @param {string} src @param {string} marker
 */
export function bodyOfSignatureContaining(src, marker) {
	const at = src.indexOf(marker);
	if (at === -1) return null;
	const open = src.indexOf('{', at);
	if (open === -1) return null;
	const close = matchDelimiter(src, open, '{', '}');
	return close === -1 ? null : src.slice(open, close + 1);
}

/**
 * Brace depth at the first occurrence of `needle` inside `body`, counting the
 * body's own opening brace as 1. Anything nested in a closure is deeper, which
 * is the whole question claim (11) asks of `stopWorkout`. -1 when absent.
 * @param {string} body @param {string} needle
 */
export function depthOf(body, needle) {
	const at = body.indexOf(needle);
	if (at === -1) return -1;
	let depth = 0;
	for (let i = 0; i < at; i += 1) {
		if (body[i] === '"') {
			i += 1;
			while (i < body.length && body[i] !== '"') i += body[i] === '\\' ? 2 : 1;
			continue;
		}
		if (body[i] === '{') depth += 1;
		else if (body[i] === '}') depth -= 1;
	}
	return depth;
}

/**
 * Every `<receiver>["…"]` key in a chunk of Swift, plus the keys of any
 * dictionary literal in it. Both halves matter on the phone rail: it READS the
 * method-channel arguments and REPACKS them, and a key read but not repacked is
 * a field dropped between two lines of one function.
 * @param {string} body @param {string} receiver
 * @returns {Set<string> | null} null when the receiver is not subscripted at
 *   all, which is a shape change rather than an empty envelope
 */
export function swiftPayloadKeys(body, receiver) {
	/** @type {Set<string>} */
	const keys = new Set();
	const sub = new RegExp(`\\b${receiver}\\s*\\[\\s*"([^"\\\\\\n]+)"\\s*\\]`, 'g');
	for (const m of body.matchAll(sub)) keys.add(m[1]);
	if (keys.size === 0) return null;
	for (const m of body.matchAll(/"([^"\\\n]+)"\s*:/g)) keys.add(m[1]);
	return keys;
}

/**
 * The keys of the map literal handed to `invokeMethod…('<method>', { … })` in
 * Dart. Returns null when the call is not there to read, for the same reason
 * `watchEnvelopeKeys` does: an empty set would report that the two Swift ends
 * agree on five keys nobody sends.
 * @param {string} src comment-stripped Dart @param {string} method
 * @returns {Set<string> | null}
 */
export function dartInvokeKeys(src, method) {
	const call = new RegExp(`invokeMethod\\s*(?:<[^>]*>)?\\s*\\(\\s*'${method}'`);
	const at = src.search(call);
	if (at === -1) return null;
	const open = src.indexOf('{', at);
	if (open === -1) return null;
	let depth = 0;
	let end = -1;
	for (let i = open; i < src.length; i += 1) {
		if (src[i] === '{' || src[i] === '[') depth += 1;
		else if (src[i] === '}' || src[i] === ']') {
			depth -= 1;
			if (depth === 0) {
				end = i;
				break;
			}
		}
	}
	if (end === -1) return null;
	/** @type {Set<string>} */
	const keys = new Set();
	for (const m of src.slice(open, end).matchAll(/'([^'\\\n]+)'\s*:/g)) keys.add(m[1]);
	return keys.size === 0 ? null : keys;
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

/**
 * Index of the delimiter closing the one at `open`, or -1. Skips string
 * literals, so a brace or paren inside `"…"` cannot unbalance the walk.
 * @param {string} src @param {number} open @param {string} o @param {string} c
 */
export function matchDelimiter(src, open, o, c) {
	let depth = 0;
	for (let i = open; i < src.length; i += 1) {
		if (src[i] === '"') {
			i += 1;
			while (i < src.length && src[i] !== '"') i += src[i] === '\\' ? 2 : 1;
			continue;
		}
		if (src[i] === o) depth += 1;
		else if (src[i] === c) {
			depth -= 1;
			if (depth === 0) return i;
		}
	}
	return -1;
}

/**
 * The `[start, end)` span of every `.confirmationDialog(…)` call, argument
 * list plus its trailing `actions:` / `message:` closures — so "is this Button
 * the dialog's own action" is a position, not a guess.
 * @param {string} src comment-stripped Swift
 * @returns {[number, number][]}
 */
export function confirmationDialogSpans(src) {
	/** @type {[number, number][]} */
	const spans = [];
	const re = /\.confirmationDialog\s*\(/g;
	let m;
	while ((m = re.exec(src)) !== null) {
		const open = m.index + m[0].length - 1;
		const close = matchDelimiter(src, open, '(', ')');
		if (close === -1) continue;
		let i = close + 1;
		for (;;) {
			const t = /^\s*(?:\w+\s*:\s*)?\{/.exec(src.slice(i));
			if (t === null) break;
			const braceOpen = i + t[0].length - 1;
			const braceEnd = matchDelimiter(src, braceOpen, '{', '}');
			if (braceEnd === -1) break;
			i = braceEnd + 1;
		}
		spans.push([m.index, i]);
	}
	return spans;
}

/**
 * Every `Button(…, role: .destructive) { … }` with its label and the body of
 * its action closure (null when it has none to read).
 * @param {string} src comment-stripped Swift
 * @returns {{ index: number, label: string, body: string | null }[]}
 */
export function destructiveButtons(src) {
	/** @type {{ index: number, label: string, body: string | null }[]} */
	const out = [];
	const re = /\bButton\s*\(/g;
	let m;
	while ((m = re.exec(src)) !== null) {
		const open = m.index + m[0].length - 1;
		const close = matchDelimiter(src, open, '(', ')');
		if (close === -1) continue;
		const args = src.slice(open, close + 1);
		if (!/role\s*:\s*\.destructive/.test(args)) continue;
		const label = /"([^"\\\n]*)"/.exec(args)?.[1] ?? '(unlabelled)';
		const t = /^\s*\{/.exec(src.slice(close + 1));
		if (t === null) {
			out.push({ index: m.index, label, body: null });
			continue;
		}
		const braceOpen = close + 1 + t[0].length - 1;
		const braceEnd = matchDelimiter(src, braceOpen, '{', '}');
		out.push({
			index: m.index,
			label,
			body: braceEnd === -1 ? null : src.slice(braceOpen + 1, braceEnd),
		});
	}
	return out;
}

/**
 * Destructive-styled buttons that destroy nothing, by label, each with the
 * reason. `role: .destructive` is a COLOUR as well as a claim, and a control
 * that ends a run into a screen still holding it is not the thing claim (8) is
 * about. An entry matching no button in the file is an error, so the register
 * cannot outlive what it exempts.
 * @type {Record<string, string>}
 */
export const UNGUARDED_DESTRUCTIVE = {
	Stop: 'ends the recording into PostRunView, which still holds the finished run, its ' +
		'on-disk track and a Sync Run button — nothing is deleted, and a runner who stops ' +
		'by accident loses the recording state, not the run',
};

// --- the checks -------------------------------------------------------------

/**
 * @param {string} watchRoot absolute path to an `apps/watch_ios` tree
 * @param {string | null} [ingestPath] absolute path to the phone's
 *   `WatchIngestBridge.swift`; null skips claims (6) and (7), which are only
 *   for a caller that has no phone half staged.
 * @param {string | null} [routeBridgePath] absolute path to the phone's
 *   `apple_watch_route_bridge.dart`; null skips claim (7) alone.
 * @returns {{ errors: string[], ok: string[] }}
 */
export function check(watchRoot, ingestPath = null, routeBridgePath = null) {
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

	// (6) The run hand-off envelope, read from both ends.
	if (ingestPath !== null) {
		const sent = watchEnvelopeKeys(stripSwiftComments(read(SYNC_SITE)));
		const lifted = phoneEnvelopeKeys(stripSwiftComments(readFileSync(ingestPath, 'utf8')));
		if (sent === null || sent.size === 0 || lifted.size === 0) {
			errors.push(
				'Parsed no metadata keys out of one end of the run hand-off envelope — claim (6) would ' +
					'pass vacuously. Either the dictionary literal in ContentView.syncRun or the lift in ' +
					'WatchIngestBridge.swift changed shape.',
			);
		} else {
			const dropped = [...sent].filter((k) => !lifted.has(k)).sort();
			const invented = [...lifted].filter((k) => !sent.has(k)).sort();
			for (const key of dropped) {
				errors.push(
					`The watch puts \`${key}\` in the WCSession metadata envelope and ${INGEST} never ` +
						'lifts it out, so it is dropped on the way to the row. Silently: the run still ' +
						'syncs, just without that field — which is exactly how Apple-Watch runs reached ' +
						'the phone with no `activity_type` (the Apr 2026 cross-client audit).',
				);
			}
			for (const key of invented) {
				errors.push(
					`${INGEST} reads \`${key}\` out of the WCSession metadata envelope and the watch ` +
						'never puts it there, so the phone is waiting for a field that cannot arrive.',
				);
			}
			if (dropped.length === 0 && invented.length === 0) {
				ok.push(`all ${sent.size} run hand-off metadata keys are lifted out on the phone side`);
			}
		}
	}

	// (7) The route-push envelope, read from all three of its ends.
	if (ingestPath !== null && routeBridgePath !== null) {
		const phone = swiftPayloadKeys(
			methodBody(stripSwiftComments(readFileSync(ingestPath, 'utf8')), 'routeUserInfo') ?? '',
			'args',
		);
		const watch = swiftPayloadKeys(
			methodBody(stripSwiftComments(read(ARMED_ROUTE)), 'decode') ?? '',
			'payload',
		);
		const dart = dartInvokeKeys(readFileSync(routeBridgePath, 'utf8'), 'push');
		/** @type {{ label: string, keys: Set<string> | null }[]} */
		const rails = [
			{ label: `${ROUTE_BRIDGE} (invokeMethod 'push')`, keys: dart },
			{ label: `${INGEST} (routeUserInfo)`, keys: phone },
			{ label: `${ARMED_ROUTE} (ArmedRoute.decode)`, keys: watch },
		];
		const unread = rails.filter((r) => r.keys === null);
		if (unread.length > 0) {
			errors.push(
				`Parsed no route-push keys out of ${unread.map((r) => r.label).join(' and ')} — ` +
					'claim (7) would pass vacuously, or report that the other rails agree on keys ' +
					'nobody sends. One of the three call sites changed shape.',
			);
		} else {
			/** @type {string[]} */
			const mismatches = [];
			for (const rail of rails) {
				for (const other of rails) {
					if (rail === other) continue;
					for (const key of /** @type {Set<string>} */ (rail.keys)) {
						if (!(/** @type {Set<string>} */ (other.keys)).has(key)) {
							mismatches.push(
								`\`${key}\` is on ${rail.label} and not on ${other.label}. Every rejection ` +
									'in the route chain drops the WHOLE push, so this is a route the runner ' +
									'arms on the phone — and is told was armed — that never reaches the wrist.',
							);
						}
					}
				}
			}
			for (const m of [...new Set(mismatches)].sort()) errors.push(m);
			if (mismatches.length === 0) {
				ok.push(
					`all ${(/** @type {Set<string>} */ (dart)).size} route-push keys agree across the ` +
						'Dart channel, the phone repack and the watch decode',
				);
			}
		}
	}

	// (8) No destructive control ends a run on one tap.
	{
		const src = stripSwiftComments(read(SYNC_SITE));
		const spans = confirmationDialogSpans(src);
		const buttons = destructiveButtons(src);
		if (buttons.length === 0) {
			errors.push(
				`Parsed no \`role: .destructive\` Button out of ${SYNC_SITE} — claim (8) would pass ` +
					'vacuously. Both Discard buttons carry that role; if the shape changed, this ' +
					'reads nothing rather than reading a clean tree.',
			);
		} else if (spans.length === 0) {
			errors.push(
				`${SYNC_SITE} has ${buttons.length} destructive Button(s) and no confirmationDialog. ` +
					'Each of them ends a run that exists nowhere else — the crash-recovery checkpoint, ' +
					'and a finished run WCSession has not been handed — and a single tap is the whole ' +
					'interaction.',
			);
		} else {
			/** @type {string[]} */
			const armedFlags = [];
			for (const b of buttons) {
				if (spans.some(([a, z]) => b.index > a && b.index < z)) continue;
				if (b.label in UNGUARDED_DESTRUCTIVE) continue;
				const armed = /^\s*(\w+)\s*=\s*true\s*$/.exec(b.body ?? '');
				if (armed === null) {
					errors.push(
						`\`Button("${b.label}", role: .destructive)\` in ${SYNC_SITE} acts on the tap ` +
							'instead of arming a confirmation. A destructive control on this watch must ' +
							'either set a `confirmationDialog` flag or BE that dialog\'s action — the run ' +
							'it ends is on no other device, and there is no undo. Body: ' +
							`\`${(b.body ?? '').trim().replace(/\s+/g, ' ').slice(0, 80)}\``,
					);
					continue;
				}
				armedFlags.push(armed[1]);
			}
			for (const flag of armedFlags) {
				if (new RegExp(`isPresented\\s*:\\s*\\$${flag}\\b`).test(src)) continue;
				errors.push(
					`\`${flag}\` is set by a destructive Button in ${SYNC_SITE} and no ` +
						'confirmationDialog is presented on it, so the tap arms a dialog that never ' +
						'appears and the control is inert.',
				);
			}
			for (const label of Object.keys(UNGUARDED_DESTRUCTIVE)) {
				if (buttons.some((b) => b.label === label)) continue;
				errors.push(
					`UNGUARDED_DESTRUCTIVE exempts a destructive Button labelled \`${label}\`, and ` +
						`${SYNC_SITE} has none. A stale exemption is a hole nobody can see: the next ` +
						'button to take that label inherits it. Delete the entry.',
				);
			}
			if (armedFlags.length > 0 && errors.length === 0) {
				const exempt = buttons.filter((b) => b.label in UNGUARDED_DESTRUCTIVE).length;
				ok.push(
					`every run-ending control in ${SYNC_SITE} is confirmed: ${armedFlags.length} ` +
						`arm a confirmationDialog, ${buttons.length - armedFlags.length - exempt} are ` +
						`a dialog's own action, ${exempt} exempt`,
				);
			}
		}
	}

	// (9) The DEBUG direct path sends what the WCSession envelope sends.
	{
		const direct = stripSwiftComments(read(DIRECT_SITE));
		const sent = watchEnvelopeKeys(stripSwiftComments(read(SYNC_SITE)));
		const columns = swiftStructFields(direct, 'RunPayload');
		const meta = swiftStructFields(direct, 'RunMetadata');
		if (
			sent === null ||
			sent.size === 0 ||
			columns === null ||
			meta === null ||
			!columns.includes('metadata')
		) {
			errors.push(
				`Parsed no fields out of one end of the two run-write paths — claim (9) would pass ` +
					`vacuously. Either the metadata literal in ${SYNC_SITE} or one of RunPayload / ` +
					`RunMetadata in ${DIRECT_SITE} changed shape; RunPayload must still carry the ` +
					'`metadata` bag, or the fields read out of RunMetadata reach no row.',
			);
		} else {
			// `metadata` is the BAG, not a datum: its contents are `meta`, which
			// is already in the union. Counting the container as a field would
			// demand the envelope carry a key called `metadata`.
			const carried = new Set([...columns.filter((f) => f !== 'metadata'), ...meta]);
			for (const key of [...sent].filter((k) => !carried.has(k)).sort()) {
				errors.push(
					`The watch sends \`${key}\` over WCSession and ${DIRECT_SITE} sends it on neither ` +
						'the row nor the metadata bag, so the DEBUG direct upload lands a row one field ' +
						'short of the one the same run produces through the phone. That is the path a ' +
						'watch-sim-alone developer reads the row on, which is exactly who a silent ' +
						'omission sends to debug the wrong tier.',
				);
			}
			for (const field of [...carried].filter((f) => !sent.has(f)).sort()) {
				if (field in DIRECT_ONLY_FIELDS) continue;
				errors.push(
					`${DIRECT_SITE} sends \`${field}\` and the WCSession envelope does not. Either the ` +
						'envelope is missing a field the row wants, or this one is phone-supplied and ' +
						'belongs in DIRECT_ONLY_FIELDS with the reason written down.',
				);
			}
			for (const field of Object.keys(DIRECT_ONLY_FIELDS)) {
				if (carried.has(field)) continue;
				errors.push(
					`DIRECT_ONLY_FIELDS exempts \`${field}\`, which ${DIRECT_SITE} no longer sends. A ` +
						'stale exemption is a hole nobody can see: the next field to take that name ' +
						'inherits it. Delete the entry.',
				);
			}
			if (errors.length === 0) {
				ok.push(
					`all ${sent.size} WCSession run fields are also written by the DEBUG direct path ` +
						`(${Object.keys(DIRECT_ONLY_FIELDS).length} phone-supplied fields exempt)`,
				);
			}
		}
	}

	// (10) Info.plist keys live in the Info.plist, and the companion
	// declaration is internally consistent.
	{
		const blocks = buildSettingsBlocks(read(PBXPROJ));
		if (blocks.length === 0) {
			errors.push(
				`Parsed no buildSettings blocks out of ${PBXPROJ} — claim (10) would pass vacuously.`,
			);
		} else {
			let manual = 0;
			for (const b of blocks) {
				// The condition is read off the setting that CAUSES the inertness,
				// so a target that switches to a generated plist correctly stops
				// being subject to this and its INFOPLIST_KEY_* become live.
				if (!/\bGENERATE_INFOPLIST_FILE\s*=\s*NO\s*;/.test(b)) continue;
				manual += 1;
				for (const m of b.matchAll(/\b(INFOPLIST_KEY_\w+)\s*=/g)) {
					errors.push(
						`${PBXPROJ} sets \`${m[1]}\` on a target whose GENERATE_INFOPLIST_FILE is NO. ` +
							'Xcode merges INFOPLIST_KEY_* settings only into a plist it GENERATES, so on ' +
							'this target the setting is inert while reading exactly like a declaration — ' +
							'which is how the watch app came to ship with a display name set here, none ' +
							`in ${WATCH_PLIST}, and the target's own name (\`WatchApp\`) on the wrist. ` +
							`Put the key in ${WATCH_PLIST} and delete the setting.`,
					);
				}
			}
			if (manual === 0) {
				errors.push(
					`No target in ${PBXPROJ} sets GENERATE_INFOPLIST_FILE = NO — claim (10)'s first ` +
						'half read nothing. Either the watch target now generates its plist (in which ' +
						'case this check no longer applies and should be removed) or the setting moved.',
				);
			}

			const plist = parseFlatPlist(read(WATCH_PLIST));
			if (plist.size === 0) {
				errors.push(`${WATCH_PLIST} parsed to zero keys — claim (10) would pass vacuously.`);
			} else {
				if (!plist.has('CFBundleDisplayName')) {
					errors.push(
						`${WATCH_PLIST} declares no \`CFBundleDisplayName\`, so the watch app is named ` +
							"by `CFBundleName` — which is `$(PRODUCT_NAME)`, the Xcode TARGET name. A " +
							'build setting cannot supply it here: see the first half of this claim.',
					);
				}
				if (plist.get('WKWatchOnly') === true && plist.has('WKCompanionAppBundleIdentifier')) {
					errors.push(
						`${WATCH_PLIST} declares both \`WKWatchOnly\` and ` +
							'`WKCompanionAppBundleIdentifier`. Apple documents these as mutually ' +
							'exclusive: the first says the app has no iOS companion, the second names ' +
							'one. Whichever is right, the other has to go — and this app syncs over ' +
							'`WCSession` to a counterpart, which is a companion relationship ' +
							'(decisions § 1256).',
					);
				}
				if (errors.length === 0) {
					ok.push(
						`${WATCH_PLIST} owns its own keys (no inert INFOPLIST_KEY_* on the manual-plist ` +
							'target) and its companion declaration is self-consistent',
					);
				}
			}
		}
	}

	// (11) The HealthKit session a delegate acts on is the one the run is
	//      holding, and the run releases it when it ENDS rather than when its
	//      save completes.
	//
	//      Both halves are invisible to every other rail. `startWorkout()`
	//      refuses to open a session while one is held, so a release chained
	//      behind `finishWorkout` — a save that can take seconds and need
	//      never call back — leaves the NEXT run recording with no heart rate,
	//      no coverage figure and no notice saying why. And a delegate that
	//      does not check identity lets the finishing run's session tear down
	//      the starting run's heart rate, or its builder stamp a sample age
	//      onto a run whose sensor it never touched — which coverage then
	//      reads as a delivering sensor (decisions § 1300). The macOS job
	//      compiles all of that happily; only a second run in one launch
	//      shows it, and nothing here has one.
	const hk = stripSwiftComments(read(HEALTHKIT));
	const stopBody = bodyOfSignatureContaining(hk, 'func stopWorkout(');
	if (stopBody === null) {
		errors.push(`${HEALTHKIT} has no \`stopWorkout\` — claim (11) would pass vacuously.`);
	} else {
		const chained = ['self.session = nil', 'self.builder = nil'].filter(
			(a) => depthOf(stopBody, a) !== 1,
		);
		if (chained.length > 0) {
			errors.push(
				`${HEALTHKIT}: \`stopWorkout\` does not release ${chained.join(' and ')} in its own ` +
					'body — the assignment is missing, or nested inside a completion handler. ' +
					'`startWorkout()` refuses to open a session while one is held, so a release that ' +
					'waits on `finishWorkout` costs the next run of the launch its heart rate ' +
					'entirely, silently, with no `heartRateUnavailable` notice.',
			);
		} else {
			ok.push('`stopWorkout` releases the session in its own body, not behind the save');
		}
	}

	for (const [marker, identity, mutates] of DELEGATE_IDENTITY_GATES) {
		const body = bodyOfSignatureContaining(hk, marker);
		if (body === null) {
			errors.push(`${HEALTHKIT} has no \`${marker}\` delegate — claim (11) would pass vacuously.`);
			continue;
		}
		const gate = body.indexOf(identity);
		const touch = body.indexOf(mutates);
		if (touch === -1) {
			errors.push(
				`${HEALTHKIT}: \`${marker}\` no longer calls \`${mutates}\`, so claim (11) can no ` +
					'longer tell whether the identity gate still precedes the mutation. Re-point the ' +
					'gate at whatever this delegate now writes.',
			);
		} else if (gate === -1 || gate > touch) {
			errors.push(
				`${HEALTHKIT}: \`${marker}\` reaches \`${mutates}\` without first checking ` +
					`\`${identity}\`. The previous run's session and builder keep delegating here ` +
					'until their workout has saved, so an unguarded callback applies one run\'s ' +
					'heart-rate state to another — a torn-down sensor, or a sample age coverage then ' +
					'credits to a run that never produced it.',
			);
		} else {
			ok.push(`\`${marker}\` checks \`${identity}\` before it writes`);
		}
	}

	return { errors, ok };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	const root = process.argv[2] ?? join(REPO_ROOT, 'apps', 'watch_ios');
	const { errors, ok } = check(
		root,
		process.argv[3] ?? join(REPO_ROOT, INGEST),
		process.argv[4] ?? join(REPO_ROOT, ROUTE_BRIDGE),
	);
	for (const line of ok) console.log(`  ok: ${line}`);
	if (errors.length > 0) {
		console.error(`\nFAIL: ${errors.length} problem(s) in apps/watch_ios:`);
		for (const e of errors) console.error(`  - ${e}`);
		process.exit(1);
	}
	console.log(`\nOK: ${ok.length} claim(s) hold across apps/watch_ios (read, not compiled).`);
}
