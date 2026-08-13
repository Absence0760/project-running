import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	LOCKFILE,
	WORKFLOW_DIR,
	checkAll,
	checkFlutter,
	checkMelos,
	parseLockedVersion,
	parseMelosActivations,
	parseWorkflow,
	resolveVersion,
} from './check_toolchain_pins.mjs';

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

test('the repo’s real workflows and lockfile agree on both toolchains', () => {
	const files = readdirSync(WORKFLOW_DIR)
		.filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
		.map((name) => ({ name, text: readFileSync(join(WORKFLOW_DIR, name), 'utf-8') }));
	const { errors, flutter, melos } = checkAll(files, readFileSync(LOCKFILE, 'utf-8'));
	assert.deepEqual(errors, []);
	assert.ok(
		flutter.ok.length >= 8,
		`expected every flutter-action step, found ${flutter.ok.length}`,
	);
	assert.ok(melos.ok.length >= 6, `expected every melos activation, found ${melos.ok.length}`);
});
