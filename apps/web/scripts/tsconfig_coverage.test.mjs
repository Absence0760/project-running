// Guardrail: no compilable file under `apps/web` sits outside every typecheck.
//
// `apps/web` has more than one tsc root and always will: SvelteKit generates
// the app's `include`, the Playwright tree needs its own (§ 749), the Node
// side needs `@types/node` the app does not, and the service worker needs the
// `WebWorker` lib, which cannot share a program with `DOM`. TypeScript does
// not merge `include` across `extends`, so a new tree simply belongs to none
// of them until somebody says so — which is how `scripts/`, `lambda/` (eight
// production Lambda handlers), `svelte.config.js` and `static/sw.js` were
// checked by nothing at all (decisions § 752).
//
// This walks the tracked files rather than a list of trees, and derives what
// is covered from the configs themselves — including the generated
// `.svelte-kit/tsconfig.json`, so SvelteKit changing what it claims changes
// what this expects, and a root added later counts the moment it exists.
//
// Run: `npm run test:tsconfig-coverage --workspace=apps/web`
// CI:  the `parity-types` job in .github/workflows/ci.yml.

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, extname, join, relative, resolve } from 'node:path';
import { test } from 'node:test';

const WEB_ROOT = resolve(import.meta.dirname, '..');
const REPO_ROOT = resolve(WEB_ROOT, '..', '..');

/** Extensions `tsc` compiles. A file carrying one is a file some root should read. */
const COMPILABLE = new Set(['.ts', '.mts', '.cts', '.tsx', '.js', '.mjs', '.cjs', '.jsx']);

/**
 * Source files under apps/web, relative to it: tracked, plus untracked ones git
 * is not ignoring. Git is the only list of "what is source here" that nobody
 * maintains by hand — and the untracked half means a file still being written
 * is covered by this before it is staged, not after.
 */
function sourceFiles() {
	const ls = (/** @type {string[]} */ args) =>
		execFileSync('git', ['ls-files', '-z', ...args], { cwd: WEB_ROOT, encoding: 'utf8' })
			.split('\0')
			.filter(Boolean);
	return [...new Set([...ls([]), ...ls(['--others', '--exclude-standard'])])];
}

/**
 * The tsc roots at the top of apps/web. Read off the directory rather than off
 * `git ls-files`, so a root added in the same change it is needed for counts
 * before it is staged.
 */
function configRoots() {
	return readdirSync(WEB_ROOT)
		.filter((f) => /^tsconfig[^/]*\.json$/.test(f))
		.sort();
}

/**
 * Comments are legal in a tsconfig and these carry them.
 * @param {string} absPath
 */
function readConfig(absPath) {
	const raw = readFileSync(absPath, 'utf8').replace(/^\s*\/\/.*$/gm, '');
	return /** @type {{ extends?: string, include?: string[], exclude?: string[] }} */ (
		JSON.parse(raw)
	);
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
			`${relative(REPO_ROOT, current)} does not exist, so a tsc root here resolves to ` +
				'nothing. If it is .svelte-kit/tsconfig.json, run `svelte-kit sync` first.',
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

test('every compilable file under apps/web is inside some tsc root', () => {
	const roots = configRoots();
	assert.ok(roots.length > 0, 'No tsconfig root is tracked under apps/web.');

	const matchers = roots.map((r) => {
		const { include, exclude } = effectivePatterns(join(WEB_ROOT, r));
		return {
			include: include.map(globToRegExp),
			exclude: exclude.map(globToRegExp),
		};
	});

	const missed = sourceFiles()
		.filter((f) => COMPILABLE.has(extname(f)))
		.filter((f) => {
			const abs = join(WEB_ROOT, f);
			return !matchers.some(
				(m) => m.include.some((re) => re.test(abs)) && !m.exclude.some((re) => re.test(abs)),
			);
		})
		.sort();

	assert.deepEqual(
		missed,
		[],
		'These files carry a compilable extension no tsconfig root under apps/web reads, so ' +
			'nothing typechecks them. Add them to an existing root, or give them one — do not ' +
			`leave them outside: ${missed.join(', ')}`,
	);
});

test('every tsc root is reachable as an npm script and runs in CI', () => {
	const pkg = /** @type {{ scripts?: Record<string, string> }} */ (
		JSON.parse(readFileSync(join(WEB_ROOT, 'package.json'), 'utf8'))
	);
	const scripts = Object.entries(pkg.scripts ?? {});
	const ci = readFileSync(join(REPO_ROOT, '.github', 'workflows', 'ci.yml'), 'utf8');

	for (const root of configRoots()) {
		const runners = scripts.filter(([, body]) => body.includes(root));
		assert.ok(
			runners.length > 0,
			`No script in apps/web/package.json names ${root}, so nothing runs that typecheck.`,
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
	const pkg = /** @type {{ scripts?: Record<string, string> }} */ (
		JSON.parse(readFileSync(join(WEB_ROOT, 'package.json'), 'utf8'))
	);
	const entry = Object.entries(pkg.scripts ?? {}).find(([, body]) =>
		body.includes('tsconfig_coverage.test.mjs'),
	);
	assert.ok(entry, 'apps/web/package.json must declare a script that runs this guard.');
	// The chain bottoms out in the generated .svelte-kit/tsconfig.json, which a
	// clean checkout does not have.
	assert.match(
		entry[1],
		/svelte-kit sync/,
		`"${entry[0]}" must sync SvelteKit before running this guard.`,
	);
	const ci = readFileSync(join(REPO_ROOT, '.github', 'workflows', 'ci.yml'), 'utf8');
	assert.ok(
		ci.includes(`npm run ${entry[0]}`),
		`.github/workflows/ci.yml must run "${entry[0]}" — a coverage guard nothing runs is ` +
			'not a guard.',
	);
});
