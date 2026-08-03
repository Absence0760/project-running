#!/usr/bin/env node
// Guardrail: verify the phone's BLE characteristic UUIDs still match the
// custom watch's GATT table, by reading BOTH sources and comparing them.
//
// Why this exists: decisions.md § 410. The phone's UUIDs had drifted one
// position against the firmware — it read the run manifest from `..e1` (the
// live-status `frame`) and wrote chunk requests to `..e2` (`run_manifest`,
// read+notify, no write property), so watch→phone run sync could not have
// worked at all. Nothing caught it: that path has never run on hardware and
// cannot be simulated (§ 210). The fix added a Dart test that TRANSCRIBES the
// firmware table, which is a snapshot — move a UUID in `ble.rs` and the
// transcription is silently wrong again, exactly as before. This script is the
// enforcement § 410 said was still owed: it parses the firmware's declaration
// and the Dart client's constants and fails on disagreement.
//
// The firmware is the source of truth for its own GATT table. Only the
// name→name pairing below lives here; every UUID is read from a file.
//
// Run: `node scripts/check_watch_ble_uuids.mjs`
// CI:  the `watch-ble-uuids` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list — a guard nothing runs enforces
//      nothing, which is what this script was for its first day.
// Unit tests: `node --test scripts/check_watch_ble_uuids.test.mjs`

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Overridable so the whole script — exit code and all — can be pointed at
// mutated copies of the two files, which is how a guard is shown to fail.
export const FIRMWARE_FILE =
	process.env.WATCH_BLE_RS ??
	join(REPO_ROOT, 'apps/custom_watch/app/src/tasks/ble.rs');
export const DART_FILE =
	process.env.WATCH_BLE_DART ??
	join(REPO_ROOT, 'apps/mobile_android/lib/reactive_ble_watch_transport.dart');

// firmware GATT field name → the Dart constant that must carry the same UUID.
// `service` is the synthetic name for the `gatt_service` attribute itself.
//
// Every row the firmware declares is claimed. `frame` — the per-second
// live-status notify — was the last holdout: the phone read status over the
// dev TCP link only (`sim_watch_link.dart`), so § 447's forwarder had no BLE
// feed. `ReactiveBleWatchFrameSource` now subscribes to it on its own
// connection, so it is a checked pair like the rest.
export const PAIRS = [
	{ firmware: 'service', dart: 'serviceUuid' },
	{ firmware: 'frame', dart: 'frameCharUuid' },
	{ firmware: 'run_manifest', dart: 'manifestCharUuid' },
	{ firmware: 'run_chunk', dart: 'chunkCharUuid' },
	{ firmware: 'settings', dart: 'settingsCharUuid' },
	{ firmware: 'course', dart: 'courseCharUuid' },
	{ firmware: 'workout', dart: 'workoutCharUuid' },
	{ firmware: 'screens', dart: 'screensCharUuid' },
	{ firmware: 'roadbook', dart: 'roadbookCharUuid' },
	{ firmware: 'push_status', dart: 'pushStatusCharUuid' },
];

// Firmware rows the Dart client is allowed to leave unclaimed. Each still has
// to be absent from the Dart side entirely: an unclaimed row whose UUID shows
// up under some OTHER Dart constant is precisely the § 410 bug — the client
// pointing at the wrong characteristic — so that IS a hard failure.
//
// Empty today: the phone consumes all nine characteristics. The rule stays
// because the watch is free to grow its table ahead of the phone, and the day
// it does, listing the new row here silences the "no phone counterpart"
// warning WITHOUT giving up the misaimed-constant check.
export const UNCLAIMED = [];

// `#[nrf_softdevice::gatt_service(uuid = "…")] pub struct LinkService { … }`,
// then one `#[characteristic(uuid = "…", …)] <name>: <ty>` per row. Parsed by
// pairing each uuid attribute with the identifier that follows it, so a
// reordered table or an inserted row is read correctly rather than positionally.
export function parseFirmware(src) {
	const service = src.match(
		/gatt_service\s*\(\s*uuid\s*=\s*"([0-9a-fA-F-]+)"\s*\)/,
	);
	const out = new Map();
	if (service) out.set('service', service[1].toLowerCase());

	const charRe =
		/#\[\s*characteristic\s*\(([\s\S]*?)\)\s*\]([\s\S]*?)([a-z_][a-z0-9_]*)\s*:/g;
	let m;
	while ((m = charRe.exec(src)) !== null) {
		const uuid = m[1].match(/uuid\s*=\s*"([0-9a-fA-F-]+)"/);
		if (!uuid) continue;
		out.set(m[3], uuid[1].toLowerCase());
	}
	return out;
}

// `static final Uuid <name> = Uuid.parse('…');` — the newline between the
// declaration and the initialiser is why this can't be a one-line regex.
export function parseDart(src) {
	const out = new Map();
	const re =
		/static\s+final\s+Uuid\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[\s\S]{0,40}?Uuid\.parse\(\s*'([0-9a-fA-F-]+)'\s*\)/g;
	let m;
	while ((m = re.exec(src)) !== null) out.set(m[1], m[2].toLowerCase());
	return out;
}

// The whole verdict as data, so the tests can assert on it without capturing
// stdout. `errors` fails the build; `warnings` do not. `pairs` / `unclaimed`
// are overridable for the same reason the two file paths are: a rule only
// exercised by the production tables stops being exercised the moment those
// tables stop containing an example of it, which is exactly what happened to
// `unclaimed` when the phone claimed `frame`.
export function compareTables(
	firmware,
	dart,
	pairs = PAIRS,
	unclaimed = UNCLAIMED,
) {
	const errors = [];
	const warnings = [];
	const ok = [];

	if (firmware.size === 0) {
		errors.push(
			`Parsed no GATT rows out of the firmware file.\n` +
				`  The declaration moved or changed shape; this guard is blind until ` +
				`parseFirmware() is taught the new form.`,
		);
	}
	if (dart.size === 0) {
		errors.push(
			`Parsed no Uuid constants out of the Dart file.\n` +
				`  The client's constants moved or changed shape; this guard is blind ` +
				`until parseDart() is taught the new form.`,
		);
	}

	for (const { firmware: fwName, dart: dartName } of pairs) {
		const fwUuid = firmware.get(fwName);
		const dartUuid = dart.get(dartName);

		if (!fwUuid) {
			errors.push(
				`firmware row "${fwName}" not found in ble.rs, but the phone claims it ` +
					`as ${dartName}.\n` +
					`  Either the row was renamed / removed (update the PAIRS entry and ` +
					`the Dart constant) or the parse broke.`,
			);
			continue;
		}
		if (!dartUuid) {
			errors.push(
				`Dart constant "${dartName}" not found in ` +
					`reactive_ble_watch_transport.dart (firmware row "${fwName}" = ` +
					`${fwUuid}).`,
			);
			continue;
		}
		if (fwUuid !== dartUuid) {
			const misread = [...firmware].find(([, u]) => u === dartUuid);
			const label = `  phone (${dartName}):`;
			errors.push(
				`UUID drift on "${fwName}":\n` +
					`  firmware (ble.rs, source of truth): ${fwUuid}\n` +
					`${label.padEnd(38)}${dartUuid}` +
					(misread
						? `  <- this is the firmware's "${misread[0]}" characteristic`
						: '  <- not any firmware characteristic') +
					`\n  Fix: set ${dartName} to ${fwUuid}.`,
			);
			continue;
		}
		ok.push(`${fwName} = ${dartName} (${fwUuid})`);
	}

	// A firmware row nobody claims is fine; a firmware row nobody claims whose
	// UUID the Dart side nonetheless references under another name is the bug.
	for (const name of unclaimed) {
		const uuid = firmware.get(name);
		if (!uuid) {
			warnings.push(
				`firmware row "${name}" is listed as deliberately unclaimed but no ` +
					`longer exists in ble.rs — drop it from UNCLAIMED.`,
			);
			continue;
		}
		const claimedAs = [...dart].find(([, u]) => u === uuid);
		if (claimedAs) {
			errors.push(
				`the phone points ${claimedAs[0]} at ${uuid}, which is the firmware's ` +
					`"${name}" characteristic — a row this client does not consume.\n` +
					`  This is the § 410 shape: a constant aimed one row off. Check the ` +
					`whole table against ble.rs.`,
			);
			continue;
		}
		ok.push(`${name} = (unclaimed by the phone, as intended)`);
	}

	// A NEW firmware characteristic with no phone counterpart is a warning, not
	// a failure: the watch must stay free to grow its GATT table without a
	// mobile change, and an unconsumed characteristic breaks nothing (the client
	// discovers by UUID, not by index — that is what made § 410's shift a bug
	// rather than a mere mismatch). It is surfaced so nobody has to notice the
	// firmware grew a row on their own.
	const claimed = new Set([...pairs.map((p) => p.firmware), ...unclaimed]);
	for (const [name, uuid] of firmware) {
		if (claimed.has(name)) continue;
		warnings.push(
			`firmware has a characteristic "${name}" (${uuid}) with no phone ` +
				`counterpart.\n` +
				`  Fine if the phone has no use for it. When it grows one, add a Dart ` +
				`constant and a PAIRS entry; to silence this permanently, add it to ` +
				`UNCLAIMED.`,
		);
	}

	// A Dart constant pointing at a UUID nothing checks against the firmware.
	for (const [name, uuid] of dart) {
		if (pairs.some((p) => p.dart === name)) continue;
		errors.push(
			`Dart constant "${name}" (${uuid}) is not in PAIRS, so nothing checks it ` +
				`against the firmware.\n` +
				`  Add a PAIRS entry naming the ble.rs row it targets.`,
		);
	}

	return { errors, warnings, ok };
}

function main() {
	const { errors, warnings, ok } = compareTables(
		parseFirmware(readFileSync(FIRMWARE_FILE, 'utf-8')),
		parseDart(readFileSync(DART_FILE, 'utf-8')),
	);

	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of warnings) console.warn(`[WARN] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);

	if (errors.length > 0) {
		console.error(
			`\n${errors.length} mismatch(es) between the watch GATT table and the ` +
				`phone client.\n` +
				`  firmware: ${FIRMWARE_FILE}\n` +
				`  phone:    ${DART_FILE}\n` +
				`ble.rs is the source of truth for its own table (decisions.md § 410); ` +
				`align the Dart side to it.`,
		);
		return 1;
	}
	console.log(
		`\nWatch GATT table and phone client agree on ${ok.length} UUID(s)` +
			(warnings.length ? `, ${warnings.length} warning(s)` : '') +
			'.',
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
