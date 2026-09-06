// Unit tests for the CodeQL build-coverage guard.
//
// The guard's whole claim is that it measures the ANSWER a workflow's own
// enumeration gives rather than the words the enumeration is spelled with, so
// the cases below plant the four shapes that answer wrongly while reading
// plausibly: a hardcoded path, a `find` that hides a tree, an exclusion that
// has outlived its directory, and an exclusion list that has swallowed
// everything. Each is checked to fail; a guard nobody has watched fail is a
// guard nobody knows the failure mode of.
//
// Run: `node --test scripts/check_codeql_coverage.test.mjs`

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
	check,
	findExpression,
	jobsDeclaring,
	parseUnbuilt,
	runScripts,
	walkSurfaces,
} from './check_codeql_coverage.mjs';

/// A fixture tree carrying the marker files the guard walks for.
/** @param {string[]} dirs */
function fixtureRoot(dirs) {
	const root = mkdtempSync(join(tmpdir(), 'codeql-coverage-'));
	for (const d of dirs) {
		mkdirSync(join(root, d), { recursive: true });
		const marker = d.endsWith('android') ? 'settings.gradle.kts' : 'go.mod';
		writeFileSync(join(root, d, marker), '');
	}
	return root;
}

const GO_STEP = `      - name: Build every Go module for CodeQL
        shell: bash
        run: |
          MODULES=$(find . -name go.mod \\
            -not -path './node_modules/*' \\
            -printf '%h\\n' | sort)
          echo "$MODULES"
`;

/** @param {{ kotlinStep?: string }} [opts] */
function workflow(opts = {}) {
	const kotlin =
		opts.kotlinStep ??
		`      - name: Build every Gradle project for the CodeQL extractor
        env:
          CODEQL_KOTLIN_UNBUILT: |
            apps/mobile_android/android=a reason long enough to say what would have to change to close it
        shell: bash
        run: |
          PROJECTS=$(find . \\( -name settings.gradle -o -name settings.gradle.kts \\) \\
            -not -path './node_modules/*' \\
            -printf '%h\\n' | sort -u)
          echo "$PROJECTS"
`;
	return `name: Security
jobs:
  codeql-go:
    steps:
      - uses: github/codeql-action/init@abc
        with:
          languages: go
${GO_STEP}  codeql-kotlin:
    steps:
      - uses: github/codeql-action/init@abc
        with:
          languages: java-kotlin
${kotlin}`;
}

const TREES = [
	'apps/job_worker',
	'apps/graph_cycle',
	'apps/watch_wear/android',
	'apps/mobile_android/android',
];

test('a workflow that enumerates every tree passes', () => {
	const root = fixtureRoot(TREES);
	const { errors, ok } = check({ root, workflowText: workflow() });
	assert.deepEqual(errors, []);
	assert.equal(ok.length, 2);
	assert.match(ok[1], /1 scanned, 1 declared unbuilt/);
});

test('a build step that names a fixed path instead of walking the tree fails', () => {
	const root = fixtureRoot(TREES);
	const { errors } = check({
		root,
		workflowText: workflow({
			kotlinStep:
				'      - name: Build watch_wear\n' +
				'        working-directory: apps/watch_wear/android\n' +
				'        run: ./gradlew compileDebugKotlin\n',
		}),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0], /builds Gradle projects from a fixed path/);
	assert.match(errors[0], /codeql-kotlin/);
});

test('an enumeration that hides a tree the repo holds fails, and names the tree', () => {
	const root = fixtureRoot(TREES);
	const hidden = workflow().replace(
		"-not -path './node_modules/*' \\\n            -printf '%h\\n' | sort -u)",
		"-not -path './apps/mobile_android/*' \\\n            -printf '%h\\n' | sort -u)",
	);
	const { errors } = check({ root, workflowText: hidden });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /does not name apps\/mobile_android\/android/);
	// The verdict has to say the expression was RUN, or a reader will look for
	// the wrong kind of defect.
	assert.match(errors[0], /run, not read/);
});

test('an exclusion naming a directory that is not a tree fails as stale', () => {
	const root = fixtureRoot(TREES);
	const stale = workflow().replace('apps/mobile_android/android=', 'apps/gone/android=');
	const { errors } = check({ root, workflowText: stale });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /excludes `apps\/gone\/android`, which is not a Gradle project/);
});

test('an exclusion bought with a placeholder reason fails', () => {
	const root = fixtureRoot(TREES);
	const thin = workflow().replace(
		/apps\/mobile_android\/android=.*/,
		'apps/mobile_android/android=TODO',
	);
	const { errors } = check({ root, workflowText: thin });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /4-character reason/);
});

test('an exclusion list covering every tree fails rather than scanning nothing', () => {
	const root = fixtureRoot(TREES);
	const all = workflow().replace(
		/(apps\/mobile_android\/android=.*)/,
		'$1\n            apps/watch_wear/android=also excluded, with a reason of at least forty characters',
	);
	const { errors } = check({ root, workflowText: all });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /runs over no source at all/);
});

test('a walk that finds fewer trees than the floor fails rather than agreeing with a broken step', () => {
	// Only one Go module and one Gradle project: a tree in which BOTH the walk
	// and a workflow's `find` could have stopped matching and still agreed.
	const root = fixtureRoot(['apps/job_worker', 'apps/watch_wear/android']);
	const { errors } = check({ root, workflowText: workflow() });
	assert.equal(errors.length, 2);
	assert.ok(errors.every((e) => /floor is 2/.test(e)));
});

test('a language declared by no job, or by two, is refused rather than guessed at', () => {
	const root = fixtureRoot(TREES);
	const none = workflow().replace('          languages: java-kotlin\n', '');
	const { errors } = check({ root, workflowText: none });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /0 job\(s\).*declare/s);
});

test('findExpression matches balanced parens, not the first escaped one', () => {
	// The shape a lazy `[\s\S]*?\)` reads as complete after `\)`, which would
	// hand the shell half an expression.
	const block = `    steps:
      - run: |
          P=$(find . \\( -name a -o -name b \\) -printf '%h\\n' | sort)
`;
	const expr = findExpression(block);
	assert.ok(expr);
	assert.equal(expr.variable, 'P');
	assert.match(expr.script, /-name b \\\) -printf/);
});

test('runScripts and jobsDeclaring read the shapes the workflow actually uses', () => {
	const text = workflow();
	assert.deepEqual(jobsDeclaring(text, 'go'), ['codeql-go']);
	assert.deepEqual(jobsDeclaring(text, 'java-kotlin'), ['codeql-kotlin']);
	assert.equal(runScripts(text).length, 2);
});

test('parseUnbuilt refuses a line the step’s own skip loop could not match', () => {
	// The loop matches on `<path>=`, so a bare path excludes nothing and the
	// build it was meant to skip runs anyway — a silent no-op, not a failure.
	const { entries, malformed } = parseUnbuilt('apps/a=because\napps/b\n\n');
	assert.deepEqual(
		entries.map((e) => e.path),
		['apps/a'],
	);
	assert.deepEqual(malformed, ['apps/b']);
});

test('walkSurfaces skips vendored and build trees', () => {
	const root = fixtureRoot(['apps/job_worker']);
	mkdirSync(join(root, 'node_modules', 'x'), { recursive: true });
	writeFileSync(join(root, 'node_modules', 'x', 'go.mod'), '');
	assert.deepEqual(
		walkSurfaces(root, (n) => n === 'go.mod'),
		['apps/job_worker'],
	);
});

test('the shipped security.yml builds every tree this repo holds', () => {
	const { errors } = check();
	assert.deepEqual(errors, []);
});
