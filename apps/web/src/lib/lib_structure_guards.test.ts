import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Structural guards for src/lib. These pin the organisation invariants the
 * topical-subfolder reorg established so they can't silently erode:
 *
 *  1. Loose production modules don't re-accumulate at the lib root. Every
 *     non-test module lives in a topical subfolder; only the two type files
 *     are allowed loose (gen:types writes database.types.ts here, and types.ts
 *     overlays it — see apps/backend/package.json `gen:types`).
 *  2. The TS↔Dart parity-pair source paths recorded in the
 *     shared-library-syncer agent actually exist — a move/rename that doesn't
 *     update the agent (or vice versa) is the exact drift this caught.
 *  3. The unit-test glob covers every suite under src/. A non-recursive
 *     `src/lib/*.test.ts` silently skips every subfolder suite, and a
 *     lib-only `src/lib/**` silently skipped the route-level source guards.
 */

const libRoot = import.meta.dirname;
const webRoot = resolve(libRoot, '..', '..');
const repoRoot = resolve(libRoot, '..', '..', '..', '..');

// Production modules permitted directly at src/lib/. Test files (cross-cutting
// guards + tests of these root modules) are allowed at the root too; every
// other module must sit in a topical subfolder.
const ROOT_PRODUCTION_ALLOWLIST = new Set(['types.ts', 'database.types.ts']);

test('no loose production modules at the src/lib root', () => {
	const offenders = readdirSync(libRoot, { withFileTypes: true })
		.filter((e) => e.isFile())
		.map((e) => e.name)
		.filter((name) => (name.endsWith('.ts') || name.endsWith('.svelte.ts')) && !name.endsWith('.d.ts'))
		.filter((name) => !name.endsWith('.test.ts'))
		.filter((name) => !ROOT_PRODUCTION_ALLOWLIST.has(name));

	assert.deepEqual(
		offenders,
		[],
		`Loose production module(s) at src/lib root: ${offenders.join(', ')}. ` +
			`Move them into a topical subfolder (core/, training/, routes/, segments/, ` +
			`social/, integrations/, backup/, share/, settings/, runs/, format/, util/, ` +
			`billing/). Only types.ts + database.types.ts may live at the root.`,
	);
});

test('every TS parity-pair source path in shared-library-syncer.md exists on disk', () => {
	const agent = readFileSync(
		resolve(repoRoot, '.claude', 'agents', 'shared-library-syncer.md'),
		'utf-8',
	);
	const paths = [...agent.matchAll(/apps\/web\/(src\/lib\/[\w./-]+\.ts)/g)].map((m) => m[1]);
	const unique = [...new Set(paths)];

	assert.ok(unique.length >= 9, `expected >=9 parity-pair paths, found ${unique.length}`);
	const missing = unique.filter((p) => !existsSync(resolve(webRoot, p)));
	assert.deepEqual(
		missing,
		[],
		`Parity-pair path(s) referenced by the shared-library-syncer agent no longer ` +
			`exist: ${missing.join(', ')}. Update the agent table (and docs/architecture/` +
			`conventions.md) when a parity helper moves.`,
	);
});

test('the unit-test glob covers every suite under src', () => {
	// Anything narrower silently skips suites rather than failing: a
	// non-recursive `src/lib/*.test.ts` dropped every subfolder, and
	// `src/lib/**` dropped the route-level source guards under src/routes.
	const RECURSIVE = 'src/**/*.test.ts';

	const pkg = JSON.parse(readFileSync(resolve(webRoot, 'package.json'), 'utf-8'));
	assert.ok(
		(pkg.scripts?.['test:unit'] ?? '').includes(RECURSIVE),
		`package.json "test:unit" must use the recursive glob '${RECURSIVE}' or suites ` +
			`outside it are silently skipped (got: ${pkg.scripts?.['test:unit']}).`,
	);

	// CI reaches the glob through the script rather than restating it (decisions
	// § 764), so what has to hold is the CHAIN: the lane invokes `test:unit`, and
	// no step quietly substitutes a narrower glob of its own. Asserting the
	// literal here instead is what went stale the moment the glob moved — the
	// same shape as § 762's `createClient(` guard.
	const ci = readFileSync(resolve(repoRoot, '.github', 'workflows', 'ci.yml'), 'utf-8');
	// Prose is stripped first, comments AND echoed text: the reproduce hint inside
	// this very lane echoes the command being looked for, so matching the raw file
	// would pass on prose alone even if the lane stopped running the suite at all.
	// Same distinction `scripts/check_workflow_binaries.mjs` draws (decisions § 764).
	const code = ci
		.split('\n')
		.filter((l) => {
			const t = l.trimStart();
			return !t.startsWith('#') && !t.startsWith('echo ') && !t.startsWith('printf ');
		})
		.join('\n');
	assert.ok(
		code.includes('npm run test:unit') || code.includes(RECURSIVE),
		`.github/workflows/ci.yml must reach the recursive glob '${RECURSIVE}', ` +
			`either by running \`npm run test:unit\` or by spelling the glob itself.`,
	);

	const inline = [...code.matchAll(/tsx --test ([^\n]*)/g)].map((m) => m[1]);
	for (const args of inline) {
		assert.ok(
			args.includes(RECURSIVE),
			`.github/workflows/ci.yml invokes 'tsx --test' with a glob that is not ` +
				`'${RECURSIVE}' (got: ${args}). A narrower glob silently skips suites.`,
		);
	}
});

test('every $lib/<segment> reference in src resolves to a real lib folder or root module', () => {
	// First path segment after `$lib/` must be an existing subfolder of src/lib
	// or one of the root modules. Catches stale references (imports AND comments)
	// left behind when a module moves into a topical subfolder.
	const entries = readdirSync(libRoot, { withFileTypes: true });
	const valid = new Set<string>();
	for (const e of entries) {
		if (e.isDirectory()) valid.add(e.name);
		else if (e.isFile() && !e.name.endsWith('.test.ts') && !e.name.endsWith('.d.ts')) {
			valid.add(e.name.endsWith('.ts') ? e.name.slice(0, -3) : e.name);
		}
	}

	const srcRoot = resolve(libRoot, '..');
	const files = readdirSync(srcRoot, { recursive: true, withFileTypes: true })
		.filter((e) => e.isFile() && /\.(ts|svelte|js)$/.test(e.name))
		.map((e) => resolve(e.parentPath ?? (e as unknown as { path: string }).path, e.name));

	const offenders: string[] = [];
	for (const file of files) {
		const text = readFileSync(file, 'utf-8');
		for (const m of text.matchAll(/\$lib\/([\w.-]+)/g)) {
			if (!valid.has(m[1])) {
				offenders.push(`${file.replace(srcRoot, 'src')}: $lib/${m[1]}`);
			}
		}
	}

	assert.deepEqual(
		[...new Set(offenders)],
		[],
		`Stale $lib reference(s) — the first path segment doesn't match a src/lib ` +
			`subfolder or root module (a module probably moved):\n  ${[...new Set(offenders)].join('\n  ')}`,
	);
});
