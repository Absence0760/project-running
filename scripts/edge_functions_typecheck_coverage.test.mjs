// Guardrail: no Edge Function module sits outside the `deno check` lane.
//
// The Supabase Edge Functions are a Deno program, not a tsc one — their
// modules import over `https:` specifiers tsc's resolver cannot follow — so
// `scripts/tsconfig_coverage.test.mjs` exempts the tree and points here
// instead. What covers it is the `Edge Function typecheck` step of the
// `edge-functions` job, added in decisions § 762 after a `deno check` over the
// tree reported 81 errors that no workflow had ever run.
//
// The lane can only stay complete if what it checks is DERIVED. Its
// predecessor in the same job was written as three hardcoded test paths and
// silently missed every `*.test.ts` added afterwards; that is the failure this
// exists to make impossible. So rather than restate the file set, this guard
// reads the workflow, lifts the step's own `files=$(…)` expression out of it,
// runs THAT, and compares the result with every Deno-compilable source file
// under the tree. The two cannot disagree, because there is only one of them.
//
// Run: `node --test scripts/edge_functions_typecheck_coverage.test.mjs`
// CI:  the `workflow-lint` job in .github/workflows/ci.yml.

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { extname, join, resolve } from 'node:path';
import { test } from 'node:test';

import { parseSteps } from './check_ci_diagnostics.mjs';

const REPO_ROOT = resolve(import.meta.dirname, '..');
const CI_WORKFLOW = join(REPO_ROOT, '.github', 'workflows', 'ci.yml');

const JOB = 'edge-functions';
const STEP = 'Edge Function typecheck';
const WARM_STEP = 'Warm the Deno dependency cache';

/**
 * Extensions Deno compiles as TypeScript. `find -name '*.ts'` covers only the
 * first, which is the shape of the miss this guard reports: a `.mts` or a
 * `.tsx` dropped into the tree is a module the lane walks straight past.
 */
const DENO_TS = new Set(['.ts', '.mts', '.cts', '.tsx']);

/// The Edge Functions tree, repo-relative with a trailing slash. Derived from
/// where `config.toml` sits, exactly as the tsconfig guard's exemption is, so
/// moving the Supabase project moves both together.
function functionsTree() {
	const config = 'apps/backend/supabase/config.toml';
	assert.ok(
		existsSync(join(REPO_ROOT, config)),
		`${config} is gone, so this guard no longer names a tree. Point it at wherever the ` +
			'Supabase project moved to, or drop it if there are no Edge Functions left.',
	);
	return 'apps/backend/supabase/functions/';
}

/// A step that derives its own file set, as `{ workingDirectory, filesExpression,
/// body }`. Two steps in this job do: the warm-cache prefetch and the typecheck,
/// and the pair only holds together while both derive the SAME set.
/**
 * @param {string} name
 * @param {RegExp} command
 * @param {string} why
 * @param {string} [text] the workflow to read; defaults to the committed one.
 *   Overridable so the mutations this guard exists to catch can be fed to it
 *   rather than only reasoned about (decisions § 775 verified them by hand and
 *   committed none of them).
 */
function derivedFilesStep(name, command, why, text = readFileSync(CI_WORKFLOW, 'utf8')) {
	const steps = parseSteps(text).filter(
		(s) => s.job === JOB && s.name === name,
	);
	assert.equal(
		steps.length,
		1,
		`expected exactly one "${name}" step in the \`${JOB}\` job of ci.yml, found ` +
			`${steps.length}. Renaming or removing it is what this guard is here to notice — ` +
			'if the lane moved, move this with it rather than deleting the check.',
	);
	const { body } = steps[0];

	const workdir = body.match(/^\s*working-directory:\s*(\S+)\s*$/m);
	assert.ok(workdir, `the "${name}" step declares no working-directory to resolve paths against.`);

	// The one line that decides what the step reads. Lifting it rather than
	// re-deriving it is the whole point: a rewrite that hardcodes paths has no
	// such line and fails here instead of quietly shrinking the lane.
	const expression = body.match(/^\s*files=\$\((.+)\)\s*$/m);
	assert.ok(
		expression,
		`the "${name}" step no longer derives its file set with a \`files=$(…)\` line. Naming ` +
			'paths instead is how the sibling test step in this job came to miss four new ' +
			'*.test.ts files; keep the derivation and this guard can keep verifying it.',
	);
	assert.match(body, command, why);

	return { workingDirectory: workdir[1], filesExpression: expression[1], body };
}

/** @param {string} [text] */
const typecheckStep = (text) =>
	derivedFilesStep(
		STEP,
		/deno check \$files/,
		`the "${STEP}" step must run \`deno check $files\` — the derived set and the set it ` +
			'actually checks have to be the same one.',
		text,
	);

/** @param {string} [text] */
const warmCacheStep = (text) =>
	derivedFilesStep(
		WARM_STEP,
		/deno cache --no-check \$files/,
		`the "${WARM_STEP}" step must run \`deno cache --no-check $files\` — it exists to pull ` +
			'the whole module graph inside the retry wrapper, over the same set the typecheck ' +
			'then reads.',
		text,
	);

/// What the CI step's own expression selects, repo-relative and sorted.
/** @param {{ workingDirectory: string, filesExpression: string }} step */
function laneFiles(step) {
	const out = execFileSync('bash', ['-c', step.filesExpression], {
		cwd: join(REPO_ROOT, step.workingDirectory),
		encoding: 'utf8',
	});
	return out
		.split('\n')
		.filter(Boolean)
		.map((p) => `${step.workingDirectory}/${p}`)
		.sort();
}

/**
 * Every Deno-compilable source file under the tree: tracked, plus untracked
 * ones git is not ignoring — the same definition of "what is source here"
 * `scripts/tsconfig_coverage.test.mjs` uses, so a module still being written
 * is covered before it is staged rather than after.
 * @param {string} tree
 */
function sourceFiles(tree) {
	/** @param {string[]} args */
	const ls = (args) =>
		execFileSync('git', ['ls-files', '-z', ...args, '--', tree], {
			cwd: REPO_ROOT,
			encoding: 'utf8',
		})
			.split('\0')
			.filter(Boolean);
	return [...new Set([...ls([]), ...ls(['--others', '--exclude-standard'])])]
		.filter((f) => DENO_TS.has(extname(f)))
		.sort();
}

test('the CI typecheck lane checks every Deno module under the functions tree', () => {
	const tree = functionsTree();
	const lane = new Set(laneFiles(typecheckStep()));
	const expected = sourceFiles(tree);

	assert.ok(
		expected.length > 0,
		`no compilable source found under ${tree}, so this guard would pass over anything.`,
	);

	const missed = expected.filter((f) => !lane.has(f));
	assert.deepEqual(
		missed,
		[],
		'These modules are inside the Edge Functions tree but outside the `deno check` lane ' +
			`the \`${JOB}\` job runs, so nothing typechecks them. Widen the step's \`files=$(…)\` ` +
			`expression in .github/workflows/ci.yml — do not leave them outside: ${missed.join(', ')}`,
	);
});

test('the lane covers test files too, not only the modules they exercise', () => {
	const tree = functionsTree();
	const lane = new Set(laneFiles(typecheckStep()));
	const tests = sourceFiles(tree).filter((f) => f.endsWith('.test.ts'));

	assert.ok(tests.length > 0, `no *.test.ts found under ${tree}.`);
	const missed = tests.filter((f) => !lane.has(f));
	assert.deepEqual(
		missed,
		[],
		'The lane skips these test files. A test that does not typecheck is as free to assert ' +
			`something impossible as any other module: ${missed.join(', ')}`,
	);
});

test('the typecheck lane runs before the Supabase stack starts', () => {
	// A `deno check` needs no database. Behind the stack-start step it would sit
	// behind a Docker pull that can fail first and take the typecheck's verdict
	// with it — the same reason `parity-types` hoisted its source-only guards
	// above its own stack start after a broken stack silently skipped the whole
	// web unit suite.
	const ci = readFileSync(CI_WORKFLOW, 'utf8');
	const steps = parseSteps(ci).filter((s) => s.job === JOB);
	const check = steps.findIndex((s) => s.name === STEP);
	const stack = steps.findIndex((s) => /start-supabase|supabase\/setup-cli/.test(s.body));
	assert.ok(check >= 0, `the "${STEP}" step is gone from \`${JOB}\`.`);
	assert.ok(stack >= 0, `no Supabase stack start found in \`${JOB}\` — has the job changed shape?`);
	assert.ok(
		check < stack,
		`"${STEP}" runs after the Supabase stack starts. Move it above, so a stack that fails ` +
			'to come up cannot swallow the typecheck result.',
	);
});

test('the warm-cache prefetch reads every file the typecheck will', () => {
	// `deno cache --no-check` skips TYPECHECKING, not type RESOLUTION: it walks
	// the declaration graph and fetches it. Measured on a cold DENO_DIR, the
	// warm step downloads 776 URLs, 458 of them `.d.ts` (286 stripe URLs among
	// them, `stripe@17.5.0/types/index.d.ts` included), and `deno check`
	// immediately afterwards downloads NOTHING. Run alone with no warm step,
	// `deno check` downloads 403 URLs, 362 of them `.d.ts` — a strict subset of
	// the warm step's 776.
	//
	// That holds only while the two read the same tree. Narrow the warm step —
	// to the test files, as the sibling test step once was — and the typecheck
	// starts fetching declarations OUTSIDE the three-attempt retry that exists
	// to absorb an esm.sh 5xx, which is a CDN blip failing the lane with a bare
	// fetch error. So the property is asserted rather than assumed.
	const warm = new Set(laneFiles(warmCacheStep()));
	const checked = laneFiles(typecheckStep());
	assert.ok(checked.length > 0, 'the typecheck step selected no files at all');
	const unwarmed = checked.filter((f) => !warm.has(f));
	assert.deepEqual(
		unwarmed,
		[],
		'These modules are typechecked but never prefetched, so `deno check` resolves their ' +
			'remote dependencies itself — outside the retry wrapper the warm step exists to be. ' +
			`Widen the "${WARM_STEP}" step's \`files=$(…)\` expression to cover them: ` +
			`${unwarmed.join(', ')}`,
	);
});

test('the warm-cache prefetch runs before the typecheck', () => {
	// A prefetch after the check it feeds is a prefetch of nothing.
	const steps = parseSteps(readFileSync(CI_WORKFLOW, 'utf8')).filter((s) => s.job === JOB);
	const warm = steps.findIndex((s) => s.name === WARM_STEP);
	const check = steps.findIndex((s) => s.name === STEP);
	assert.ok(warm >= 0, `the "${WARM_STEP}" step is gone from \`${JOB}\`.`);
	assert.ok(check >= 0, `the "${STEP}" step is gone from \`${JOB}\`.`);
	assert.ok(warm < check, `"${WARM_STEP}" must run before "${STEP}", not after it.`);
});

// ---------------------------------------------------------------------------
// The mutations § 775 measured by hand. Each is the shape the assertions above
// exist to refuse, fed to them from a rewritten copy of the workflow — because
// an assertion that has only ever read a passing tree is one nobody has seen
// fail.
// ---------------------------------------------------------------------------

/** @param {(text: string) => string} rewrite */
function mutatedWorkflow(rewrite) {
	const text = readFileSync(CI_WORKFLOW, 'utf8');
	const next = rewrite(text);
	assert.notEqual(next, text, 'the mutation changed nothing — it has gone stale against ci.yml');
	return next;
}

test('narrowing the warm step to the test files puts ~450 declaration fetches outside the retry', () => {
	// The exact regression § 775 named: the sibling test step in this job once
	// listed paths, and a warm step written the same way leaves `deno check`
	// resolving stripe's declarations itself, outside the three-attempt wrapper.
	const narrowed = mutatedWorkflow((text) =>
		text.replace(
			/(- name: Warm the Deno dependency cache[\s\S]*?files=\$\()[^)]+(\))/,
			"$1find . -name '*.test.ts' -not -path './_shared/*'$2",
		),
	);
	const warm = new Set(laneFiles(warmCacheStep(narrowed)));
	const checked = laneFiles(typecheckStep(narrowed));
	const unwarmed = checked.filter((f) => !warm.has(f));
	assert.ok(
		unwarmed.length > 0,
		'the narrowed warm step must leave the non-test modules unwarmed',
	);
	// And the committed pair does not, which is the half that makes the
	// assertion above a control rather than an arithmetic coincidence.
	const committedWarm = new Set(laneFiles(warmCacheStep()));
	assert.deepEqual(laneFiles(typecheckStep()).filter((f) => !committedWarm.has(f)), []);
});

test('a step that names its files instead of deriving them is refused', () => {
	const hardcoded = mutatedWorkflow((text) =>
		text.replace(
			/(- name: Edge Function typecheck\n[\s\S]*?)^(\s*)files=\$\([^)]+\)$/m,
			'$1$2files="functions/a.ts functions/b.ts"',
		),
	);
	assert.throws(
		() => typecheckStep(hardcoded),
		/no longer derives its file set/,
		'hardcoding the paths is how the sibling test step came to miss four new files',
	);
});

test('a renamed or duplicated step is reported, not silently read as one', () => {
	const renamed = mutatedWorkflow((text) =>
		text.replace('- name: Edge Function typecheck\n', '- name: Edge Function typecheck (deno)\n'),
	);
	assert.throws(() => typecheckStep(renamed), /expected exactly one "Edge Function typecheck" step/);
});

test('a typecheck step that stops running deno check over its own set is refused', () => {
	const detached = mutatedWorkflow((text) =>
		text.replace('deno check $files', 'deno check ./_shared/env.ts'),
	);
	assert.throws(() => typecheckStep(detached), /must run `deno check \$files`/);
});
