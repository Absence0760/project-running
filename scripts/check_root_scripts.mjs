#!/usr/bin/env node
// Guardrail: every target a root script hands to another package exists, and
// every directory one changes into does too.
//
// Why it was rewritten (decisions § 773): it read shell with `String.split`
// and two regexes, and misread it four ways at once. `pnpm -C apps/web
// --silent run check` named `--silent` as the script to look for; `cd
// apps/backend; supabase db reset` looked for a directory called
// `apps/backend;`; `cd "apps/web"` was reported missing because the quotes
// stayed on the word — three false accusations from one synthetic manifest —
// while a genuinely absent directory after a `;` went unreported, because the
// `(?:^|&&\s*)cd` anchor covered `&&` and not `;`. And switching a script to
// `pnpm --filter`, pnpm's own recommended workspace form, made the guard
// verify nothing at all while still printing that it had passed.
//
// It also ran in NO workflow. `test:scripts` in the root manifest was the only
// caller, and no job invoked it — the § 439 shape, a guard enforcing nothing
// for as long as it had existed.
//
// The shell is now read by scripts/shell_lex.mjs, and `cd` is tracked as a
// shell tracks it: each one resolves against the directory the previous one
// left the script in, so `cd apps/backend && … && cd ../..` means the repo
// root rather than two levels above whatever the process started in.
//
// What cannot be verified is COUNTED and reported rather than dropped: a path
// or a target an expression decides at run time is not something a static read
// can vouch for, and a summary line claiming it checked 95 scripts when 14 of
// them are documentation headers is the same species of overclaim as the
// misreads above.
//
// Run: `node scripts/check_root_scripts.mjs` (or `npm run test:scripts`)
// CI:  the `workflow-lint` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_root_scripts.test.mjs`

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { splitShellCommands } from './shell_lex.mjs';

/** @typedef {{ name?: string, scripts?: Record<string, string>, workspaces?: unknown }} PackageJson */
/**
 * @typedef {object} Deps
 * @property {(dir: string) => PackageJson | null} readManifest repo-relative dir -> its package.json
 * @property {(dir: string) => boolean} dirExists repo-relative dir
 * @property {readonly string[]} workspaceDirs repo-relative workspace directories
 */

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/// npm's convention for a comment entry in `scripts`. This manifest uses it
/// for section headers, whose values are prose rather than commands.
export const isDocumentationKey = (/** @type {string} */ name) => name.startsWith('//');

/// pnpm's own subcommands. `pnpm <x>` runs the script `x` unless `x` is one of
/// these, in which case there is no script to look for.
export const RESERVED_PNPM_VERBS = new Set([
	'install', 'add', 'remove', 'update', 'exec', 'dlx',
	'run', 'test', 'start', 'build', 'publish', 'pack', 'audit',
	'list', 'ls', 'why', 'outdated', 'config', 'store', 'recursive',
	'rebuild', 'prune', 'link', 'unlink', 'import', 'fetch',
]);

/// The pnpm options that take a value, so the word after one is that value
/// rather than the subcommand.
const PNPM_VALUE_OPTIONS = new Set(['-C', '--dir', '--filter', '-F', '--workspace-root', '--reporter']);

/// Nothing static can say what an interpolation expands to.
const isDynamic = (/** @type {string} */ word) => word.includes('$');

/**
 * The workspace directories, read off both manifests rather than either alone
 * — npm reads `workspaces`, pnpm reads `pnpm-workspace.yaml`, and a package
 * listed in one and not the other is its own problem, not this guard's.
 * @param {PackageJson} manifest
 * @param {string | null} pnpmWorkspaceText
 * @returns {string[]}
 */
export function workspaceDirs(manifest, pnpmWorkspaceText) {
	/** @type {Set<string>} */
	const dirs = new Set();
	if (Array.isArray(manifest.workspaces)) {
		for (const d of manifest.workspaces) if (typeof d === 'string') dirs.add(d);
	}
	if (pnpmWorkspaceText !== null) {
		for (const m of pnpmWorkspaceText.matchAll(/^\s*-\s*['"]?([^'"\s#]+)['"]?\s*$/gm)) {
			dirs.add(m[1]);
		}
	}
	return [...dirs];
}

/**
 * @param {PackageJson} manifest the root package.json
 * @param {Deps} deps
 * @returns {{ errors: string[], ok: string[], unverifiable: string[], scriptCount: number }}
 */
export function checkRootScripts(manifest, deps) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	/** @type {string[]} */
	const unverifiable = [];
	const scripts = manifest.scripts ?? {};

	/** @type {Map<string, string | null>} */
	const packageNameToDir = new Map();
	for (const dir of deps.workspaceDirs) {
		const child = deps.readManifest(dir);
		if (child?.name) packageNameToDir.set(child.name, dir);
	}

	/**
	 * @param {string} script
	 * @param {string} dir repo-relative, '' for the root
	 * @param {string} target
	 */
	const checkTarget = (script, dir, target) => {
		const label = dir === '' ? 'the root package.json' : `${dir}/package.json`;
		const child = dir === '' ? manifest : deps.readManifest(dir);
		if (!child) {
			errors.push(`${script}: missing ${dir}/package.json`);
			return;
		}
		if (!(target in (child.scripts ?? {}))) {
			errors.push(`${script}: ${label} has no "${target}" script`);
			return;
		}
		ok.push(`${script}: ${label} declares "${target}"`);
	};

	let scriptCount = 0;
	for (const [script, cmd] of Object.entries(scripts)) {
		if (isDocumentationKey(script)) continue;
		scriptCount++;

		/** @type {import('./shell_lex.mjs').ShellCommand[]} */
		let commands;
		try {
			commands = splitShellCommands(cmd);
		} catch (err) {
			errors.push(`${script}: unreadable shell — ${err instanceof Error ? err.message : String(err)}`);
			continue;
		}

		// Where the script has cd'd to so far, repo-relative. '' is the root.
		let cwd = '';
		for (const { words } of commands) {
			if (words[0] === 'cd') {
				const arg = words[1];
				if (arg === undefined || arg === '-' || isDynamic(arg)) {
					unverifiable.push(`${script}: \`cd ${arg ?? ''}\`.trim() names no static directory`);
					cwd = '';
					continue;
				}
				const next = path.normalize(path.join(cwd, arg));
				if (next.startsWith('..')) {
					errors.push(
						`${script}: \`cd ${arg}\` leaves the repository (from ${cwd || '.'}). ` +
							'Whether that directory exists is a property of the machine, not of this checkout.',
					);
					cwd = '';
					continue;
				}
				const rel = next === '.' ? '' : next;
				if (rel !== '' && !deps.dirExists(rel)) {
					errors.push(`${script}: missing directory ${rel}`);
					cwd = '';
					continue;
				}
				ok.push(`${script}: \`cd ${arg}\` -> ${rel || '.'}`);
				cwd = rel;
				continue;
			}

			if (words[0] !== 'pnpm') continue;

			/** @type {string | null} */
			let dirOption = null;
			/** @type {string | null} */
			let filter = null;
			/** @type {string[]} */
			const positional = [];
			for (let i = 1; i < words.length; i++) {
				const w = words[i];
				if (!w.startsWith('-')) {
					positional.push(w);
					continue;
				}
				const [flag, inlineValue] = w.includes('=') ? [w.slice(0, w.indexOf('=')), w.slice(w.indexOf('=') + 1)] : [w, null];
				const value = inlineValue ?? (PNPM_VALUE_OPTIONS.has(flag) ? words[++i] : null);
				if ((flag === '-C' || flag === '--dir') && value !== undefined) dirOption = value ?? null;
				if ((flag === '--filter' || flag === '-F') && value !== undefined) filter = value ?? null;
			}

			const verb = positional[0];
			if (verb === undefined) continue;
			const target = verb === 'run' ? positional[1] : verb;
			if (target === undefined) continue;
			// Reported rather than dropped. Some of these are genuine pnpm
			// subcommands with no script behind them (`install`, `exec`); others
			// — `build`, `test`, `start` — are script shortcuts this list treats
			// as commands, so naming them here is the honest way to say the guard
			// looked at the invocation and checked nothing.
			if (RESERVED_PNPM_VERBS.has(target)) {
				unverifiable.push(`${script}: \`pnpm ${target}\` is a reserved pnpm verb, not a script lookup`);
				continue;
			}

			/** @type {string | null} */
			let dir;
			if (dirOption !== null) {
				dir = isDynamic(dirOption) ? null : path.normalize(path.join(cwd, dirOption));
			} else if (filter !== null) {
				dir = packageNameToDir.get(filter) ?? (deps.dirExists(filter) ? filter : undefined) ?? null;
				if (dir === null) {
					unverifiable.push(
						`${script}: \`pnpm --filter ${filter}\` names no workspace package this guard can resolve`,
					);
					continue;
				}
			} else {
				dir = cwd;
			}
			if (dir === null || isDynamic(target)) {
				unverifiable.push(`${script}: \`pnpm … ${target}\` names no static package/target pair`);
				continue;
			}
			checkTarget(script, dir === '.' ? '' : dir, target);
		}
	}

	// Vacuity: a manifest whose scripts all stopped matching would otherwise
	// report a clean pass over nothing, which is what the `--filter` hole did.
	if (scriptCount === 0) {
		errors.push('The root package.json declares no runnable scripts — nothing here checked anything.');
	} else if (ok.length === 0 && errors.length === 0) {
		errors.push(
			`Verified nothing across ${scriptCount} root script(s). Every \`cd\` and ` +
				'every package-runner target changed shape at once, or this guard stopped ' +
				'recognising the shapes it reads — which is what switching one script from ' +
				'`pnpm -C` to `pnpm --filter` used to do, silently, while this line still ' +
				'said the check had passed.',
		);
	}

	return { errors, ok, unverifiable, scriptCount };
}

function main() {
	/** @type {PackageJson} */
	const manifest = JSON.parse(fs.readFileSync(path.join(rootDir, 'package.json'), 'utf8'));
	let pnpmWorkspace = null;
	try {
		pnpmWorkspace = fs.readFileSync(path.join(rootDir, 'pnpm-workspace.yaml'), 'utf8');
	} catch {
		// npm-only workspaces; `workspaces` in the root manifest is the whole list.
	}

	/** @type {Map<string, PackageJson | null>} */
	const cache = new Map();
	const { errors, ok, unverifiable, scriptCount } = checkRootScripts(manifest, {
		workspaceDirs: workspaceDirs(manifest, pnpmWorkspace),
		dirExists: (dir) => fs.existsSync(path.join(rootDir, dir)),
		readManifest: (dir) => {
			const hit = cache.get(dir);
			if (hit !== undefined) return hit;
			const file = path.join(rootDir, dir, 'package.json');
			const value = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : null;
			cache.set(dir, value);
			return value;
		},
	});

	for (const line of unverifiable) console.warn(`[SKIP] ${line}`);
	for (const line of errors) console.error(`  - ${line}`);

	if (errors.length) {
		console.error(
			`Root scripts validation failed (${errors.length} issue${errors.length === 1 ? '' : 's'}).`,
		);
		return 1;
	}
	console.log(
		`Root scripts validation passed: ${ok.length} directory/target claim(s) across ` +
			`${scriptCount} script(s)` +
			(unverifiable.length ? `, ${unverifiable.length} unverifiable` : '') +
			'.',
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
