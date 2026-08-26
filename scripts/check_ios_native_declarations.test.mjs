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
	evaluate,
	parseBuildConfigurations,
	parsePlist,
	stripWholeLineComments,
} from './check_ios_native_declarations.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// --- the parser -------------------------------------------------------------

test('parsePlist reads scalars, arrays and booleans out of a dict', () => {
	const dict = parsePlist(`<?xml version="1.0" encoding="UTF-8"?>
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
	const dict = parsePlist(`<plist version="1.0">
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
	const dict = parsePlist(`<plist version="1.0">
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
	const dict = parsePlist(`<plist version="1.0">
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

const dart = (text) => [{ path: join(REPO_ROOT, 'apps/mobile_ios/lib/x.dart'), text }];
const swift = (text) => [{ path: join(IOS_ROOT, 'Runner/X.swift'), text }];

/// A structurally faithful PrivacyInfo.xcprivacy carrying exactly the entries
/// the baseline's sources oblige — the two fixed API categories, the two fixed
/// data types, and the no-tracking stance.
function fakeManifest({ apis = ['3EC4.1', 'E174.1'], data = null, tracking = false } = {}) {
	const apiEntry = (type, reason) =>
		`\t\t<dict>\n\t\t\t<key>NSPrivacyAccessedAPIType</key>\n` +
		`\t\t\t<string>${type}</string>\n` +
		`\t\t\t<key>NSPrivacyAccessedAPITypeReasons</key>\n` +
		`\t\t\t<array><string>${reason}</string></array>\n\t\t</dict>`;
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

/// The smallest tree that satisfies every rule, so a mutation below is the
/// only difference between green and red.
function baseline(overrides = {}) {
	return {
		infoPlist: new Map([
			['UIBackgroundModes', ['audio']],
			['BGTaskSchedulerPermittedIdentifiers', ['com.threkir.backgroundSync']],
			['ITSAppUsesNonExemptEncryption', false],
			['NSPhotoLibraryAddUsageDescription', 'Threkir saves cards.'],
		]),
		entitlements: new Map([['com.apple.developer.aps-environment', APS_SUBSTITUTION]]),
		privacyManifest: fakeManifest(),
		appDelegate:
			'isExcludedFromBackup = true\n.documentDirectory\n' +
			'WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "com.threkir.backgroundSync")',
		pbxproj: PBX,
		backgroundSyncDart:
			"const backgroundSyncTaskName = 'com.threkir.backgroundSync';\n" +
			'final registered = Platform.isIOS\n' +
			'    ? Workmanager().registerProcessingTask(backgroundSyncTaskName)\n' +
			'    : Workmanager().registerPeriodicTask(backgroundSyncTaskName);',
		dartSources: dart(
			'IosTextToSpeechAudioCategory.playback\n' + "import 'package:firebase_messaging/x.dart';",
		),
		swiftSources: swift(''),
		root: REPO_ROOT,
		...overrides,
	};
}

test('the baseline passes, so every mutation below is the only cause of its failure', () => {
	const { errors } = evaluate(baseline());
	assert.deepEqual(errors, []);
});

test('a playback TTS session with no `audio` background mode fails', () => {
	const { errors } = evaluate(
		baseline({ infoPlist: new Map([...baseline().infoPlist, ['UIBackgroundModes', []]]) }),
	);
	assert.equal(errors.filter((e) => e.includes('`audio`')).length, 1);
});

test('deleting the playback call deletes the requirement with it', () => {
	const { errors, ok } = evaluate(
		baseline({
			infoPlist: new Map([...baseline().infoPlist, ['UIBackgroundModes', []]]),
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
		baseline({ infoPlist: new Map([...baseline().infoPlist, ['UIBackgroundModes', ['audio', 'fetch']]]) }),
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
	for (const [field, mutated] of [
		[
			'backgroundSyncDart',
			baseline().backgroundSyncDart.replace('com.threkir.backgroundSync', 'com.threkir.other'),
		],
		[
			'infoPlist',
			new Map([...baseline().infoPlist, ['BGTaskSchedulerPermittedIdentifiers', ['other']]]),
		],
		[
			'appDelegate',
			baseline().appDelegate.replace('com.threkir.backgroundSync', 'com.threkir.other'),
		],
	]) {
		const { errors } = evaluate(baseline({ [field]: mutated }));
		assert.ok(errors.length > 0, `mutating ${field} produced no error`);
	}
});

test('an iOS branch submitting the periodic task type fails', () => {
	const { errors } = evaluate(
		baseline({
			backgroundSyncDart: baseline().backgroundSyncDart.replace(
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
			infoPlist: new Map([
				...baseline().infoPlist,
				['CFBundleDisplayName', 'Threkir'],
				['NSMotionUsageDescription', 'Run App counts your steps.'],
			]),
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
