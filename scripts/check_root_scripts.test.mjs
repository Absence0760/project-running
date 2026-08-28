import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	RESERVED_PNPM_VERBS,
	checkRootScripts,
	isDocumentationKey,
	workspaceDirs,
} from './check_root_scripts.mjs';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** @typedef {import('./check_root_scripts.mjs').PackageJson} PackageJson */

// A tree with two workspace packages and no surprises, so every failure below
// is caused by the script under test rather than by the fixture.
const TREE = {
	'apps/web': { name: '@app/web', scripts: { dev: 'vite', check: 'svelte-check' } },
	'apps/backend': { name: '@app/backend', scripts: { 'gen:types': 'supabase gen types' } },
};

/**
 * The fixture always carries one script that resolves, so a mutation is graded
 * on its own findings rather than on the "verified nothing" vacuity rule, which
 * is itself under test below.
 * @param {Record<string, string>} scripts
 * @param {{ dirs?: string[], bare?: boolean }} [over]
 */
function verdict(scripts, over = {}) {
	/** @type {PackageJson} */
	const manifest = {
		scripts: over.bare ? scripts : { _base: 'pnpm -C apps/web check', ...scripts },
		workspaces: ['apps/web', 'apps/backend'],
	};
	const dirs = over.dirs ?? ['apps/web', 'apps/backend', 'apps/mobile_android'];
	const out = checkRootScripts(manifest, {
		workspaceDirs: ['apps/web', 'apps/backend'],
		dirExists: (d) => dirs.includes(d),
		readManifest: (d) => /** @type {PackageJson | null} */ (TREE[/** @type {keyof TREE} */ (d)] ?? null),
	});
	/** @param {string[]} lines */
	const mine = (lines) => lines.filter((l) => !l.startsWith('_base:'));
	return {
		...out,
		errors: mine(out.errors),
		ok: mine(out.ok),
		unverifiable: mine(out.unverifiable),
	};
}

test('the baseline passes, so every mutation below is the only cause of its failure', () => {
	const { errors, ok } = verdict({ a: 'pnpm -C apps/web check' });
	assert.deepEqual(errors, []);
	assert.deepEqual(ok, ['a: apps/web/package.json declares "check"']);
});

// ── decisions § 773 — the four misreads, each from the shape that produced it

test('a pnpm flag is not read as the script name', () => {
	const { errors, ok } = verdict({ a: 'pnpm -C apps/web --silent run check' });
	assert.deepEqual(errors, []);
	assert.deepEqual(ok, ['a: apps/web/package.json declares "check"']);
});

test('a semicolon is not swallowed into the directory name', () => {
	const { errors } = verdict({ a: 'cd apps/web; svelte-check' });
	assert.deepEqual(errors, []);
});

test('a quoted directory is the directory, not a name with quotes in it', () => {
	const { errors } = verdict({ a: 'cd "apps/web" && npm run build' });
	assert.deepEqual(errors, []);
});

// The other half of the same anchor bug: `(?:^|&&\s*)cd` covered `&&` and not
// `;`, so the missing directory after a semicolon went unreported entirely.
test('a missing directory after a semicolon is reported', () => {
	const { errors } = verdict({ a: 'cd apps/web; cd nope/here && x' });
	assert.deepEqual(errors, ['a: missing directory apps/web/nope/here']);
});

// pnpm's own recommended workspace form made the guard verify nothing while
// still printing that it had passed.
test('pnpm --filter resolves through the workspace package name', () => {
	const { errors, ok } = verdict({ a: 'pnpm --filter @app/web run check' });
	assert.deepEqual(errors, []);
	assert.deepEqual(ok, ['a: apps/web/package.json declares "check"']);
});

test('pnpm --filter naming a script the package does not have fails', () => {
	const { errors } = verdict({ a: 'pnpm --filter @app/web run nope' });
	assert.deepEqual(errors, ['a: apps/web/package.json has no "nope" script']);
});

test('pnpm --filter naming no resolvable package is reported, not silently skipped', () => {
	const { errors, unverifiable } = verdict({ a: 'pnpm --filter @app/nothing run check' });
	assert.deepEqual(errors, []);
	assert.equal(unverifiable.length, 1);
	assert.match(unverifiable[0], /names no workspace package/);
});

// ── what the rewrite has to keep doing ──────────────────────────────────────

test('a missing child manifest and a missing script each fail, naming which', () => {
	assert.deepEqual(verdict({ a: 'pnpm -C apps/mobile_android run x' }).errors, [
		'a: missing apps/mobile_android/package.json',
	]);
	assert.deepEqual(verdict({ a: 'pnpm -C apps/web run nope' }).errors, [
		'a: apps/web/package.json has no "nope" script',
	]);
});

test('a bare `pnpm <target>` is a root script and is checked as one', () => {
	const { errors } = verdict({ all: 'pnpm one && pnpm two', one: 'echo 1' });
	assert.deepEqual(errors, ['all: the root package.json has no "two" script']);
});

test('a reserved pnpm verb is reported as unchecked rather than dropped', () => {
	const { errors, unverifiable } = verdict({ a: 'pnpm -C apps/web install' });
	assert.deepEqual(errors, []);
	assert.match(unverifiable[0], /reserved pnpm verb/);
	assert.ok(RESERVED_PNPM_VERBS.has('install'));
});

// A shell tracks cd; so does this. `cd apps/backend && … && cd ../..` means
// the repo root, and resolving both against the root made the second vacuous.
test('cd is resolved against where the previous cd left the script', () => {
	const { errors, ok } = verdict({ a: 'cd apps/backend && x && cd ../.. && cd apps/web' });
	assert.deepEqual(errors, []);
	assert.equal(ok.length, 3);
	assert.ok(ok.some((l) => /`cd \.\.\/\.\.` -> \./.test(l)));
});

test('a cd that leaves the repository fails rather than resolving on the machine', () => {
	const { errors } = verdict({ a: 'cd apps/web && cd ../../..' });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /leaves the repository/);
});

test('a cd into an interpolated path is reported as unverifiable, not passed', () => {
	const { errors, unverifiable } = verdict({ a: 'cd "$TARGET" && x' });
	assert.deepEqual(errors, []);
	assert.equal(unverifiable.length, 1);
});

test('a documentation key is prose, not a command', () => {
	assert.ok(isDocumentationKey('//-- test --'));
	assert.ok(!isDocumentationKey('test:web'));
	const { errors, scriptCount } = verdict({
		'//-- x --': "prose with an apostrophe and a stray ; and cd nowhere",
		a: 'pnpm -C apps/web check',
	});
	assert.deepEqual(errors, []);
	assert.equal(scriptCount, 2);
});

test('a real script the lexer cannot read fails rather than being skipped', () => {
	const { errors } = verdict({ a: "cd 'apps/web && x" });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /unreadable shell/);
});

// The failure this guard's own summary line hid: `--filter` made it check
// nothing while printing that it passed.
test('checking nothing across a manifest full of scripts fails', () => {
	const { errors } = verdict({ a: 'echo hi', b: 'make all' }, { bare: true });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /Verified nothing across 2 root script\(s\)/);
});

test('a manifest with no runnable scripts fails rather than passing vacuously', () => {
	const { errors } = verdict({}, { bare: true });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /no runnable scripts/);
});

test('workspaceDirs reads both manifests, and neither alone', () => {
	assert.deepEqual(workspaceDirs({ workspaces: ['apps/web'] }, '  - apps/backend\n'), [
		'apps/web',
		'apps/backend',
	]);
	assert.deepEqual(workspaceDirs({}, null), []);
});

// ── the committed manifest ──────────────────────────────────────────────────

test('the committed root scripts all resolve', () => {
	/** @type {PackageJson} */
	const manifest = JSON.parse(fs.readFileSync(path.join(REPO_ROOT, 'package.json'), 'utf8'));
	const pnpmWorkspace = fs.readFileSync(path.join(REPO_ROOT, 'pnpm-workspace.yaml'), 'utf8');
	const { errors, ok, scriptCount } = checkRootScripts(manifest, {
		workspaceDirs: workspaceDirs(manifest, pnpmWorkspace),
		dirExists: (d) => fs.existsSync(path.join(REPO_ROOT, d)),
		readManifest: (d) => {
			const file = path.join(REPO_ROOT, d, 'package.json');
			return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : null;
		},
	});
	assert.deepEqual(errors, []);
	assert.ok(ok.length > 20, `expected the manifest to give this guard real work, got ${ok.length}`);
	assert.ok(
		scriptCount < Object.keys(manifest.scripts ?? {}).length,
		'the documentation headers must not be counted as scripts',
	);
});
