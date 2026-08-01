import { readFileSync } from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	DART_FILE,
	FIRMWARE_FILE,
	PAIRS,
	UNCLAIMED,
	compareTables,
	parseDart,
	parseFirmware,
} from './check_watch_ble_uuids.mjs';

const U = (n) => `d1f6a7e${n}-5b2c-4e9a-9c3d-1a2b3c4d5e6f`;

// The shape the firmware declares, minimal but structurally faithful — the
// attribute macro, the extra attribute keys, the doc comment between rows.
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
const ALIGNED_ROWS = [
	['frame', U(1)],
	['run_manifest', U(2)],
	['run_chunk', U(3)],
	['settings', U(4)],
	['course', U(5)],
	['workout', U(6)],
	['screens', U(7)],
];
const ALIGNED_CONSTS = [
	['manifestCharUuid', U(2)],
	['chunkCharUuid', U(3)],
	['settingsCharUuid', U(4)],
	['courseCharUuid', U(5)],
	['workoutCharUuid', U(6)],
	['screensCharUuid', U(7)],
];

const verdict = (rows, consts) =>
	compareTables(parseFirmware(fakeFirmware(rows)), parseDart(fakeDart(consts)));

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
		['manifestCharUuid', U(1)],
		['chunkCharUuid', U(2)],
		...ALIGNED_CONSTS.slice(2),
	]);
	assert.equal(errors.length, 3);
	assert.match(errors[0], /drift on "run_manifest"/);
	assert.match(errors[0], /this is the firmware's "frame" characteristic/);
	assert.match(errors[0], new RegExp(`Fix: set manifestCharUuid to ${U(2)}`));
	assert.match(errors[1], /drift on "run_chunk"/);
	assert.match(errors[1], /the firmware's "run_manifest" characteristic/);
	// The unclaimed-row rule catches the same bug from the other direction, so
	// the report names it twice rather than leaving it to be inferred.
	assert.match(errors[2], /points manifestCharUuid at .* "frame"/s);
});

test('a UUID belonging to no characteristic at all says so', () => {
	const { errors } = verdict(ALIGNED_ROWS, [
		['manifestCharUuid', 'deadbeef-0000-0000-0000-000000000000'],
		...ALIGNED_CONSTS.slice(1),
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /not any firmware characteristic/);
});

test('a renamed firmware row fails rather than silently dropping out', () => {
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
	const { errors } = verdict(ALIGNED_ROWS, ALIGNED_CONSTS.slice(1));
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
