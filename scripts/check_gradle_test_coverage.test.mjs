// Unit tests for the Gradle test-coverage guard.
//
// The guard's claim is that a committed Gradle unit-test suite is executed by
// some job, so the cases below plant the ways a suite stops running while every
// check stays green: the task word deleted from an invocation that still
// builds, a project nothing invokes Gradle in at all, an excuse that has
// outlived its project or its tests, and an excuse list that has swallowed the
// lot. Each is checked to fail; a guard nobody has watched fail is a guard
// nobody knows the failure mode of.
//
// The last test drives the workflow's OWN echo shell, lifted out of ci.yml,
// because shell inside a workflow runs in no other suite — the same instrument
// as `wait_for_sidecars.test.mjs` one directory over.
//
// Run: `node --test scripts/check_gradle_test_coverage.test.mjs`

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { TEST_TASK, check, gradleInvocations, testSources } from './check_gradle_test_coverage.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

const REASON = 'a reason long enough to say what would have to change to close it';

/**
 * A fixture repo: Gradle projects with or without a unit-test source set, plus
 * one workflow file.
 *
 * @param {{ projects: Record<string, boolean>, workflow: string }} spec
 */
function fixture(spec) {
	const root = mkdtempSync(join(tmpdir(), 'gradle-test-coverage-'));
	for (const [p, hasTests] of Object.entries(spec.projects)) {
		mkdirSync(join(root, p), { recursive: true });
		writeFileSync(join(root, p, 'settings.gradle.kts'), '');
		if (!hasTests) continue;
		const dir = join(root, p, 'app', 'src', 'test', 'kotlin');
		mkdirSync(dir, { recursive: true });
		writeFileSync(join(dir, 'ThingTest.kt'), '@Test fun t() {}\n');
	}
	mkdirSync(join(root, '.github', 'workflows'), { recursive: true });
	writeFileSync(join(root, '.github', 'workflows', 'ci.yml'), spec.workflow);
	return root;
}

/**
 * @param {{ tasks?: string, untested?: string | null, dir?: string, cacheKey?: string | null }} [opts]
 */
function workflow(opts = {}) {
	const untested =
		opts.untested === null
			? ''
			: `        env:
          GRADLE_UNTESTED: |
            ${opts.untested ?? `apps/host/android=1=${REASON}`}
`;
	const dir = opts.dir ?? 'apps/watch_wear/android';
	// Claim 4 reads the job's `~/.gradle` cache step, so every fixture that is
	// not about claim 4 carries a well-formed one — a fixture missing it would
	// fail for a reason the case is not about, which is how these eight tests
	// started failing when claim 4 landed without them.
	const cache =
		opts.cacheKey === null
			? ''
			: `      - uses: actions/cache@v4
        with:
          path: ~/.gradle/caches
          key: gradle-${opts.cacheKey ?? `\${{ hashFiles('${dir}/**/*.gradle*') }}`}
`;
	return `name: CI
jobs:
  build-watch-wear:
    steps:
${cache}      - working-directory: ${dir}
        run: ./gradlew ${opts.tasks ?? 'assembleDebug testDebugUnitTest'} --no-daemon
      - name: Gradle unit tests nothing runs
${untested}        shell: bash
        run: |
          echo done
`;
}

const PROJECTS = { 'apps/watch_wear/android': true, 'apps/host/android': true };

test('a project whose tests are run, beside one declared unrun, passes', () => {
	const root = fixture({ projects: PROJECTS, workflow: workflow() });
	const { errors, ok } = check({ root });
	assert.deepEqual(errors, []);
	assert.match(ok[0], /1 of 2 Gradle project\(s\)/);
	assert.match(ok[0], /1 test source file\(s\) declared unrun/);
});

test('deleting the test task from an invocation that still builds fails', () => {
	// The one-word deletion the whole guard exists for: the job keeps its name,
	// keeps building the app, and stops running every assertion in it.
	const root = fixture({ projects: PROJECTS, workflow: workflow({ tasks: 'assembleDebug' }) });
	const { errors } = check({ root });
	assert.equal(errors.length, 2);
	assert.match(errors[0], /apps\/watch_wear\/android/);
	assert.match(errors[0], /compiles the app and runs none of them/);
	// And the floor underneath it: nothing at all is being tested now.
	assert.match(errors[1], /no Gradle test runs in CI at all/);
});

test('a project no workflow invokes Gradle in at all fails, and says so', () => {
	const root = fixture({
		projects: { ...PROJECTS, 'apps/third/android': true },
		workflow: workflow(),
	});
	const { errors } = check({ root });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /apps\/third\/android .*no workflow invokes Gradle there at all/);
});

test('a project holding no tests needs no invocation and no excuse', () => {
	const root = fixture({
		projects: { 'apps/watch_wear/android': true, 'apps/host/android': true, 'apps/bare/android': false },
		workflow: workflow(),
	});
	assert.deepEqual(check({ root }).errors, []);
});

test('an excuse for a project that has stopped holding tests is stale, and fails', () => {
	const root = fixture({
		projects: { 'apps/watch_wear/android': true, 'apps/host/android': false },
		workflow: workflow(),
	});
	const { errors } = check({ root });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /holds no test sources at all/);
});

test('an excuse for a project that is not in this tree is stale, and fails', () => {
	const root = fixture({
		projects: PROJECTS,
		workflow: workflow({ untested: `apps/gone/android=1=${REASON}` }),
	});
	const { errors } = check({ root });
	assert.equal(errors.length, 2);
	assert.ok(errors.some((e) => /is not a Gradle project in this tree/.test(e)));
	assert.ok(errors.some((e) => /apps\/host\/android/.test(e)));
});

test('an excuse for a project whose tests DO run is stale in the other direction', () => {
	const root = fixture({
		projects: PROJECTS,
		workflow: workflow({
			untested: `apps/watch_wear/android=1=${REASON}\n            apps/host/android=1=${REASON}`,
		}),
	});
	const { errors } = check({ root });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /but ci\.yml:\d+ runs `assembleDebug testDebugUnitTest` there/);
});

test('an excuse bought with a placeholder reason fails', () => {
	const root = fixture({ projects: PROJECTS, workflow: workflow({ untested: 'apps/host/android=1=TODO' }) });
	const { errors } = check({ root });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /4-character reason/);
	assert.match(errors[0], /1 test source file\(s\) that run nowhere/);
});

test('an excuse list that has swallowed every project fails rather than testing nothing', () => {
	const root = fixture({
		projects: PROJECTS,
		workflow: workflow({
			dir: 'apps/nowhere',
			untested: `apps/watch_wear/android=1=${REASON}\n            apps/host/android=1=${REASON}`,
		}),
	});
	const { errors } = check({ root });
	assert.ok(errors.some((e) => /no Gradle test runs in CI at all/.test(e)));
});

test('a malformed declaration line names no project, and is refused rather than ignored', () => {
	const root = fixture({ projects: PROJECTS, workflow: workflow({ untested: 'apps/host/android' }) });
	const { errors } = check({ root });
	assert.ok(errors.some((e) => /which is not `<path>=<untested-source-count>=<reason>`/.test(e)));
});

test('an excuse whose declared size no longer matches the project fails, both directions', () => {
	// The half a reason cannot carry: tests are added to a project no job runs,
	// and the excuse still reads as if it covered a known quantity. Shares
	// `parseUnbuilt` with the CodeQL exclusion list for exactly this rule.
	const grown = check({
		root: fixture({ projects: PROJECTS, workflow: workflow({ untested: `apps/host/android=0=${REASON}` }) }),
	});
	assert.equal(grown.errors.length, 1);
	assert.match(grown.errors[0], /hides 0 test source file\(s\) and it now holds 1/);
	assert.match(grown.errors[0], /a green CI says nothing about them/);

	const shrunk = check({
		root: fixture({ projects: PROJECTS, workflow: workflow({ untested: `apps/host/android=4=${REASON}` }) }),
	});
	assert.equal(shrunk.errors.length, 1);
	assert.match(shrunk.errors[0], /hides 4 test source file\(s\) and it now holds 1/);
	assert.match(shrunk.errors[0], /covers more than the project still holds/);
});

test('a walk that finds fewer projects than the floor fails rather than passing over an empty tree', () => {
	const root = fixture({ projects: { 'apps/watch_wear/android': true }, workflow: workflow() });
	const { errors } = check({ root });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /floor is 2/);
});

test('gradleInvocations reads both shapes, and the task list minus the flags', () => {
	const invs = gradleInvocations(
		[
			'      - working-directory: apps/watch_wear/android',
			'        run: ./gradlew assembleDebug testDebugUnitTest --no-daemon',
			'      - name: something else entirely',
			'        run: echo ./gradlew nope',
			'        run: |',
			'          if ! (cd "$p" && ./gradlew --no-daemon compileDebugKotlin); then',
		].join('\n'),
	);
	assert.deepEqual(invs.map((i) => [i.dir, i.tasks.join(' ')]), [
		['apps/watch_wear/android', 'assembleDebug testDebugUnitTest'],
		['$p', 'compileDebugKotlin'],
	]);
});

test('a working-directory does not leak past the step that declared it', () => {
	// Two steps, one with a working-directory and one without: reading the
	// second as if it inherited the first would credit a project with an
	// invocation nobody made there.
	const invs = gradleInvocations(
		[
			'      - working-directory: apps/a/android',
			'        run: ./gradlew test',
			'      - name: elsewhere',
			'        run: ./gradlew test',
		].join('\n'),
	);
	assert.deepEqual(invs.map((i) => i.dir), ['apps/a/android']);
});

test('TEST_TASK matches what runs tests and not what merely compiles', () => {
	for (const t of ['test', 'check', 'build', 'testDebugUnitTest', 'testProdReleaseUnitTest', ':app:test', 'connectedDebugAndroidTest'])
		assert.ok(TEST_TASK.test(t), t);
	for (const t of ['assembleDebug', 'compileDebugKotlin', 'bundleRelease', 'lint', 'testing', 'assembleAndroidTest'])
		assert.equal(TEST_TASK.test(t), false, t);
});

test('testSources reads src/test and not src/main or a nested "test" package', () => {
	const root = mkdtempSync(join(tmpdir(), 'gradle-sources-'));
	for (const p of ['app/src/test/kotlin', 'app/src/main/kotlin/com/x/test', 'app/src/androidTest/kotlin'])
		mkdirSync(join(root, p), { recursive: true });
	writeFileSync(join(root, 'app/src/test/kotlin/ATest.kt'), '');
	writeFileSync(join(root, 'app/src/main/kotlin/com/x/test/Helper.kt'), '');
	writeFileSync(join(root, 'app/src/androidTest/kotlin/BTest.kt'), '');
	assert.deepEqual(
		testSources(root).map((f) => f.slice(root.length + 1)),
		['app/src/test/kotlin/ATest.kt'],
	);
});

test('the shipped workflows run or declare every Gradle test suite this repo holds', () => {
	assert.deepEqual(check().errors, []);
});

test('a declaration and the step that echoes it exist together, or neither does', () => {
	// The echoing step is how a declaration reaches a reader of the run rather
	// than only the guard, so the two are one thing: § 1439 removed both at once
	// when the last declared project started running its tests. What must never
	// happen is a declaration with no echo — a gap recorded where nobody looks.
	const text = readFileSync(join(REPO_ROOT, '.github', 'workflows', 'ci.yml'), 'utf-8');
	const lines = text.split('\n');
	const start = lines.findIndex((l) => /^\s+- name: Gradle unit tests nothing runs\s*$/.test(l));
	const declared = lines.findIndex((l) => /^\s+GRADLE_UNTESTED: \|\s*$/.test(l));
	assert.equal(
		start >= 0,
		declared >= 0,
		start >= 0
			? 'the echoing step is there with nothing declared to echo'
			: 'a GRADLE_UNTESTED declaration is read by the guard alone, with nothing printing it',
	);
	if (declared < 0) return;

	const env = [];
	let i = declared + 1;
	const envIndent = lines[i].search(/\S/);
	for (; lines[i] && lines[i].search(/\S/) >= envIndent && lines[i].trim() !== ''; i++)
		env.push(lines[i].slice(envIndent));

	const runAt = lines.findIndex((l, n) => n > start && /^\s+run: \|\s*$/.test(l));
	const bodyIndent = lines[runAt].indexOf('run:') + 2;
	const body = [];
	for (let j = runAt + 1; lines[j] !== undefined; j++) {
		if (lines[j].trim() !== '' && !lines[j].startsWith(' '.repeat(bodyIndent))) break;
		body.push(lines[j].slice(bodyIndent));
	}

	const out = execFileSync('/bin/bash', ['-c', body.join('\n')], {
		env: { ...process.env, GRADLE_UNTESTED: `${env.join('\n')}\n` },
		encoding: 'utf-8',
	});
	const warnings = out.split('\n').filter((l) => l.startsWith('::warning::'));
	assert.equal(warnings.length, env.length);
	assert.ok(warnings.every((w) => /^::warning::\S+ holds unit tests that no job runs: \S/.test(w)));
	// A blank trailing line must not become a warning about nothing.
	assert.equal(
		execFileSync('/bin/bash', ['-c', body.join('\n')], {
			env: { ...process.env, GRADLE_UNTESTED: '\n\n' },
			encoding: 'utf-8',
		}).trim(),
		'',
	);
});

test('a job whose ~/.gradle key ignores a project it builds fails, and names it', () => {
	// Claim 4. One GRADLE_USER_HOME serves both invocations while the key hashes
	// one of them, so a change to the other project's build files restores the
	// cache written before it.
	const root = fixture({
		projects: PROJECTS,
		workflow: `name: CI
jobs:
  build:
    steps:
      - uses: actions/cache@v4
        with:
          path: ~/.gradle/caches
          key: gradle-\${{ hashFiles('apps/watch_wear/android/**/*.gradle*') }}
      - working-directory: apps/watch_wear/android
        run: ./gradlew testDebugUnitTest --no-daemon
      - working-directory: apps/host/android
        run: ./gradlew testDebugUnitTest --no-daemon
`,
	});
	const { errors } = check({ root });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /invokes Gradle in apps\/host\/android/);
	assert.match(errors[0], /hashes no file under it/);
});

test('a key hashing every project the job invokes passes', () => {
	const root = fixture({
		projects: PROJECTS,
		workflow: `name: CI
jobs:
  build:
    steps:
      - uses: actions/cache@v4
        with:
          path: ~/.gradle/caches
          key: gradle-\${{ hashFiles('apps/watch_wear/android/**/*.gradle*', 'apps/host/android/**/*.gradle*') }}
      - working-directory: apps/watch_wear/android
        run: ./gradlew testDebugUnitTest --no-daemon
      - working-directory: apps/host/android
        run: ./gradlew testDebugUnitTest --no-daemon
`,
	});
	assert.deepEqual(check({ root }).errors, []);
});

test('a key with no hashFiles() covers nothing rather than everything', () => {
	const root = fixture({
		projects: PROJECTS,
		workflow: workflow({ cacheKey: 'v1-fixed' }),
	});
	const { errors } = check({ root });
	assert.ok(errors.some((e) => /hashing nothing/.test(e)), errors.join('\n'));
});

test('a workflow set that caches no ~/.gradle at all fails rather than measuring nothing', () => {
	// The detection is a regex over a step body; if it ever stopped matching,
	// claim 4 would agree with every key in the file. Silence is the one answer
	// it must not give.
	const root = fixture({ projects: PROJECTS, workflow: workflow({ cacheKey: null }) });
	const { errors } = check({ root });
	assert.ok(errors.some((e) => /no workflow caches/.test(e)), errors.join('\n'));
});

test('a gradlew command quoted inside a diagnostic is not an invocation', () => {
	// security.yml prints its own reproduce command in an `::error::`. A reader
	// that counted it would credit a project with a suite that exists only in a
	// sentence — and a message is exactly where such a line is cheapest to add.
	const invs = gradleInvocations(
		[
			'      - working-directory: apps/a/android',
			'        run: |',
			'          if ! ./gradlew assembleDebug; then',
			'            echo "::error::failed; reproduce with: cd apps/a/android && ./gradlew test"',
			'          fi',
			'          echo "or run ./gradlew testDebugUnitTest by hand"',
		].join('\n'),
	);
	assert.deepEqual(
		invs.map((i) => [i.dir, i.tasks.join(' ')]),
		[['apps/a/android', 'assembleDebug']],
	);
});
