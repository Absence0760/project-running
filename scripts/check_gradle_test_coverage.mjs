#!/usr/bin/env node
// Guardrail: a Gradle project's committed unit tests are run by some job.
//
// This is the CodeQL coverage defect (§ 1304, § 1352) one layer over: a scanner
// that reports success over ground it never read. Here the scanner is the test
// suite. `apps/watch_wear/android` carries 767 `@Test` methods and exactly one
// line in one workflow runs them — `./gradlew assembleDebug testDebugUnitTest`,
// a hardcoded `working-directory` with nothing reading it. Drop the second task
// from that line and 767 tests stop running, every check stays green, and the
// job even keeps its name: it still builds the app. Nothing in the repo could
// tell the difference.
//
// `apps/mobile_android/android` is the case that shows the shape is not
// hypothetical. Its 32 `@Test` methods across three files have never been
// executed by anything: `build-mobile-android` compiles the project on every PR
// (`flutter build apk --release` configures and assembles the whole Gradle
// host, plugin subprojects included), so the AGP / KGP / plugin break the
// followup worried about IS covered — but `assembleRelease` has no dependency
// on a `test*UnitTest` task, so the tests written for those platform-channel
// bridges have been committed, listed in the test inventory, and run nowhere
// (decisions § 1393).
//
// The subject is deliberately narrow: a Gradle project that HOLDS tests. One
// with no `src/test` source set needs no invocation and no excuse, and an
// excuse for a project that has stopped holding tests is stale and fails —
// otherwise an exclusion outlives the thing it excused, which is exactly what
// `check_codeql_coverage.mjs` was written to stop on the other leg.
//
// Three claims, and each is anchored to something that cannot be removed
// without changing what CI does:
//
//   1. Every Gradle project holding tests is named by a Gradle invocation in
//      some workflow. Read from the tree, not from a roster, so a third project
//      is somebody's decision the day it lands rather than a silent gap.
//   2. That invocation runs a TEST task. Not "the job is called build-and-test"
//      and not "a test task is mentioned somewhere" — the task list handed to
//      Gradle in the directory that holds the tests. This is the check that
//      survives the one-word deletion above.
//   3. A project whose tests nothing runs is DECLARED in `GRADLE_UNTESTED` with
//      a reason, the value is echoed by the job itself so the gap is in every
//      run's log rather than in a document, and the entry is re-measured here:
//      it must name a project this tree still holds, that project must still
//      hold tests, and it may not swallow every project at once.
//
// Run: `node scripts/check_gradle_test_coverage.mjs`
// CI:  the `workflow-lint` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_gradle_test_coverage.test.mjs`

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	MIN_REASON_CHARS,
	blockScalar,
	parseUnbuilt,
	walkSurfaces,
} from './check_codeql_coverage.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/// Overridable so the whole script can be pointed at a mutated copy of the
/// tree, which is how a guard is shown to fail.
export const ROOT = process.env.GRADLE_TEST_COVERAGE_ROOT ?? REPO_ROOT;

export const WORKFLOW_DIR = join('.github', 'workflows');

/// The value carrying `<path>=<reason>` lines for projects whose tests nothing
/// runs. Named once, here and in the workflow that declares and echoes it.
export const UNTESTED_KEY = 'GRADLE_UNTESTED';

/**
 * The floor under the WALK, not under the workflows. A walk that stopped
 * matching would find no projects and agree with a repo that runs no Gradle
 * tests at all, and two broken halves pass by agreeing. Raise it, never lower
 * it without meaning to.
 */
export const MIN_PROJECTS = 2;

const MARKER = (/** @type {string} */ name) =>
	name === 'settings.gradle' || name === 'settings.gradle.kts';

const SKIP_DIRS = new Set(['node_modules', '.git', 'build', '.dart_tool', 'target']);

/**
 * Whether a Gradle project holds a JVM unit-test source set with anything in
 * it. An empty `src/test` directory is not tests.
 *
 * @param {string} projectDir
 * @returns {string[]} repo-relative test source files, empty when there are none
 */
export function testSources(projectDir) {
	/** @type {string[]} */
	const found = [];
	/** @param {string} dir @param {boolean} underTest */
	const visit = (dir, underTest) => {
		/** @type {import('node:fs').Dirent[]} */
		let entries;
		try {
			entries = readdirSync(dir, { withFileTypes: true });
		} catch {
			return;
		}
		for (const e of entries) {
			const abs = join(dir, e.name);
			if (e.isDirectory()) {
				if (SKIP_DIRS.has(e.name)) continue;
				visit(abs, underTest || (e.name === 'test' && dir.endsWith(`${sep}src`)));
				continue;
			}
			if (underTest && /\.(kt|java)$/.test(e.name)) found.push(abs);
		}
	};
	visit(projectDir, false);
	return found.sort();
}

/**
 * Every Gradle invocation any workflow makes, as a directory plus the task
 * words handed to Gradle.
 *
 * Both shapes the repo uses are read: a step's `working-directory:` with a
 * `./gradlew …` run, and a `cd <dir> && ./gradlew …` inside a run block. A
 * reader of only the first would see the CodeQL job's loop as no invocation at
 * all — which is the failure mode this whole family of guards exists for.
 *
 * @param {string} text
 * @returns {{ dir: string, tasks: string[], line: number }[]}
 */
export function gradleInvocations(text) {
	const lines = text.split('\n');
	/** @type {{ dir: string, tasks: string[], line: number }[]} */
	const out = [];
	/** @type {string | null} */
	let workingDir = null;
	let stepIndent = -1;

	/// The task words, cut at the first shell terminator: the CodeQL job's own
	/// invocation is `(cd "$p" && ./gradlew … compileDebugKotlin); then`, and a
	/// reader that swallowed the tail would compare `compileDebugKotlin);`
	/// against the task shapes and answer about a task nobody named.
	/** @param {string} raw @returns {string[]} */
	const tasksOf = (raw) =>
		raw
			.split(/\)|;|&&|\|\||\||#/)[0]
			.replace(/\\$/, '')
			.split(/\s+/)
			.filter((w) => w !== '' && !w.startsWith('-') && !/gradlew?$/.test(w));

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		const item = /^(\s*)-\s+\S/.exec(line);
		if (item && item[1].length <= (stepIndent < 0 ? Infinity : stepIndent)) {
			workingDir = null;
			stepIndent = item[1].length;
		}
		const wd = /^\s*(?:-\s+)?working-directory:\s*(\S+)\s*$/.exec(line);
		if (wd) {
			workingDir = wd[1].replace(/^\.\//, '').replace(/\/+$/, '');
			continue;
		}
		const cd = /\bcd\s+(?:"([^"]+)"|'([^']+)'|([^\s;&|)]+))\s*&&\s*\.\/gradlew\s*(.*)$/.exec(line);
		if (cd) {
			const dir = (cd[1] ?? cd[2] ?? cd[3]).replace(/^\.\//, '').replace(/\/+$/, '');
			out.push({ dir, tasks: tasksOf(cd[4]), line: i + 1 });
			continue;
		}
		const gw = /(?:^|[\s;&(])\.\/gradlew\s+(.*)$/.exec(line);
		if (gw && workingDir !== null) {
			out.push({ dir: workingDir, tasks: tasksOf(gw[1]), line: i + 1 });
		}
	}
	return out;
}

/// A task word that makes Gradle run the project's tests. Matched on the task's
/// own shape rather than on the exact spelling the repo uses today, so a
/// variant-qualified task (`testDebugUnitTest`, `testProdReleaseUnitTest`) and
/// the aggregates that depend on them all count — and `assembleDebug`, which is
/// what the invocation reads as once the test task is deleted, does not.
export const TEST_TASK = /^(?::[\w:-]+:)?(test|check|build|connectedCheck|(test[A-Za-z0-9]*UnitTest)|(connected[A-Za-z0-9]*AndroidTest))$/;

/**
 * @param {{ root?: string }} [opts]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function check(opts = {}) {
	const root = opts.root ?? ROOT;
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];

	const dir = join(root, WORKFLOW_DIR);
	if (!existsSync(dir)) {
		return { errors: [`${WORKFLOW_DIR} does not exist; nothing runs any test at all.`], ok };
	}
	/** @type {{ name: string, text: string }[]} */
	const workflows = readdirSync(dir)
		.filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
		.sort()
		.map((f) => ({ name: f, text: readFileSync(join(dir, f), 'utf-8') }));

	const projects = walkSurfaces(root, MARKER);
	if (projects.length < MIN_PROJECTS) {
		errors.push(
			`the tree holds ${projects.length} Gradle project(s) and this guard's floor is ` +
				`${MIN_PROJECTS}. Either the walk stopped matching — in which case this guard has ` +
				`nothing to measure and would pass over a repo that runs no Gradle tests at all — or ` +
				`a project was deleted, in which case lower MIN_PROJECTS deliberately.`,
		);
		return { errors, ok };
	}

	/** @type {{ dir: string, tasks: string[], line: number, file: string }[]} */
	const invocations = [];
	for (const wf of workflows) {
		for (const inv of gradleInvocations(wf.text)) invocations.push({ ...inv, file: wf.name });
	}

	/** @type {{ path: string, reason: string }[]} */
	let declared = [];
	/** @type {string[]} */
	const declaringFiles = [];
	for (const wf of workflows) {
		const raw = blockScalar(wf.text, UNTESTED_KEY);
		if (raw === null) continue;
		declaringFiles.push(wf.name);
		const { entries, malformed } = parseUnbuilt(raw);
		declared = declared.concat(entries);
		for (const line of malformed) {
			errors.push(
				`\`${UNTESTED_KEY}\` in ${wf.name} carries \`${line}\`, which is not ` +
					`\`<path>=<reason>\`. The step that echoes it splits on the first \`=\`, so a line ` +
					`in any other shape names no project and warns about nothing.`,
			);
		}
	}
	if (declaringFiles.length > 1) {
		errors.push(
			`\`${UNTESTED_KEY}\` is declared in ${declaringFiles.join(' and ')}. One declaration ` +
				`site, or two lists disagree about which projects are covered and each looks ` +
				`complete on its own.`,
		);
	}

	/** @type {string[]} */
	const untestedButUndeclared = [];
	let ranProjects = 0;
	let declaredTests = 0;

	for (const project of projects) {
		const tests = testSources(join(root, project));
		const excuse = declared.find((e) => e.path === project);
		if (tests.length === 0) {
			if (excuse) {
				errors.push(
					`\`${UNTESTED_KEY}\` excuses \`${project}\`, which holds no test sources at all. ` +
						`An excuse that has outlived the tests it covered is cover for nothing and hides ` +
						`the next one; delete it.`,
				);
			}
			continue;
		}

		const mine = invocations.filter((inv) => inv.dir === project);
		const testing = mine.filter((inv) => inv.tasks.some((t) => TEST_TASK.test(t)));
		if (testing.length > 0) {
			if (excuse) {
				errors.push(
					`\`${UNTESTED_KEY}\` excuses \`${project}\`, but ${testing[0].file}:${testing[0].line} ` +
						`runs \`${testing[0].tasks.join(' ')}\` there. A stale excuse is a standing ` +
						`invitation to stop running them again.`,
				);
			}
			ranProjects++;
			continue;
		}

		if (excuse) {
			if (excuse.reason.length < MIN_REASON_CHARS) {
				errors.push(
					`\`${UNTESTED_KEY}\` excuses \`${project}\` with a ${excuse.reason.length}-character ` +
						`reason, covering ${tests.length} test source file(s) that run nowhere. It costs ` +
						`at least ${MIN_REASON_CHARS} characters saying what would have to change to ` +
						`close it.`,
				);
			}
			declaredTests += tests.length;
			continue;
		}

		untestedButUndeclared.push(
			`${project} (${tests.length} test source file(s)` +
				(mine.length > 0
					? `; ${mine[0].file}:${mine[0].line} runs \`${mine[0].tasks.join(' ')}\` there, which ` +
						`compiles the app and runs none of them`
					: '; no workflow invokes Gradle there at all') +
				')',
		);
	}

	for (const entry of declared) {
		if (!projects.includes(entry.path)) {
			errors.push(
				`\`${UNTESTED_KEY}\` excuses \`${entry.path}\`, which is not a Gradle project in this ` +
					`tree. Delete it, or point it at where the project moved to.`,
			);
		}
	}

	if (untestedButUndeclared.length > 0) {
		errors.push(
			`no workflow runs a Gradle test task for ${untestedButUndeclared.join('; ')}. Those ` +
				`tests are committed and are executed by nothing, which is the state a green CI is ` +
				`least able to tell you about. Run them, or declare the project in \`${UNTESTED_KEY}\` ` +
				`with a reason saying what would have to change.`,
		);
	}

	if (ranProjects === 0 && projects.length > 0) {
		errors.push(
			`not one of the ${projects.length} Gradle project(s) in this tree has its tests run by ` +
				`any workflow — every suite is either excused or invoked without a test task, so no ` +
				`Gradle test runs in CI at all. A suite nothing executes reports exactly as green as ` +
				`one that passes.`,
		);
	}

	if (errors.length === 0) {
		ok.push(
			`${ranProjects} of ${projects.length} Gradle project(s) have their unit tests run by a ` +
				`workflow` +
				(declaredTests > 0
					? `; ${declaredTests} test source file(s) declared unrun in \`${UNTESTED_KEY}\``
					: ''),
		);
	}
	return { errors, ok };
}

function main() {
	const { errors, ok } = check();
	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);
	if (errors.length > 0) {
		console.error(`\n${errors.length} Gradle test-coverage problem(s).`);
		return 1;
	}
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
