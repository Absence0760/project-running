import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	WORKFLOW_DIR,
	checkWorkflows,
	parseWorkflow,
	resolveVersion,
} from './check_flutter_version_pin.mjs';

const SHA = 'subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2';

/// A workflow with one flutter-action step, shaped like the real ones:
/// a top-level `env:` block carrying an unrelated key alongside the pin,
/// and the step nested two levels down inside a job.
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
	assert.match(resolveVersion({ version: null }, '3.47.0').error, /floats/);
});

test('resolveVersion rejects a reference the workflow never declares', () => {
	assert.match(
		resolveVersion({ version: '${{ env.FLUTTER_VERSION }}' }, null).error,
		/declares no top-level/,
	);
});

test('resolveVersion rejects some other env key', () => {
	assert.match(
		resolveVersion({ version: '${{ env.SDK }}' }, '3.47.0').error,
		/every pin must read/,
	);
});

test('checkWorkflows passes when every workflow pins the same version', () => {
	const { errors, ok, versions } = checkWorkflows([
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

test('checkWorkflows fails when a release workflow drifts from CI', () => {
	const { errors } = checkWorkflows([
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

test('checkWorkflows fails on a step that reverted to bare `channel: stable`', () => {
	const { errors } = checkWorkflows([
		{ name: 'release-ios.yml', text: workflow({ declared: '3.47.0', pin: null }) },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /release-ios\.yml:\d+ — no `flutter-version:`/);
});

test('checkWorkflows fails rather than passing vacuously when nothing matches', () => {
	// The failure this guards against is the guard itself going blind — a
	// renamed action would otherwise report success over an empty set.
	const { errors } = checkWorkflows([
		{ name: 'ci.yml', text: 'name: Fake\njobs:\n  build:\n    steps:\n      - run: echo hi\n' },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /now checks nothing/);
});

test('the repo’s real workflows pin one Flutter version', () => {
	const files = readdirSync(WORKFLOW_DIR)
		.filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
		.map((name) => ({ name, text: readFileSync(join(WORKFLOW_DIR, name), 'utf-8') }));
	const { errors, ok } = checkWorkflows(files);
	assert.deepEqual(errors, []);
	assert.ok(ok.length >= 8, `expected every flutter-action step, found ${ok.length}`);
});
