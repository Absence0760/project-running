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
	countSources,
	findExpression,
	globNamesSomething,
	jobsDeclaring,
	parseNarrowing,
	parseUnbuilt,
	reasonAbove,
	runScripts,
	walkSurfaces,
} from './check_codeql_coverage.mjs';

/// A fixture tree carrying the marker files the guard walks for.
/** @param {string[]} dirs */
function fixtureRoot(dirs) {
	const root = mkdtempSync(join(tmpdir(), 'codeql-coverage-'));
	for (const d of dirs) {
		mkdirSync(join(root, d), { recursive: true });
		const gradle = d.endsWith('android');
		writeFileSync(join(root, d, gradle ? 'settings.gradle.kts' : 'go.mod'), '');
		// Two source files per Gradle project, so an exclusion's declared size
		// has something to be measured against rather than agreeing with an
		// empty directory by accident.
		if (gradle) for (const f of ['Main.kt', 'Bridge.kt']) writeFileSync(join(root, d, f), '');
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

/// A reason long enough to buy a narrowing, so a case testing something else
/// does not fail on the reason floor.
const REASON = '# a reason long enough to say what would have to change to close this narrowing';

/** @param {{ jsWith?: string, actionsWith?: string }} [opts] */
function interpretedJobs(opts = {}) {
	const jsWith =
		opts.jsWith ?? `          languages: javascript-typescript
          build-mode: none
          queries: security-and-quality
`;
	const actionsWith =
		opts.actionsWith ?? `          languages: actions
          build-mode: none
          queries: security-and-quality
`;
	return `  codeql-javascript:
    steps:
      - uses: github/codeql-action/init@abc
        with:
${jsWith}  codeql-actions:
    steps:
      - uses: github/codeql-action/init@abc
        with:
${actionsWith}`;
}

/** @param {{ kotlinStep?: string, jsWith?: string, actionsWith?: string }} [opts] */
function workflow(opts = {}) {
	const kotlin =
		opts.kotlinStep ??
		`      - name: Build every Gradle project for the CodeQL extractor
        env:
          CODEQL_KOTLIN_UNBUILT: |
            apps/mobile_android/android=2=a reason long enough to say what would have to change to close it
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
${kotlin}${interpretedJobs(opts)}`;
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
	assert.equal(ok.length, 4);
	assert.match(ok[1], /1 scanned, 1 declared unbuilt/);
	assert.match(ok[2], /scans the whole checkout$/);
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
		'apps/mobile_android/android=2=TODO',
	);
	const { errors } = check({ root, workflowText: thin });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /4-character reason/);
});

test('an exclusion list covering every tree fails rather than scanning nothing', () => {
	const root = fixtureRoot(TREES);
	const all = workflow().replace(
		/(apps\/mobile_android\/android=.*)/,
		'$1\n            apps/watch_wear/android=2=also excluded, with a reason of at least forty characters',
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
	// A line carrying no count is refused for the other half of the same
	// reason: it excludes fine and stops saying how much it hides.
	const { entries, malformed } = parseUnbuilt(
		'apps/a=3=because\napps/b\napps/c=because\napps/d=many=because\n\n',
	);
	assert.deepEqual(entries, [{ path: 'apps/a', hidden: 3, reason: 'because' }]);
	assert.deepEqual(malformed, ['apps/b', 'apps/c=because', 'apps/d=many=because']);
});

test('an exclusion whose declared size no longer matches the tree fails, both directions', () => {
	// The state the prose figure could not reach: a bridge lands in a project
	// no security scan reads, and the only thing that said how much was hidden
	// is a sentence nobody recomputes.
	const root = fixtureRoot(TREES);
	writeFileSync(join(root, 'apps/mobile_android/android', 'NewReceiver.kt'), '');
	const grown = check({ root, workflowText: workflow() });
	assert.equal(grown.errors.length, 1);
	assert.match(grown.errors[0], /hides 2 \.kt\/\.java file\(s\) and it now holds 3/);
	assert.match(grown.errors[0], /reports clean over it either way/);

	const shrunk = check({
		root,
		workflowText: workflow().replace(
			'apps/mobile_android/android=2=',
			'apps/mobile_android/android=9=',
		),
	});
	assert.equal(shrunk.errors.length, 1);
	assert.match(shrunk.errors[0], /hides 9 .* and it now holds 3/);
	assert.match(shrunk.errors[0], /covers less than it was granted for/);
});

test('countSources counts the language’s files under a tree and skips generated ones', () => {
	const root = fixtureRoot(['apps/watch_wear/android']);
	mkdirSync(join(root, 'apps/watch_wear/android/build/generated'), { recursive: true });
	writeFileSync(join(root, 'apps/watch_wear/android/build/generated/Gen.kt'), '');
	mkdirSync(join(root, 'apps/watch_wear/android/src'), { recursive: true });
	writeFileSync(join(root, 'apps/watch_wear/android/src/Legacy.java'), '');
	assert.equal(countSources(root, 'apps/watch_wear/android', ['.kt', '.java']), 3);
	assert.equal(countSources(root, 'apps/watch_wear/android', ['.go']), 0);
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

// --- the interpreted legs -------------------------------------------------
//
// `build-mode: none` means no build step can narrow these, which is what the
// guard used to take for "nothing can". The cases below are the routes that
// still can: a `paths` / `paths-ignore` in the init config, a `query-filters`
// exclusion, a narrower `queries:` suite, and a `config-file` holding any of
// the three out of the guard's sight. Each has to fail, because each reads as
// a clean scan afterwards.

test('an interpreted leg that narrows nothing passes and says it scans the whole checkout', () => {
	const root = fixtureRoot(TREES);
	const { errors, ok } = check({ root, workflowText: workflow() });
	assert.deepEqual(errors, []);
	assert.match(ok[2], /javascript-typescript: .* scans the whole checkout$/);
	assert.match(ok[3], /actions: .* scans the whole checkout$/);
});

test('a paths-ignore bought with no reason fails', () => {
	const root = fixtureRoot(TREES);
	const { errors } = check({
		root,
		workflowText: workflow({
			jsWith:
				'          languages: javascript-typescript\n' +
				'          build-mode: none\n' +
				'          queries: security-and-quality\n' +
				'          config: |\n' +
				'            paths-ignore:\n' +
				'              - apps/job_worker\n',
		}),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0], /`paths-ignore` entry `apps\/job_worker` carries a 0-character reason/);
});

test('a paths entry that has stopped matching anything fails, exclusion or inclusion', () => {
	const root = fixtureRoot(TREES);
	for (const key of ['paths', 'paths-ignore']) {
		const { errors } = check({
			root,
			workflowText: workflow({
				jsWith:
					'          languages: javascript-typescript\n' +
					'          build-mode: none\n' +
					'          queries: security-and-quality\n' +
					'          config: |\n' +
					`            ${key}:\n` +
					`              ${REASON}\n` +
					'              - apps/deleted_last_year\n',
			}),
		});
		assert.equal(errors.length, 1, key);
		assert.match(errors[0], /`apps\/deleted_last_year` matches no path in this tree/);
	}
});

test('a paths-ignore that is declared, reasoned and still real is allowed', () => {
	const root = fixtureRoot(TREES);
	const { errors, ok } = check({
		root,
		workflowText: workflow({
			jsWith:
				'          languages: javascript-typescript\n' +
				'          build-mode: none\n' +
				'          queries: security-and-quality\n' +
				'          config: |\n' +
				'            paths-ignore:\n' +
				`              ${REASON}\n` +
				'              - apps/job_worker\n',
		}),
	});
	assert.deepEqual(errors, []);
	assert.match(ok[2], /less 1 declared narrowing\(s\) \(apps\/job_worker\)/);
});

test('a narrower query suite is a narrowing and costs a reason of its own', () => {
	const root = fixtureRoot(TREES);
	const bare =
		'          languages: javascript-typescript\n' +
		'          build-mode: none\n' +
		'          queries: security\n';
	const { errors } = check({ root, workflowText: workflow({ jsWith: bare }) });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /runs `queries: security` .* rather than `security-and-quality`/);

	const excused = check({
		root,
		workflowText: workflow({
			jsWith:
				'          languages: javascript-typescript\n' +
				'          build-mode: none\n' +
				`          ${REASON}\n` +
				'          queries: security\n',
		}),
	});
	assert.deepEqual(excused.errors, []);
});

test('a reason may not be reached across a key that carries a value', () => {
	// Measured regression: an earlier version skipped ANY single line, so
	// `queries:` adopted the comment written about `build-mode:` and a narrowed
	// suite passed with a reason that never mentioned queries.
	const lines = ['# a comment about the line below it, long enough to buy something', 'build-mode: none', 'queries: security'];
	assert.equal(reasonAbove(lines, 2), '');
	assert.match(reasonAbove(lines, 1), /^a comment about/);
	// One container key IS reached across — that is the shape a first list item
	// under its own key always has.
	assert.match(reasonAbove(['# why this filter exists at all', 'query-filters:', '- exclude:'], 2), /^why this filter/);
});

test('a second exclusion appended under the first one’s reason fails rather than inheriting it', () => {
	const root = fixtureRoot(TREES);
	const { errors } = check({
		root,
		workflowText: workflow({
			actionsWith:
				'          languages: actions\n' +
				'          build-mode: none\n' +
				'          queries: security-and-quality\n' +
				'          config: |\n' +
				'            query-filters:\n' +
				`              ${REASON}\n` +
				'              - exclude:\n' +
				'                  id: actions/first-rule\n' +
				'              - exclude:\n' +
				'                  id: actions/second-rule\n',
		}),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0], /`actions\/second-rule` carries a 0-character reason/);
});

test('a query filter naming a rule family this leg cannot emit excludes nothing, and fails', () => {
	const root = fixtureRoot(TREES);
	const { errors } = check({
		root,
		workflowText: workflow({
			actionsWith:
				'          languages: actions\n' +
				'          build-mode: none\n' +
				'          queries: security-and-quality\n' +
				'          config: |\n' +
				'            query-filters:\n' +
				`              ${REASON}\n` +
				'              - exclude:\n' +
				'                  id: js/incomplete-url-substring-sanitization\n',
		}),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0], /is not a rule family this leg emits/);
	assert.match(errors[0], /no-op/);
});

test('narrowing moved into a config-file is refused, not assumed harmless', () => {
	const root = fixtureRoot(TREES);
	const { errors } = check({
		root,
		workflowText: workflow({
			jsWith:
				'          languages: javascript-typescript\n' +
				'          build-mode: none\n' +
				'          queries: security-and-quality\n' +
				'          config-file: ./.github/codeql/js.yml\n',
		}),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0], /does not follow/);
});

test('an interpreted leg that names no query suite runs a narrower default and says so nowhere', () => {
	const root = fixtureRoot(TREES);
	const { errors } = check({
		root,
		workflowText: workflow({
			jsWith: '          languages: javascript-typescript\n          build-mode: none\n',
		}),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0], /names no `queries:` suite/);
});

test('a leg whose scope stops being the whole checkout is sent to SURFACES, not measured here', () => {
	const root = fixtureRoot(TREES);
	const { errors } = check({
		root,
		workflowText: workflow({
			jsWith:
				'          languages: javascript-typescript\n          queries: security-and-quality\n',
		}),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0], /does not declare `build-mode: none`/);
	assert.match(errors[0], /belongs in SURFACES/);
});

test('globNamesSomething reads a bare directory as everything under it, and * as one segment', () => {
	const paths = ['apps', 'apps/web', 'apps/web/src', 'apps/web/src/app.css', 'infra/dns'];
	assert.equal(globNamesSomething('apps/web', paths), true);
	assert.equal(globNamesSomething('apps/web/', paths), true);
	assert.equal(globNamesSomething('apps/*', paths), true);
	assert.equal(globNamesSomething('apps/**/*.css', paths), true);
	// `*` must not cross a separator, or every stale glob "names something".
	assert.equal(globNamesSomething('apps/*.css', paths), false);
	assert.equal(globNamesSomething('apps/mobile_ios', paths), false);
	assert.equal(globNamesSomething('', paths), false);
});

test('parseNarrowing reads both path keys and a query filter, each with its own reason', () => {
	const entries = parseNarrowing(
		[
			'paths-ignore:',
			'  # the generated bundle tree, re-derived from source on every build',
			'  - apps/web/build',
			'query-filters:',
			'  # this note fires on our own advanced config and is not actionable',
			'  - exclude:',
			'      id: actions/unnecessary-use-of-advanced-config',
		].join('\n'),
	);
	assert.deepEqual(
		entries.map((e) => [e.kind, e.value]),
		[
			['paths-ignore', 'apps/web/build'],
			['query-filter', 'actions/unnecessary-use-of-advanced-config'],
		],
	);
	assert.ok(entries.every((e) => e.reason.length >= 40));
});
