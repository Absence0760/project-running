import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	APS_SUBSTITUTION,
	BACKGROUND_MODES,
	ENTITLEMENTS,
	IOS_ROOT,
	PRIVACY_API_TYPES,
	PRIVACY_DATA_TYPES,
	PURPOSE_STRINGS,
	collectDartSources,
	collectSwiftSources,
	evaluate,
	parseBuildConfigurations,
	parsePlist,
	stripWholeLineComments,
	swiftRuleKeys,
} from './check_ios_native_declarations.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** @typedef {import('./check_ios_native_declarations.mjs').EvaluateInput} EvaluateInput */

/**
 * `parsePlist` is nullable and a null is a parser failure, not a fixture that
 * happens to be empty — so every reader asserts before it reads.
 * @param {string} xml
 * @returns {Map<string, unknown>}
 */
function parsed(xml) {
	const dict = parsePlist(xml);
	assert.ok(dict, 'parsePlist returned no dictionary for this fixture');
	return dict;
}

// --- the parser -------------------------------------------------------------

test('parsePlist reads scalars, arrays and booleans out of a dict', () => {
	const dict = parsed(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>Threkir</string>
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
		<string>location</string>
	</array>
</dict>
</plist>`);
	assert.equal(dict.get('CFBundleDisplayName'), 'Threkir');
	assert.equal(dict.get('ITSAppUsesNonExemptEncryption'), false);
	assert.deepEqual(dict.get('UIBackgroundModes'), ['audio', 'location']);
});

test('parsePlist ignores keys that appear only inside a comment', () => {
	const dict = parsed(`<plist version="1.0">
<dict>
	<!-- <key>UIBackgroundModes</key><array><string>audio</string></array> -->
	<key>CFBundleName</key>
	<string>Threkir</string>
</dict>
</plist>`);
	assert.equal(dict.has('UIBackgroundModes'), false);
	assert.equal(dict.get('CFBundleName'), 'Threkir');
});

test('parsePlist strips comments to a fixpoint, not in a single pass', () => {
	// Removing the inner span leaves the outer delimiters spelling a fresh
	// comment. A single pass drops one and hands the tokenizer the remainder,
	// where the key inside it reads as a declaration the binary never carries.
	const dict = parsed(`<plist version="1.0">
<dict>
	<!--<!-- <key>UIBackgroundModes</key><array><string>audio</string></array> -->-->
	<key>CFBundleName</key>
	<string>Threkir</string>
</dict>
</plist>`);
	assert.equal(dict.has('UIBackgroundModes'), false);
	assert.equal(dict.get('CFBundleName'), 'Threkir');
});

test('parsePlist walks past a nested dict-in-array without losing the next key', () => {
	const dict = parsed(`<plist version="1.0">
<dict>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>GPS Exchange Format</string>
			<key>LSItemContentTypes</key>
			<array><string>com.topografix.gpx</string></array>
		</dict>
	</array>
	<key>UIBackgroundModes</key>
	<array><string>audio</string></array>
</dict>
</plist>`);
	assert.deepEqual(dict.get('UIBackgroundModes'), ['audio']);
});

test('parseBuildConfigurations pairs each configuration name with its settings', () => {
	const configs = parseBuildConfigurations(
		`\t\tAAA /* Debug */ = {\n` +
			`\t\t\tisa = XCBuildConfiguration;\n` +
			`\t\t\tbuildSettings = {\n` +
			`\t\t\t\tAPS_ENVIRONMENT = development;\n` +
			`\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n` +
			`\t\t\t};\n` +
			`\t\t\tname = Debug;\n` +
			`\t\t};\n` +
			`\t\tBBB /* Release */ = {\n` +
			`\t\t\tisa = XCBuildConfiguration;\n` +
			`\t\t\tbuildSettings = {\n` +
			`\t\t\t\tAPS_ENVIRONMENT = production;\n` +
			`\t\t\t};\n` +
			`\t\t\tname = Release;\n` +
			`\t\t};\n`,
	);
	assert.deepEqual(
		configs.map((c) => c.name),
		['Debug', 'Release'],
	);
	assert.match(configs[0].settings, /CODE_SIGN_ENTITLEMENTS/);
	assert.doesNotMatch(configs[1].settings, /CODE_SIGN_ENTITLEMENTS/);
});

test('stripWholeLineComments blanks prose but keeps a trailing comment line intact', () => {
	const src = [
		'// Workmanager().registerProcessingTask is what iOS calls processing.',
		'  /// allowBackgroundLocationUpdates: true',
		'   * IosTextToSpeechAudioCategory.playback',
		"  final category = 'spoken'; // playback",
	].join('\n');
	const out = stripWholeLineComments(src);
	assert.doesNotMatch(out, /registerProcessingTask/);
	assert.doesNotMatch(out, /allowBackgroundLocationUpdates/);
	assert.doesNotMatch(out, /IosTextToSpeechAudioCategory/);
	assert.match(out, /final category = 'spoken';/);
});

// --- the verdict ------------------------------------------------------------

/** @param {string} text */
const dart = (text) => [{ path: join(REPO_ROOT, 'apps/mobile_ios/lib/x.dart'), text }];
/** @param {string} text */
const swift = (text) => [{ path: join(IOS_ROOT, 'Runner/X.swift'), text }];

/// A structurally faithful PrivacyInfo.xcprivacy carrying exactly the entries
/// the baseline's sources oblige — the two fixed API categories, the two fixed
/// data types, and the no-tracking stance.
/**
 * @param {{ apis?: string[], data?: string[] | null, tracking?: boolean }} [options]
 */
function fakeManifest({ apis = ['3EC4.1', 'E174.1'], data = null, tracking = false } = {}) {
	/**
	 * @param {string} type
	 * @param {string} reason
	 */
	const apiEntry = (type, reason) =>
		`\t\t<dict>\n\t\t\t<key>NSPrivacyAccessedAPIType</key>\n` +
		`\t\t\t<string>${type}</string>\n` +
		`\t\t\t<key>NSPrivacyAccessedAPITypeReasons</key>\n` +
		`\t\t\t<array><string>${reason}</string></array>\n\t\t</dict>`;
	/** @param {string} type */
	const dataEntry = (type) =>
		`\t\t<dict>\n\t\t\t<key>NSPrivacyCollectedDataType</key>\n` +
		`\t\t\t<string>${type}</string>\n\t\t</dict>`;
	const types =
		data ??
		['NSPrivacyCollectedDataTypeName', 'NSPrivacyCollectedDataTypeOtherUserContent'];
	return (
		`<plist version="1.0">\n<dict>\n` +
		`\t<key>NSPrivacyTracking</key>\n\t<${tracking}/>\n` +
		`\t<key>NSPrivacyAccessedAPITypes</key>\n\t<array>\n` +
		[
			apis.includes('3EC4.1')
				? apiEntry('NSPrivacyAccessedAPICategoryActiveKeyboards', '3EC4.1')
				: null,
			apis.includes('E174.1')
				? apiEntry('NSPrivacyAccessedAPICategoryDiskSpace', 'E174.1')
				: null,
		]
			.filter(Boolean)
			.join('\n') +
		`\n\t</array>\n` +
		`\t<key>NSPrivacyCollectedDataTypes</key>\n\t<array>\n` +
		types.map(dataEntry).join('\n') +
		`\n\t</array>\n</dict>\n</plist>`
	);
}

const PBX =
	`\t\t\tisa = XCBuildConfiguration;\n` +
	`\t\t\tbuildSettings = {\n` +
	`\t\t\t\tAPS_ENVIRONMENT = production;\n` +
	`\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n` +
	`\t\t\t};\n` +
	`\t\t\tname = Release;\n` +
	`\t\t};\n`;

const APP_DELEGATE =
	'isExcludedFromBackup = true\n.documentDirectory\n' +
	'WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "com.threkir.backgroundSync")';

const BACKGROUND_SYNC_DART =
	"const backgroundSyncTaskName = 'com.threkir.backgroundSync';\n" +
	'final registered = Platform.isIOS\n' +
	'    ? Workmanager().registerProcessingTask(backgroundSyncTaskName)\n' +
	'    : Workmanager().registerPeriodicTask(backgroundSyncTaskName);';

/// The smallest tree that satisfies every rule, so a mutation below is the
/// only difference between green and red.
/**
 * @param {Partial<EvaluateInput>} [overrides]
 * @returns {EvaluateInput}
 */
function baseline(overrides = {}) {
	return {
		infoPlist: new Map(
			/** @type {[string, unknown][]} */ ([
				['UIBackgroundModes', ['audio']],
				['BGTaskSchedulerPermittedIdentifiers', ['com.threkir.backgroundSync']],
				['ITSAppUsesNonExemptEncryption', false],
				['NSPhotoLibraryAddUsageDescription', 'Threkir saves cards.'],
			]),
		),
		entitlements: new Map([['com.apple.developer.aps-environment', APS_SUBSTITUTION]]),
		privacyManifest: fakeManifest(),
		appDelegate: APP_DELEGATE,
		pbxproj: PBX,
		backgroundSyncDart: BACKGROUND_SYNC_DART,
		dartSources: dart(
			'IosTextToSpeechAudioCategory.playback\n' + "import 'package:firebase_messaging/x.dart';",
		),
		swiftSources: swift(''),
		root: REPO_ROOT,
		...overrides,
	};
}

/**
 * The baseline's Info.plist with one key replaced. Built by copy-then-set
 * rather than by spreading into a `new Map([...])` literal, which infers the
 * added pair as an array rather than as an entry tuple.
 * @param {string} key
 * @param {unknown} value
 */
const plistWith = (key, value) => new Map(baseline().infoPlist).set(key, value);

test('the baseline passes, so every mutation below is the only cause of its failure', () => {
	const { errors } = evaluate(baseline());
	assert.deepEqual(errors, []);
});

test('a playback TTS session with no `audio` background mode fails', () => {
	const { errors } = evaluate(
		baseline({ infoPlist: plistWith('UIBackgroundModes', []) }),
	);
	assert.equal(errors.filter((e) => e.includes('`audio`')).length, 1);
});

test('deleting the playback call deletes the requirement with it', () => {
	const { errors, ok } = evaluate(
		baseline({
			infoPlist: plistWith('UIBackgroundModes', []),
			dartSources: dart("import 'package:firebase_messaging/x.dart';"),
		}),
	);
	assert.deepEqual(errors, []);
	assert.equal(
		ok.some((line) => line.includes('`audio`')),
		false,
	);
});

test('firebase_messaging with no aps-environment entitlement fails', () => {
	const { errors } = evaluate(baseline({ entitlements: new Map() }));
	assert.equal(errors.filter((e) => e.includes('aps-environment')).length, 1);
});

test('an aps-environment value that is neither a substitution nor a legal literal fails', () => {
	const { errors } = evaluate(
		baseline({ entitlements: new Map([['com.apple.developer.aps-environment', 'sandbox']]) }),
	);
	assert.equal(errors.filter((e) => e.includes('unusable')).length, 1);
});

test('a background mode nothing claims is an error, not a warning', () => {
	const { errors } = evaluate(
		baseline({ infoPlist: plistWith('UIBackgroundModes', ['audio', 'fetch']) }),
	);
	assert.equal(errors.filter((e) => e.includes('`fetch`')).length, 1);
});

test('the substitution obliges every Runner configuration to define APS_ENVIRONMENT', () => {
	const { errors } = evaluate(
		baseline({
			pbxproj: PBX.replace('\t\t\t\tAPS_ENVIRONMENT = production;\n', ''),
		}),
	);
	assert.equal(errors.filter((e) => e.includes('does not define')).length, 1);
});

test('a Release configuration minting sandbox tokens fails', () => {
	const { errors } = evaluate(
		baseline({ pbxproj: PBX.replace('production', 'development') }),
	);
	assert.equal(errors.filter((e) => e.includes('expected production')).length, 1);
});

test('a renamed background-sync identifier is caught in each of the three files', () => {
	/** @type {[string, Partial<EvaluateInput>][]} */
	const mutations = [
		[
			'background_sync.dart',
			{
				backgroundSyncDart: BACKGROUND_SYNC_DART.replace(
					'com.threkir.backgroundSync',
					'com.threkir.other',
				),
			},
		],
		['Info.plist', { infoPlist: plistWith('BGTaskSchedulerPermittedIdentifiers', ['other']) }],
		[
			'AppDelegate.swift',
			{
				appDelegate: APP_DELEGATE.replace(
					'com.threkir.backgroundSync',
					'com.threkir.other',
				),
			},
		],
	];
	for (const [what, mutated] of mutations) {
		const { errors } = evaluate(baseline(mutated));
		assert.ok(errors.length > 0, `mutating ${what} produced no error`);
	}
});

test('an iOS branch submitting the periodic task type fails', () => {
	const { errors } = evaluate(
		baseline({
			backgroundSyncDart: BACKGROUND_SYNC_DART.replace(
				'? Workmanager().registerProcessingTask(backgroundSyncTaskName)',
				'? Workmanager().registerPeriodicTask(backgroundSyncTaskName)',
			),
		}),
	);
	assert.equal(errors.filter((e) => e.includes('registerProcessingTask')).length, 1);
});

test('a missing CODE_SIGN_ENTITLEMENTS wiring fails', () => {
	const { errors } = evaluate({
		...baseline(),
		pbxproj: PBX.replace('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;', ''),
	});
	assert.equal(errors.filter((e) => e.includes('CODE_SIGN_ENTITLEMENTS')).length, 1);
});

test('a usage string naming a different product than CFBundleDisplayName fails', () => {
	const { errors } = evaluate(
		baseline({
			infoPlist: new Map(baseline().infoPlist)
				.set('CFBundleDisplayName', 'Threkir')
				.set('NSMotionUsageDescription', 'Run App counts your steps.'),
			dartSources: dart('import \'package:pedometer/pedometer.dart\';'),
		}),
	);
	assert.equal(errors.filter((e) => e.includes('does not name the app')).length, 1);
});

test('a required-reason API the manifest omits fails', () => {
	const { errors } = evaluate(baseline({ privacyManifest: fakeManifest({ apis: ['3EC4.1'] }) }));
	assert.equal(errors.filter((e) => e.includes('DiskSpace')).length, 1);
});

test('a collected data type the code implies but the manifest omits fails', () => {
	const { errors } = evaluate(
		baseline({ dartSources: dart("import 'package:health/health.dart';") }),
	);
	assert.equal(
		errors.filter((e) => e.includes('NSPrivacyCollectedDataTypeHealth')).length,
		1,
	);
});

test('claiming tracking fails the no-IDFA stance', () => {
	const { errors } = evaluate(baseline({ privacyManifest: fakeManifest({ tracking: true }) }));
	assert.equal(errors.filter((e) => e.includes('NSPrivacyTracking')).length, 1);
});

test('an absent PrivacyInfo.xcprivacy fails rather than skipping every check under it', () => {
	// The manifest reader is the only input whose absence used to be silent:
	// Info.plist and Runner.entitlements hard-fail, a null AppDelegate and a
	// null pbxproj each fall through to a named error — but a null manifest
	// skipped the whole block, so deleting the file took the unconditional
	// required-reason and collected-data checks with it and reported nothing.
	const { errors } = evaluate(baseline({ privacyManifest: null }));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /No PrivacyInfo\.xcprivacy was read/);
});

test('a NSPrivacyAccessedAPITypes that is not an array of dicts reports rather than throwing', () => {
	const { errors } = evaluate(
		baseline({
			privacyManifest:
				'<plist version="1.0">\n<dict>\n' +
				'\t<key>NSPrivacyTracking</key>\n\t<false/>\n' +
				'\t<key>NSPrivacyAccessedAPITypes</key>\n\t<string>see the wiki</string>\n' +
				'\t<key>NSPrivacyCollectedDataTypes</key>\n\t<array></array>\n' +
				'</dict>\n</plist>',
		}),
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /something other than an array of\s+dictionaries/);
});

test('a required-reason category whose reasons are not an array reports rather than throwing', () => {
	const { errors } = evaluate(
		baseline({
			privacyManifest: fakeManifest().replace(
				'<array><string>3EC4.1</string></array>',
				'<string>3EC4.1</string>',
			),
		}),
	);
	assert.equal(
		errors.filter((e) => e.includes('NSPrivacyAccessedAPITypeReasons that is not an array')).length,
		1,
	);
});

test('an empty Dart source set fails rather than passing vacuously', () => {
	const { errors } = evaluate(baseline({ dartSources: [] }));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /vacuously/);
});

test('an unparseable Info.plist fails rather than passing vacuously', () => {
	const { errors } = evaluate(baseline({ infoPlist: null }));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /blind/);
});

// --- decisions § 773 — the Swift half ---------------------------------------

// `walk` swallows a readdirSync failure, so moving CalendarBridge.swift out of
// ios/Runner/ made both EventKit rules stop enforcing and printed nothing: two
// fewer [OK] lines out of 43 and an exit code of 0. dartSources had this check
// from the day it was written; swiftSources did not.
test('an empty Swift source set fails rather than passing vacuously', () => {
	const { errors } = evaluate(baseline({ swiftSources: [] }));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /vacuously/);
	assert.match(errors[0], /NSCalendarsUsageDescription/);
});

test('the Swift rules the blindness check names are derived, not counted', () => {
	assert.deepEqual(swiftRuleKeys(), [
		...PURPOSE_STRINGS.filter((r) => r.source === 'swift').map((r) => r.key),
	]);
	assert.ok(swiftRuleKeys().length > 0, 'a rule reads Swift, so the check has a subject');
});

// The other half of the same hole: a Swift rule can fall silent while some
// OTHER Swift file keeps the tree non-empty, and the purpose string it obliged
// then stands with nothing claiming it. Every other derived declaration was
// read both ways; this one was not.
test('a usage string no rule claims is an error', () => {
	const { errors } = evaluate(
		baseline({ infoPlist: plistWith('NSCalendarsUsageDescription', 'Threkir files events.') }),
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /no rule in this script claims it/);
});

test('deleting the EventKit import obliges deleting the usage string with it', () => {
	const withEventKit = baseline({
		swiftSources: swift('import EventKit'),
		infoPlist: new Map(baseline().infoPlist)
			.set('NSCalendarsUsageDescription', 'Threkir files events.')
			.set('NSCalendarsWriteOnlyAccessUsageDescription', 'Threkir files events.'),
	});
	assert.deepEqual(evaluate(withEventKit).errors, []);
	const gone = evaluate({ ...withEventKit, swiftSources: swift('import UIKit') });
	assert.equal(gone.errors.length, 2);
	assert.ok(gone.errors.every((e) => /no rule in this script claims it/.test(e)));
});

test('a usage string named in FIXED_PLIST_KEYS is claimed by that admission', () => {
	assert.deepEqual(evaluate(baseline()).errors, []);
	const { errors } = evaluate(
		baseline({ infoPlist: plistWith('NSRemindersUsageDescription', 'Threkir reminds.') }),
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /NSRemindersUsageDescription/);
});

test('the committed ios/Runner tree is not empty, so the Swift rules have a subject', () => {
	assert.ok(collectSwiftSources().length > 0);
});

// --- the committed tree -----------------------------------------------------
// Last, so a stale plist reports as column drift rather than as a broken guard.

test('every derivation pattern still matches something in the committed tree', () => {
	const dartSources = collectDartSources();
	const swiftSources = [
		{ path: 'x', text: readFileSync(join(IOS_ROOT, 'Runner/CalendarBridge.swift'), 'utf-8') },
	];
	// A rule whose pattern matches nothing is not necessarily wrong — the
	// feature may be gone — but every rule in the table today has a live
	// consumer, and a pattern that silently stops matching is how a derived
	// guard turns permissive.
	for (const rule of [
		...BACKGROUND_MODES,
		...ENTITLEMENTS,
		...PURPOSE_STRINGS,
		...PRIVACY_API_TYPES,
		...PRIVACY_DATA_TYPES,
	]) {
		const sources = rule.source === 'swift' ? swiftSources : dartSources;
		assert.ok(
			sources.some((s) => rule.pattern.test(s.text)),
			`${rule.pattern} matched no ${rule.source} source — the rule is now inert`,
		);
	}
});

test('the committed iOS tree satisfies every rule', () => {
	const { errors } = evaluate({
		infoPlist: parsePlist(readFileSync(join(IOS_ROOT, 'Runner/Info.plist'), 'utf-8')),
		entitlements: parsePlist(readFileSync(join(IOS_ROOT, 'Runner/Runner.entitlements'), 'utf-8')),
		privacyManifest: readFileSync(join(IOS_ROOT, 'Runner/PrivacyInfo.xcprivacy'), 'utf-8'),
		appDelegate: readFileSync(join(IOS_ROOT, 'Runner/AppDelegate.swift'), 'utf-8'),
		pbxproj: readFileSync(join(IOS_ROOT, 'Runner.xcodeproj/project.pbxproj'), 'utf-8'),
		backgroundSyncDart: readFileSync(
			join(REPO_ROOT, 'apps/mobile_ios/lib/background_sync.dart'),
			'utf-8',
		),
		dartSources: collectDartSources(),
		swiftSources: [
			{ path: 'x', text: readFileSync(join(IOS_ROOT, 'Runner/CalendarBridge.swift'), 'utf-8') },
		],
	});
	assert.deepEqual(errors, []);
});
