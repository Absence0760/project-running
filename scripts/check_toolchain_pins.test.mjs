import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	ACTION_DIR,
	LOCKFILE,
	RUST_TOOLCHAIN,
	WORKFLOW_DIR,
	checkActionPins,
	checkAll,
	checkDefmtPrint,
	checkFlutter,
	checkMelos,
	checkRustToolchain,
	parseActionUses,
	parseDefmtPrint,
	parseDefmtPrintByJob,
	parseLockedVersion,
	parseMelosActivations,
	parseRustChannel,
	parseWorkflow,
	readCompositeActions,
	resolveVersion,
} from './check_toolchain_pins.mjs';

/// A firmware-sim job shaped like the real one: an actions/cache step whose
/// key embeds the version, then the `command -v || cargo install` line.
/** @param {{ install: string | null, key?: string | null, rawKey?: string }} opts */
function defmtWorkflow({ install, key = install, rawKey }) {
	const keyLine =
		rawKey !== undefined
			? `          key: ${rawKey}\n`
			: key === null
				? ''
				: `          key: defmt-print-${key}-\${{ runner.os }}\n`;
	return (
		`name: Fake\njobs:\n  sim:\n    steps:\n` +
		`      - name: Cache defmt-print\n` +
		`        uses: actions/cache@abc\n` +
		`        with:\n` +
		`          path: ~/.cargo/bin/defmt-print\n` +
		keyLine +
		`      - name: Install defmt-print\n` +
		`        run: command -v defmt-print || cargo install defmt-print --locked` +
		(install === null ? '' : ` --version ${install}`) +
		`\n`
	);
}

/// A pubspec.lock fragment shaped like the real one: two-space package keys,
/// a nested description block, the version last.
/** @param {string | null} melosVersion */
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
/** @param {string | null} version */
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
/** @param {{ declared: string | null, pin: string | null, extraStep?: string }} opts */
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
	const resolved = resolveVersion({ version: null }, '3.47.0');
	assert.ok(resolved.error);
	assert.match(resolved.error, /floats/);
});

test('resolveVersion rejects a reference the workflow never declares', () => {
	const resolved = resolveVersion({ version: '${{ env.FLUTTER_VERSION }}' }, null);
	assert.ok(resolved.error);
	assert.match(resolved.error, /declares no top-level/);
});

test('resolveVersion rejects some other env key', () => {
	const resolved = resolveVersion({ version: '${{ env.SDK }}' }, '3.47.0');
	assert.ok(resolved.error);
	assert.match(resolved.error, /every pin must read/);
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
	assert.match(errors[0], /cache key names defmt-print 1\.1\.0 but job `sim` installs 1\.2\.0/);
	assert.match(errors[0], /the pin would never run/);
});

/// Two sim jobs in one file, each with its own cache key and its own pin.
/// ci.yml has held two of them since the day it was written; they agree only
/// by hand.
/**
 * @param {{ a: string, aKey?: string, b: string, bKey?: string }} spec
 */
function twoSimJobs({ a, aKey = a, b, bKey = b }) {
	const job = (/** @type {string} */ name, /** @type {string} */ install, /** @type {string} */ key) =>
		`  ${name}:\n    steps:\n` +
		`      - name: Cache defmt-print\n` +
		`        uses: actions/cache@abc\n` +
		`        with:\n` +
		`          path: ~/.cargo/bin/defmt-print\n` +
		`          key: defmt-print-${key}-\${{ runner.os }}\n` +
		`      - name: Install defmt-print\n` +
		`        run: command -v defmt-print || cargo install defmt-print --locked --version ${install}\n`;
	return `name: Fake\njobs:\n` + job('sim-a', a, aKey) + job('sim-b', b, bKey);
}

test('parseDefmtPrintByJob groups by job and reports file-absolute lines', () => {
	const byJob = parseDefmtPrintByJob(twoSimJobs({ a: '1.1.0', b: '2.0.0' }));
	assert.deepEqual([...byJob.keys()], ['sim-a', 'sim-b']);
	assert.deepEqual(byJob.get('sim-a'), {
		installs: [{ line: 11, version: '1.1.0' }],
		cacheKeys: [{ line: 9, version: '1.1.0' }],
	});
	assert.deepEqual(byJob.get('sim-b'), {
		installs: [{ line: 20, version: '2.0.0' }],
		cacheKeys: [{ line: 18, version: '2.0.0' }],
	});
});

// Read per FILE, every key was compared against the FIRST install in it, so
// the second job's correct key read as stale.
test('a cache key correct for its own job is not reported stale', () => {
	const { errors, ok } = checkDefmtPrint([
		{ name: 'ci.yml', text: twoSimJobs({ a: '1.1.0', b: '2.0.0' }) },
	]);
	assert.equal(
		errors.filter((e) => e.includes('cache key')).length,
		0,
		errors.join('\n'),
	);
	assert.equal(ok.filter((o) => o.includes('cache key')).length, 2);
	// The two jobs really do disagree, and that is still reported.
	assert.equal(errors.length, 1);
	assert.match(errors[0], /2 different defmt-print versions/);
});

// The mirror, and the worse half: job B's key restores job A's binary, so
// `command -v defmt-print` wins and B's pin never executes — run 31623789083
// exactly. Per FILE this key EQUALLED the first install and was reported OK.
test('a cache key that defeats its own job\'s pin is not reported OK', () => {
	const { errors, ok } = checkDefmtPrint([
		{ name: 'ci.yml', text: twoSimJobs({ a: '1.1.0', b: '2.0.0', bKey: '1.1.0' }) },
	]);
	assert.equal(ok.filter((o) => o.includes('cache key')).length, 1);
	const stale = errors.filter((e) => e.includes('cache key'));
	assert.equal(stale.length, 1);
	assert.match(stale[0], /cache key names defmt-print 1\.1\.0 but job `sim-b` installs 2\.0\.0/);
});

test('a job that caches defmt-print but never installs it is named', () => {
	const text =
		`name: Fake\njobs:\n  sim:\n    steps:\n` +
		`      - name: Cache defmt-print\n` +
		`        uses: actions/cache@abc\n` +
		`        with:\n` +
		`          key: defmt-print-1.1.0-\${{ runner.os }}\n` +
		`  other:\n    steps:\n` +
		`      - name: Install defmt-print\n` +
		`        run: command -v defmt-print || cargo install defmt-print --locked --version 1.1.0\n`;
	const { errors } = checkDefmtPrint([{ name: 'ci.yml', text }]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /job `sim` restores a defmt-print cache but never runs/);
});

// The cache half going blind. A key simplified to `defmt-print-${{ runner.os }}`
// is the exact hazard this half exists for, and the old pattern only matched a
// key that ALREADY carried a version — so dropping it made the key invisible
// and the check reported nothing while `command -v` kept winning.
test('checkDefmtPrint fails a cache key that carries no version at all', () => {
	const { errors } = checkDefmtPrint([
		{
			name: 'ci.yml',
			text: defmtWorkflow({ install: '1.1.0', rawKey: 'defmt-print-${{ runner.os }}' }),
		},
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /cache key carries no version/);
	assert.match(errors[0], /the pin never runs/);
});

// Removing the cache step is sound — `cargo install` simply always runs — so
// the absence of a key must not be reported as a stale one.
test('checkDefmtPrint passes an install with no cache step at all', () => {
	const { errors } = checkDefmtPrint([
		{ name: 'ci.yml', text: defmtWorkflow({ install: '1.1.0', key: null }) },
	]);
	assert.deepEqual(errors, []);
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

const PINNED_SHA = 'a'.repeat(40);

test('parseActionUses reads a use whether it is live or commented out', () => {
	const uses = parseActionUses(
		`      - uses: actions/checkout@${PINNED_SHA} # v7.0.1\n` +
			`      #   uses: apple-actions/upload-testflight-build@v1\n` +
			`      - uses: ./.github/actions/start-supabase\n`,
	);
	assert.deepEqual(
		uses.map((u) => [u.ref, u.commented, u.local]),
		[
			[`actions/checkout@${PINNED_SHA}`, false, false],
			['apple-actions/upload-testflight-build@v1', true, false],
			['./.github/actions/start-supabase', false, true],
		],
	);
});

// The composite action's own header sentence mentions the key in prose. A
// guard that matched it would report an unpinned action that does not exist.
test('parseActionUses ignores prose that merely mentions the key', () => {
	assert.deepEqual(
		parseActionUses('  flutter-action, and start-supabase carries no `uses:` for this reason.\n'),
		[],
	);
});

test('a tag-pinned action fails, and the message says it is still read when commented', () => {
	const { errors } = checkActionPins([
		{
			name: 'release-ios.yml',
			text: `      #   uses: apple-actions/upload-testflight-build@v1\n`,
		},
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /pins a tag, not a commit \(commented out/);
});

test('a SHA-pinned action with no trailing version comment fails', () => {
	const { errors } = checkActionPins([
		{ name: 'ci.yml', text: `      - uses: actions/checkout@${PINNED_SHA}\n` },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /no trailing `# vN` comment/);
});

test('a local `./` reference needs no pin', () => {
	const { errors, seen } = checkActionPins([
		{
			name: 'ci.yml',
			text: `      - uses: ./.github/actions/start-supabase\n      - uses: actions/checkout@${PINNED_SHA} # v7\n`,
		},
	]);
	assert.deepEqual(errors, []);
	assert.equal(seen, 1);
});

test('checkActionPins fails rather than passing vacuously when nothing matches', () => {
	const { errors } = checkActionPins([{ name: 'ci.yml', text: 'jobs:\n  a:\n    steps:\n      - run: hi\n' }]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /enforces nothing/);
});

test('the repo’s real workflows and lockfile agree on both toolchains', () => {
	const files = readdirSync(WORKFLOW_DIR)
		.filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
		.map((name) => ({ name, text: readFileSync(join(WORKFLOW_DIR, name), 'utf-8') }));
	const { errors, flutter, melos, defmt, actions, rust } = checkAll(
		files,
		readFileSync(LOCKFILE, 'utf-8'),
		readCompositeActions(ACTION_DIR),
		readFileSync(RUST_TOOLCHAIN, 'utf-8'),
	);
	assert.match(String(rust.channel), /^\d+\.\d+\.\d+$/);
	assert.deepEqual(errors, []);
	assert.ok(
		actions.ok.length >= 100,
		`expected every third-party action reference, found ${actions.ok.length}`,
	);
	assert.ok(
		flutter.ok.length >= 8,
		`expected every flutter-action step, found ${flutter.ok.length}`,
	);
	assert.ok(melos.ok.length >= 6, `expected every melos activation, found ${melos.ok.length}`);
	assert.ok(defmt.ok.length >= 4, `expected both installs + both cache keys, found ${defmt.ok.length}`);
});

/// decisions.md § 705. The firmware channel is the one toolchain in this repo
/// nothing checked, and the shape that hurts is the one that reads as fine:
/// `channel = "stable"` installs, builds and clippies cleanly today.
test('the committed firmware channel is an exact version, not a channel name', () => {
	const { errors, ok, channel } = checkRustToolchain(readFileSync(RUST_TOOLCHAIN, 'utf-8'));
	assert.deepEqual(errors, []);
	assert.equal(ok.length, 1);
	assert.match(String(channel), /^\d+\.\d+\.\d+$/);
});

test('a floating channel is refused, whichever name it floats under', () => {
	for (const floating of ['stable', 'beta', 'nightly', 'nightly-2026-01-01', 'stable-x86_64-unknown-linux-gnu']) {
		const { errors, ok } = checkRustToolchain(`[toolchain]\nchannel = "${floating}"\n`);
		assert.equal(errors.length, 1, floating);
		assert.equal(ok.length, 0, floating);
		assert.match(errors[0], /not an exact MAJOR\.MINOR\.PATCH/);
		assert.match(errors[0], new RegExp(floating.replace(/[.*+?^${}()|[\]\\-]/g, '\\$&')));
	}
});

test('a two-component version is a range, not a pin', () => {
	// `1.98` admits 1.98.1, which is a different clippy with different lints —
	// the same reason `--version ^1.1` was refused for defmt-print.
	const { errors } = checkRustToolchain('[toolchain]\nchannel = "1.98"\n');
	assert.equal(errors.length, 1);
	assert.match(errors[0], /not an exact MAJOR\.MINOR\.PATCH/);
});

test('a toolchain file naming no channel fails rather than passing over nothing', () => {
	const { errors, ok } = checkRustToolchain('[toolchain]\ntargets = ["thumbv7em-none-eabihf"]\n');
	assert.equal(ok.length, 0);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /declares no `channel`/);
});

test('a missing toolchain file is an error, not a silent skip', () => {
	const { errors, ok, channel } = checkRustToolchain(null);
	assert.equal(ok.length, 0);
	assert.equal(channel, null);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /is missing/);
});

test('a commented-out channel does not stand in for the real one', () => {
	// `#` opens a TOML comment, so the first LIVE assignment is the channel;
	// reading the commented one would report a pin the toolchain never sees.
	assert.equal(parseRustChannel('# channel = "1.98.0"\nchannel = "stable"\n'), 'stable');
	assert.equal(parseRustChannel('channel = "1.98.0" # was stable\n'), '1.98.0');
	assert.equal(parseRustChannel("channel = '1.98.0'\n"), '1.98.0');
});

test('a floating firmware channel reaches checkAll rather than stopping at its own function', () => {
	const files = readdirSync(WORKFLOW_DIR)
		.filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
		.map((name) => ({ name, text: readFileSync(join(WORKFLOW_DIR, name), 'utf-8') }));
	const { errors } = checkAll(
		files,
		readFileSync(LOCKFILE, 'utf-8'),
		readCompositeActions(ACTION_DIR),
		'[toolchain]\nchannel = "stable"\n',
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /rust-toolchain\.toml/);
});
