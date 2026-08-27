import test from 'node:test';
import assert from 'node:assert/strict';

import {
	ANNOTATION,
	DIAGNOSING_JOBS,
	WORKFLOW_DIR,
	checkAll,
	GATE_JOB,
	checkFailureScoping,
	checkGateCoverage,
	checkStepDiagnoses,
	derivedBundles,
	isGuardStep,
	parseJobKeys,
	parseNeeds,
	parseSteps,
	readWorkflows,
	runBody,
} from './check_ci_diagnostics.mjs';

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

test('checkGateCoverage fails rather than passing vacuously when the gate is gone', () => {
	const { errors } = checkGateCoverage([
		{ name: 'ci.yml', text: 'name: CI\njobs:\n  a:\n    steps:\n      - run: echo hi\n' },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /nothing now aggregates/);
});

test('the repo’s real workflows carry no misattributable diagnosis', () => {
	const files = readWorkflows(WORKFLOW_DIR);
	const { errors, diagnoses, scoping, gate } = checkAll(files);
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
