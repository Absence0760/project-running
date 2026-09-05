import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	ACTION_DIR,
	GO_MODS,
	LOCKFILE,
	RUST_TOOLCHAIN,
	SETUP_NODE_USES,
	TOOL_VERSIONS,
	WORKFLOW_DIR,
	checkActionPins,
	checkAll,
	checkDefmtPrint,
	checkDeno,
	checkFlutter,
	checkMelos,
	checkNode,
	checkRustToolchain,
	checkToolVersions,
	parseActionUses,
	parseDefmtPrint,
	parseDefmtPrintByJob,
	parseDenoSteps,
	parseLockedVersion,
	parseMelosActivations,
	parseGoDirective,
	parseNodeSteps,
	parseRustChannel,
	parseToolVersions,
	parseUsesStepVersions,
	parseWorkflow,
	readCompositeActions,
	repoPins,
	resolveVersion,
	toolVersionAgrees,
} from './check_toolchain_pins.mjs';

const REPO_ROOT = join(WORKFLOW_DIR, '..', '..');

/// The two arguments checkAll grew for the developer-toolchain rail, read from
/// the committed tree.
const realToolVersions = () => readFileSync(TOOL_VERSIONS, 'utf-8');
const realGoMods = () =>
	GO_MODS.map((path) => ({ path, text: readFileSync(join(REPO_ROOT, path), 'utf-8') }));

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
	const { errors, flutter, melos, defmt, actions, rust, node, tools } = checkAll(
		files,
		readFileSync(LOCKFILE, 'utf-8'),
		readCompositeActions(ACTION_DIR),
		readFileSync(RUST_TOOLCHAIN, 'utf-8'),
		realToolVersions(),
		realGoMods(),
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
	// Every setup-node step in the tree, including audit.yml's — which is
	// written `- name:` then `uses:` and was invisible to the first cut of the
	// Node rail, while its own comment claimed it "matches the rest of the
	// workflows in this repo".
	assert.ok(node.ok.length >= 21, `expected every setup-node step, found ${node.ok.length}`);
	assert.equal(node.versions.size, 1);
	// The developer toolchain is compared against the pins, not merely parsed.
	assert.ok(tools.ok.length >= 5, `expected the checked .tool-versions lines, found ${tools.ok.length}`);
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
		realToolVersions(),
		realGoMods(),
	);
	// The rust rail's own error, plus the .tool-versions line that now
	// disagrees with a channel name rather than a version.
	assert.equal(errors.length, 2);
	assert.match(errors[0], /rust-toolchain\.toml/);
	assert.match(errors[1], /\.tool-versions/);
});

// --- Node + developer toolchain -------------------------------------------

// The blind spot the shared resolver exists for. `audit.yml` writes its
// setup-node step as `- name:` then `uses:`, so a scan anchored on `- uses:`
// found nothing there — and 54 steps across the committed workflows use that
// form, including every flutter-action step's nearest neighbours.
test('a step whose uses: sits under a name: is found, with its version', () => {
	const named =
		'jobs:\n  a:\n    steps:\n      - name: Set up Node\n' +
		'        uses: actions/setup-node@abc\n        with:\n          node-version: 24\n';
	assert.deepEqual(parseNodeSteps(named), [{ line: 4, version: '24' }]);
	// And the marker-line form still reads the same.
	const marker =
		'jobs:\n  a:\n    steps:\n      - uses: actions/setup-node@abc\n' +
		'        with:\n          node-version: 24\n';
	assert.deepEqual(parseNodeSteps(marker), [{ line: 4, version: '24' }]);
});

test('a with: block written above the uses: does not hide the step marker', () => {
	const text =
		'jobs:\n  a:\n    steps:\n      - name: Set up Node\n        with:\n' +
		'          node-version: 24\n        uses: actions/setup-node@abc\n';
	assert.deepEqual(parseNodeSteps(text), [{ line: 4, version: '24' }]);
});

test('a uses: under no list marker is not invented as a step', () => {
	assert.deepEqual(parseNodeSteps('uses: actions/setup-node@abc\n'), []);
});

test('the version is read from the step, not from a neighbour', () => {
	const text =
		'jobs:\n  a:\n    steps:\n      - uses: actions/setup-node@abc\n' +
		'      - name: something else\n        with:\n          node-version: 22\n';
	assert.deepEqual(parseNodeSteps(text), [{ line: 4, version: null }]);
});

test('a setup-node step naming no version floats to the runner image, and fails', () => {
	const { errors } = checkNode([
		{ name: 'ci.yml', text: 'jobs:\n  a:\n    steps:\n      - uses: actions/setup-node@abc\n' },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /names no `node-version`/);
});

test('two workflows on different Node versions is the reported bug', () => {
	const wf = (/** @type {string} */ v) =>
		`jobs:\n  a:\n    steps:\n      - uses: actions/setup-node@abc\n        with:\n          node-version: ${v}\n`;
	const { errors } = checkNode([
		{ name: 'ci.yml', text: wf('24') },
		{ name: 'release-web.yml', text: wf('26') },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /pin 2 different Node versions/);
	assert.match(errors[0], /release-web\.yml/);
});

test('checkNode fails rather than passing vacuously over no setup-node step', () => {
	const { errors } = checkNode([{ name: 'ci.yml', text: 'jobs:\n  a:\n    steps:\n      - run: hi\n' }]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /now checks nothing/);
});

test('quoting is not a divergence', () => {
	const wf = (/** @type {string} */ v) =>
		`jobs:\n  a:\n    steps:\n      - uses: actions/setup-node@abc\n        with:\n          node-version: ${v}\n`;
	const { errors, versions } = checkNode([
		{ name: 'a.yml', text: wf('24') },
		{ name: 'b.yml', text: wf('"24"') },
		{ name: 'c.yml', text: wf("'24'") },
	]);
	assert.deepEqual(errors, []);
	assert.equal(versions.size, 1);
});

// --- Deno ------------------------------------------------------------------

const denoWf = (/** @type {string} */ v) =>
	`jobs:\n  a:\n    steps:\n      - uses: denoland/setup-deno@abc\n        with:\n          deno-version: ${v}\n`;

test('a channel is refused where an exact Deno version is required', () => {
	// The state this rail was added over: both steps took `v2.x`, so a Deno
	// release landing between two runs changed the toolchain under code nobody
	// touched. A major alone is enough for Node because the runner image
	// resolves the rest; a Deno MINOR carries new `deno check` diagnostics.
	for (const channel of ['v2.x', '2.x', '2', 'canary', 'v2']) {
		const { errors } = checkDeno([{ name: 'ci.yml', text: denoWf(channel) }]);
		assert.equal(errors.length, 1, channel);
		assert.match(errors[0], /is a channel rather than a version/);
	}
});

test('an exact Deno version passes, with or without the leading v', () => {
	const { errors, versions } = checkDeno([
		{ name: 'a.yml', text: denoWf('v2.9.6') },
		{ name: 'b.yml', text: denoWf('2.9.6') },
		{ name: 'c.yml', text: denoWf("'2.9.6'") },
	]);
	assert.deepEqual(errors, []);
	assert.equal(versions.size, 1);
	assert.ok(versions.has('2.9.6'));
});

test('a setup-deno step naming no deno-version is refused', () => {
	const { errors } = checkDeno([
		{ name: 'ci.yml', text: 'jobs:\n  a:\n    steps:\n      - uses: denoland/setup-deno@abc\n' },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /no `deno-version` at all/);
});

test('two workflows on different Deno versions is the reported bug', () => {
	const { errors } = checkDeno([
		{ name: 'ci.yml', text: denoWf('v2.9.6') },
		{ name: 'other.yml', text: denoWf('v2.8.0') },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /pin 2 different Deno versions/);
});

test('checkDeno fails rather than passing vacuously over no setup-deno step', () => {
	const { errors } = checkDeno([{ name: 'ci.yml', text: 'jobs:\n  a:\n    steps:\n      - run: hi\n' }]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /now checks nothing/);
});

test('parseDenoSteps reads the version off the step, not off a neighbour', () => {
	const text =
		'jobs:\n  a:\n    steps:\n      - uses: denoland/setup-deno@abc\n' +
		'      - name: something else\n        with:\n          deno-version: v2.8.0\n';
	assert.deepEqual(parseDenoSteps(text), [{ line: 4, version: null }]);
});

test('.tool-versions must carry the deno line the workflows pin', () => {
	// The half that makes the pin a contributor's too. Dropping the line —
	// which is where it was, commented, before this rail existed — fails.
	const pins = repoPins({ deno: '2.9.6' });
	assert.match(checkToolVersions('nodejs 24\n', pins).errors[0], /names no `deno` line/);
	assert.match(
		checkToolVersions('nodejs 24\n# deno 2.1.5\n', pins).errors[0],
		/disagrees with the 2\.9\.6/,
	);
	assert.deepEqual(checkToolVersions('nodejs 24\ndeno 2.9.6\n', pins).errors, []);
});

test('parseToolVersions keeps a commented line, and takes the first spelling of a plugin', () => {
	const parsed = parseToolVersions('nodejs 24\n# rust 1.98.0\n\n# a comment\nrust 1.0.0\n');
	assert.deepEqual(parsed.get('nodejs'), { line: 1, version: '24', commented: false });
	assert.deepEqual(parsed.get('rust'), { line: 2, version: '1.98.0', commented: true });
});

// § 711's reasoning applied one file over: a commented pin is one keystroke
// from being the version a contributor installs.
test('a commented .tool-versions line that disagrees with the repo pin fails', () => {
	const pins = repoPins({ rust: '1.98.0' });
	const { errors } = checkToolVersions('# rust 1.84.0\n', pins);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /the commented `rust 1\.84\.0` disagrees with the 1\.98\.0/);
	assert.match(errors[0], /uncommenting it is one keystroke/);
});

test('an active .tool-versions line that disagrees says the contributor develops off CI', () => {
	const { errors } = checkToolVersions('nodejs 22\n', repoPins({ node: '24' }));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /`nodejs 22` disagrees with the 24/);
	assert.match(errors[0], /a toolchain CI\s+never runs/);
});

test('a toolchain the repo pins and the file omits fails', () => {
	const { errors } = checkToolVersions('nodejs 24\n', repoPins({ node: '24', flutter: '3.47.0' }));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /names no `flutter` line/);
});

test('a plugin with no in-repo pin is reported, not compared against nothing', () => {
	const { errors, unbacked } = checkToolVersions('nodejs 24\n# zola 0.22.1\n', repoPins({ node: '24' }));
	assert.deepEqual(errors, []);
	assert.equal(unbacked.length, 1);
	assert.match(unbacked[0], /`zola 0\.22\.1` has no in-repo pin/);
});

test('a missing .tool-versions fails rather than reading as nothing to check', () => {
	const { errors } = checkToolVersions(null, repoPins({ node: '24' }));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /\.tool-versions is missing/);
});

// Every plugin is compared exactly, nodejs included since § 1216 — the
// carve-out's own reason ("asdf wants a resolvable build, CI states a major")
// stopped being true when § 1214 made every setup-node step name the patch.
test('every plugin agrees only on the exact version, nodejs included', () => {
	assert.equal(toolVersionAgrees('nodejs', '24.20.0', '24.20.0'), true);
	// The hole the major-only comparison left: twenty minor releases apart, and
	// called equal.
	assert.equal(toolVersionAgrees('nodejs', '24.0.0', '24.20.0'), false);
	assert.equal(toolVersionAgrees('nodejs', '24', '24.20.0'), false);
	assert.equal(toolVersionAgrees('nodejs', '22.11.0', '24.20.0'), false);
	assert.equal(toolVersionAgrees('rust', '1.98', '1.98.0'), false);
	assert.equal(toolVersionAgrees('rust', '1.98.0', '1.98.0'), true);
});

test('the committed .tool-versions names the exact Node the workflows install', () => {
	const declared = parseToolVersions(realToolVersions()).get('nodejs');
	assert.ok(declared, '.tool-versions names no `nodejs` line');
	assert.match(declared.version, /^\d+\.\d+\.\d+$/, `nodejs ${declared.version} is not exact`);
	const files = readdirSync(WORKFLOW_DIR)
		.filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
		.map((name) => ({ name, text: readFileSync(join(WORKFLOW_DIR, name), 'utf-8') }));
	const versions = checkNode(files).versions;
	assert.equal(versions.size, 1, `the setup-node steps name ${versions.size} versions`);
	assert.equal(declared.version, [...versions.keys()][0]);
});

test('parseGoDirective refuses to pin when the modules disagree', () => {
	assert.equal(
		parseGoDirective([{ path: 'a/go.mod', text: 'module a\ngo 1.26.6\n' }]).version,
		'1.26.6',
	);
	const split = parseGoDirective([
		{ path: 'a/go.mod', text: 'module a\ngo 1.26.6\n' },
		{ path: 'b/go.mod', text: 'module b\ngo 1.25.0\n' },
	]);
	assert.equal(split.version, null);
	assert.equal(split.errors.length, 1);
	assert.match(split.errors[0], /2 different `go` directives/);
});

test('parseUsesStepVersions is what both rails read through', () => {
	const text =
		'jobs:\n  a:\n    steps:\n      - name: SDK\n        uses: subosito/flutter-action@abc\n' +
		'        with:\n          flutter-version: 3.47.0\n';
	assert.deepEqual(parseUsesStepVersions(text, SETUP_NODE_USES, 'node-version'), []);
	assert.deepEqual(parseWorkflow(text).steps, [{ line: 4, version: '3.47.0' }]);
});
