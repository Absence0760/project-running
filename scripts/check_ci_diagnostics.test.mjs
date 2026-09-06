import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

import {
	ANNOTATION,
	DIAGNOSING_JOBS,
	WORKFLOW_DIR,
	checkAll,
	GATE_JOB,
	checkFailureScoping,
	checkGateCoverage,
	checkGateVerdict,
	checkRuleSubjects,
	checkShellSafeDiagnoses,
	checkStepDiagnoses,
	derivedBundles,
	hasShellSubstitutionBacktick,
	ACTION_DIR,
	RULE_SUBJECTS,
	parseActionSteps,
	readActions,
	stepSources,
	isGuardStep,
	parseJobBlock,
	parseJobIf,
	parseJobKeys,
	parseNeeds,
	parseSteps,
	readWorkflows,
	runBody,
	checkStatedJobCount,
	ORIENTATION_DOC,
} from './check_ci_diagnostics.mjs';

const CENSUS_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/**
 * @param {string} name
 * @param {string} cmd
 */
const selfDiagnosing = (name, cmd) =>
	`      - name: ${name}\n` +
	`        run: |\n` +
	`          if ! ${cmd}; then\n` +
	`            echo "${ANNOTATION}${name} failed."\n` +
	`            exit 1\n` +
	`          fi\n`;

/// The job under test in every `checkStepDiagnoses` fixture below.
const BUNDLED = 'parity-types';

/// A command that reads as one of this repo's guards, so a job carrying two of
/// them is DERIVED as bundled. Fixtures use it wherever they only need a job to
/// exist and be well-formed: a fixture whose every job ran `echo hi` would
/// derive no bundle at all and collect the vacuous-pass complaint, which is a
/// real error and has its own test below.
/** @param {string} label */
const guardCmd = (label) => `node --test scripts/${label}.test.mjs`;

/// A workflow holding a job shaped like the real `parity-types` — several
/// named check steps, then whatever trailing step the caller wants — plus a
/// minimal well-formed body for every OTHER registered job. Those have to be
/// present: `checkStepDiagnoses` also reports a registered job it cannot find,
/// which is the point of that half, and a fixture naming only one of them
/// would collect that complaint about all the rest.
/** @param {string} steps */
function bundledJob(steps) {
	const others = [...DIAGNOSING_JOBS.keys()]
		.filter((job) => job !== BUNDLED)
		.map(
			(job) =>
				`  ${job}:\n    steps:\n` +
				`${selfDiagnosing('one', guardCmd('one'))}${selfDiagnosing('two', guardCmd('two'))}`,
		)
		.join('');
	return `name: CI\njobs:\n  ${BUNDLED}:\n    name: Schema / type drift\n    steps:\n${steps}${others}`;
}

test('parseSteps splits a job into its steps and reads name / if / run off each', () => {
	const steps = parseSteps(
		`name: CI\njobs:\n  a:\n    steps:\n` +
			`      - uses: actions/checkout@abc\n` +
			`      - name: one\n        run: echo hi\n` +
			`      - name: two\n        if: failure()\n        run: echo bye\n`,
	);
	assert.deepEqual(
		steps.map((s) => [s.job, s.name, s.if, s.hasRun]),
		[
			['a', null, null, false],
			['a', 'one', null, true],
			['a', 'two', 'failure()', true],
		],
	);
});

// A comment sitting between two steps belongs to neither. Folding it into the
// step above would let prose that merely mentions an annotation satisfy the
// per-step rule for a step that prints nothing.
test('parseSteps leaves a comment between two steps out of both', () => {
	const [first, second] = parseSteps(
		`name: CI\njobs:\n  a:\n    steps:\n` +
			`      - name: one\n        run: echo hi\n` +
			`      # ${ANNOTATION}prose, not a diagnosis\n` +
			`      - name: two\n        run: echo bye\n`,
	);
	assert.equal(first.body.includes(ANNOTATION), false);
	assert.equal(second.body.includes(ANNOTATION), false);
});

test('parseSteps ends a job at the next job key rather than running on', () => {
	const steps = parseSteps(
		`name: CI\njobs:\n  a:\n    steps:\n      - name: one\n        run: echo hi\n` +
			`\n  b:\n    steps:\n      - name: two\n        run: echo bye\n`,
	);
	assert.deepEqual(steps.map((s) => [s.job, s.name]), [
		['a', 'one'],
		['b', 'two'],
	]);
});

test('an `if: failure()` step that prints a diagnosis is the reported bug', () => {
	const { errors } = checkFailureScoping([
		{
			name: 'ci.yml',
			text: bundledJob(
				selfDiagnosing('Web TS unit tests', 'npx tsx --test') +
					`      - run: npm run gen:types:check\n` +
					`      - if: failure()\n` +
					`        run: |\n` +
					`          echo "${ANNOTATION}database.types.ts is out of sync."\n`,
			),
		},
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /true for a failure anywhere earlier in the job/);
});

// The distinction the rule turns on: an on-failure artifact upload asserts
// nothing about which step failed, so it is not a misattribution.
test('an `if: failure()` step that only uploads artifacts is allowed', () => {
	const { errors, ok } = checkFailureScoping([
		{
			name: 'ci.yml',
			text:
				`name: CI\njobs:\n  sim:\n    steps:\n` +
				`      - name: Upload logs on failure\n        if: failure()\n` +
				`        uses: actions/upload-artifact@abc\n`,
		},
	]);
	assert.deepEqual(errors, []);
	assert.deepEqual(ok, []);
});

test('a diagnosis scoped to one step’s outcome is allowed', () => {
	const { errors, ok } = checkFailureScoping([
		{
			name: 'ci.yml',
			text:
				`name: CI\njobs:\n  a:\n    steps:\n` +
				`      - id: drift\n        run: npm run gen:types:check\n` +
				`      - if: failure() && steps.drift.outcome == 'failure'\n` +
				`        run: echo "${ANNOTATION}out of sync."\n`,
		},
	]);
	assert.deepEqual(errors, []);
	assert.equal(ok.length, 1);
});

test('checkFailureScoping fails rather than passing vacuously over no on-failure steps', () => {
	const { errors } = checkFailureScoping([
		{ name: 'ci.yml', text: 'name: CI\njobs:\n  a:\n    steps:\n      - run: echo hi\n' },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /enforces nothing/);
});

test('a bundled job’s check step with no diagnosis of its own fails', () => {
	const { errors } = checkStepDiagnoses([
		{
			name: 'ci.yml',
			text: bundledJob(
				selfDiagnosing('Migration version keys are unique', 'node check.mjs') +
					`      - name: Web TS unit tests\n        run: npx tsx --test\n`,
			),
		},
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /"Web TS unit tests" in job `parity-types` prints no/);
});

// `uses:` steps (checkout, setup-node, the stack-start composite) and the
// unnamed `npm ci` run nothing this rule can ask to diagnose itself.
test('a bundled job’s setup steps are not asked to diagnose themselves', () => {
	const { errors, ok } = checkStepDiagnoses([
		{
			name: 'ci.yml',
			text: bundledJob(
				`      - uses: actions/checkout@abc\n` +
					`      - run: npm ci\n` +
					selfDiagnosing('one', guardCmd('one')) +
					selfDiagnosing('two', guardCmd('two')),
			),
		},
	]);
	assert.deepEqual(errors, []);
	// Two per registered job: the two named `run:` steps each one carries here.
	// The `uses:` and the unnamed `npm ci` above are not among them.
	assert.equal(ok.length, 2 * DIAGNOSING_JOBS.size);
});

test('checkStepDiagnoses fails when a registered job is renamed out from under it', () => {
	const { errors } = checkStepDiagnoses([
		{
			name: 'ci.yml',
			text:
				`name: CI\njobs:\n  renamed:\n    steps:\n` +
				`${selfDiagnosing('one', guardCmd('one'))}${selfDiagnosing('two', guardCmd('two'))}`,
		},
	]);
	// One error per registered job — the synthetic workflow above holds none of
	// them. Counted off the registry rather than written down, so registering a
	// second bundled job does not fail this on arithmetic.
	assert.equal(errors.length, DIAGNOSING_JOBS.size);
	for (const error of errors) assert.match(error, /reading nothing/);
});

// The derived half of rule 2. A job that runs two of this repo's guards is
// bundled BY THAT FACT — nothing has to remember to register it, which is how
// `parity-matrix` bundled four registry guards for its whole life while the
// registry named neither it nor `workflow-lint`.
test('a job running two guards is derived as bundled; one guard is not', () => {
	const bundles = derivedBundles([
		{
			name: 'ci.yml',
			text:
				`name: CI\njobs:\n` +
				`  two-guards:\n    steps:\n` +
				`      - run: node scripts/check_a.mjs\n` +
				`      - run: node --test scripts/b.test.mjs\n` +
				`  one-guard:\n    steps:\n` +
				`      - run: node scripts/check_c.mjs\n` +
				`      - run: npm ci\n`,
		},
	]);
	assert.deepEqual([...bundles], [['two-guards', 2]]);
});

// A step called "check_production_env tests" is not a guard invocation because
// of its LABEL. Matching the whole step body would make the name decide.
test('a step is a guard by what it runs, not by what it is called', () => {
	const [named, guard] = parseSteps(
		`name: CI\njobs:\n  a:\n    steps:\n` +
			`      - name: check_production_env tests\n        run: echo hi\n` +
			`      - name: something else\n        run: node scripts/check_x.mjs\n`,
	);
	assert.equal(runBody(named).includes('check_production_env'), false);
	assert.equal(isGuardStep(named), false);
	assert.equal(isGuardStep(guard), true);
});

// `parity-matrix`'s Dart matrix check was UNNAMED, so a names-only rule made
// "delete the name" a way out of the requirement. The step GitHub displays as
// its own command is still the step a reader has to attribute.
test('an unnamed guard step in a bundled job must diagnose itself too', () => {
	const { errors } = checkStepDiagnoses([
		{
			name: 'ci.yml',
			text:
				`name: CI\njobs:\n  registries:\n    steps:\n` +
				`${selfDiagnosing('one', guardCmd('one'))}` +
				`      - run: dart run scripts/check_parity_matrix.dart\n`,
		},
	]);
	const derived = errors.filter((e) => e.includes('check_parity_matrix.dart'));
	assert.equal(derived.length, 1);
	assert.match(derived[0], /runs 2 of this repo's guards under one job name/);
});

// The other side of the same rule: an unnamed step that runs no guard is setup,
// and setup has nothing to diagnose. Without this the rule would demand an
// `::error::` from `npm ci`.
test('an unnamed non-guard step in a derived bundle is left alone', () => {
	const { errors, ok } = checkStepDiagnoses([
		{
			name: 'ci.yml',
			text: bundledJob(
				`      - run: npm ci\n` +
					selfDiagnosing('one', guardCmd('one')) +
					selfDiagnosing('two', guardCmd('two')),
			),
		},
	]);
	assert.deepEqual(errors, []);
	assert.equal(
		ok.some((line) => line.includes('npm ci')),
		false,
	);
});

test('checkStepDiagnoses fails rather than passing vacuously over no derived bundle', () => {
	const { errors } = checkStepDiagnoses([
		{
			name: 'ci.yml',
			text: bundledJob(selfDiagnosing('one', 'echo a') + selfDiagnosing('two', 'echo b')).replace(
				/node --test scripts\/\w+\.test\.mjs/g,
				'echo hi',
			),
		},
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /enforces nothing beyond/);
});

/// A workflow whose `ci-gate` needs exactly the jobs named.
/**
 * @param {readonly string[]} jobs
 * @param {readonly string[]} needs
 */
const gated = (jobs, needs) =>
	`name: CI\non:\n  push:\n  pull_request:\njobs:\n` +
	jobs.map((job) => `  ${job}:\n    steps:\n      - run: echo hi\n`).join('') +
	`  ${GATE_JOB}:\n    needs:\n${needs.map((n) => `      - ${n}\n`).join('')}` +
	`    steps:\n      - run: echo gate\n`;

// `on:` holds two-space keys too. Reading them as jobs would demand the gate
// wait for `push` and `pull_request`, which are triggers, not work.
test('parseJobKeys reads the jobs mapping and not the trigger list', () => {
	assert.deepEqual(parseJobKeys(gated(['a', 'b'], ['a', 'b'])), ['a', 'b', GATE_JOB]);
});

test('parseNeeds reads a block list, a flow sequence and a bare scalar alike', () => {
	assert.deepEqual(parseNeeds(gated(['a', 'b'], ['a', 'b']), GATE_JOB), ['a', 'b']);
	assert.deepEqual(
		parseNeeds(`name: CI\njobs:\n  ${GATE_JOB}:\n    needs: [a, b]\n`, GATE_JOB),
		['a', 'b'],
	);
	assert.deepEqual(parseNeeds(`name: CI\njobs:\n  ${GATE_JOB}:\n    needs: a\n`, GATE_JOB), ['a']);
	assert.equal(parseNeeds(`name: CI\njobs:\n  ${GATE_JOB}:\n    steps: []\n`, GATE_JOB), null);
});

// The failure mode splitting a bundled job into N jobs invites, and the reason
// this repo keeps the bundles: the aggregator counts a job it never waited for
// as no result at all, so the new job's RED is a row nobody is gated on.
test('a job missing from the gate’s needs is the reported bug', () => {
	const { errors } = checkGateCoverage([{ name: 'ci.yml', text: gated(['a', 'b'], ['a']) }]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /job `b` is in no `needs:` entry/);
});

test('a needs entry naming no job fails rather than waiting forever', () => {
	const { errors } = checkGateCoverage([{ name: 'ci.yml', text: gated(['a'], ['a', 'deleted']) }]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /not a job in this file/);
});

test('a gate with no needs at all is green whatever the file does, and fails', () => {
	const { errors } = checkGateCoverage([
		{ name: 'ci.yml', text: `name: CI\njobs:\n  a:\n    steps:\n      - run: echo hi\n  ${GATE_JOB}:\n    steps:\n      - run: echo gate\n` },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /declares no `needs:`/);
});

/// A workflow whose `ci-gate` waits for `jobs` and judges them with `verdict`.
/// The default verdict is the real one's shape: the whole context injected
/// through `env:`, and a non-zero exit on anything that is neither success nor
/// skipped.
/**
 * @param {readonly string[]} jobs
 * @param {{ cond?: string | null, verdict?: string }} [opts]
 */
const gateWith = (jobs, opts = {}) => {
	const cond = opts.cond === undefined ? '    if: always()\n' : opts.cond === null ? '' : `    if: ${opts.cond}\n`;
	const verdict =
		opts.verdict ??
		`      - name: Require every upstream job to have passed\n` +
			`        env:\n` +
			`          NEEDS_JSON: \${{ toJSON(needs) }}\n` +
			`        run: |\n` +
			`          if [ -n "$NEEDS_JSON" ]; then\n` +
			`            exit 1\n` +
			`          fi\n`;
	return (
		`name: CI\non:\n  push:\njobs:\n` +
		jobs.map((job) => `  ${job}:\n    steps:\n      - run: echo hi\n`).join('') +
		`  ${GATE_JOB}:\n${cond}    needs:\n${jobs.map((n) => `      - ${n}\n`).join('')}` +
		`    steps:\n${verdict}`
	);
};

test('parseJobBlock and parseJobIf read the job level, not a step’s condition', () => {
	const text = gateWith(['a']);
	const block = parseJobBlock(text, GATE_JOB);
	assert.ok(block !== null && block.startsWith(`  ${GATE_JOB}:`));
	assert.ok(!block.includes('  a:\n'), 'the gate block must stop at the previous job');
	assert.equal(parseJobIf(text, GATE_JOB), 'always()');
	assert.equal(parseJobIf(text, 'a'), null);
	// A step's own `if:` sits deeper and is not the job's. Asserted on a
	// `steps:` line the block-scan cannot recognise (a trailing comment), which
	// is the one shape that puts the step lines inside the scanned range: with a
	// bare `steps:` the slice already excludes them, so a looser condition
	// pattern would go unnoticed there.
	assert.equal(
		parseJobIf(`name: CI\njobs:\n  a:\n    steps: # the checks\n      - if: failure()\n        run: echo hi\n`, 'a'),
		null,
	);
	// The gate is the last job in the real file, so the block runs to EOF. A
	// top-level key AFTER the mapping is the other boundary, and it is a
	// different branch.
	const trailing = `${gateWith(['a'])}defaults:\n  run:\n    shell: bash\n`;
	const gateBlock = parseJobBlock(trailing, GATE_JOB);
	assert.ok(gateBlock !== null && !gateBlock.includes('defaults:'), gateBlock ?? 'null');
	assert.equal(parseJobBlock(gateWith(['a']), 'nope'), null);
});

// The real gate at the time rule 4 was written, so a rewrite of the shape has
// to keep meaning the same thing rather than merely keep passing.
test('the repo’s own gate derives its verdict from every job it waits for', () => {
	const { errors, ok } = checkGateVerdict(readWorkflows(WORKFLOW_DIR));
	assert.deepEqual(errors, []);
	assert.ok(
		ok.some((l) => /reads the whole `needs` context/.test(l)),
		`expected a whole-context read, got ${JSON.stringify(ok)}`,
	);
	assert.ok(ok.some((l) => /exits non-zero/.test(l)));
});

// Rule 3 is satisfied in every one of the four fixtures below — the `needs:`
// list is complete in all of them. That is the point: the list being right is
// not what makes a merge blocked.
test('a gate without `always()` is skipped on exactly the runs it exists to block', () => {
	for (const cond of [null, "github.event_name == 'push'"]) {
		const text = gateWith(['a', 'b'], { cond });
		assert.deepEqual(checkGateCoverage([{ name: 'ci.yml', text }]).errors, []);
		const { errors } = checkGateVerdict([{ name: 'ci.yml', text }]);
		assert.equal(errors.length, 1, `cond=${cond}`);
		assert.match(errors[0], /skipped required check does not hold a merge/);
	}
	assert.deepEqual(checkGateVerdict([{ name: 'ci.yml', text: gateWith(['a'], { cond: 'always()' }) }]).errors, []);
});

test('a gate that never reads the needs context is a green row that means nothing', () => {
	const text = gateWith(['a', 'b'], {
		verdict: `      - run: |\n          echo "all good"\n          exit 1\n`,
	});
	assert.deepEqual(checkGateCoverage([{ name: 'ci.yml', text }]).errors, []);
	const { errors } = checkGateVerdict([{ name: 'ci.yml', text }]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /never reads the `needs` context/);
});

test('a gate reading only some of the jobs it waits for names the ones it cannot judge', () => {
	const text = gateWith(['a', 'b', 'c'], {
		verdict:
			`      - run: |\n` +
			`          if [ "\${{ needs.a.result }}" != success ]; then exit 1; fi\n`,
	});
	const { errors } = checkGateVerdict([{ name: 'ci.yml', text }]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /reads only 1 of them; b, c could fail with the gate still green/);
});

test('a gate that reads every result and never exits non-zero prints the failure on a green check', () => {
	const text = gateWith(['a', 'b'], {
		verdict:
			`      - env:\n          NEEDS_JSON: \${{ toJSON(needs) }}\n` +
			`        run: echo "$NEEDS_JSON"\n`,
	});
	const { errors } = checkGateVerdict([{ name: 'ci.yml', text }]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /no non-zero `exit` on any path/);
});

test('a gate with no command at all reports success as soon as its runner starts', () => {
	const text = gateWith(['a'], { verdict: `      - uses: actions/checkout@v5\n` });
	const { errors } = checkGateVerdict([{ name: 'ci.yml', text }]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /runs no command at all/);
});

test('checkGateVerdict says nothing about a workflow that defines no gate', () => {
	const text = 'name: Release\njobs:\n  a:\n    steps:\n      - run: echo hi\n';
	assert.deepEqual(checkGateVerdict([{ name: 'release.yml', text }]), { errors: [], ok: [] });
});

test('checkGateCoverage fails rather than passing vacuously when the gate is gone', () => {
	const { errors } = checkGateCoverage([
		{ name: 'ci.yml', text: 'name: CI\njobs:\n  a:\n    steps:\n      - run: echo hi\n' },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /nothing now aggregates/);
});

// Rule 2's blind spot, reported rather than only described in an ADR. The
// followup that asked for it said nobody had measured how many steps a
// widening would newly catch; the guard now states the set at every run, so
// the next reader does not have to derive it again.
test('an unnamed non-guard step in a bundled job is reported as exempt, not silently skipped', () => {
	const { errors, exempt } = checkStepDiagnoses([
		{
			name: 'ci.yml',
			text: bundledJob(
				`      - run: npm ci\n` +
					selfDiagnosing('one', guardCmd('one')) +
					selfDiagnosing('two', guardCmd('two')) +
					`      - if: failure()\n        run: echo done\n`,
			),
		},
	]);
	assert.deepEqual(errors, []);
	assert.equal(exempt.length, 2);
	assert.match(exempt[0], /job `parity-types` runs `npm ci` unnamed/);
	assert.match(exempt[1], /runs `echo done` unnamed/);
	assert.match(exempt[0], /rule 2 does not ask it to diagnose itself/);
});

test('the exempt set over the real workflows is unnamed setup, and nothing else', () => {
	const { exempt } = checkStepDiagnoses(readWorkflows(WORKFLOW_DIR));
	// Not a pinned count: the assertion is that nothing in the blind spot runs
	// anything from THIS repo. A step invoking a repo-local path is a check
	// whose failure the job name cannot explain, and would have to be named.
	for (const line of exempt) {
		assert.doesNotMatch(line, /\bbin\/|\bscripts\/|\bapps\/|\binfra\/|\.github\//, line);
	}
});

test('the repo’s real workflows carry no misattributable diagnosis', () => {
	const files = readWorkflows(WORKFLOW_DIR);
	const { errors, diagnoses, scoping, gate } = checkAll(files, readActions(ACTION_DIR));
	assert.deepEqual(errors, []);
	assert.ok(scoping.conditioned >= 5, `expected the on-failure steps, found ${scoping.conditioned}`);
	assert.ok(
		diagnoses.ok.length >= 4,
		`expected every check step of ${[...DIAGNOSING_JOBS.keys()].join(', ')}, found ${diagnoses.ok.length}`,
	);
	// The three the registry never named. Pinned by name because each one is a
	// bundle that shipped un-diagnosed, and a rule that stopped seeing them
	// would go quiet rather than red.
	for (const job of ['parity-matrix', 'workflow-lint', 'pgtap-rls']) {
		assert.ok(diagnoses.bundles.has(job), `${job} should derive as a bundled job`);
	}
	assert.equal(
		DIAGNOSING_JOBS.has('parity-matrix'),
		false,
		'parity-matrix is derived, so registering it by hand would be the coupling this replaced',
	);
	assert.ok(gate.covered >= 20, `expected ci.yml's jobs to be gated, found ${gate.covered}`);
});

// ---------------------------------------------------------------------------
// A guard that no workflow invokes enforces nothing, and a guard invoked only
// by a workflow the required check does not wait for blocks nothing.
//
// decisions.md § 773 found `check_root_scripts.mjs` in that first state — "a
// guard enforcing nothing for as long as it has existed", the § 439 shape, and
// the filing that reported four misreads in it did not notice. § 775 found the
// second state: `web-bundle-budget.yml` was its own workflow, in no `needs:` of
// the `CI gate` aggregator, so a red budget did not block a merge. Both were
// found by reading rather than by anything that would find the next one.
//
// The census below is that thing. It is a test rather than a rule inside
// `check_ci_diagnostics.mjs` because the answer for a guard living outside
// ci.yml is a judgement — some of them legitimately do — and a judgement
// recorded as a named entry with a reason is the shape § 775 settled on for
// exactly this ("a moving boundary exempts things nobody has read; a name
// exempts one thing somebody did").
// ---------------------------------------------------------------------------

/// Directories holding this repo's own guards.
const GUARD_DIRS = ['scripts', 'apps/web/scripts', 'apps/backend/scripts'];

/// Files in those directories that are not guards: shared lexers and helpers
/// reached only through a consumer, generators, and local dev tools. Each is
/// named rather than pattern-matched, so a new guard cannot join the list by
/// being spelled a certain way.
const NOT_A_GUARD = new Map([
	['scripts/comment_strip.mjs', 'a lexer, consumed by four guards'],
	['scripts/hcl_lex.mjs', 'a lexer, consumed by three guards'],
	['scripts/markdown_lines.mjs', 'a lexer, consumed by three guards'],
	['scripts/shell_lex.mjs', 'a lexer, consumed by two guards'],
	['scripts/web_icon_font.mjs', "the icon extractor, consumed by the generator and its suite"],
	['scripts/gen_web_icon_font.mjs', 'a generator; its output is what the guard checks'],
	['scripts/gen_catalogue_fold_table.mjs', 'a generator; its output is what the guard checks'],
	[
		'scripts/gen_exercise_fold_table.mjs',
		'a generator; unlike the catalogue table it is FROZEN, so nothing re-renders it '
			+ '(decisions § 1176) and what CI checks is check_shared_constants.mjs comparing its '
			+ 'three rails',
	],
	['scripts/sync_deno_lock.mjs', 'a syncer; ci.yml runs it with --check'],
	['scripts/dev_run_graphhopper.mjs', 'a local dev tool'],
	['scripts/dev_run_osrm.mjs', 'a local dev tool'],
	['scripts/seed-run-tracks.mjs', 'a local dev seeding tool'],
	['apps/backend/scripts/sql_lex.mjs', 'a lexer, consumed by four guards'],
	['apps/backend/scripts/edge_function_neuter.mjs', "the vacuity guard's mutation operator"],
	['apps/backend/scripts/pgtap_definer_neutralisers.mjs', "the pgtap guard's mutation operator"],
	['apps/web/scripts/env_isolation.mjs', 'a vite plugin, loaded by the web build'],
	['apps/web/scripts/cross_client_roundtrip_read.mjs', 'a round-trip lane read half'],
	['apps/web/scripts/cross_client_roundtrip_route_read.mjs', 'a round-trip lane read half'],
	['apps/web/scripts/cross_client_roundtrip_live_read.mjs', 'a round-trip lane read half'],
	['apps/web/scripts/cross_client_roundtrip_sync_read.mjs', 'a round-trip lane read half'],
]);

/// Guards whose invoking workflow is NOT ci.yml, and therefore whose failure
/// the required `CI gate` status check does not wait for. Each entry says which
/// workflow runs it and why that is the arrangement; a guard that leaves this
/// state, or a stale entry, fails below.
const OFF_THE_GATE = new Map([
	[
		'apps/web/scripts/check_production_env.mjs',
		'release-web.yml at tag time, and only there — the guard is an assertion ABOUT a ' +
			'release env (a real https Supabase host, a set anon + MapTiler key), and CI has ' +
			'placeholders by design: `build-web` compiles against placeholder.supabase.co, ' +
			'which this guard exists to refuse. Its CLI in ci.yml could therefore only ever ' +
			'fail, or be inverted into an assertion that also passes when the guard crashes. ' +
			'What the gate holds instead is its SUITE, which spawns that CLI against crafted ' +
			'envs, in the `env-isolation` job of ci.yml (decisions § 862).',
	],
	[
		'scripts/check_compliance_drift.mjs',
		'compliance-drift.yml, deliberately advisory (COMPLIANCE_DRIFT_MODE=warn) — it ' +
			'reports findings and never fails the job, so being off the gate is the design ' +
			'rather than a gap.',
	],
]);

/// Guard SUITES ci.yml does not run — the same judgement as OFF_THE_GATE, one
/// level down. A guard can legitimately live off the required check (a release
/// gate, an advisory sweep); its own tests measure the GUARD, which is repo
/// source like any other, so they belong on the gate even when the guard's
/// subject does not exist there. The one exception is a guard that is advisory
/// end to end.
const SUITE_OFF_THE_GATE = new Map([
	[
		'scripts/check_compliance_drift.test.mjs',
		'compliance-drift.yml, alongside the advisory guard it tests — that guard never ' +
			'fails its job (COMPLIANCE_DRIFT_MODE=warn), so neither half of the pair is ' +
			'something a merge waits for, and moving only the suite would gate the ' +
			'instrument while its verdict stayed advisory.',
	],
]);

/** @returns {string[]} repo-relative paths of every .mjs under GUARD_DIRS */
function allScripts() {
	return GUARD_DIRS.flatMap((dir) =>
		readdirSync(join(CENSUS_ROOT, dir))
			.filter((f) => f.endsWith('.mjs'))
			.map((f) => `${dir}/${f}`),
	).sort();
}

/** Every workflow and composite action, as `{ name, text }`. */
function allAutomation() {
	const files = readWorkflows(WORKFLOW_DIR).map((f) => ({ name: f.name, text: f.text }));
	const actionDir = join(CENSUS_ROOT, '.github', 'actions');
	for (const entry of readdirSync(actionDir, { withFileTypes: true })) {
		if (!entry.isDirectory()) continue;
		for (const f of ['action.yml', 'action.yaml']) {
			const abs = join(actionDir, entry.name, f);
			if (!existsSync(abs)) continue;
			files.push({ name: `actions/${entry.name}/${f}`, text: readFileSync(abs, 'utf-8') });
		}
	}
	return files;
}

/// Every package.json script this repo declares, as `name -> body`. A workflow
/// reaches several guards through one (`npm run check:check-constraints`), so a
/// census reading only the workflow text would report those as run by nothing.
function packageScripts() {
	/** @type {Map<string, string>} */
	const out = new Map();
	for (const manifest of ['package.json', 'apps/web/package.json', 'apps/backend/package.json']) {
		const abs = join(CENSUS_ROOT, manifest);
		if (!existsSync(abs)) continue;
		const scripts = JSON.parse(readFileSync(abs, 'utf-8')).scripts ?? {};
		for (const [name, body] of Object.entries(scripts)) {
			out.set(name, `${out.get(name) ?? ''}\n${body}`);
		}
	}
	return out;
}

/// A workflow file's commands, with the package.json scripts they run spliced
/// in — and with comments and `echo`'d reproduce lines removed.
///
/// Those two exclusions are the point. A comment or an `echo` makes the same
/// claim a command does and executes nothing, and § 773's `check_root_scripts`
/// was named in a comment inside the very file that did not run it. A census
/// reading whole file text would have scored it as covered.
/** @param {{name: string, text: string}} file @param {Map<string,string>} scripts */
function commandsOf(file, scripts) {
	const lines = (file.name.startsWith('actions/')
		? file.text
		: parseSteps(file.text)
				.map((step) => runBody(step))
				.join('\n')
	)
		.split('\n')
		.filter((line) => !/^\s*#/.test(line) && !/^\s*echo\b/.test(line));
	const commands = lines.join('\n');
	const expanded = [commands];
	for (const [name, body] of scripts) {
		if (new RegExp(`(?:npm run|pnpm run|pnpm|npm exec|yarn)\\s+${name.replace(/[.*+?^\${}()|[\]\\]/g, '\\$&')}(?:\\s|$)`).test(commands)) {
			expanded.push(body);
		}
	}
	return expanded.join('\n');
}

/** @param {string} path @param {{name: string, text: string}[]} automation */
function invokers(path, automation) {
	const base = path.split('/').pop() ?? '';
	const scripts = packageScripts();
	return automation.filter((f) => commandsOf(f, scripts).includes(base)).map((f) => f.name);
}

test('every guard this repo ships is invoked by some workflow', () => {
	const automation = allAutomation();
	const guards = allScripts().filter((p) => !p.endsWith('.test.mjs') && !NOT_A_GUARD.has(p));
	assert.ok(guards.length >= 20, `expected the guard population, found ${guards.length}`);
	assert.deepEqual(
		guards.filter((p) => invokers(p, automation).length === 0),
		[],
		'a guard no workflow runs enforces nothing for as long as it exists (decisions § 439 / § 773). ' +
			'Wire it into a job, or name it in NOT_A_GUARD with what it actually is.',
	);
});

test("every guard's own unit suite exists and is run by the required gate", () => {
	const automation = allAutomation();
	const guards = allScripts().filter((p) => !p.endsWith('.test.mjs') && !NOT_A_GUARD.has(p));
	const missing = guards.filter((p) => !existsSync(join(CENSUS_ROOT, p.replace(/\.mjs$/, '.test.mjs'))));
	assert.deepEqual(missing, [], 'a guard with no suite of its own is one nothing proves fires');
	const suites = guards.map((p) => p.replace(/\.mjs$/, '.test.mjs'));
	assert.deepEqual(
		suites.filter((p) => invokers(p, automation).length === 0),
		[],
		"a guard whose own tests no job runs can regress into passing over anything, and " +
			'the guard would still report success (decisions § 711).',
	);
	assert.deepEqual(
		suites.filter((p) => !SUITE_OFF_THE_GATE.has(p) && !invokers(p, automation).includes('ci.yml')),
		[],
		'a suite run by SOME workflow is not a suite the merge waits for. `check_production_env.test.mjs` ' +
			'satisfied the assertion above for its whole life from inside env-isolation.yml, a ' +
			'path-filtered workflow in no `needs:` of the `CI gate` (decisions § 863). Run it from a ' +
			'ci.yml job, or record it in SUITE_OFF_THE_GATE with a reason.',
	);
	assert.deepEqual(
		[...SUITE_OFF_THE_GATE.keys()].filter((p) => invokers(p, automation).includes('ci.yml')),
		[],
		'a SUITE_OFF_THE_GATE entry for a suite that ci.yml now runs is cover for nothing — delete it.',
	);
	for (const [path, why] of SUITE_OFF_THE_GATE) {
		assert.ok(existsSync(join(CENSUS_ROOT, path)), `SUITE_OFF_THE_GATE names ${path}, which is gone`);
		assert.ok(why.length > 40, `SUITE_OFF_THE_GATE's reason for ${path} has to say something`);
	}
});

test('the guards the required gate does not wait for are named, with a reason', () => {
	const automation = allAutomation();
	const guards = allScripts().filter((p) => !p.endsWith('.test.mjs') && !NOT_A_GUARD.has(p));
	const offGate = guards.filter((p) => !invokers(p, automation).includes('ci.yml'));
	assert.deepEqual(
		offGate.filter((p) => !OFF_THE_GATE.has(p)),
		[],
		'the required status check is a job named `CI gate` inside ci.yml, so a guard run ' +
			'only by another workflow blocks no merge (decisions § 775). Move it into a ci.yml ' +
			'job, or record it in OFF_THE_GATE with which workflow runs it and why.',
	);
	assert.deepEqual(
		[...OFF_THE_GATE.keys()].filter((p) => !offGate.includes(p)),
		[],
		'an OFF_THE_GATE entry for a guard that ci.yml now runs is cover for nothing — delete it.',
	);
	for (const [path, why] of OFF_THE_GATE) {
		assert.ok(existsSync(join(CENSUS_ROOT, path)), `OFF_THE_GATE names ${path}, which is gone`);
		assert.ok(why.length > 40, `OFF_THE_GATE's reason for ${path} has to say something`);
	}
});

/// Every shell a composite action runs, and every suite that drives one. The
/// census above walks `scripts/` only, so this directory — where two
/// non-trivial shells live — was outside it entirely.
/** @returns {{ shells: string[], suites: string[] }} */
function compositeActionFiles() {
	const root = join(CENSUS_ROOT, '.github', 'actions');
	/** @type {string[]} */
	const shells = [];
	/** @type {string[]} */
	const suites = [];
	for (const entry of readdirSync(root, { withFileTypes: true })) {
		if (!entry.isDirectory()) continue;
		for (const f of readdirSync(join(root, entry.name))) {
			const rel = `.github/actions/${entry.name}/${f}`;
			if (f.endsWith('.sh')) shells.push(rel);
			if (f.endsWith('.test.mjs')) suites.push(rel);
		}
	}
	return { shells: shells.sort(), suites: suites.sort() };
}

// A composite action's steps run inside no job's test suite, so a shell that
// lives there is executed by CI and by nothing else. Both of the ones this repo
// has were extracted from an `action.yml` for exactly that reason, and both
// turned out to have a branch that had never run (decisions § 912).
test('every composite-action shell has a suite that drives it', () => {
	const { shells, suites } = compositeActionFiles();
	assert.ok(shells.length >= 2, `expected the composite-action shells, found ${shells.length}`);
	const undriven = shells.filter(
		(sh) => !suites.some((t) => t.replace(/\.test\.mjs$/, '.sh') === sh),
	);
	assert.deepEqual(
		undriven,
		[],
		'a composite-action shell with no suite is executed only by CI, and its repair ' +
			'branches only by CI on a bad day. Extract it and drive it with stubs, the way ' +
			'wait_for_sidecars.sh and verify_chromium.sh are.',
	);
});

// § 863, applied to the directory the census does not walk: these suites are
// the only thing that reads those shells, so a suite the required gate does not
// wait for leaves them read by nothing that can block a merge.
test('every composite-action suite is run by a ci.yml job', () => {
	const automation = allAutomation();
	const { suites } = compositeActionFiles();
	assert.ok(suites.length >= 2, `expected the composite-action suites, found ${suites.length}`);
	assert.deepEqual(
		suites.filter((p) => !invokers(p, automation).includes('ci.yml')),
		[],
		'the required status check is a job named `CI gate` inside ci.yml, so a suite run ' +
			'only by another workflow — or by nothing — blocks no merge (decisions § 863).',
	);
});

test('a NOT_A_GUARD entry that no longer exists fails rather than sitting as cover', () => {
	const present = new Set(allScripts());
	assert.deepEqual(
		[...NOT_A_GUARD.keys()].filter((p) => !present.has(p)),
		[],
		'a list of exemptions that has stopped describing the tree exempts nothing (decisions § 775)',
	);
});

// ───────── rule 5: the message the shell prints is the message written ─────────

test('a backtick inside double quotes is command substitution, escaped or single-quoted is not', () => {
	assert.equal(hasShellSubstitutionBacktick('echo "a `Partial` with no Notes"'), true);
	assert.equal(hasShellSubstitutionBacktick('echo "a \\`Partial\\` with no Notes"'), false);
	assert.equal(hasShellSubstitutionBacktick("echo 'a `Partial` with no Notes'"), false);
	assert.equal(hasShellSubstitutionBacktick("echo '```json'"), false);
	assert.equal(hasShellSubstitutionBacktick('echo "$(go env GOPATH)/bin/actionlint"'), false);
	assert.equal(hasShellSubstitutionBacktick("awk '{print \"x\"}' # `y`"), false);
});

test('a diagnosis the shell would eat half of fails, naming the file and line', () => {
	const { errors } = checkShellSafeDiagnoses([
		{
			name: 'ci.yml',
			text: [
				'jobs:',
				'  parity-matrix:',
				'    steps:',
				'      - name: Table shape',
				'        run: |',
				'          echo "::error::a symbol outside `A / B`, or a `Partial` with no Notes"',
			].join('\n'),
		},
	]);
	assert.equal(errors.length, 1, errors.join('\n'));
	assert.match(errors[0], /^ci\.yml:6 — job `parity-matrix`/);
});

test('a comment carrying a backtick reaches no shell and is left alone', () => {
	const { errors, ok } = checkShellSafeDiagnoses([
		{
			name: 'ci.yml',
			text: [
				'jobs:',
				'  a:',
				'    steps:',
				'      # a `Partial` cell, in prose',
				'      - name: x',
				'        run: |',
				'          # the `stack:` matrix',
				'          echo ok',
			].join('\n'),
		},
	]);
	assert.deepEqual(errors, []);
	assert.equal(ok.length, 1);
});

test('reading no shell line at all is reported rather than passing every workflow', () => {
	const { errors } = checkShellSafeDiagnoses([{ name: 'ci.yml', text: 'jobs:\n  a:\n' }]);
	assert.ok(
		errors.some((e) => /passed over nothing/.test(e)),
		errors.join('\n'),
	);
});

test('every committed workflow prints its diagnoses whole', () => {
	const { errors, scanned } = checkShellSafeDiagnoses(readWorkflows(WORKFLOW_DIR));
	assert.deepEqual(errors, []);
	assert.ok(scanned > 500, `only ${scanned} shell line(s) read`);
});

// ───────── the subject is per rule, and composite actions are half of it ─────────

const ACTION_FIXTURE = [
	'name: Do a thing',
	'inputs:',
	'  steps:',
	'    description: a decoy key at the same indent as the real one',
	'runs:',
	'  using: composite',
	'  steps:',
	'    - name: First',
	'      shell: bash',
	'      run: echo hello',
	'    - shell: bash',
	'      if: failure()',
	'      run: |',
	'        echo "::error::something above failed"',
].join('\n');

test('a composite action’s runs.steps are read, and a decoy `steps:` key outside runs is not', () => {
	const steps = parseActionSteps(ACTION_FIXTURE, 'do-a-thing');
	assert.equal(steps.length, 2);
	assert.deepEqual(
		steps.map((s) => [s.job, s.line, s.name, s.if, s.hasRun]),
		[
			['do-a-thing', 8, 'First', null, true],
			['do-a-thing', 11, null, 'failure()', true],
		],
	);
});

test('a workflow has no runs.steps, so the action reader returns nothing for one', () => {
	assert.deepEqual(parseActionSteps(readWorkflows(WORKFLOW_DIR)[0].text, 'x'), []);
});

test('the shared collector gives a job step and an action step the same shape', () => {
	const body = ['      - name: Same', '        shell: bash', '        run: echo hi'].join('\n');
	const [job] = parseSteps(['jobs:', '  a:', '    steps:', body].join('\n'));
	const [act] = parseActionSteps(
		['runs:', '  using: composite', '  steps:', body.replace(/^ {2}/gm, '')].join('\n'),
		'a',
	);
	assert.deepEqual(
		{ ...job, line: 0, body: '' },
		{ ...act, line: 0, body: '' },
		'the two readers disagree about the same step',
	);
});

test('the committed composite actions are read, named by directory', () => {
	const actions = readActions(ACTION_DIR);
	assert.ok(actions.length >= 2, `found ${actions.length} composite action(s)`);
	for (const a of actions) assert.match(a.name, /^[a-z0-9-]+\/action\.ya?ml$/);
	const sources = stepSources([], actions);
	assert.ok(sources.every((s) => s.kind === 'action'));
	const owners = new Set(sources.flatMap((s) => s.steps.map((x) => x.job)));
	assert.ok(owners.has('start-supabase') && owners.has('install-playwright'), [...owners].join(','));
	assert.ok(
		sources.reduce((n, s) => n + s.steps.length, 0) >= 4,
		'the composite actions contributed no steps, so rules 1 + 5 read nothing there',
	);
});

test('rule 5 reads a composite action, and names it as one rather than as a job', () => {
	const { errors } = checkShellSafeDiagnoses(
		[],
		[{ name: 'setup-x/action.yml', text: ACTION_FIXTURE.replace('echo hello', 'echo "a `bad` word"') }],
	);
	assert.equal(errors.length, 1, errors.join('\n'));
	assert.match(errors[0], /^setup-x\/action\.yml:10 — composite action `setup-x`/);
});

test('rule 1 reads a composite action’s unscoped failure() diagnosis', () => {
	const { errors, conditioned } = checkFailureScoping(
		[],
		[{ name: 'setup-x/action.yml', text: ACTION_FIXTURE }],
	);
	assert.equal(conditioned, 1);
	assert.equal(errors.length, 1, errors.join('\n'));
	assert.match(errors[0], /^setup-x\/action\.yml:11 — this step prints an `::error::`/);
});

test('rules 2, 3 and 4 are not applied to a composite action', () => {
	// Two guard steps in one action would bundle a JOB; an action has no job to
	// bundle, and nothing in it can be named in a `needs:` list.
	const text = [
		'runs:',
		'  using: composite',
		'  steps:',
		'    - name: One',
		'      shell: bash',
		'      run: node --test a.test.mjs',
		'    - name: Two',
		'      shell: bash',
		'      run: node scripts/check_thing.mjs',
	].join('\n');
	const actions = [{ name: 'setup-x/action.yml', text }];
	assert.equal(derivedBundles(actions).size, 0, 'an action was derived as a bundled job');
	// Rule 2 still reports its own vacuity (a list with no jobs derives no
	// bundle), which is the point: what it must not do is say anything about
	// the action or the steps inside it.
	const { errors, ok } = checkStepDiagnoses(actions);
	assert.deepEqual(ok, []);
	for (const e of errors) assert.doesNotMatch(e, /setup-x|\bOne\b|\bTwo\b/, e);
	assert.equal(checkGateCoverage(actions).covered, 0);
});

test('RULE_SUBJECTS names every rule exactly once, with a reason', () => {
	assert.deepEqual(
		RULE_SUBJECTS.map((r) => r.rule),
		[1, 2, 3, 4, 5],
	);
	for (const r of RULE_SUBJECTS) {
		assert.ok(r.what.length > 10 && r.why.length > 10, `rule ${r.rule} states no reason`);
	}
});

test('an empty subject list fails rather than reading as a clean pass', () => {
	const files = readWorkflows(WORKFLOW_DIR);
	assert.ok(
		checkRuleSubjects(files, []).errors.some((e) => /no composite action was read/.test(e)),
		'rules 1 + 5 silently covered workflows only',
	);
	assert.ok(
		checkRuleSubjects([], readActions(ACTION_DIR)).errors.some((e) => /no workflow file/.test(e)),
	);
	const both = checkRuleSubjects(files, readActions(ACTION_DIR));
	assert.deepEqual(both.errors, []);
	assert.ok(both.ok.some((l) => /rule\(s\) 1 \+ 5 read \d+ workflow\(s\) AND \d+ composite/.test(l)));
});

test('the committed composite actions carry no rule-1 or rule-5 defect', () => {
	const actions = readActions(ACTION_DIR);
	assert.deepEqual(checkFailureScoping(readWorkflows(WORKFLOW_DIR), actions).errors, []);
	const delivery = checkShellSafeDiagnoses([], actions);
	assert.deepEqual(delivery.errors, []);
	assert.ok(delivery.scanned > 50, `only ${delivery.scanned} action shell line(s) read`);
});

// ---------------------------------------------------------------------------
// Rule 6 — the job count the orientation doc states.
// ---------------------------------------------------------------------------

const THREE_JOBS = [
	'name: CI',
	'on:',
	'  push:',
	'  pull_request:',
	'jobs:',
	'  alpha:',
	'    runs-on: ubuntu-latest',
	'  beta:',
	'    runs-on: ubuntu-latest',
	'  ci-gate:',
	'    needs: [alpha, beta]',
	'    runs-on: ubuntu-latest',
].join('\n');

const CI_ONLY = [{ name: 'ci.yml', text: THREE_JOBS }];

const DOC_OK = [
	'.github/workflows/',
	'  ci.yml             → the same 3 CI jobs run on every PR and push to main',
	'                       check is the "CI gate" aggregator, which needs: every',
	'                       one of the other 2 — among them `terraform`',
].join('\n');

test('rule 6 passes when both figures match the workflow', () => {
	const { errors, ok, stated } = checkStatedJobCount(CI_ONLY, DOC_OK);
	assert.deepEqual(errors, []);
	assert.equal(stated, 2);
	assert.match(ok[0], /3 job key\(s\), 2 of them/);
});

test('rule 6 fails on a stale job count', () => {
	const { errors } = checkStatedJobCount(CI_ONLY, DOC_OK.replace('the same 3 CI jobs', 'the same 9 CI jobs'));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /states 9 where ci\.yml has 3 job keys/);
});

test('rule 6 fails on a stale needs count, which is a different figure', () => {
	const { errors } = checkStatedJobCount(CI_ONLY, DOC_OK.replace('the other 2', 'the other 3'));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /states 3 where ci\.yml has 2 entries/);
});

test('rule 6 fails LOUDLY when the sentence is reworded away, rather than checking nothing', () => {
	const { errors } = checkStatedJobCount(CI_ONLY, DOC_OK.replace('the same 3 CI jobs', 'a few jobs'));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /holds no sentence matching .*so that rule checks nothing/);
});

test('rule 6 fails on a second job-count claim written in a form no template reads', () => {
	const { errors } = checkStatedJobCount(CI_ONLY, `${DOC_OK}\n\nElsewhere: all 7 CI jobs are required.`);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /"7 CI jobs", which no template in checkStatedJobCount reads/);
});

test('rule 6 refuses to report a verdict when ci.yml was not read', () => {
	const { errors } = checkStatedJobCount([{ name: 'other.yml', text: THREE_JOBS }], DOC_OK);
	assert.match(errors[0], /ci\.yml was not read/);
});

test('the committed CLAUDE.md agrees with the committed ci.yml', () => {
	const { errors } = checkStatedJobCount(readWorkflows(WORKFLOW_DIR), readFileSync(ORIENTATION_DOC, 'utf-8'));
	assert.deepEqual(errors, []);
});
