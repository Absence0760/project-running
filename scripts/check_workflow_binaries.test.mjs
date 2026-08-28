import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	ACTION_DIR,
	DYNAMIC,
	PROVIDERS,
	ROOT_MANIFEST,
	WORKFLOW_DIR,
	binaryOf,
	checkWorkflowBinaries,
	declaredPackages,
	logicalLines,
	parseInvocations,
	readCompositeActions,
	readWorkflows,
} from './check_workflow_binaries.mjs';

/// Every mapped binary invoked once, so a fixture exercising one of them does
/// not also collect the stale-entry complaint about the other two. Counted off
/// PROVIDERS rather than written down, so mapping a fourth binary does not fail
/// these on arithmetic.
const everyBin = () =>
	[...PROVIDERS.keys()].map((bin) => `        run: pnpm exec ${bin} --version\n`).join('');

/** @param {readonly string[]} names */
const declared = (names) => new Set(names);

const allProviders = declared([...PROVIDERS.values()]);

test('binaryOf skips the runner’s own flags and the -- that ends them', () => {
	assert.equal(binaryOf('--no -- tsx scripts/read.mjs'), 'tsx');
	assert.equal(binaryOf('-y playwright test'), 'playwright');
});

test('binaryOf strips the quoting and punctuation prose wraps a name in', () => {
	assert.equal(binaryOf('`tsx`, while the script'), 'tsx');
	assert.equal(binaryOf('"svelte-kit" sync'), 'svelte-kit');
	assert.equal(binaryOf('(playwright).'), 'playwright');
});

test('binaryOf reports nothing when the flags are all there is', () => {
	assert.equal(binaryOf('--help'), null);
	assert.equal(binaryOf('   '), null);
});

// A guard that trips over its own documentation gets its documentation
// reworded, and then trips over the next sentence instead. `<bin>` and the `/`
// between two alternatives are not programs, so they are not invocations.
test('a token that cannot be a command name is prose, not an invocation', () => {
	assert.equal(binaryOf('<bin> scripts/read.mjs'), null);
	assert.equal(binaryOf('/ pnpm exec / dlx)'), null);
	assert.deepEqual(
		parseInvocations([{ name: 'ci.yml', text: '      # `npx <bin>` runs whatever is there\n' }]),
		[],
	);
});

// The one shape that is neither a name nor prose: a binary the workflow decides
// at run time. Nothing static can check it, which is the reason to say so
// rather than to skip it.
test('a runner handed an interpolated binary is reported, not skipped', () => {
	assert.equal(binaryOf('${{ matrix.tool }} build'), DYNAMIC);
	const { errors } = checkWorkflowBinaries(
		[{ name: 'ci.yml', text: `      - run: npx $TOOL build\n${everyBin()}` }],
		allProviders,
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /an expression decides at run\s+time/);
});

test('parseInvocations reads every runner form with its file and line', () => {
	const found = parseInvocations([
		{
			name: 'ci.yml',
			text:
				`jobs:\n  a:\n    steps:\n` +
				`      - run: npx tsx scripts/read.mjs\n` +
				`      - run: pnpm exec playwright test\n` +
				`      - run: pnpm dlx svelte-kit sync\n`,
		},
	]);
	assert.deepEqual(
		found.map((i) => [i.file, i.line, i.runner, i.bin]),
		[
			['ci.yml', 4, 'npx', 'tsx'],
			['ci.yml', 5, 'pnpm exec', 'playwright'],
			['ci.yml', 6, 'pnpm dlx', 'svelte-kit'],
		],
	);
});

// `npm run <script>` executes something this repo wrote. It is the FIX for a
// run-time download, not an instance of one, so it must not be read as a
// package runner — the web unit step is exactly that shape now.
test('npm run is not a package runner', () => {
	assert.deepEqual(
		parseInvocations([{ name: 'ci.yml', text: '      - run: npm run test:unit\n' }]),
		[],
	);
});

test('a binary whose package nothing declares is the reported bug', () => {
	const { errors } = checkWorkflowBinaries(
		[{ name: 'ci.yml', text: `      - run: npx tsx x.mjs\n${everyBin()}` }],
		declared([...PROVIDERS.values()].filter((p) => p !== 'tsx')),
	);
	// One per invocation of the undeclared binary: the fixture's own line and
	// the everyBin() line for the same name.
	assert.equal(errors.length, 2);
	for (const error of errors) assert.match(error, /downloads an unpinned copy from the registry/);
});

// A name the table has never seen is precisely the new run-time download this
// exists to catch, so it fails rather than being skipped as unrecognised.
test('a binary PROVIDERS has never been told about fails rather than passing', () => {
	const { errors } = checkWorkflowBinaries(
		[{ name: 'ci.yml', text: `      - run: npx some-fetched-tool build\n${everyBin()}` }],
		allProviders,
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /never been told about/);
});

test('a PROVIDERS entry no workflow invokes any more fails rather than rotting', () => {
	const kept = [...PROVIDERS.keys()][0];
	const { errors } = checkWorkflowBinaries(
		[{ name: 'ci.yml', text: `      - run: pnpm exec ${kept} --version\n` }],
		allProviders,
	);
	assert.equal(errors.length, PROVIDERS.size - 1);
	for (const error of errors) assert.match(error, /reading nothing/);
});

test('checkWorkflowBinaries fails rather than passing vacuously over no invocations', () => {
	const { errors } = checkWorkflowBinaries(
		[{ name: 'ci.yml', text: '      - run: echo hi\n' }],
		allProviders,
	);
	assert.match(errors[0], /enforces nothing/);
});

test('declaredPackages reads the root manifest and every workspace it lists', () => {
	const found = declaredPackages(
		JSON.stringify({
			workspaces: ['apps/web'],
			devDependencies: { svelte: '5.0.0' },
		}),
		(dir) => {
			assert.equal(dir, 'apps/web');
			return JSON.stringify({ dependencies: { marked: '1.0.0' }, devDependencies: { tsx: '4.0.0' } });
		},
	);
	assert.deepEqual([...found].sort(), ['marked', 'svelte', 'tsx']);
});

test('the repo’s real workflows fetch no binary at run time', () => {
	const files = [...readWorkflows(WORKFLOW_DIR), ...readCompositeActions(ACTION_DIR)];
	const rootText = readFileSync(ROOT_MANIFEST, 'utf-8');
	const root = join(ROOT_MANIFEST, '..');
	const { errors, invocations } = checkWorkflowBinaries(
		files,
		declaredPackages(rootText, (dir) => readFileSync(join(root, dir, 'package.json'), 'utf-8')),
	);
	assert.deepEqual(errors, []);
	assert.ok(
		invocations.length >= PROVIDERS.size,
		`expected at least one invocation per mapped binary, found ${invocations.length}`,
	);
});

// The reason this guard exists: tsx is what runs the web unit suite, and it was
// declared by nothing. vite lists it as an optional peer, which installs no
// copy — so asserting "some manifest mentions tsx" would have passed then too.
test('tsx is declared as a real dependency, not merely as somebody’s optional peer', () => {
	const web = JSON.parse(
		readFileSync(join(ROOT_MANIFEST, '..', 'apps', 'web', 'package.json'), 'utf-8'),
	);
	assert.ok(web.devDependencies?.tsx, 'apps/web must declare tsx so `test:unit` runs on a clean checkout');
	assert.ok(
		web.scripts['test:unit'].startsWith('tsx '),
		'test:unit is the command the CI diagnosis tells a reader to reproduce with',
	);
});


// decisions § 773. Both layers that put a runner and its binary on different
// physical lines dropped the invocation entirely: `binaryOf('\\')` is null and
// the caller continued, so the file's other invocations kept the
// `invocations.length === 0` blindness check quiet and nothing was printed.
test('a binary on a shell continuation line is still read', () => {
	const text = [
		'      - run: |',
		'          npx \\',
		'            totally-unpinned-cli --do-something',
	].join('\n');
	assert.deepEqual(parseInvocations([{ name: 'w.yml', text }]), [
		{ file: 'w.yml', line: 2, runner: 'npx', bin: 'totally-unpinned-cli' },
	]);
});

test('a binary on the next line of a folded scalar is still read', () => {
	const text = ['      - run: >-', '          pnpm exec', '          totally-unpinned-cli'].join('\n');
	assert.deepEqual(parseInvocations([{ name: 'w.yml', text }]), [
		{ file: 'w.yml', line: 2, runner: 'pnpm exec', bin: 'totally-unpinned-cli' },
	]);
});

// The unpinned binary is what has to reach the error list, not merely the
// parse: the whole defect was that it never became an error.
test('an unpinned binary reached over a continuation still fails the check', () => {
	const text = [everyBin(), '      - run: |', '          npx \\', '            unpinned-cli'].join('\n');
	const { errors } = checkWorkflowBinaries([{ name: 'w.yml', text }], allProviders);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /unpinned-cli/);
});

// A blank line inside a folded scalar is a newline, not a space, so folding
// across one would invent a command nothing runs.
test('a folded scalar does not fold across its paragraph breaks', () => {
	const text = ['      - run: >-', '          npx', '', '          totally-unpinned-cli'].join('\n');
	assert.deepEqual(parseInvocations([{ name: 'w.yml', text }]), []);
});

// `|` keeps its newlines, so each line IS its own command; joining them would
// read `npx` and the next unrelated command as one invocation.
test('a literal block scalar is not folded', () => {
	const text = ['      - run: |', '          npx', '          totally-unpinned-cli'].join('\n');
	assert.deepEqual(parseInvocations([{ name: 'w.yml', text }]), []);
});

test('logicalLines leaves an ordinary file line-for-line', () => {
	const text = ['a: 1', 'b: 2', 'c: 3'].join('\n');
	assert.deepEqual(logicalLines(text), [
		{ line: 1, text: 'a: 1' },
		{ line: 2, text: 'b: 2' },
		{ line: 3, text: 'c: 3' },
	]);
});

// Measured while fixing it: the joining changes nothing about the committed
// tree, which is what "latent" has to mean rather than be assumed to.
test('joining logical lines finds the same invocations in the committed workflows', () => {
	const files = [...readWorkflows(WORKFLOW_DIR), ...readCompositeActions(ACTION_DIR)];
	const found = parseInvocations(files);
	const raw = files.flatMap(({ name, text }) =>
		text.split('\n').flatMap((line, i) =>
			[...line.matchAll(/(?:^|[^\w./@-])(npx|pnpm\s+exec)\s+(\S[^\n]*)/g)]
				.map((m) => binaryOf(m[2]))
				.filter((b) => b !== null)
				.map((b) => `${name}:${i + 1} ${b}`),
		),
	);
	assert.deepEqual(
		found.map((i) => `${i.file}:${i.line} ${i.bin}`),
		raw,
	);
});
