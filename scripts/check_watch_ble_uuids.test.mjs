import { readFileSync } from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	DART_FILE,
	DOC_FILE,
	FIRMWARE_FILE,
	PAIRS,
	UNCLAIMED,
	checkAdvertisedUuid,
	checkDoc,
	compareTables,
	parseDart,
	parseFirmware,
} from './check_watch_ble_uuids.mjs';

/**
 * A GATT row or a Dart constant as the fixtures write it: `[name, uuid]`.
 * @typedef {readonly [string, string]} Row
 */

/** @param {string | number} n */
const U = (n) => `d1f6a7e${n}-5b2c-4e9a-9c3d-1a2b3c4d5e6f`;

// The shape the firmware declares, minimal but structurally faithful — the
// attribute macro, the extra attribute keys, the doc comment between rows.
/** @param {readonly Row[]} rows */
function fakeFirmware(rows) {
	const body = rows
		.map(
			([name, uuid]) =>
				`        /// Doc comment that must not be mistaken for the field name.\n` +
				`        #[characteristic(\n` +
				`            uuid = "${uuid}",\n` +
				`            write,\n` +
				`            notify,\n` +
				`            security = "justworks"\n` +
				`        )]\n` +
				`        ${name}: Vec<u8, CAP>,`,
		)
		.join('\n');
	return (
		`    #[nrf_softdevice::gatt_service(uuid = "${U(0)}")]\n` +
		`    pub struct LinkService {\n${body}\n    }\n`
	);
}

/** @param {readonly Row[]} consts */
function fakeDart(consts) {
	return (
		`class ReactiveBleWatchTransport implements WatchBleTransport {\n` +
		`  static final Uuid serviceUuid =\n      Uuid.parse('${U(0)}');\n` +
		consts
			.map(([n, u]) => `  static final Uuid ${n} =\n      Uuid.parse('${u}');`)
			.join('\n') +
		`\n}\n`
	);
}

// Every firmware row the phone claims, aligned. The baseline the mutations
// below diverge from.
/** @type {readonly Row[]} */
const ALIGNED_ROWS = [
	['frame', U(1)],
	['run_manifest', U(2)],
	['run_chunk', U(3)],
	['settings', U(4)],
	['course', U(5)],
	['workout', U(6)],
	['screens', U(7)],
	['roadbook', U(8)],
	['push_status', U(9)],
];
/** @type {readonly Row[]} */
const ALIGNED_CONSTS = [
	['frameCharUuid', U(1)],
	['manifestCharUuid', U(2)],
	['chunkCharUuid', U(3)],
	['settingsCharUuid', U(4)],
	['courseCharUuid', U(5)],
	['workoutCharUuid', U(6)],
	['screensCharUuid', U(7)],
	['roadbookCharUuid', U(8)],
	['pushStatusCharUuid', U(9)],
];

/**
 * @param {readonly Row[]} rows
 * @param {readonly Row[]} consts
 * @param {typeof PAIRS} [pairs]
 * @param {readonly string[]} [unclaimed]
 */
const verdict = (rows, consts, pairs, unclaimed) =>
	compareTables(
		parseFirmware(fakeFirmware(rows)),
		parseDart(fakeDart(consts)),
		pairs,
		unclaimed,
	);

test('the real firmware table and the real phone client agree', () => {
	const { errors, ok } = compareTables(
		parseFirmware(readFileSync(FIRMWARE_FILE, 'utf-8')),
		parseDart(readFileSync(DART_FILE, 'utf-8')),
	);
	assert.deepEqual(errors, []);
	assert.equal(ok.length, PAIRS.length + UNCLAIMED.length);
});

test('the firmware parse reads names off the fields, not the attribute order', () => {
	// Reversed declaration order: a positional parse would pair every row with
	// the wrong name, which is the class of mistake § 410 is about.
	const parsed = parseFirmware(fakeFirmware([...ALIGNED_ROWS].reverse()));
	assert.equal(parsed.get('run_manifest'), U(2));
	assert.equal(parsed.get('screens'), U(7));
	assert.equal(parsed.get('service'), U(0));
});

test('an aligned table passes with no errors and no warnings', () => {
	const { errors, warnings, ok } = verdict(ALIGNED_ROWS, ALIGNED_CONSTS);
	assert.deepEqual(errors, []);
	assert.deepEqual(warnings, []);
	assert.equal(ok.length, PAIRS.length + UNCLAIMED.length);
});

test('the § 410 one-row shift fails and names the characteristic misread', () => {
	// Exactly the shipped bug: manifest aimed at `frame`, chunk at
	// `run_manifest`, everything from `settings` on still aligned.
	const { errors } = verdict(ALIGNED_ROWS, [
		['frameCharUuid', U(1)],
		['manifestCharUuid', U(1)],
		['chunkCharUuid', U(2)],
		...ALIGNED_CONSTS.slice(3),
	]);
	assert.equal(errors.length, 2);
	assert.match(errors[0], /drift on "run_manifest"/);
	assert.match(errors[0], /this is the firmware's "frame" characteristic/);
	assert.match(errors[0], new RegExp(`Fix: set manifestCharUuid to ${U(2)}`));
	assert.match(errors[1], /drift on "run_chunk"/);
	assert.match(errors[1], /the firmware's "run_manifest" characteristic/);
});

// The production UNCLAIMED list emptied out when the phone claimed `frame`, so
// these two drive the rule with an explicit table. It has to keep working: the
// next characteristic the firmware adds ahead of the phone lands there, and a
// constant misaimed at it is the § 410 shape all over again.
test('an unclaimed firmware row the phone leaves alone passes', () => {
	const { errors, warnings, ok } = verdict(
		[...ALIGNED_ROWS, ['telemetry', U('a')]],
		ALIGNED_CONSTS,
		PAIRS,
		['telemetry'],
	);
	assert.deepEqual(errors, []);
	assert.deepEqual(warnings, []);
	assert.equal(ok.length, PAIRS.length + 1);
});

test('an unclaimed firmware row a Dart constant points at fails', () => {
	// Named rather than sliced by index: the aligned table grows every time
	// the watch does, and a positional edit here silently drops a pair from
	// the fixture — which is the very failure the guard exists to catch.
	/** @type {readonly Row[]} */
	const misaimed = ALIGNED_CONSTS.map(([n, u]) =>
		n === 'roadbookCharUuid' ? [n, U('a')] : [n, u],
	);
	const { errors } = verdict(
		[...ALIGNED_ROWS, ['telemetry', U('a')]],
		misaimed,
		PAIRS,
		['telemetry'],
	);
	assert.equal(errors.length, 2);
	assert.match(errors[0], /drift on "roadbook"/);
	assert.match(errors[1], /points roadbookCharUuid at .* "telemetry"/s);
});

test('a UUID belonging to no characteristic at all says so', () => {
	const { errors } = verdict(ALIGNED_ROWS, [
		ALIGNED_CONSTS[0],
		['manifestCharUuid', 'deadbeef-0000-0000-0000-000000000000'],
		...ALIGNED_CONSTS.slice(2),
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /not any firmware characteristic/);
});

test('a renamed firmware row fails rather than silently dropping out', () => {
	/** @type {readonly Row[]} */
	const renamed = ALIGNED_ROWS.map(([n, u]) =>
		n === 'course' ? ['course_v2', u] : [n, u],
	);
	const { errors, warnings } = verdict(renamed, ALIGNED_CONSTS);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /firmware row "course" not found/);
	// And the new name shows up as the unpaired row it now is.
	assert.equal(warnings.length, 1);
	assert.match(warnings[0], /characteristic "course_v2"/);
});

test('a new firmware characteristic warns but does not fail the build', () => {
	const { errors, warnings } = verdict(
		[...ALIGNED_ROWS, ['telemetry', U(8)]],
		ALIGNED_CONSTS,
	);
	assert.deepEqual(errors, []);
	assert.equal(warnings.length, 1);
	assert.match(warnings[0], /characteristic "telemetry"/);
	assert.match(warnings[0], /Fine if the phone has no use for it/);
});

test('a Dart constant nothing pairs against fails rather than going unchecked', () => {
	const { errors } = verdict(
		[...ALIGNED_ROWS, ['telemetry', U(8)]],
		[...ALIGNED_CONSTS, ['telemetryCharUuid', U(8)]],
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /"telemetryCharUuid".*is not in PAIRS/s);
});

test('a missing Dart constant fails', () => {
	const { errors } = verdict(ALIGNED_ROWS, [
		ALIGNED_CONSTS[0],
		...ALIGNED_CONSTS.slice(2),
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /Dart constant "manifestCharUuid" not found/);
});

test('a parse that reads nothing fails loudly instead of passing vacuously', () => {
	// The failure mode that would make this guard worthless: either file
	// refactored past the regex, every pair silently absent, exit 0.
	const blind = compareTables(parseFirmware(''), parseDart(''));
	assert.ok(blind.errors.length > 2);
	assert.match(blind.errors[0], /Parsed no GATT rows/);
	assert.match(blind.errors[1], /Parsed no Uuid constants/);
});

// ───────────── decisions § 773 — both parsers read comments ─────────────

// The service match was not global, so the first `gatt_service(uuid = "…")`
// ANYWHERE in ble.rs won — and the module doc is above the declaration.
test('a UUID quoted in the firmware module doc does not answer for the declaration', () => {
	const src =
		`//! The service is \`gatt_service(uuid = "aaaaaaaa-0000-0000-0000-000000000000")\`.\n` +
		fakeFirmware(ALIGNED_ROWS);
	assert.equal(parseFirmware(src).get('service'), U(0));
});

// The characteristic scan is last-writer-wins, so a table preserved in a
// TRAILING comment overwrote every live row.
test('a table preserved in a trailing firmware comment does not overwrite the live one', () => {
	const shifted = ALIGNED_ROWS.map(([name], i) => /** @type {Row} */ ([name, U(i + 2)]));
	const src =
		fakeFirmware(shifted) +
		'\n// Previous layout, kept while the migration lands:\n' +
		fakeFirmware(ALIGNED_ROWS)
			.split('\n')
			.map((l) => `// ${l}`)
			.join('\n');
	const parsed = parseFirmware(src);
	assert.equal(parsed.get('frame'), U(2));
	assert.equal(parsed.get('run_manifest'), U(3));
});

// The whole point: this is § 410's one-row shift, and before the fix it
// produced zero errors and a full set of [OK] lines.
test('a shifted firmware table with the old one in a comment is caught, not certified', () => {
	const shifted = ALIGNED_ROWS.map(([name], i) => /** @type {Row} */ ([name, U(i + 2)]));
	const src =
		fakeFirmware(shifted) +
		'\n' +
		fakeFirmware(ALIGNED_ROWS)
			.split('\n')
			.map((l) => `// ${l}`)
			.join('\n');
	const { errors, ok } = compareTables(parseFirmware(src), parseDart(fakeDart(ALIGNED_CONSTS)));
	assert.ok(errors.length > 0, 'a one-row shift must not read as agreement');
	assert.ok(errors.some((e) => /UUID drift on "frame"/.test(e)));
	assert.equal(ok.length, 1, 'only the service, whose UUID did not move, still agrees');
});

// The Dart window is 40 characters, which crosses the `//` of a commented-out
// declaration and reads its initialiser as live.
test('a commented-out Dart constant is not read as a live one', () => {
	const src =
		`class X {\n` +
		`  // static final Uuid frameCharUuid =\n` +
		`  //     Uuid.parse('${U(1)}');\n` +
		`  static final Uuid frameCharUuid =\n      Uuid.parse('${U('f')}');\n` +
		`}\n`;
	assert.deepEqual([...parseDart(src)], [['frameCharUuid', U('f')]]);
});

test('a UUID inside a Dart doc comment is not a constant', () => {
	const src =
		`/// The table mirrors the firmware: \`..e1\` frame.\n` +
		`/// static final Uuid frameCharUuid = Uuid.parse('${U(1)}');\n` +
		`class X {}\n`;
	assert.deepEqual([...parseDart(src)], []);
});

// Which of two GATT tables the phone talks to is not something this parser can
// know, and the first-match-wins read was answering anyway.
test('a second gatt_service declaration throws rather than picking one', () => {
	assert.throws(
		() => parseFirmware(fakeFirmware(ALIGNED_ROWS) + fakeFirmware(ALIGNED_ROWS)),
		/2 gatt_service declarations/,
	);
});

// Measured while fixing it: the committed files carry no UUID in a comment, so
// the misread was latent — a measurement rather than a claim.
test('blanking comments changes nothing about the committed tables', () => {
	const fw = parseFirmware(readFileSync(FIRMWARE_FILE, 'utf-8'));
	const dt = parseDart(readFileSync(DART_FILE, 'utf-8'));
	assert.equal(fw.size, PAIRS.length + UNCLAIMED.length);
	assert.equal(dt.size, PAIRS.length);
	assert.deepEqual(compareTables(fw, dt).errors, []);
});

test('checkDoc catches a count claim the firmware table has outgrown', () => {
	const firmware = new Map([
		['service', U(0)],
		['frame', U(1)],
		['run_manifest', U(2)],
		['run_chunk', U(3)],
	]);
	const stale =
		'What shipped is two on one service: `frame`, `run_manifest`, `run_chunk`.';
	const staleResult = checkDoc(firmware, stale);
	assert.equal(staleResult.errors.length, 1);
	assert.match(staleResult.errors[0], /says the GATT service carries "two"/);

	const fixed = stale.replace('is two on', 'is three on');
	assert.deepEqual(checkDoc(firmware, fixed).errors, []);
	assert.deepEqual(checkDoc(firmware, fixed.replace('is three', 'is 3')).errors, []);
});

test('checkDoc reports a row the doc never names', () => {
	const firmware = new Map([['service', U(0)], ['frame', U(1)], ['roadbook', U(8)]]);
	const doc = 'What shipped is two on one service: `frame`.';
	const { errors } = checkDoc(firmware, doc);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /never names the "roadbook" characteristic/);
});

test('checkDoc fails rather than passes when its anchor phrase is gone', () => {
	const firmware = new Map([['service', U(0)], ['frame', U(1)]]);
	const { errors } = checkDoc(firmware, 'The service has some characteristics: `frame`.');
	assert.equal(errors.length, 1);
	assert.match(errors[0], /no longer carries the .* count claim/);
});

test('the committed doc agrees with the committed GATT table', () => {
	const firmware = parseFirmware(readFileSync(FIRMWARE_FILE, 'utf-8'));
	assert.deepEqual(checkDoc(firmware, readFileSync(DOC_FILE, 'utf-8')).errors, []);
});

test('checkAdvertisedUuid catches a scan-response UUID that has drifted', () => {
	const src = 'const LINK_SERVICE_UUID: u128 = 0xd1f6a7e1_5b2c_4e9a_9c3d_1a2b3c4d5e6f;';
	const { errors } = checkAdvertisedUuid(src, 'd1f6a7e0-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
	assert.equal(errors.length, 1);
	assert.match(errors[0], /never finds the watch at all/);
	const aligned = src.replace('a7e1', 'a7e0');
	assert.deepEqual(
		checkAdvertisedUuid(aligned, 'd1f6a7e0-5b2c-4e9a-9c3d-1a2b3c4d5e6f').errors,
		[],
	);
});

test('checkAdvertisedUuid fails rather than passes when the constant is gone', () => {
	const { errors } = checkAdvertisedUuid('// nothing here', 'd1f6a7e0-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
	assert.equal(errors.length, 1);
	assert.match(errors[0], /is gone from ble\.rs/);
});

test('the committed scan-response UUID matches the committed service attribute', () => {
	const src = readFileSync(FIRMWARE_FILE, 'utf-8');
	const firmware = parseFirmware(src);
	assert.deepEqual(checkAdvertisedUuid(src, firmware.get('service')).errors, []);
});
