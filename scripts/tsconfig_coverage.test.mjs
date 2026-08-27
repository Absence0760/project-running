// Guardrail: no compilable file outside `apps/web` sits outside every typecheck.
//
// This repo has no root `tsconfig.json`, so for as long as the guard scripts
// under `scripts/` and `apps/backend/scripts/` have existed, nothing has
// typechecked any of them — 35 `.mjs` files whose verdicts every merge depends
// on, plus a CloudFront Function running at the edge on every request to the
// site (decisions § 757). `apps/web` had the same hole and closed it in § 752.
//
// Two guards rather than one, deliberately. The `apps/web` half must resolve
// SvelteKit's GENERATED `.svelte-kit/tsconfig.json`, so it cannot run before a
// `svelte-kit sync`; this half must run with nothing built and nothing
// installed. Neither can state the other's coverage, so each states its own
// and this one asserts the other still exists — the seam between them is what
// would otherwise open silently.
//
// It walks the tracked files rather than a list of trees, and derives what is
// covered from the configs themselves, so a root added later counts the moment
// it exists and a tree added later is uncovered the moment it appears.
//
// Run: `npm run test:tsconfig-coverage`
// CI:  the `parity-types` job in .github/workflows/ci.yml.

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, extname, join, relative, resolve } from 'node:path';
import { test } from 'node:test';

const REPO_ROOT = resolve(import.meta.dirname, '..');

/** The `apps/web` half of this rule, which this one deliberately does not cover. */
const WEB_GUARD = 'apps/web/scripts/tsconfig_coverage.test.mjs';

/** Extensions `tsc` compiles. A file carrying one is a file some root should read. */
const COMPILABLE = new Set(['.ts', '.mts', '.cts', '.tsx', '.js', '.mjs', '.cjs', '.jsx']);

/**
 * Source files outside `apps/web`, repo-relative: tracked, plus untracked ones
 * git is not ignoring. Git is the only list of "what is source here" that
 * nobody maintains by hand — and the untracked half means a file still being
 * written is covered by this before it is staged, not after.
 * @returns {string[]}
 */
function sourceFiles() {
	/** @param {string[]} args */
	const ls = (args) =>
		execFileSync('git', ['ls-files', '-z', ...args], { cwd: REPO_ROOT, encoding: 'utf8' })
			.split('\0')
			.filter(Boolean);
	return [...new Set([...ls([]), ...ls(['--others', '--exclude-standard'])])].filter(
		(f) => !f.startsWith('apps/web/'),
	);
}

/**
 * Comments are legal in a tsconfig and these carry them.
 * @param {string} absPath
 * @returns {{ extends?: string, include?: string[], exclude?: string[],
 *             compilerOptions?: { types?: string[] } }}
 */
function readConfig(absPath) {
	return JSON.parse(readFileSync(absPath, 'utf8').replace(/^\s*\/\/.*$/gm, ''));
}

/** Every `tsconfig*.json` at the top of the repo, base configs included. */
function configFiles() {
	return readdirSync(REPO_ROOT)
		.filter((f) => /^tsconfig[^/]*\.json$/.test(f))
		.sort();
}

/**
 * The ones that are ROOTS: a config nothing else extends. A config that is
 * extended is a shared base and is not run on its own, so requiring it to
 * declare an `include` or to have an npm script would be requiring the wrong
 * thing — while a base nobody extends falls through to here and fails the
 * include assertion below, which is the honest answer for dead config.
 */
function configRoots() {
	const files = configFiles();
	const extended = new Set();
	for (const file of files) {
		const config = readConfig(join(REPO_ROOT, file));
		if (config.extends) extended.add(resolve(REPO_ROOT, config.extends));
	}
	return files.filter((f) => !extended.has(join(REPO_ROOT, f)));
}

/**
 * A config's effective `include`/`exclude`, as absolute-path patterns.
 * TypeScript does not merge either across `extends` — the nearest one that
 * declares it wins — so this follows the chain until one does.
 * @param {string} absPath
 */
function effectivePatterns(absPath) {
	let current = absPath;
	const seen = new Set();
	while (!seen.has(current)) {
		seen.add(current);
		assert.ok(
			existsSync(current),
			`${relative(REPO_ROOT, current)} does not exist, so a tsc root here resolves to nothing.`,
		);
		const config = readConfig(current);
		if (config.include) {
			const dir = dirname(current);
			return {
				include: config.include.map((p) => resolve(dir, p)),
				exclude: (config.exclude ?? []).map((p) => resolve(dir, p)),
			};
		}
		assert.ok(
			config.extends,
			`${relative(REPO_ROOT, current)} declares no "include" and extends nothing, so it ` +
				'checks whatever happens to be passed on the command line.',
		);
		current = resolve(dirname(current), config.extends);
	}
	throw new Error(`Circular "extends" chain reaching ${relative(REPO_ROOT, absPath)}.`);
}

/**
 * A tsconfig include/exclude glob as a regex: `**` spans directories, `*` and
 * `?` do not.
 * @param {string} pattern
 */
function globToRegExp(pattern) {
	let body = '';
	for (let i = 0; i < pattern.length; i++) {
		const c = pattern[i];
		if (c === '*') {
			if (pattern[i + 1] === '*') {
				body += '.*';
				i++;
				if (pattern[i + 1] === '/') i++;
			} else {
				body += '[^/]*';
			}
		} else if (c === '?') body += '[^/]';
		else body += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
	}
	// A pattern naming no extension and no wildcard is a directory in tsconfig
	// grammar, and covers everything beneath it.
	if (!/[*?]/.test(pattern) && !extname(pattern)) body += '(?:/.*)?';
	return new RegExp(`^${body}$`);
}

/**
 * The Supabase Edge Functions tree, repo-relative with a trailing slash.
 * Derived from where `config.toml` sits rather than written down, so moving
 * the Supabase project moves the exemption with it and a `.ts` dropped
 * anywhere else is still uncovered.
 *
 * It is exempt because it is a DENO program, not a tsc one: its modules import
 * over `npm:`, `jsr:` and `https:` specifiers that tsc's resolver cannot
 * follow, so putting it in a root here would report a hundred unresolved
 * imports and prove nothing. What typechecks it is `deno check`, in the
 * `Edge Function typecheck` step of the `edge-functions` job — which nothing
 * ran until decisions § 762, when the tree turned out to hold 81 errors. That
 * lane has a coverage guard of its own,
 * `scripts/edge_functions_typecheck_coverage.test.mjs`, standing to it exactly
 * as this file stands to the tsconfig roots; the exemption here points at it
 * rather than merely disclaiming the tree.
 */
function denoFunctionsTree() {
	const config = 'apps/backend/supabase/config.toml';
	assert.ok(
		existsSync(join(REPO_ROOT, config)),
		`${config} is gone, so the Deno exemption below no longer names anything. Point it at ` +
			"wherever the Supabase project moved to, or drop it if there are no Edge Functions left.",
	);
	return `${dirname(config)}/functions/`;
}

test('every compilable file outside apps/web is inside some tsc root', () => {
	const roots = configRoots();
	assert.ok(roots.length > 0, 'No tsconfig root is tracked at the repo root.');

	const matchers = roots.map((r) => {
		const { include, exclude } = effectivePatterns(join(REPO_ROOT, r));
		return { include: include.map(globToRegExp), exclude: exclude.map(globToRegExp) };
	});

	const deno = denoFunctionsTree();
	const missed = sourceFiles()
		.filter((f) => COMPILABLE.has(extname(f)))
		.filter((f) => !f.startsWith(deno))
		.filter((f) => {
			const abs = join(REPO_ROOT, f);
			return !matchers.some(
				(m) => m.include.some((re) => re.test(abs)) && !m.exclude.some((re) => re.test(abs)),
			);
		})
		.sort();

	assert.deepEqual(
		missed,
		[],
		'These files carry a compilable extension no tsconfig root at the repo root reads, so ' +
			'nothing typechecks them. Add them to an existing root, or give them one — do not ' +
			`leave them outside: ${missed.join(', ')}`,
	);
});

test('the apps/web half of this rule still exists', () => {
	assert.ok(
		existsSync(join(REPO_ROOT, WEB_GUARD)),
		`${WEB_GUARD} is gone. This guard skips apps/web because that one states its coverage ` +
			'completely; with it deleted, the largest tree in the repo is covered by neither.',
	);
});

test('every tsc root is reachable as an npm script and runs in CI', () => {
	/** @type {{ scripts?: Record<string, string> }} */
	const pkg = JSON.parse(readFileSync(join(REPO_ROOT, 'package.json'), 'utf8'));
	const scripts = Object.entries(pkg.scripts ?? {});
	const ci = readFileSync(join(REPO_ROOT, '.github', 'workflows', 'ci.yml'), 'utf8');

	for (const root of configRoots()) {
		const runners = scripts.filter(([, body]) => body.includes(root));
		assert.ok(
			runners.length > 0,
			`No script in package.json names ${root}, so nothing runs that typecheck.`,
		);
		const inCi = runners.some(([name]) =>
			new RegExp(`npm run ${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?![\\w:-])`).test(ci),
		);
		assert.ok(
			inCi,
			`.github/workflows/ci.yml runs none of ${runners.map(([n]) => n).join(', ')}, so ` +
				`${root} typechecks nothing on a pull request — which is the gap these roots exist ` +
				'to close.',
		);
	}
});

test('the coverage guard itself runs in CI', () => {
	/** @type {{ scripts?: Record<string, string> }} */
	const pkg = JSON.parse(readFileSync(join(REPO_ROOT, 'package.json'), 'utf8'));
	const entry = Object.entries(pkg.scripts ?? {}).find(([, body]) =>
		body.includes('scripts/tsconfig_coverage.test.mjs'),
	);
	assert.ok(entry, 'package.json must declare a script that runs this guard.');
	const ci = readFileSync(join(REPO_ROOT, '.github', 'workflows', 'ci.yml'), 'utf8');
	assert.ok(
		ci.includes(`npm run ${entry[0]}`),
		`.github/workflows/ci.yml must run "${entry[0]}" — a coverage guard nothing runs is not ` +
			'a guard.',
	);
});

/**
 * A config's effective `compilerOptions.types`, following `extends` until one
 * declares it. TypeScript does not merge `types` across a chain either — the
 * nearest declaration wins — so this stops at the first one, exactly as
 * `effectivePatterns` does for `include`.
 * @param {string} absPath
 * @returns {string[] | undefined}
 */
function effectiveTypes(absPath) {
	let current = absPath;
	const seen = new Set();
	while (!seen.has(current) && existsSync(current)) {
		seen.add(current);
		const config = readConfig(current);
		const types = config.compilerOptions?.types;
		if (types) return types;
		if (!config.extends) return undefined;
		current = resolve(dirname(current), config.extends);
	}
	return undefined;
}

test('every "types" entry a root names is a dependency the ROOT package.json declares', () => {
	// `types: ["node"]` makes `@types/node` an entry point of the program, so
	// tsc fails outright — `TS2688`, no file even read — when it is missing.
	// npm places a package where the lockfile says, and a workspace's
	// devDependency is not guaranteed to hoist: `@types/node` was declared by
	// `apps/web` alone, so `npm ci` put it in `apps/web/node_modules` and a
	// root-level `tsc` on a clean checkout could not see it. It resolved on a
	// developer machine whose `node_modules` had drifted from the lockfile,
	// which is why this only ever failed in CI (decisions § 757).
	const manifest = JSON.parse(readFileSync(join(REPO_ROOT, 'package.json'), 'utf8'));
	const declared = new Set([
		...Object.keys(manifest.dependencies ?? {}),
		...Object.keys(manifest.devDependencies ?? {}),
	]);

	for (const root of configRoots()) {
		for (const name of effectiveTypes(join(REPO_ROOT, root)) ?? []) {
			// A `types` entry is a package name, either bare or an `@types/` one.
			const candidates = name.startsWith('@types/') ? [name] : [`@types/${name}`, name];
			assert.ok(
				candidates.some((c) => declared.has(c)),
				`${root} names "${name}" in compilerOptions.types, but the root package.json ` +
					`declares none of ${candidates.join(' / ')}. A workspace declaring it is not ` +
					'enough — npm may install it under that workspace, and a root tsc then fails ' +
					'with TS2688 on a clean checkout while passing wherever node_modules has ' +
					'drifted. Declare it at the root.',
			);
		}
	}
});
