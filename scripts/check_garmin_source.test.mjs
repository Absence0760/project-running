// Unit tests for apps/watch_garmin/scripts/check_garmin_source.sh.
//
// That script is the only automated claim anything makes about the Garmin
// tier. No CI job compiles the Monkey C, no CI job runs its `(:test)` suite,
// and the SDK is on no machine here — so every failure it exists to catch is
// one nothing else in the repo can see. It also cannot be measured by "does
// the app work": a stale grade after an activity discard renders a confident
// wrong pace, an unannotated test file ships silently against a memory ceiling,
// and a missing permission throws on the watch mid-activity and nowhere else.
//
// So it is measured the way its two siblings are (`check_xcstrings_parity`,
// `check_watch_ios_source`): by mutating a copy of the real tree into each
// shape the guard exists to refuse and asserting it refuses, with the
// unmutated copy as the positive control. Without that control every rejection
// below could be an accident of the copy rather than of the mutation.
//
// Run: node --test scripts/check_garmin_source.test.mjs
// CI:  the `watch-garmin-source` job in .github/workflows/ci.yml.

import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const GARMIN = join(REPO_ROOT, 'apps', 'watch_garmin');

const SCRIPT = join('scripts', 'check_garmin_source.sh');
const VIEW = join('source', 'GradeAdjustedPaceView.mc');
const APP = join('source', 'RunGarminApp.mc');
const TEST_SRC = join('source-test', 'GradeAdjustedPaceTest.mc');
const JUNGLE = 'monkey.jungle';
const MANIFEST = 'manifest.xml';
const STRINGS = join('resources', 'strings', 'strings.xml');

const FILES = [SCRIPT, VIEW, APP, TEST_SRC, JUNGLE, MANIFEST, STRINGS];

/** Copy the files the guard reads into a throwaway tree. */
function stage() {
	const dir = mkdtempSync(join(tmpdir(), 'garmin-source-'));
	for (const rel of FILES) {
		mkdirSync(join(dir, dirname(rel)), { recursive: true });
		cpSync(join(GARMIN, rel), join(dir, rel));
	}
	return dir;
}

/** @param {string} dir */
function run(dir) {
	const r = spawnSync('bash', [join(dir, SCRIPT)], { encoding: 'utf8' });
	return { status: r.status, out: `${r.stdout}${r.stderr}` };
}

/**
 * Stage, mutate, run, clean up.
 * @param {(dir: string) => void} mutate
 */
function runMutated(mutate) {
	const dir = stage();
	try {
		mutate(dir);
		return run(dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

/** A replacement that must actually match, so a reworded source fails here
 *  rather than staging an unmutated tree and reporting a pass.
 * @param {string} dir @param {string} rel @param {string | RegExp} from @param {string} to */
function edit(dir, rel, from, to) {
	const p = join(dir, rel);
	const before = readFileSync(p, 'utf8');
	const after = before.replace(from, to);
	assert.notEqual(after, before, `the mutation of ${rel} matched nothing`);
	writeFileSync(p, after);
}

test('the shipped Garmin tree passes', () => {
	const { status, out } = runMutated(() => {});
	assert.equal(status, 0, out);
	assert.match(out, /source-level checks pass/);
});

// --- claim 1: recovery from a distance rewind ------------------------------

test('a tracker with no negative-run branch is refused', () => {
	// `elapsedDistance` restarts at 0 on a reset or discard. Without the
	// re-anchor the `run >= MIN_SEGMENT_M` gate never opens again and the
	// discarded activity's last hill is applied to the whole of the next run.
	const { status, out } = runMutated((dir) =>
		edit(dir, VIEW, /if \(run < 0\.0\) \{[\s\S]*?\n        \}\n/, ''),
	);
	assert.equal(status, 1, out);
	assert.match(out, /no negative-run branch/);
});

test('a rewind branch that re-anchors only one of the two anchors is refused', () => {
	const { status, out } = runMutated((dir) =>
		edit(dir, VIEW, 'if (run < 0.0) {\n            mLastDistance = dist;', 'if (run < 0.0) {'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /does not re-anchor `mLastDistance`/);
});

test('a reset() that clears the grade but not the anchor is refused', () => {
	// The exact half-fix: the number goes to 0.0 and the anchor stays parked
	// at the discarded activity's distance total, which reproduces the freeze.
	const { status, out } = runMutated((dir) =>
		edit(dir, VIEW, '        mLastDistance = null;\n        mGrade = 0.0;', '        mGrade = 0.0;'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /reset\(\) does not clear `mLastDistance`/);
});

test('a view that never overrides onTimerReset is refused', () => {
	const { status, out } = runMutated((dir) =>
		edit(dir, VIEW, 'function onTimerReset() as Void {', 'function onTimerResetX() as Void {'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /does not override `onTimerReset`/);
});

test('a tracker class renamed to a longer name is refused', () => {
	// The same prefix defect as the case above, on the other declaration the
	// guard locates by name: `class GradeTrackerV2` is not `class GradeTracker`,
	// and reading it as one reports state the view no longer holds.
	const { status, out } = runMutated((dir) =>
		edit(dir, VIEW, 'class GradeTracker {', 'class GradeTrackerV2 {'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /no `class GradeTracker` in/);
});

test('an onTimerReset that does not call the tracker is refused as inert', () => {
	const { status, out } = runMutated((dir) =>
		edit(dir, VIEW, 'function onTimerReset() as Void {\n        mTracker.reset();', 'function onTimerReset() as Void {'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /override is inert/);
});

// --- claim 2: test sources stay off the watch ------------------------------

test('a build that stops excluding the test annotation is refused', () => {
	const { status, out } = runMutated((dir) =>
		edit(dir, JUNGLE, 'base.excludeAnnotations = test', 'base.excludeAnnotations = debug'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /does not exclude `test`/);
});

test('an unannotated file under source-test is refused', () => {
	const { status, out } = runMutated((dir) => edit(dir, TEST_SRC, /\(:test\)/g, '(:debug)'));
	assert.equal(status, 1, out);
	assert.match(out, /carries no `\(:test\)` annotation/);
});

test('a sourcePath that drops source-test is refused as a suite reporting zero tests', () => {
	const { status, out } = runMutated((dir) =>
		edit(dir, JUNGLE, 'base.sourcePath = source;source-test', 'base.sourcePath = source'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /compiles none of them/);
});

// --- claim 3: permission-gated modules -------------------------------------

test('a gated Toybox module used without its manifest permission is refused', () => {
	// The runtime refuses the call on the watch, mid-activity. The build says
	// nothing, which is why no compiler can stand in for this claim.
	const { status, out } = runMutated((dir) =>
		edit(dir, VIEW, 'import Toybox.Activity;', 'import Toybox.Activity;\nimport Toybox.Position;'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /uses Toybox\.Position but manifest\.xml declares no/);
});

test('a declared permission no source uses is refused', () => {
	const { status, out } = runMutated((dir) =>
		edit(dir, MANIFEST, '<iq:permissions/>', '<iq:permissions><iq:uses-permission id="Communications"/></iq:permissions>'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /install-prompt line the runner is asked to accept for nothing/);
});

test('the permission map reads the code and not the manifest comment', () => {
	// That comment spells out the `<iq:uses-permission id="Communications"/>`
	// line the sync path will one day need. A guard that read XML comments
	// would report a permission the app does not hold — and the shipped tree
	// would fail. The positive control covers it; this pins WHY.
	assert.match(readFileSync(join(GARMIN, MANIFEST), 'utf8'), /uses-permission id="Communications"/);
	assert.equal(run(stageAndKeep()).status, 0);
});

/** stage() without the cleanup, for the one case that only reads. */
function stageAndKeep() {
	const dir = stage();
	process.on('exit', () => rmSync(dir, { recursive: true, force: true }));
	return dir;
}

// --- claim 4: cross-rail constants are named -------------------------------

test('a cross-rail constant spelled inline as well as named is refused', () => {
	// `check_watch_wire_vectors.mjs` reads these by name. A second copy is
	// what drifts, and the far side's comment claiming a mirror is then an
	// instruction rather than an enforcement.
	const { status, out } = runMutated((dir) =>
		edit(dir, VIEW, 'if (totalSeconds > MAX_PACE_S) {', 'if (totalSeconds > 5940.0) {'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /spells `5940\.0` inline/);
});

test('a cross-rail constant that stops being declared is refused', () => {
	const { status, out } = runMutated((dir) =>
		edit(dir, VIEW, 'const MIN_SPEED_MPS = 0.4;', 'const WALK_GATE = 0.4;'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /declares no `const MIN_SPEED_MPS`/);
});

// --- claim 5: string resources, both directions ----------------------------

test('a string the source loads with no table entry is refused', () => {
	const { status, out } = runMutated((dir) =>
		edit(dir, VIEW, 'Rez.Strings.FieldLabel', 'Rez.Strings.FieldLabelling'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /FieldLabelling` is loaded from the string table/);
});

test('a table entry nothing references is refused', () => {
	const { status, out } = runMutated((dir) =>
		edit(dir, STRINGS, '</strings>', '    <string id="Orphan">nobody</string>\n</strings>'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /`Orphan` and nothing references it/);
});

// --- vacuity ---------------------------------------------------------------

test('a renamed view class fails loudly rather than passing on an unread file', () => {
	// Every claim above reads this file. A rename that made the reads return
	// nothing would otherwise report a clean tier it never looked at.
	const { status, out } = runMutated((dir) =>
		edit(dir, VIEW, /class GradeAdjustedPaceView/g, 'class GapView'),
	);
	assert.equal(status, 1, out);
	assert.match(out, /would pass on an empty file/);
});

test('an empty string table fails rather than passing vacuously', () => {
	const { status, out } = runMutated((dir) =>
		edit(dir, STRINGS, /<string id="[\s\S]*<\/string>/, ''),
	);
	assert.equal(status, 1, out);
	assert.match(out, /defines no <string>/);
});

test('a missing file is reported rather than read as nothing to check', () => {
	const { status, out } = runMutated((dir) => rmSync(join(dir, JUNGLE)));
	assert.equal(status, 1, out);
	assert.match(out, /missing file: monkey\.jungle/);
});
