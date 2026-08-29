#!/usr/bin/env node
// Guardrail: every npm dependency this repo declares is read by something in
// it, and no plugin is configured that contributes nothing.
//
// `unplugin-icons` was registered in `apps/web/vite.config.ts` with
// `autoInstall: true` for months while no `~icons/` import existed anywhere
// the build compiles, so the plugin resolved nothing and its
// `@iconify-json/material-symbols` icon set was read by nobody. `autoInstall`
// is what makes that worse than idle: on a miss the plugin installs a package
// the lockfile does not carry, at build time. `normalize.css` was the same
// shape one layer quieter — declared in the scaffold commit, never imported,
// and described by two docs as part of the styling stack for the life of the
// repo. Both, plus a stray root `html-to-image`, are gone (decisions § 786).
//
// The docs are the reason a guard and not a sweep. Each of those three was
// DESCRIBED as live by a file a reader would consult, so the tree carried the
// claim and the claim was false; a human reading either doc could not tell,
// and a human reading the manifest had no reason to look. That is the failure
// mode a periodic sweep does not fix, because the sweep is what nobody runs.
//
// A dependency is READ when any of these holds. Everything is derived except
// the last, which is a table that cannot rot (a stale entry fails):
//
//   1. Some source file imports it — `from 'p'`, `import 'p'`, `import('p')`,
//      `require('p')`, a CSS `@import`, or any subpath of those.
//   2. It is `@types/x` and `x` is imported, is a module scheme some file
//      imports through (`node:fs` for `@types/node`), or is named in a
//      tsconfig's `compilerOptions.types`.
//   3. Some file reaches into `node_modules/<p>` by path. That is how
//      `material-symbols` is consumed: `scripts/web_icon_font.mjs` reads the
//      upstream `.woff2` out of the installed package and subsets it, so the
//      package is load-bearing while nothing imports it.
//   4. INDIRECT names it, either as a binary some script or workflow runs
//      (`tsc`, `tsx`, `svelte-check` — the name differs from the package's,
//      which is why this cannot be derived without an install) or as a
//      root-level hoist pin.
//
// The scan is deliberately NOT repo-wide over every extension. `docs/` quotes
// import statements in prose, and a guard that counted an ADR's code sample as
// a use would have reported every one of the three deletions above as live.
// Only real source trees are read, and `.md` only inside a workspace's `src/`
// where mdsvex compiles it.
//
// Usage is measured repo-wide across those trees rather than per-manifest,
// because a root-level script legitimately consumes a workspace member's
// package (rule 3 is exactly that). The redundancy rule is what covers the
// other direction: a package the root declares that only a workspace member
// reads, and that the member declares itself, is a stray root entry — which is
// what `npm install <pkg>` run from the repo root leaves behind.
//
// Run: `node scripts/check_dead_dependencies.mjs`
// CI:  the `parity-types` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_dead_dependencies.test.mjs`

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/// Extensions a bundler or a Node process actually reads.
const CODE = new Set(['.ts', '.mts', '.cts', '.tsx', '.js', '.mjs', '.cjs', '.jsx', '.svelte', '.css']);

/// Never descended into: installed packages, build output, and generated
/// framework state. A match inside any of them says nothing about this repo.
const SKIP_DIRS = new Set([
	'node_modules',
	'.git',
	'.svelte-kit',
	'build',
	'dist',
	'.vercel',
	'coverage',
	'test-results',
	'playwright-report',
]);

/// Trees outside the workspace members that still read npm packages. `docs/`
/// is absent on purpose — see the header.
const EXTRA_ROOTS = ['scripts', 'bin', 'infra', '.github'];

/**
 * Packages nothing imports and nothing can derive a use for. Each entry is
 * checked, so it fails when it stops being true rather than aging into an
 * allowlist: a `bin` entry must still be invoked somewhere, and a `hoistPin`
 * must still be declared by a workspace member (that is what makes it a pin
 * rather than a stray).
 * @type {Map<string, { bin?: string, hoistPin?: true, why: string }>}
 */
export const INDIRECT = new Map([
	[
		'apps/web:tsx',
		{ bin: 'tsx', why: 'runs the web unit suite — `tsx --test` in apps/web test:unit' },
	],
	[
		'apps/web:typescript',
		{ bin: 'tsc', why: 'the typecheck roots run `tsc -p`; svelte-check needs it too' },
	],
	[
		'apps/web:svelte-check',
		{ bin: 'svelte-check', why: 'the `check` script is the only caller' },
	],
	[
		'.:svelte',
		{
			hoistPin: true,
			why: "pins the hoisted copy @sveltejs/vite-plugin-svelte resolves as a peer — apps/web's own dep lands nested and is invisible to it (_svelte_root_pin_rationale)",
		},
	],
]);

/**
 * @typedef {{ dir: string, deps: string[] }} Manifest
 * @typedef {{
 *   specifiers: Set<string>,
 *   schemes: Set<string>,
 *   nodeModulePaths: Set<string>,
 *   tsTypes: Set<string>,
 * }} Usage
 */

/// Everything one scope says it reads. Two of these are built: one over the
/// whole repo, one over only what sits outside the workspace members — and the
/// redundancy rule below is the same predicate run against the second.
/** @returns {Usage} */
export function emptyUsage() {
	return {
		specifiers: new Set(),
		schemes: new Set(),
		nodeModulePaths: new Set(),
		tsTypes: new Set(),
	};
}

/**
 * Whether a scope reads a package: by import, by a `node_modules/<p>` path, or
 * — for a `@types/x` — by anything that makes `x` itself used.
 * @param {string} dep
 * @param {Usage} usage
 * @returns {string | null} how, or null when nothing in the scope reads it
 */
export function readBy(dep, usage) {
	if (usage.specifiers.has(dep)) return 'imported';
	if (usage.nodeModulePaths.has(dep)) return 'read out of node_modules by path';
	if (!dep.startsWith('@types/')) return null;
	const typed = dep.slice('@types/'.length);
	if (usage.specifiers.has(typed)) return `types for \`${typed}\`, which is imported`;
	if (usage.schemes.has(typed)) return `types for the \`${typed}:\` module scheme, which is imported through`;
	if (usage.tsTypes.has(typed)) return `types for \`${typed}\`, named in a tsconfig \`types\` array`;
	return null;
}

/// Strips a subpath off an import specifier, keeping both segments of a scope.
/**
 * @param {string} specifier
 * @returns {string | null}
 */
export function packageOf(specifier) {
	if (!specifier || specifier.startsWith('.') || specifier.startsWith('/')) return null;
	if (specifier.startsWith('$') || specifier.includes(':')) return null;
	const parts = specifier.split('/');
	if (specifier.startsWith('@')) {
		if (parts.length < 2 || !parts[1]) return null;
		return `${parts[0]}/${parts[1]}`;
	}
	return parts[0] || null;
}

/// The import forms a bundler or Node resolves. Written as separate patterns
/// rather than one alternation because the capture group has to stay at index
/// 1 in every branch, and a `from` clause can be arbitrarily far from its
/// `import` keyword.
const SPECIFIER_PATTERNS = [
	/(?:^|[^\w$.])from\s*['"]([^'"\n]+)['"]/g,
	/(?:^|[^\w$.])import\s*\(\s*['"]([^'"\n]+)['"]/g,
	/(?:^|[^\w$.])import\s+['"]([^'"\n]+)['"]/g,
	/(?:^|[^\w$.])require\s*\(\s*['"]([^'"\n]+)['"]/g,
	/@import\s+(?:url\(\s*)?['"]([^'"\n]+)['"]/g,
];

/// `node_modules/<pkg>` reached by path rather than by import.
const NODE_MODULE_PATH = /node_modules['"\s,)\]]*[/,\s]\s*['"]?(@[\w.-]+\/[\w.-]+|[\w.-]+)/g;

/// Whether the match at `index` sits in a comment. A commented-out import is
/// the shape dead configuration takes when someone disables it instead of
/// deleting it, and a comment QUOTING an import is how a guard reads its own
/// documentation as a use — both would answer for a package nothing builds.
///
/// Line-based, and honest about it: this repo's block comments continue with a
/// leading `*` on every line (conventions.md keeps comments near zero and
/// JSDoc-shaped), so a prefix test covers them. A block comment whose
/// continuation lines carry no marker at all would slip through; that costs a
/// false pass, never a false accusation.
/**
 * @param {string} text
 * @param {number} index
 * @returns {boolean}
 */
export function inComment(text, index) {
	const lineStart = text.lastIndexOf('\n', index - 1) + 1;
	const prefix = text.slice(lineStart, index);
	const trimmed = prefix.trimStart();
	if (trimmed.startsWith('*') || trimmed.startsWith('//') || trimmed.startsWith('#')) return true;
	if (trimmed.startsWith('<!--')) return true;
	// `://` is a URL, not a line comment.
	if (prefix.replace(/:\/\//g, '').includes('//')) return true;
	return prefix.includes('/*');
}

/**
 * Everything one file says about which packages it reads.
 * @param {string} text
 * @returns {Usage}
 */
export function scanSource(text) {
	const usage = emptyUsage();
	for (const pattern of SPECIFIER_PATTERNS) {
		pattern.lastIndex = 0;
		for (const match of text.matchAll(pattern)) {
			const raw = match[1];
			if (!raw || match.index === undefined) continue;
			if (inComment(text, match.index)) continue;
			const scheme = /^([a-z][\w.-]*):/.exec(raw);
			if (scheme && scheme[1]) usage.schemes.add(scheme[1]);
			const name = packageOf(raw);
			if (name) usage.specifiers.add(name);
		}
	}
	NODE_MODULE_PATH.lastIndex = 0;
	for (const match of text.matchAll(NODE_MODULE_PATH)) {
		if (!match[1] || match.index === undefined) continue;
		if (inComment(text, match.index)) continue;
		usage.nodeModulePaths.add(match[1]);
	}
	return usage;
}

/**
 * @param {Usage[]} intos
 * @param {Usage} from
 */
export function mergeUsage(intos, from) {
	for (const into of intos) {
		for (const s of from.specifiers) into.specifiers.add(s);
		for (const s of from.schemes) into.schemes.add(s);
		for (const s of from.nodeModulePaths) into.nodeModulePaths.add(s);
		for (const s of from.tsTypes) into.tsTypes.add(s);
	}
}

/// `.md` counts only under a `src/` tree, where mdsvex compiles it. Elsewhere
/// a markdown file is documentation, and documentation quotes imports.
/**
 * @param {string} relPath
 * @returns {boolean}
 */
export function isScannable(relPath) {
	const dot = relPath.lastIndexOf('.');
	if (dot < 0) return false;
	const ext = relPath.slice(dot);
	if (CODE.has(ext)) return true;
	return ext === '.md' && /(^|\/)src\//.test(relPath);
}

/**
 * @param {string} absDir
 * @param {(relPath: string) => void} visit
 * @param {string} [prefix]
 */
export function walk(absDir, visit, prefix = '') {
	/** @type {string[]} */
	let entries;
	try {
		entries = readdirSync(absDir).sort();
	} catch {
		return;
	}
	for (const entry of entries) {
		if (SKIP_DIRS.has(entry)) continue;
		const abs = join(absDir, entry);
		const rel = prefix ? `${prefix}/${entry}` : entry;
		let stats;
		try {
			stats = statSync(abs);
		} catch {
			continue;
		}
		if (stats.isDirectory()) walk(abs, visit, rel);
		else visit(rel);
	}
}

/**
 * The `types` names one tsconfig declares. That is how `@types/node` is
 * consumed by the script roots — no file imports the package by name. A
 * tsconfig carries comments, so it is read with a pattern, not JSON.parse.
 * @param {string} text
 * @returns {Set<string>}
 */
export function tsconfigTypes(text) {
	/** @type {Set<string>} */
	const names = new Set();
	const block = /"types"\s*:\s*\[([^\]]*)\]/.exec(text);
	if (!block || !block[1]) return names;
	for (const match of block[1].matchAll(/"([^"]+)"/g)) {
		if (match[1]) names.add(match[1]);
	}
	return names;
}

/**
 * Command words a package.json script or a workflow `run:` block invokes.
 * @param {string[]} texts
 * @returns {Set<string>}
 */
export function invokedCommands(texts) {
	/** @type {Set<string>} */
	const words = new Set();
	for (const text of texts) {
		for (const match of text.matchAll(/(?:^|[^\w$./@-])([a-z][\w.-]*)(?=\s|$)/gm)) {
			if (match[1]) words.add(match[1]);
		}
	}
	return words;
}

/**
 * @param {object} input
 * @param {Manifest[]} input.manifests  root first, then workspace members
 * @param {Usage} input.usage           what the whole repo reads
 * @param {Usage} input.outside         what only the trees outside the members read
 * @param {Set<string>} input.commands  command words scripts and workflows invoke
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkDeadDependencies({ manifests, usage, outside, commands }) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];

	if (manifests.length === 0) {
		errors.push(
			'no package.json was read, so this guard checked nothing. Either the ' +
				'workspace layout moved or the manifest walk broke.',
		);
		return { errors, ok };
	}

	const root = manifests[0];
	const memberDeps = new Set(manifests.slice(1).flatMap((m) => m.deps));
	/** @type {Set<string>} */
	const usedIndirect = new Set();

	for (const manifest of manifests) {
		const where = manifest.dir === '.' ? 'package.json' : `${manifest.dir}/package.json`;
		for (const dep of manifest.deps) {
			const key = `${manifest.dir}:${dep}`;
			const indirect = INDIRECT.get(key);
			if (indirect) {
				usedIndirect.add(key);
				if (indirect.bin && !commands.has(indirect.bin)) {
					errors.push(
						`${key} — INDIRECT says it is kept for the \`${indirect.bin}\` binary, ` +
							`but no package.json script and no workflow runs \`${indirect.bin}\` ` +
							`any more. Drop the dependency and the INDIRECT entry together.`,
					);
					continue;
				}
				if (indirect.hoistPin && !memberDeps.has(dep)) {
					errors.push(
						`${key} — INDIRECT says it pins the hoisted copy of \`${dep}\`, but no ` +
							`workspace member declares \`${dep}\` any more, so there is nothing ` +
							`to pin. Drop the dependency and the INDIRECT entry together.`,
					);
					continue;
				}
				ok.push(`${key} -> ${indirect.why}`);
				continue;
			}

			const how = readBy(dep, usage);
			if (how) {
				ok.push(`${key} -> ${how}`);
				continue;
			}

			errors.push(
				`${key} — declared, and nothing in this repo reads it: no import, no ` +
					`node_modules/${dep} path, no tsconfig \`types\` entry. Delete it from ` +
					`${where} and commit both lockfiles, or — if it is consumed some way ` +
					`this guard cannot see — add it to INDIRECT in ` +
					`scripts/check_dead_dependencies.mjs saying how.`,
			);
		}
	}

	// A root declaration a workspace member also carries, that only that member
	// reads, is what an `npm install <pkg>` from the repo root leaves behind:
	// 10b5ec519 added `html-to-image` in both places at once that way. Same
	// predicate, narrower scope.
	for (const dep of root.deps) {
		if (INDIRECT.has(`.:${dep}`)) continue;
		if (!memberDeps.has(dep)) continue;
		if (readBy(dep, outside)) continue;
		errors.push(
			`.:${dep} — the root manifest and a workspace member both declare it, and ` +
				`nothing outside the workspace directories reads it. The member's own ` +
				`declaration is the real one; drop the root copy, or record it in INDIRECT ` +
				`as a hoist pin the way \`svelte\` is.`,
		);
	}

	for (const [key, entry] of INDIRECT) {
		if (usedIndirect.has(key)) continue;
		const [dir, dep] = key.split(':');
		const where = dir === '.' ? 'the root manifest' : `${dir}/package.json`;
		errors.push(
			`INDIRECT names \`${key}\` (${entry.why}), but ${where} does not declare ` +
				`\`${dep}\` any more. Drop the entry rather than leaving it reading nothing.`,
		);
	}

	return { errors, ok };
}

/**
 * @param {string} text
 * @returns {string[]}
 */
export function declaredDeps(text) {
	/** @type {{ dependencies?: Record<string, string>, devDependencies?: Record<string, string> }} */
	const json = JSON.parse(text);
	return [...Object.keys(json.dependencies ?? {}), ...Object.keys(json.devDependencies ?? {})].sort();
}

/**
 * @param {string} text
 * @returns {string[]}
 */
export function workspaceDirs(text) {
	/** @type {{ workspaces?: string[] }} */
	const json = JSON.parse(text);
	return (json.workspaces ?? []).filter((w) => !w.includes('*'));
}

function main() {
	const rootText = readFileSync(join(REPO_ROOT, 'package.json'), 'utf-8');
	const memberDirs = workspaceDirs(rootText);
	/** @type {Manifest[]} */
	const manifests = [
		{ dir: '.', deps: declaredDeps(rootText) },
		...memberDirs.map((dir) => ({
			dir,
			deps: declaredDeps(readFileSync(join(REPO_ROOT, dir, 'package.json'), 'utf-8')),
		})),
	];

	const usage = emptyUsage();
	const outside = emptyUsage();
	/** @type {string[]} */
	const commandTexts = [];

	/**
	 * @param {string} relPath
	 * @param {boolean} insideMember
	 */
	const readFile = (relPath, insideMember) => {
		const scopes = insideMember ? [usage] : [usage, outside];
		if (/(^|\/)tsconfig[\w.-]*\.json$/.test(relPath)) {
			const types = tsconfigTypes(readFileSync(join(REPO_ROOT, relPath), 'utf-8'));
			mergeUsage(scopes, { ...emptyUsage(), tsTypes: types });
			return;
		}
		if (/(^|\/)package\.json$/.test(relPath)) {
			commandTexts.push(readFileSync(join(REPO_ROOT, relPath), 'utf-8'));
			return;
		}
		if (!isScannable(relPath)) return;
		mergeUsage(scopes, scanSource(readFileSync(join(REPO_ROOT, relPath), 'utf-8')));
	};

	for (const dir of memberDirs) {
		walk(join(REPO_ROOT, dir), (rel) => readFile(`${dir}/${rel}`, true));
	}
	for (const dir of EXTRA_ROOTS) {
		walk(join(REPO_ROOT, dir), (rel) => readFile(`${dir}/${rel}`, false));
	}
	for (const entry of readdirSync(REPO_ROOT).sort()) {
		if (SKIP_DIRS.has(entry)) continue;
		if (!statSync(join(REPO_ROOT, entry)).isFile()) continue;
		readFile(entry, false);
	}

	const { errors, ok } = checkDeadDependencies({
		manifests,
		usage,
		outside,
		commands: invokedCommands(commandTexts),
	});

	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);

	if (errors.length > 0) {
		console.error(`\n${errors.length} dependency declaration(s) that nothing reads.`);
		return 1;
	}
	const total = manifests.reduce((n, m) => n + m.deps.length, 0);
	console.log(
		`\n${total} dependency declaration(s) across ${manifests.length} manifest(s); ` +
			`every one is imported, read by path, backs a used @types, or is one of the ` +
			`${INDIRECT.size} INDIRECT entries.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
