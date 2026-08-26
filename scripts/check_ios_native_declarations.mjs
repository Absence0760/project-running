#!/usr/bin/env node
// Guardrail: every iOS capability the phone app's code exercises is declared
// in `Info.plist` / `Runner.entitlements`, and the requirement is DERIVED from
// the code that needs it rather than transcribed from a list.
//
// Why this exists: decisions.md § 742. Two capabilities the shipped Dart
// depends on were undeclared, and both failed silently rather than loudly.
// `audio_cues.dart` puts the TTS session in AVAudioSession's `playback`
// category — the navigation-cue configuration — while `UIBackgroundModes`
// declared only `location` and `processing`, and iOS gates background audio
// OUTPUT on the `audio` mode specifically. A runner who pockets the phone
// mid-run, the case the cues exist for, hears nothing; the recording is
// unaffected, so nothing surfaces. Separately, `firebase_messaging` is a live
// dependency and the entitlements carried no `aps-environment`, so a signed
// build could not register for APNs at all.
//
// Neither was catchable by anything that runs. A `group('iOS Info.plist')`
// existed in `architecture_guards_test.dart` and read these very files, but
// every assertion sat behind `if (!file.existsSync()) return;` and the only
// package where the file exists — `mobile_ios` — is not in the `test-packages`
// job's `melos exec --scope=` list. Twelve tests, zero executions, for as long
// as they had existed: the § 741 shape, a guard whose verdict was decided by
// its environment rather than by the code. Those tests are gone; this script
// is what replaced them, and it runs on every PR against the one tree where
// the files exist.
//
// The derivation is the point (§ 739 / § 740). A guard that restates
// `['location', 'processing', 'audio']` is a second copy of the plist and
// drifts from the code the same way the first one did. Every rule below names
// a PATTERN IN THE SOURCE and the declaration that pattern obliges, so
// deleting the TTS playback category deletes the `audio` requirement with it,
// and adding a plugin that needs a purpose string fails the build until the
// string is written.
//
// Run: `node scripts/check_ios_native_declarations.mjs`
// CI:  the `ios-native-declarations` job in .github/workflows/ci.yml, which is
//      in the `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_ios_native_declarations.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Overridable so the whole script — exit code and all — can be pointed at a
// mutated copy of the tree, which is how a guard is shown to fail.
export const IOS_ROOT =
	process.env.IOS_RUNNER_ROOT ?? join(REPO_ROOT, 'apps/mobile_ios/ios');

/// The Dart the iOS binary runs. Deliberately the `mobile_ios` copy and not
/// `mobile_android`'s: the plist configures THIS app, and asking "does the
/// code inside this bundle need the capability" is the question. The twin
/// invariant (§ 39, enforced by the `twin-parity` job) makes the two copies
/// the same bytes, so nothing is lost by reading the honest one. `packages/`
/// is included because the capability that matters most is declared there —
/// `run_recorder` is what asks CoreLocation to keep running in the background.
export const DART_ROOTS = ['apps/mobile_ios/lib', 'packages'];

/// Swift under `ios/Runner/` — the native half that can oblige a declaration
/// no Dart import implies (EventKit reaches the calendar with no plugin).
export const SWIFT_ROOT = 'Runner';

const APS_KEY = 'com.apple.developer.aps-environment';
export const APS_SUBSTITUTION = '$(APS_ENVIRONMENT)';
export const APS_VALUES = new Set(['development', 'production']);

/// `UIBackgroundModes` entries, each derived from the call that needs it.
///
/// The reverse direction is checked too and is an ERROR, not a warning: App
/// Review rejects a binary declaring a background capability it does not
/// exercise, and a mode nothing here claims is either an over-claim or a rule
/// this table is missing. Both want a human.
export const BACKGROUND_MODES = [
	{
		mode: 'audio',
		source: 'dart',
		pattern: /IosTextToSpeechAudioCategory\.(playback|playAndRecord)/,
		needed_by: 'the TTS session is put in the AVAudioSession `playback` category',
		why:
			'`playback` is the category that keeps sounding with the screen locked, ' +
			'but iOS licenses that only against the `audio` background mode. The ' +
			'`location` mode keeps the PROCESS alive for GPS and does not license ' +
			'the session, so cues die the moment the run screen backgrounds — ' +
			'silently, because the recording carries on.',
	},
	{
		mode: 'location',
		source: 'dart',
		pattern: /allowBackgroundLocationUpdates:\s*true/,
		needed_by: 'CoreLocation is asked to deliver fixes while backgrounded',
		why:
			'CLLocationManager.allowBackgroundLocationUpdates throws unless the ' +
			'`location` background mode is declared, which would take the whole ' +
			'recorder down rather than degrade it.',
	},
	{
		mode: 'processing',
		source: 'dart',
		pattern: /Workmanager\(\)\s*\.\s*registerProcessingTask/,
		needed_by: 'background sync submits a BGProcessingTaskRequest',
		why:
			'iOS gates each BGTaskScheduler request type on a different mode — ' +
			'`fetch` authorises BGAppRefreshTaskRequest, `processing` authorises ' +
			'BGProcessingTaskRequest. Submitting a type the plist does not ' +
			'authorise makes submit() throw, and workmanager swallows it.',
	},
];

/// A background mode allowed to stand with no rule claiming it. Empty today
/// and expected to stay that way; the escape hatch exists so a genuinely
/// undetectable capability can be admitted in writing rather than by widening
/// the over-claim check into a warning that nobody reads.
export const UNCLAIMED_BACKGROUND_MODES = [];

/// `Runner.entitlements` keys, each derived from the code that needs it.
export const ENTITLEMENTS = [
	{
		key: 'com.apple.developer.healthkit',
		source: 'dart',
		pattern: /package:health\//,
		needed_by: 'the `health` plugin is imported',
		accepts: (v) => v === true,
		shape: '<true/>',
		why:
			'App Store Connect rejects an IPA that calls HealthKit without the ' +
			'entitlement, and the first HealthKit call crashes on device.',
	},
	{
		key: 'com.apple.developer.applesignin',
		source: 'dart',
		pattern: /package:sign_in_with_apple\//,
		needed_by: 'the sign-in screen offers Sign in with Apple',
		accepts: (v) => Array.isArray(v) && v.includes('Default'),
		shape: '<array><string>Default</string></array>',
		why:
			'The App Store rejects an upload whose binary uses an OAuth capability ' +
			'with no provisioned entitlement.',
	},
	{
		key: APS_KEY,
		source: 'dart',
		pattern: /package:firebase_messaging\//,
		needed_by: 'the push bridge asks firebase_messaging for an APNs token',
		accepts: (v) => v === APS_SUBSTITUTION || APS_VALUES.has(v),
		shape: `<string>${APS_SUBSTITUTION}</string> (or a literal development / production)`,
		why:
			'Without it `registerForRemoteNotifications` never yields a token, so ' +
			'`getToken()` returns null forever and the device silently registers ' +
			'nothing. It is a checked-in capability declaration, not a credential ' +
			'— the Firebase plist and the APNs key are the operator-supplied half.',
	},
];

/// Purpose strings the OS demands before it will grant the permission. A
/// missing one is not a build error: iOS denies the permission and the feature
/// returns empty or never streams, which is the same silent shape as the two
/// capabilities above.
export const PURPOSE_STRINGS = [
	{
		key: 'NSLocationWhenInUseUsageDescription',
		source: 'dart',
		pattern: /package:geolocator\//,
		needed_by: 'geolocator is imported (foreground GPS)',
	},
	{
		key: 'NSLocationAlwaysAndWhenInUseUsageDescription',
		source: 'dart',
		pattern: /allowBackgroundLocationUpdates:\s*true/,
		needed_by: 'the recorder keeps GPS running while backgrounded',
	},
	{
		key: 'NSHealthShareUsageDescription',
		source: 'dart',
		pattern: /package:health\//,
		needed_by: 'the `health` plugin reads HealthKit workouts',
	},
	{
		key: 'NSHealthUpdateUsageDescription',
		source: 'dart',
		pattern: /package:health\//,
		needed_by: 'the `health` plugin writes runs back to HealthKit',
	},
	{
		key: 'NSBluetoothAlwaysUsageDescription',
		source: 'dart',
		pattern: /package:flutter_reactive_ble\//,
		needed_by: 'flutter_reactive_ble talks to the chest strap / watch',
	},
	{
		key: 'NSMotionUsageDescription',
		source: 'dart',
		pattern: /package:pedometer\//,
		needed_by: 'pedometer counts steps on treadmill runs',
	},
	{
		key: 'NSPhotoLibraryUsageDescription',
		source: 'dart',
		pattern: /package:image_picker\//,
		needed_by: 'image_picker attaches library photos',
	},
	{
		key: 'NSCameraUsageDescription',
		source: 'dart',
		pattern: /package:mobile_scanner\//,
		needed_by: 'mobile_scanner scans a food barcode',
	},
	{
		key: 'NSCalendarsWriteOnlyAccessUsageDescription',
		source: 'swift',
		pattern: /import\s+EventKit\b/,
		needed_by: 'CalendarBridge.swift files a club event via EventKit',
	},
	{
		key: 'NSCalendarsUsageDescription',
		source: 'swift',
		pattern: /import\s+EventKit\b/,
		needed_by: 'the pre-iOS-17 spelling of the same EventKit grant',
	},
];

/// Declarations no pattern can derive, each carried with the reason it is
/// here. Listing them beats deriving them dishonestly: a rule keyed on a
/// plugin that does not actually perform the action would read as evidence.
export const FIXED_PLIST_KEYS = [
	{
		key: 'ITSAppUsesNonExemptEncryption',
		why:
			'App Store Connect blocks every upload without it — the reviewer ' +
			'cannot determine export-compliance status. Nothing in the source ' +
			'implies it; it is a property of submitting at all.',
	},
	{
		key: 'NSPhotoLibraryAddUsageDescription',
		why:
			'Carried pre-emptively since the 2026-05 app-store-privacy audit for a ' +
			'save-to-photos write-back. No Dart writes to the library today, so ' +
			'there is nothing to derive it from — and an extra purpose string ' +
			'costs nothing, unlike an extra background mode.',
	},
];

/// `PrivacyInfo.xcprivacy`'s required-reason API declarations, derived from
/// the plugin that touches the API. Apple's upload validation rejects a binary
/// that uses one of these without an entry.
export const PRIVACY_API_TYPES = [
	{
		type: 'NSPrivacyAccessedAPICategoryUserDefaults',
		source: 'dart',
		pattern: /package:(?:shared_preferences|flutter_secure_storage)\//,
		needed_by: 'shared_preferences / flutter_secure_storage read UserDefaults',
	},
	{
		type: 'NSPrivacyAccessedAPICategoryFileTimestamp',
		source: 'dart',
		pattern: /package:path_provider\//,
		needed_by: 'the disk-backed tile cache and local stores stat their files',
	},
	{
		type: 'NSPrivacyAccessedAPICategorySystemBootTime',
		source: 'dart',
		pattern: /package:workmanager\//,
		needed_by: 'workmanager schedules against system boot time',
	},
];

/// Required-reason categories no import implies, each with the reason code it
/// must carry.
export const PRIVACY_API_TYPES_FIXED = [
	{
		type: 'NSPrivacyAccessedAPICategoryActiveKeyboards',
		reason: '3EC4.1',
		why:
			"Flutter's own text-input plugin calls UITextInputMode.activeInputModes " +
			'during keyboard handling — nothing in this repo imports it, and the ' +
			'engine is not scanned. 3EC4.1 is app functionality initiated by the user.',
	},
	{
		type: 'NSPrivacyAccessedAPICategoryDiskSpace',
		reason: 'E174.1',
		why:
			'Backup and export size estimation asks for free space. The call sits ' +
			'behind platform plumbing rather than a named plugin import.',
	},
];

/// The data types the binary collects, derived from the code that collects
/// them. A partial `NSPrivacyCollectedDataTypes` array fails Privacy Manifest
/// validation, and it also has to agree with the App Store Connect nutrition
/// label, so under-declaring here is a compliance answer as well as a build one.
export const PRIVACY_DATA_TYPES = [
	{
		type: 'NSPrivacyCollectedDataTypePreciseLocation',
		source: 'dart',
		pattern: /package:geolocator\//,
		needed_by: 'geolocator records the GPS trace',
	},
	{
		type: 'NSPrivacyCollectedDataTypeCoarseLocation',
		source: 'dart',
		pattern: /package:geolocator\//,
		needed_by: 'the same fixes arrive coarse under an Approximate-Location grant',
	},
	{
		type: 'NSPrivacyCollectedDataTypeHealth',
		source: 'dart',
		pattern: /package:health\//,
		needed_by: 'the health plugin reads and writes HealthKit',
	},
	{
		type: 'NSPrivacyCollectedDataTypeFitness',
		source: 'dart',
		pattern: /package:pedometer\//,
		needed_by: 'pedometer counts steps',
	},
	{
		type: 'NSPrivacyCollectedDataTypePhotosorVideos',
		source: 'dart',
		pattern: /package:image_picker\//,
		needed_by: 'runs carry photo attachments',
	},
	{
		type: 'NSPrivacyCollectedDataTypePurchaseHistory',
		source: 'dart',
		pattern: /package:purchases_flutter\//,
		needed_by: 'RevenueCat records subscription events',
	},
	{
		type: 'NSPrivacyCollectedDataTypeCrashData',
		source: 'dart',
		pattern: /package:sentry_flutter\//,
		needed_by: 'Sentry captures unhandled exceptions',
	},
	{
		type: 'NSPrivacyCollectedDataTypePerformanceData',
		source: 'dart',
		pattern: /package:sentry_flutter\//,
		needed_by: 'Sentry captures performance traces',
	},
	{
		type: 'NSPrivacyCollectedDataTypeEmailAddress',
		source: 'dart',
		pattern: /package:supabase_flutter\//,
		needed_by: 'Supabase Auth signs the runner in by email',
	},
	{
		type: 'NSPrivacyCollectedDataTypeUserID',
		source: 'dart',
		pattern: /package:supabase_flutter\//,
		needed_by: "auth.users.id is stored against the runner's rows and on RevenueCat",
	},
];

/// Collected types that are a property of the product rather than of an
/// import: they arrive as ordinary columns, so no plugin names them.
export const PRIVACY_DATA_TYPES_FIXED = [
	{ type: 'NSPrivacyCollectedDataTypeName', why: 'user_profiles.display_name' },
	{
		type: 'NSPrivacyCollectedDataTypeOtherUserContent',
		why: 'coach chat messages, run titles and notes',
	},
];

// ---------------------------------------------------------------------------
// Plist reading
// ---------------------------------------------------------------------------

const ENTITIES = {
	'&amp;': '&',
	'&lt;': '<',
	'&gt;': '>',
	'&quot;': '"',
	'&apos;': "'",
};

const decodeEntities = (s) => s.replace(/&(?:amp|lt|gt|quot|apos);/g, (m) => ENTITIES[m]);

/// Tag stream for an XML plist. Comments are dropped BEFORE parsing: the plist
/// in this repo carries several, and a key mentioned in prose is not a key the
/// binary declares.
export function tokenizePlist(xml) {
	// Stripped to a fixpoint, not in one pass: removing a `<!-- ... -->` span can
	// leave its neighbours spelling a fresh one (`<!--<!-- -->-->` reduces to a
	// bare `-->`), and a residue the tag regex then reads as text is a key this
	// guard would count as declared when the binary never sees it.
	let clean = xml;
	for (;;) {
		const next = clean
			.replace(/<\?[\s\S]*?\?>/g, '')
			.replace(/<!DOCTYPE[\s\S]*?>/g, '')
			.replace(/<!--[\s\S]*?-->/g, '');
		if (next === clean) break;
		clean = next;
	}
	const tokens = [];
	const re = /<\s*(\/?)([A-Za-z][\w.:-]*)\b[^>]*?(\/?)\s*>/g;
	let last = 0;
	let m;
	while ((m = re.exec(clean)) !== null) {
		const text = clean.slice(last, m.index);
		if (text.trim()) tokens.push({ kind: 'text', name: '', value: decodeEntities(text.trim()) });
		last = re.lastIndex;
		if (m[1]) tokens.push({ kind: 'close', name: m[2] });
		else if (m[3]) tokens.push({ kind: 'empty', name: m[2] });
		else tokens.push({ kind: 'open', name: m[2] });
	}
	return tokens;
}

function parseValue(tokens, i) {
	const t = tokens[i];
	if (!t) return [undefined, i];
	if (t.kind === 'empty') {
		if (t.name === 'true') return [true, i + 1];
		if (t.name === 'false') return [false, i + 1];
		if (t.name === 'array') return [[], i + 1];
		if (t.name === 'dict') return [new Map(), i + 1];
		if (t.name === 'string') return ['', i + 1];
		return [null, i + 1];
	}
	if (t.kind !== 'open') return [undefined, i + 1];

	if (t.name === 'dict') {
		const map = new Map();
		let j = i + 1;
		while (j < tokens.length && !(tokens[j].kind === 'close' && tokens[j].name === 'dict')) {
			if (tokens[j].kind === 'open' && tokens[j].name === 'key') {
				const key = tokens[j + 1]?.kind === 'text' ? tokens[j + 1].value : '';
				let k = j + 1;
				while (k < tokens.length && !(tokens[k].kind === 'close' && tokens[k].name === 'key')) k++;
				const [value, next] = parseValue(tokens, k + 1);
				map.set(key, value);
				j = next;
				continue;
			}
			j++;
		}
		return [map, j + 1];
	}

	if (t.name === 'array') {
		const arr = [];
		let j = i + 1;
		while (j < tokens.length && !(tokens[j].kind === 'close' && tokens[j].name === 'array')) {
			if (tokens[j].kind === 'text' || tokens[j].kind === 'close') {
				j++;
				continue;
			}
			const [value, next] = parseValue(tokens, j);
			arr.push(value);
			j = next;
		}
		return [arr, j + 1];
	}

	const text = tokens[i + 1]?.kind === 'text' ? tokens[i + 1].value : '';
	let j = i + 1;
	while (j < tokens.length && !(tokens[j].kind === 'close' && tokens[j].name === t.name)) j++;
	return [t.name === 'integer' || t.name === 'real' ? Number(text) : text, j + 1];
}

/// The plist's root dictionary as a Map, or null when the file is not one.
export function parsePlist(xml) {
	const tokens = tokenizePlist(xml);
	const at = tokens.findIndex((t) => t.kind === 'open' && t.name === 'plist');
	if (at < 0) return null;
	const [value] = parseValue(tokens, at + 1);
	return value instanceof Map ? value : null;
}

// ---------------------------------------------------------------------------
// Source reading
// ---------------------------------------------------------------------------

/// Blank out lines that are ENTIRELY a comment. A rule that fires on prose is
/// a rule that lies — `background_sync.dart` explains `registerPeriodicTask`
/// and the `fetch` mode in a comment directly above the call it does NOT make.
/// Only whole-line comments are removed, never a trailing one: a trailing
/// strip would have to guess at `//` inside a string literal, and guessing
/// wrong there deletes real code and turns the guard silently permissive.
export function stripWholeLineComments(src) {
	return src
		.split('\n')
		.map((line) => (/^\s*(\/\/|\/\*|\*)/.test(line) ? '' : line))
		.join('\n');
}

function walk(dir, suffix, out, filter) {
	let entries;
	try {
		entries = readdirSync(dir, { withFileTypes: true });
	} catch {
		return out;
	}
	for (const entry of entries) {
		const name = entry.name;
		const full = join(dir, name);
		if (entry.isDirectory()) {
			walk(full, suffix, out, filter);
			continue;
		}
		if (!name.endsWith(suffix)) continue;
		if (filter && !filter(full)) continue;
		// Read and let it throw rather than stat-then-read: a separate existence
		// check is a claim about a moment that has passed by the time the read
		// happens, and a source file that vanished mid-walk is a broken checkout
		// this guard should fail on rather than silently skip.
		let text;
		try {
			text = readFileSync(full, 'utf-8');
		} catch {
			continue;
		}
		out.push({ path: full, text: stripWholeLineComments(text) });
	}
	return out;
}

/// Every `.dart` file the iOS binary compiles, comments stripped. `packages/`
/// is filtered to `lib/` so a test fixture importing a plugin cannot conjure a
/// capability requirement out of nothing.
export function collectDartSources(root = REPO_ROOT, roots = DART_ROOTS) {
	const out = [];
	for (const rel of roots) {
		walk(join(root, rel), '.dart', out, (p) => p.includes(`${'/'}lib${'/'}`));
	}
	return out;
}

export function collectSwiftSources(iosRoot = IOS_ROOT) {
	return walk(join(iosRoot, SWIFT_ROOT), '.swift', [], null);
}

/// The first file matching `pattern`, repo-relative, or null.
export function firstMatch(sources, pattern, root = REPO_ROOT) {
	const hit = sources.find((s) => pattern.test(s.text));
	return hit ? relative(root, hit.path) : null;
}

// ---------------------------------------------------------------------------
// pbxproj reading
// ---------------------------------------------------------------------------

/// Every `XCBuildConfiguration` in the project, as `{ name, settings }`.
/// Brace-counted rather than indentation-matched: the closing `};` of
/// `buildSettings` and the closing `};` of the configuration differ only by a
/// tab, and a guard that depends on a tab is a guard one reformat from blind.
export function parseBuildConfigurations(pbx) {
	const out = [];
	const marker = 'isa = XCBuildConfiguration;';
	let from = 0;
	for (;;) {
		const at = pbx.indexOf(marker, from);
		if (at < 0) break;
		let depth = 1;
		let i = at + marker.length;
		for (; i < pbx.length && depth > 0; i++) {
			if (pbx[i] === '{') depth++;
			else if (pbx[i] === '}') depth--;
		}
		const body = pbx.slice(at + marker.length, i);
		const name = body.match(/\bname\s*=\s*([A-Za-z0-9_"-]+)\s*;/);
		out.push({ name: name ? name[1].replace(/"/g, '') : '', settings: body });
		from = i;
	}
	return out;
}

const settingOf = (settings, key) => {
	const m = settings.match(new RegExp(`\\b${key}\\s*=\\s*([^;\\n]+);`));
	return m ? m[1].trim().replace(/^"|"$/g, '') : null;
};

// ---------------------------------------------------------------------------
// The verdict
// ---------------------------------------------------------------------------

export function evaluate(input) {
	const {
		infoPlist,
		entitlements,
		privacyManifest,
		appDelegate,
		pbxproj,
		backgroundSyncDart,
		dartSources,
		swiftSources,
		root = REPO_ROOT,
	} = input;

	const errors = [];
	const warnings = [];
	const ok = [];

	// Blindness checks, in the shape check_watch_ble_uuids.mjs uses: a parser
	// that quietly stops matching passes vacuously, which is the failure this
	// whole script exists because of.
	if (!infoPlist || infoPlist.size === 0) {
		errors.push(
			'Parsed no keys out of Info.plist.\n' +
				'  The file moved or changed shape; this guard is blind until ' +
				'parsePlist() is taught the new form.',
		);
		return { errors, warnings, ok };
	}
	if (!entitlements) {
		errors.push(
			'Parsed no dictionary out of Runner.entitlements.\n' +
				'  The file moved or changed shape; this guard is blind until ' +
				'parsePlist() is taught the new form.',
		);
		return { errors, warnings, ok };
	}
	if (dartSources.length === 0) {
		errors.push(
			'Found no Dart sources to derive requirements from.\n' +
				`  Looked under ${DART_ROOTS.join(', ')}. Every rule below would ` +
				'pass vacuously.',
		);
		return { errors, warnings, ok };
	}

	const sourcesFor = (kind) => (kind === 'swift' ? swiftSources : dartSources);

	// --- UIBackgroundModes, both directions -------------------------------
	const declaredModes = infoPlist.get('UIBackgroundModes');
	if (!Array.isArray(declaredModes)) {
		errors.push(
			'Info.plist has no UIBackgroundModes array.\n' +
				'  The app records GPS in the background; without this key nothing ' +
				'below can be honoured.',
		);
		return { errors, warnings, ok };
	}

	const claimedModes = new Set(UNCLAIMED_BACKGROUND_MODES);
	for (const rule of BACKGROUND_MODES) {
		const where = firstMatch(sourcesFor(rule.source), rule.pattern, root);
		if (!where) continue;
		claimedModes.add(rule.mode);
		if (declaredModes.includes(rule.mode)) {
			ok.push(`UIBackgroundModes contains \`${rule.mode}\` (${where}: ${rule.needed_by})`);
			continue;
		}
		errors.push(
			`UIBackgroundModes is missing \`${rule.mode}\`, but ${where} ` +
				`means ${rule.needed_by}.\n  ${rule.why}\n` +
				`  Fix: add <string>${rule.mode}</string> to the UIBackgroundModes ` +
				'array in Info.plist, or remove the code that needs it.',
		);
	}
	for (const mode of declaredModes) {
		if (claimedModes.has(mode)) continue;
		errors.push(
			`UIBackgroundModes declares \`${mode}\` and no rule in this script ` +
				'claims it.\n' +
				'  App Review rejects a binary declaring a background capability it ' +
				'does not exercise. Either the code that needed it was deleted (drop ' +
				'the mode), or a new capability arrived without a derivation rule ' +
				'(add one to BACKGROUND_MODES, or name it in ' +
				'UNCLAIMED_BACKGROUND_MODES with the reason).',
		);
	}

	// --- Entitlements ------------------------------------------------------
	const claimedEntitlements = new Set();
	for (const rule of ENTITLEMENTS) {
		const where = firstMatch(sourcesFor(rule.source), rule.pattern, root);
		if (!where) continue;
		claimedEntitlements.add(rule.key);
		if (!entitlements.has(rule.key)) {
			errors.push(
				`Runner.entitlements is missing \`${rule.key}\`, but ${where} ` +
					`means ${rule.needed_by}.\n  ${rule.why}\n` +
					`  Fix: declare <key>${rule.key}</key> ${rule.shape}.`,
			);
			continue;
		}
		const value = entitlements.get(rule.key);
		if (!rule.accepts(value)) {
			errors.push(
				`Runner.entitlements declares \`${rule.key}\` with an unusable ` +
					`value (${JSON.stringify(value)}).\n  Expected ${rule.shape}.`,
			);
			continue;
		}
		ok.push(`entitlement \`${rule.key}\` (${where}: ${rule.needed_by})`);
	}
	for (const key of entitlements.keys()) {
		if (claimedEntitlements.has(key)) continue;
		// `com.apple.developer.healthkit.access` is a companion of the
		// capability above it, not an independent one.
		if ([...claimedEntitlements].some((c) => key.startsWith(`${c}.`))) continue;
		warnings.push(
			`Runner.entitlements declares \`${key}\` and no rule claims it.\n` +
				'  Fine if it is deliberate; a provisioning profile that does not ' +
				'carry it will fail to sign. Add a rule to ENTITLEMENTS when the ' +
				'code that needs it lands.',
		);
	}

	// --- Purpose strings ---------------------------------------------------
	for (const rule of PURPOSE_STRINGS) {
		const where = firstMatch(sourcesFor(rule.source), rule.pattern, root);
		if (!where) continue;
		const value = infoPlist.get(rule.key);
		if (typeof value === 'string' && value.trim() !== '') {
			ok.push(`Info.plist declares \`${rule.key}\` (${where}: ${rule.needed_by})`);
			continue;
		}
		errors.push(
			`Info.plist has no usable \`${rule.key}\`, but ${where} means ` +
				`${rule.needed_by}.\n` +
				'  iOS denies the permission silently when the string is missing or ' +
				'empty — the feature returns nothing rather than throwing.',
		);
	}

	for (const { key, why } of FIXED_PLIST_KEYS) {
		if (infoPlist.has(key)) {
			ok.push(`Info.plist declares \`${key}\``);
			continue;
		}
		errors.push(`Info.plist is missing \`${key}\`.\n  ${why}`);
	}

	// The display name is "Threkir"; the usage strings once said "Run App",
	// and App Review flags a metadata-name mismatch.
	const displayName = infoPlist.get('CFBundleDisplayName');
	if (typeof displayName === 'string' && displayName) {
		const stale = [...infoPlist.entries()].filter(
			([k, v]) =>
				k.endsWith('UsageDescription') &&
				typeof v === 'string' &&
				!v.includes(displayName),
		);
		for (const [k] of stale) {
			errors.push(
				`Info.plist's \`${k}\` does not name the app (CFBundleDisplayName = ` +
					`"${displayName}").\n` +
					'  A usage string naming a different product than the listing is an ' +
					'App Review rejection cause; the legacy "Run App" copy was exactly ' +
					'that.',
			);
		}
		if (stale.length === 0) ok.push(`every usage description names "${displayName}"`);
	}

	// --- The background-sync identifier, across three files ----------------
	// Repeated as a bare string in Dart, the plist and Swift, with nothing
	// linking them. A rename in one place produces no build error — the task
	// simply stops being delivered.
	const dartId = backgroundSyncDart?.match(
		/const\s+backgroundSyncTaskName\s*=\s*['"]([^'"]+)['"]/,
	);
	if (!dartId) {
		errors.push(
			'background_sync.dart declares no top-level `backgroundSyncTaskName` ' +
				'string constant.\n  It is the identifier the plist and AppDelegate ' +
				'are checked against; without it nothing here can be verified.',
		);
	} else {
		const identifier = dartId[1];
		const permitted = infoPlist.get('BGTaskSchedulerPermittedIdentifiers');
		if (!Array.isArray(permitted) || !permitted.includes(identifier)) {
			errors.push(
				`BGTaskSchedulerPermittedIdentifiers does not list "${identifier}".\n` +
					'  iOS rejects a submission whose identifier is not in this array, ' +
					'and workmanager logs the rejection rather than surfacing it.',
			);
		}
		// iOS gates each BGTaskScheduler request type on a different background
		// mode — `fetch` authorises BGAppRefreshTaskRequest, `processing`
		// authorises BGProcessingTaskRequest — so which one the iOS BRANCH
		// submits is what the declared mode has to match. Dropping to the
		// periodic task would need `fetch` declared as well, not just a
		// different call, and workmanager logs the resulting rejection rather
		// than surfacing it.
		if (!/Platform\.isIOS[\s\S]{0,120}?Workmanager\(\)\s*\.\s*registerProcessingTask/.test(
			backgroundSyncDart ?? '',
		)) {
			errors.push(
				'background_sync.dart does not call `registerProcessingTask` on its ' +
					'`Platform.isIOS` branch.\n  registerPeriodicTask submits a ' +
					'BGAppRefreshTaskRequest, which needs the `fetch` background mode ' +
					'this app deliberately does not declare — the submission then ' +
					'throws and workmanager swallows it, so background sync silently ' +
					'never runs.',
			);
		}

		const swiftId = appDelegate?.match(
			/registerBGProcessingTask\(\s*withIdentifier:\s*"([^"]+)"/,
		);
		if (!swiftId) {
			errors.push(
				'AppDelegate.swift does not call ' +
					'`WorkmanagerPlugin.registerBGProcessingTask(withIdentifier:)`.\n' +
					'  The handler dispatches on the delivered task type, so the ' +
					'periodic registrar leaves a submitted BGProcessingTaskRequest ' +
					'unhandled. It must also run during didFinishLaunchingWithOptions ' +
					'— this app adopts UIScene, so the plugin cannot register in time ' +
					'itself.',
			);
		} else if (swiftId[1] !== identifier) {
			errors.push(
				`AppDelegate registers "${swiftId[1]}" but Dart submits ` +
					`"${identifier}".\n  BGTaskScheduler matches the launch handler to ` +
					'the request by identifier, so the task is never delivered.',
			);
		} else if (Array.isArray(permitted) && permitted.includes(identifier)) {
			ok.push(`background-sync identifier "${identifier}" agrees across Dart, plist and Swift`);
		}
	}

	// --- The Xcode wiring the two declarations depend on -------------------
	const configs = parseBuildConfigurations(pbxproj ?? '');
	const runnerConfigs = configs.filter(
		(c) => settingOf(c.settings, 'CODE_SIGN_ENTITLEMENTS') === 'Runner/Runner.entitlements',
	);
	if (runnerConfigs.length === 0) {
		errors.push(
			'No Runner build configuration sets ' +
				'`CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;`.\n' +
				'  Without it the entitlements file is a text file the build ignores ' +
				'— every capability above reaches the binary through this setting.',
		);
	} else {
		ok.push(
			`${runnerConfigs.length} Runner build configuration(s) point ` +
				'CODE_SIGN_ENTITLEMENTS at Runner.entitlements',
		);
	}

	// `aps-environment` written as a build-setting substitution is only
	// meaningful if every configuration defines the setting. An undefined one
	// expands to the literal `$(APS_ENVIRONMENT)`, which no provisioning
	// profile carries — loud at signing time, which is the point, but the
	// guard should say so first.
	if (entitlements.get(APS_KEY) === APS_SUBSTITUTION) {
		for (const config of runnerConfigs) {
			const value = settingOf(config.settings, 'APS_ENVIRONMENT');
			if (!value) {
				errors.push(
					`The \`${config.name}\` Runner build configuration does not define ` +
						'`APS_ENVIRONMENT`, but Runner.entitlements resolves ' +
						`\`${APS_KEY}\` through it.\n  An undefined setting expands to ` +
						'the literal string, which no profile carries.',
				);
				continue;
			}
			if (!APS_VALUES.has(value)) {
				errors.push(
					`The \`${config.name}\` Runner build configuration sets ` +
						`APS_ENVIRONMENT = ${value}, which is not one of ` +
						`${[...APS_VALUES].join(' / ')}.`,
				);
				continue;
			}
			// Release is what `flutter build ipa --release` archives, and a
			// TestFlight/App Store build must mint production tokens or the
			// worker's production APNs host answers BadDeviceToken for every
			// one of them — push that silently never arrives.
			const expected = config.name === 'Release' ? 'production' : 'development';
			if (value !== expected) {
				errors.push(
					`The \`${config.name}\` Runner build configuration sets ` +
						`APS_ENVIRONMENT = ${value}; expected ${expected}.\n` +
						'  Release is what is archived for TestFlight / the App Store ' +
						'(production APNs); Debug and Profile are dev-signed (sandbox ' +
						'APNs). A mismatch answers BadDeviceToken for every token.',
				);
				continue;
			}
			ok.push(`APS_ENVIRONMENT = ${value} in the ${config.name} configuration`);
		}
	}

	// --- Native posture the Dart cannot express ----------------------------
	if (appDelegate && !/isExcludedFromBackup\s*=\s*true/.test(appDelegate)) {
		errors.push(
			'AppDelegate.swift does not mark the Documents directory ' +
				'`isExcludedFromBackup`.\n' +
				'  path_provider stores the GPS/HR run cache there; without the flag ' +
				'the whole subtree rides into iCloud / iTunes backups.',
		);
	} else if (appDelegate && !/\.documentDirectory/.test(appDelegate)) {
		errors.push(
			'AppDelegate.swift sets `isExcludedFromBackup` on something other than ' +
				'`.documentDirectory`.\n  The run cache is what has to be excluded.',
		);
	} else if (appDelegate) {
		ok.push('AppDelegate excludes the Documents directory from iCloud backup');
	}

	// --- PrivacyInfo.xcprivacy --------------------------------------------
	// Parsed rather than substring-matched: a category named in a comment, or
	// in the wrong array, satisfies `includes()` while declaring nothing.
	if (privacyManifest !== null && privacyManifest !== undefined) {
		const manifest = parsePlist(privacyManifest);
		if (!manifest) {
			errors.push(
				'Parsed no dictionary out of PrivacyInfo.xcprivacy.\n' +
					'  Apple requires the manifest for every binary touching a ' +
					'required-reason API; this guard is blind until parsePlist() is ' +
					'taught the new form.',
			);
		} else {
			const apiEntries = manifest.get('NSPrivacyAccessedAPITypes') ?? [];
			const apiTypes = new Map(
				apiEntries
					.filter((e) => e instanceof Map)
					.map((e) => [e.get('NSPrivacyAccessedAPIType'), e.get('NSPrivacyAccessedAPITypeReasons') ?? []]),
			);
			const dataTypes = new Set(
				(manifest.get('NSPrivacyCollectedDataTypes') ?? [])
					.filter((e) => e instanceof Map)
					.map((e) => e.get('NSPrivacyCollectedDataType')),
			);

			for (const rule of PRIVACY_API_TYPES) {
				const where = firstMatch(sourcesFor(rule.source), rule.pattern, root);
				if (!where) continue;
				if (apiTypes.has(rule.type)) {
					ok.push(`PrivacyInfo declares \`${rule.type}\` (${where}: ${rule.needed_by})`);
					continue;
				}
				errors.push(
					`PrivacyInfo.xcprivacy does not declare \`${rule.type}\`, but ` +
						`${where} means ${rule.needed_by}.\n  Apple's upload validation ` +
						'rejects a binary using a required-reason API it has not declared.',
				);
			}
			for (const { type, reason, why } of PRIVACY_API_TYPES_FIXED) {
				const reasons = apiTypes.get(type);
				if (!reasons) {
					errors.push(`PrivacyInfo.xcprivacy does not declare \`${type}\`.\n  ${why}`);
					continue;
				}
				if (!reasons.includes(reason)) {
					errors.push(
						`PrivacyInfo.xcprivacy declares \`${type}\` without reason code ` +
							`${reason}.\n  ${why}`,
					);
					continue;
				}
				ok.push(`PrivacyInfo declares \`${type}\` (${reason})`);
			}

			for (const rule of PRIVACY_DATA_TYPES) {
				const where = firstMatch(sourcesFor(rule.source), rule.pattern, root);
				if (!where) continue;
				if (dataTypes.has(rule.type)) {
					ok.push(`PrivacyInfo collects \`${rule.type}\` (${where}: ${rule.needed_by})`);
					continue;
				}
				errors.push(
					`PrivacyInfo.xcprivacy does not list \`${rule.type}\`, but ${where} ` +
						`means ${rule.needed_by}.\n  A partial NSPrivacyCollectedDataTypes ` +
						'array fails Privacy Manifest validation, and the App Store ' +
						'nutrition label is answered from it.',
				);
			}
			for (const { type, why } of PRIVACY_DATA_TYPES_FIXED) {
				if (dataTypes.has(type)) {
					ok.push(`PrivacyInfo collects \`${type}\``);
					continue;
				}
				errors.push(`PrivacyInfo.xcprivacy does not list \`${type}\`.\n  ${why}`);
			}

			if (manifest.get('NSPrivacyTracking') !== false) {
				errors.push(
					'PrivacyInfo.xcprivacy does not set NSPrivacyTracking to <false/>.\n' +
						'  The app reads no IDFA and does no cross-app tracking; claiming ' +
						'otherwise changes what App Review and the nutrition label expect.',
				);
			} else {
				ok.push('PrivacyInfo declares NSPrivacyTracking false');
			}
		}
	}

	return { errors, warnings, ok };
}

function readOrNull(path) {
	try {
		return readFileSync(path, 'utf-8');
	} catch {
		return null;
	}
}

function main() {
	const infoPlistText = readOrNull(join(IOS_ROOT, 'Runner/Info.plist'));
	const entitlementsText = readOrNull(join(IOS_ROOT, 'Runner/Runner.entitlements'));
	if (infoPlistText === null || entitlementsText === null) {
		console.error(
			`[FAIL] Could not read the iOS declaration files under ${IOS_ROOT}.\n` +
				'  This guard is the only thing checking them; a move must bring it ' +
				'along rather than silently disable it.',
		);
		return 1;
	}

	const { errors, warnings, ok } = evaluate({
		infoPlist: parsePlist(infoPlistText),
		entitlements: parsePlist(entitlementsText),
		privacyManifest: readOrNull(join(IOS_ROOT, 'Runner/PrivacyInfo.xcprivacy')),
		appDelegate: readOrNull(join(IOS_ROOT, 'Runner/AppDelegate.swift')),
		pbxproj: readOrNull(join(IOS_ROOT, 'Runner.xcodeproj/project.pbxproj')),
		backgroundSyncDart: readOrNull(join(REPO_ROOT, 'apps/mobile_ios/lib/background_sync.dart')),
		dartSources: collectDartSources(),
		swiftSources: collectSwiftSources(),
	});

	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of warnings) console.warn(`[WARN] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);

	if (errors.length > 0) {
		console.error(
			`\n${errors.length} iOS declaration problem(s). The code is the source ` +
				'of truth: every rule above names the file whose behaviour obliges ' +
				'the declaration (decisions.md § 742).',
		);
		return 1;
	}
	console.log(
		`\n${ok.length} iOS declaration(s) verified against the code that needs them` +
			(warnings.length ? `, ${warnings.length} warning(s)` : '') +
			'.',
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
