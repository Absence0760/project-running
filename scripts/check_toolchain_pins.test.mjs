import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	LOCKFILE,
	WORKFLOW_DIR,
	checkAll,
	checkDefmtPrint,
	checkFlutter,
	checkMelos,
	parseDefmtPrint,
	parseLockedVersion,
	parseMelosActivations,
	parseWorkflow,
	resolveVersion,
} from './check_toolchain_pins.mjs';

/// A firmware-sim job shaped like the real one: an actions/cache step whose
/// key embeds the version, then the `command -v || cargo install` line.
function defmtWorkflow({ install, key = install }) {
	return (
		`name: Fake\njobs:\n  sim:\n    steps:\n` +
		`      - name: Cache defmt-print\n` +
		`        uses: actions/cache@abc\n` +
		`        with:\n` +
		`          path: ~/.cargo/bin/defmt-print\n` +
		(key === null ? '' : `          key: defmt-print-${key}-\${{ runner.os }}\n`) +
		`      - name: Install defmt-print\n` +
		`        run: command -v defmt-print || cargo install defmt-print --locked` +
		(install === null ? '' : ` --version ${install}`) +
		`\n`
	);
}

/// A pubspec.lock fragment shaped like the real one: two-space package keys,
/// a nested description block, the version last.
function fakeLock(melosVersion) {
	return (
		`packages:\n` +
		`  matcher:\n` +
		`    dependency: transitive\n` +
		`    description:\n` +
		`      name: matcher\n` +
		`    source: hosted\n` +
		`    version: "0.12.16"\n` +
		(melosVersion === null
			? ''
			: `  melos:\n` +
				`    dependency: "direct dev"\n` +
				`    description:\n` +
				`      name: melos\n` +
				`      sha256: "5fc1a858"\n` +
				`    source: hosted\n` +
				`    version: "${melosVersion}"\n`) +
		`  meta:\n` +
		`    dependency: transitive\n` +
		`    version: "1.16.0"\n`
	);
}

/// A workflow that activates melos, optionally with a version.
function melosWorkflow(version) {
	return (
		`name: Fake\njobs:\n  build:\n    steps:\n` +
		`      - run: dart pub global activate melos${version === null ? '' : ` ${version}`}\n` +
		`      - run: melos bootstrap\n`
	);
}

const SHA = 'subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2';

/// A workflow with one flutter-action step, shaped like the real ones:
/// a top-level `env:` block carrying an unrelated key alongside the pin,
/// and the step nested two levels down inside a job.
function workflow({ declared, pin, extraStep = '' }) {
	const env =
		`env:\n` +
		`  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true\n` +
		(declared === null ? '' : `  FLUTTER_VERSION: "${declared}"\n`);
	const step =
		`      - uses: ${SHA} # v2\n` +
		`        with:\n` +
		`          channel: stable\n` +
		(pin === null ? '' : `          flutter-version: ${pin}\n`);
	return (
		`name: Fake\n\non:\n  push:\n\n${env}\njobs:\n  build:\n    steps:\n` +
		`      - uses: actions/checkout@abc\n` +
		step +
		extraStep +
		`      - run: flutter build\n`
	);
}

test('parseWorkflow finds the top-level env pin and each step version', () => {
	const parsed = parseWorkflow(
		workflow({ declared: '3.47.0', pin: '${{ env.FLUTTER_VERSION }}' }),
	);
	assert.equal(parsed.declared, '3.47.0');
	assert.equal(parsed.steps.length, 1);
	assert.equal(parsed.steps[0].version, '${{ env.FLUTTER_VERSION }}');
});

test('parseWorkflow ignores a FLUTTER_VERSION that is not top-level', () => {
	const text =
		`name: Fake\n\njobs:\n  build:\n    env:\n      FLUTTER_VERSION: "9.9.9"\n` +
		`    steps:\n      - uses: ${SHA}\n        with:\n          channel: stable\n`;
	// A job-level env is invisible to the other workflows this guard compares,
	// so it must not be mistaken for the shared declaration.
	assert.equal(parseWorkflow(text).declared, null);
});

test('parseWorkflow does not read a later step version into an earlier step', () => {
	const text = workflow({
		declared: '3.47.0',
		pin: null,
		extraStep:
			`      - uses: ${SHA} # v2\n` +
			`        with:\n` +
			`          flutter-version: 3.47.0\n`,
	});
	const parsed = parseWorkflow(text);
	assert.equal(parsed.steps.length, 2);
	assert.equal(parsed.steps[0].version, null, 'the unpinned step must stay unpinned');
	assert.equal(parsed.steps[1].version, '3.47.0');
});

test('parseWorkflow strips quotes and trailing comments', () => {
	const parsed = parseWorkflow(workflow({ declared: '3.47.0', pin: '"3.44.9" # old' }));
	assert.equal(parsed.steps[0].version, '3.44.9');
});

test('resolveVersion dereferences env.FLUTTER_VERSION', () => {
	assert.deepEqual(
		resolveVersion({ version: '${{ env.FLUTTER_VERSION }}' }, '3.47.0'),
		{ version: '3.47.0' },
	);
});

test('resolveVersion accepts a literal', () => {
	assert.deepEqual(resolveVersion({ version: '3.47.0' }, null), { version: '3.47.0' });
});

test('resolveVersion rejects a missing pin', () => {
	assert.match(resolveVersion({ version: null }, '3.47.0').error, /floats/);
});

test('resolveVersion rejects a reference the workflow never declares', () => {
	assert.match(
		resolveVersion({ version: '${{ env.FLUTTER_VERSION }}' }, null).error,
		/declares no top-level/,
	);
});

test('resolveVersion rejects some other env key', () => {
	assert.match(
		resolveVersion({ version: '${{ env.SDK }}' }, '3.47.0').error,
		/every pin must read/,
	);
});

test('checkFlutter passes when every workflow pins the same version', () => {
	const { errors, ok, versions } = checkFlutter([
		{ name: 'ci.yml', text: workflow({ declared: '3.47.0', pin: '${{ env.FLUTTER_VERSION }}' }) },
		{
			name: 'release-android.yml',
			text: workflow({ declared: '3.47.0', pin: '${{ env.FLUTTER_VERSION }}' }),
		},
	]);
	assert.deepEqual(errors, []);
	assert.equal(ok.length, 2);
	assert.deepEqual([...versions.keys()], ['3.47.0']);
});

test('checkFlutter fails when a release workflow drifts from CI', () => {
	const { errors } = checkFlutter([
		{ name: 'ci.yml', text: workflow({ declared: '3.47.0', pin: '${{ env.FLUTTER_VERSION }}' }) },
		{
			name: 'release-android.yml',
			text: workflow({ declared: '3.44.9', pin: '${{ env.FLUTTER_VERSION }}' }),
		},
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /2 different Flutter versions/);
	assert.match(errors[0], /3\.44\.9 — release-android\.yml/);
	assert.match(errors[0], /3\.47\.0 — ci\.yml/);
});

test('checkFlutter fails on a step that reverted to bare `channel: stable`', () => {
	const { errors } = checkFlutter([
		{ name: 'release-ios.yml', text: workflow({ declared: '3.47.0', pin: null }) },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /release-ios\.yml:\d+ — no `flutter-version:`/);
});

test('checkFlutter fails rather than passing vacuously when nothing matches', () => {
	// The failure this guards against is the guard itself going blind — a
	// renamed action would otherwise report success over an empty set.
	const { errors } = checkFlutter([
		{ name: 'ci.yml', text: 'name: Fake\njobs:\n  build:\n    steps:\n      - run: echo hi\n' },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /now checks nothing/);
});

test('parseMelosActivations finds the version, or null when unpinned', () => {
	assert.deepEqual(parseMelosActivations(melosWorkflow('7.8.2')), [
		{ line: 5, version: '7.8.2' },
	]);
	assert.deepEqual(parseMelosActivations(melosWorkflow(null)), [{ line: 5, version: null }]);
});

test('parseMelosActivations ignores the command inside a YAML comment', () => {
	// This file's own comments name the command; prose about it is not a
	// use of it, and counting one would make the vacuous-pass check lie.
	const text = `jobs:\n  build:\n    steps:\n      # dart pub global activate melos\n      - run: echo hi\n`;
	assert.deepEqual(parseMelosActivations(text), []);
});

test('parseLockedVersion reads the resolved version, not a neighbour’s', () => {
	assert.equal(parseLockedVersion(fakeLock('7.8.2'), 'melos'), '7.8.2');
	assert.equal(parseLockedVersion(fakeLock('7.8.2'), 'matcher'), '0.12.16');
	assert.equal(parseLockedVersion(fakeLock(null), 'melos'), null);
});

test('checkMelos passes when every activation matches the lockfile', () => {
	const { errors, ok, locked } = checkMelos(
		[
			{ name: 'ci.yml', text: melosWorkflow('7.8.2') },
			{ name: 'release-ios.yml', text: melosWorkflow('7.8.2') },
		],
		fakeLock('7.8.2'),
	);
	assert.deepEqual(errors, []);
	assert.equal(ok.length, 2);
	assert.equal(locked, '7.8.2');
});

test('checkMelos fails an unpinned activation', () => {
	const { errors } = checkMelos([{ name: 'ci.yml', text: melosWorkflow(null) }], fakeLock('7.8.2'));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /passes no version/);
	assert.match(errors[0], /7\.8\.2/, 'the message must name the version to use');
});

test('checkMelos fails an activation that disagrees with the lockfile', () => {
	// The point of reading the lock rather than comparing the sites to each
	// other: six workflows could agree with one another and all be wrong.
	const { errors } = checkMelos(
		[
			{ name: 'ci.yml', text: melosWorkflow('7.5.1') },
			{ name: 'release-ios.yml', text: melosWorkflow('7.5.1') },
		],
		fakeLock('7.8.2'),
	);
	assert.equal(errors.length, 2);
	assert.match(errors[0], /activates melos 7\.5\.1, but pubspec\.lock resolves 7\.8\.2/);
});

test('checkMelos fails rather than passing vacuously when nothing matches', () => {
	const { errors } = checkMelos(
		[{ name: 'ci.yml', text: 'jobs:\n  build:\n    steps:\n      - run: echo hi\n' }],
		fakeLock('7.8.2'),
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /enforces nothing/);
});

test('checkMelos fails when the lockfile has no melos at all', () => {
	const { errors } = checkMelos([{ name: 'ci.yml', text: melosWorkflow('7.8.2') }], fakeLock(null));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /no resolved `melos` version/);
});

test('parseDefmtPrint finds the install version and the cache key version', () => {
	const { installs, cacheKeys } = parseDefmtPrint(defmtWorkflow({ install: '1.1.0' }));
	assert.deepEqual(installs, [{ line: 11, version: '1.1.0' }]);
	assert.deepEqual(cacheKeys, [{ line: 9, version: '1.1.0' }]);
});

test('parseDefmtPrint reports a missing --version as null', () => {
	const { installs } = parseDefmtPrint(defmtWorkflow({ install: null, key: '1.1.0' }));
	assert.deepEqual(installs, [{ line: 11, version: null }]);
});

test('parseDefmtPrint reads a quoted range as written', () => {
	const { installs } = parseDefmtPrint(defmtWorkflow({ install: "'^1.1'", key: '1.1' }));
	assert.equal(installs[0].version, '^1.1');
});

test('checkDefmtPrint passes on an exact version with a matching cache key', () => {
	const { errors, ok } = checkDefmtPrint([
		{ name: 'ci.yml', text: defmtWorkflow({ install: '1.1.0' }) },
	]);
	assert.deepEqual(errors, []);
	assert.equal(ok.length, 2, 'the install and the cache key each report');
});

test('checkDefmtPrint fails an install with no --version at all', () => {
	const { errors } = checkDefmtPrint([
		{ name: 'ci.yml', text: defmtWorkflow({ install: null, key: '1.1.0' }) },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /passes no `--version`/);
});

test('checkDefmtPrint fails a caret range — the float this closed', () => {
	// `^1.1` is what shipped, and it admits any 1.x. A range is not a pin.
	const { errors } = checkDefmtPrint([
		{ name: 'ci.yml', text: defmtWorkflow({ install: "'^1.1'", key: '1.1' }) },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /is a range, not a pin/);
});

test('checkDefmtPrint fails a cache key that lags the pinned version', () => {
	// The install short-circuits on `command -v`, so a stale key silently keeps
	// serving the old binary — the pin would be cosmetic.
	const { errors } = checkDefmtPrint([
		{ name: 'ci.yml', text: defmtWorkflow({ install: '1.2.0', key: '1.1.0' }) },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /cache key names defmt-print 1\.1\.0 but the install pins 1\.2\.0/);
	assert.match(errors[0], /the pin would never run/);
});

test('checkDefmtPrint fails when the two sim jobs disagree', () => {
	const { errors } = checkDefmtPrint([
		{ name: 'ci.yml', text: defmtWorkflow({ install: '1.1.0' }) },
		{ name: 'ci2.yml', text: defmtWorkflow({ install: '1.0.0' }) },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /2 different defmt-print versions/);
});

test('checkDefmtPrint fails rather than passing vacuously when nothing matches', () => {
	const { errors } = checkDefmtPrint([
		{ name: 'ci.yml', text: 'jobs:\n  sim:\n    steps:\n      - run: echo hi\n' },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /enforces nothing/);
});

test('the repo’s real workflows and lockfile agree on both toolchains', () => {
	const files = readdirSync(WORKFLOW_DIR)
		.filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
		.map((name) => ({ name, text: readFileSync(join(WORKFLOW_DIR, name), 'utf-8') }));
	const { errors, flutter, melos, defmt } = checkAll(files, readFileSync(LOCKFILE, 'utf-8'));
	assert.deepEqual(errors, []);
	assert.ok(
		flutter.ok.length >= 8,
		`expected every flutter-action step, found ${flutter.ok.length}`,
	);
	assert.ok(melos.ok.length >= 6, `expected every melos activation, found ${melos.ok.length}`);
	assert.ok(defmt.ok.length >= 4, `expected both installs + both cache keys, found ${defmt.ok.length}`);
});
