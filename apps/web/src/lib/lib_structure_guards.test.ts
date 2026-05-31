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
 *  3. The unit-test glob recurses into subfolders. A non-recursive
 *     `src/lib/*.test.ts` silently skips every subfolder suite.
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

test('the unit-test glob recurses into lib subfolders', () => {
	const RECURSIVE = 'src/lib/**/*.test.ts';

	const pkg = JSON.parse(readFileSync(resolve(webRoot, 'package.json'), 'utf-8'));
	assert.ok(
		(pkg.scripts?.['test:unit'] ?? '').includes(RECURSIVE),
		`package.json "test:unit" must use the recursive glob '${RECURSIVE}' or subfolder ` +
			`suites are silently skipped (got: ${pkg.scripts?.['test:unit']}).`,
	);

	const ci = readFileSync(resolve(repoRoot, '.github', 'workflows', 'ci.yml'), 'utf-8');
	assert.ok(
		ci.includes(RECURSIVE),
		`.github/workflows/ci.yml must run the recursive glob '${RECURSIVE}'.`,
	);
});
