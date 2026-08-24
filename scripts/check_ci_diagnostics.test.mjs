import test from 'node:test';
import assert from 'node:assert/strict';

import {
	ANNOTATION,
	DIAGNOSING_JOBS,
	WORKFLOW_DIR,
	checkAll,
	checkFailureScoping,
	checkStepDiagnoses,
	parseSteps,
	readWorkflows,
} from './check_ci_diagnostics.mjs';

/// A job shaped like the real `parity-types`: several named check steps, then
/// whatever trailing step the caller wants.
function bundledJob(steps) {
	return `name: CI\njobs:\n  parity-types:\n    name: Schema / type drift\n    steps:\n${steps}`;
}

const selfDiagnosing = (name, cmd) =>
	`      - name: ${name}\n` +
	`        run: |\n` +
	`          if ! ${cmd}; then\n` +
	`            echo "${ANNOTATION}${name} failed."\n` +
	`            exit 1\n` +
	`          fi\n`;

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
					selfDiagnosing('one', 'a') +
					selfDiagnosing('two', 'b'),
			),
		},
	]);
	assert.deepEqual(errors, []);
	assert.equal(ok.length, 2);
});

test('checkStepDiagnoses fails when a registered job is renamed out from under it', () => {
	const { errors } = checkStepDiagnoses([
		{
			name: 'ci.yml',
			text: `name: CI\njobs:\n  renamed:\n    steps:\n${selfDiagnosing('one', 'a')}`,
		},
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /reading nothing/);
});

test('the repo’s real workflows carry no misattributable diagnosis', () => {
	const files = readWorkflows(WORKFLOW_DIR);
	const { errors, diagnoses, scoping } = checkAll(files);
	assert.deepEqual(errors, []);
	assert.ok(scoping.conditioned >= 5, `expected the on-failure steps, found ${scoping.conditioned}`);
	assert.ok(
		diagnoses.ok.length >= 4,
		`expected every check step of ${[...DIAGNOSING_JOBS.keys()].join(', ')}, found ${diagnoses.ok.length}`,
	);
});
