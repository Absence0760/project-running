#!/usr/bin/env node
// Guardrail: a CI step never fetches the program it runs.
//
// `npx <bin>`, `pnpm exec <bin>` and the `dlx` family run whatever binary
// `node_modules/.bin` provides — and when nothing provides it, `npx` silently
// resolves the name against the public registry and executes the newest thing
// it finds. No version pin, no lockfile entry, no integrity hash: third-party
// code, chosen at test time, running in a job that holds this repo's checkout
// and its GITHUB_TOKEN. That is the same species of hazard as an action pinned
// to a mutable tag, which check_toolchain_pins.mjs already refuses.
//
// It is not hypothetical. `parity-types` ran the entire web unit suite through
// `npx tsx`, and `tsx` was declared by no package.json in the repo — vite lists
// it as an OPTIONAL peer, which installs nothing. Every green run of that job
// had downloaded a tsx off the network first. The same absence broke the other
// half: `apps/web`'s own `test:unit` script invoked a bare `tsx`, so the
// reproduce command printed by that step's own diagnosis failed with
// `tsx: command not found` on a clean checkout (decisions § 764).
//
// The rule: every binary a workflow hands to a package runner is provided by a
// package this repo DECLARES. Declared means the runner resolves it out of
// node_modules after the job's install step, which is the whole difference
// between a pinned dependency and a run-time download.
//
// PROVIDERS is explicit rather than derived because the mapping cannot be read
// without an install — `playwright` comes from `@playwright/test`, `svelte-kit`
// from `@sveltejs/kit` — and this runs in `workflow-lint`, which has no
// `npm ci`. An unmapped binary is therefore a FAILURE, not a skip: a guard that
// shrugged at a name it had not seen would pass over exactly the new
// run-time download it exists to catch. A mapped binary that no workflow
// invokes any more fails too, so the table cannot rot into prose.
//
// Comments and echoed prose inside a `run:` block are read like any other
// line, on purpose. A diagnosis that tells the reader to run `npx foo` is
// making the same claim the command makes, and it was the half that was wrong
// last time.
//
// What is read is the LOGICAL command, not the physical line. Two layers put a
// runner and its binary on different lines: YAML folds a `>`-headed scalar's
// lines into one before any shell sees them, and the shell then joins a line
// ending in a backslash with the next. Scanning raw lines dropped both — the
// binary landed on a line with no runner on it and the runner's own line
// carried nothing that could be a command name, so `binaryOf` returned null
// and the invocation vanished with no output at all (decisions § 773).
//
// Run: `node scripts/check_workflow_binaries.mjs`
// CI:  the `workflow-lint` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_workflow_binaries.test.mjs`

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const WORKFLOW_DIR = join(REPO_ROOT, '.github', 'workflows');
export const ACTION_DIR = join(REPO_ROOT, '.github', 'actions');
export const ROOT_MANIFEST = join(REPO_ROOT, 'package.json');

/// Binary name -> the npm package that installs it. Anything a workflow runs
/// through a package runner has to appear here, and everything here has to be
/// run by some workflow.
export const PROVIDERS = new Map([
	['tsx', 'tsx'],
	['playwright', '@playwright/test'],
	['svelte-kit', '@sveltejs/kit'],
]);

/// The package runners. `npm run` is deliberately absent: it executes a script
/// this repo wrote, not a package it fetched.
const RUNNER = /(?:^|[^\w./@-])(npx|npm\s+exec|npm\s+x|pnpm\s+exec|pnpm\s+dlx|yarn\s+dlx)\s+(\S[^\n]*)/g;

/**
 * @typedef {{ name: string, text: string }} SourceFile
 * @typedef {{ file: string, line: number, runner: string, bin: string }} Invocation
 */

/// What a command name may look like. A runner is handed a program, so a token
/// that cannot be one — `<bin>` in a comment's template, the `/` separating
/// alternatives in a sentence — is prose that merely sits next to the word
/// `npx`, not an invocation. Anything an expression interpolates is neither,
/// and is reported rather than skipped.
const COMMAND_NAME = /^[@A-Za-z0-9][A-Za-z0-9@._/-]*$/;
export const DYNAMIC = '<expression>';

/// The binary a runner was handed, skipping the runner's own flags and the
/// `--` that ends them. `null` when there is no invocation here.
///
/// Quoting and sentence punctuation come off both ends: half the lines this
/// reads sit inside prose — a comment above the step, an `echo`'d reproduce
/// command — where the name is followed by a comma or closes a backtick. No
/// binary is named `tsx`,` and reading one that way would report an unknown
/// command rather than the tsx the sentence is about.
/**
 * @param {string} rest
 * @returns {string | null}
 */
export function binaryOf(rest) {
	for (const raw of rest.split(/\s+/)) {
		const token = raw.replace(/^["'`(]+/, '').replace(/["'`),;.]+$/, '');
		if (token === '' || token === '--') continue;
		if (token.startsWith('-')) continue;
		if (token.includes('$') || token.includes('{{')) return DYNAMIC;
		return COMMAND_NAME.test(token) ? token : null;
	}
	return null;
}

/// A `>`-headed block scalar: `run: >-`, `description: >`, a bare `- >`. YAML
/// joins its lines with spaces, so what the shell receives is one command per
/// paragraph rather than one per physical line. `|` is deliberately absent —
/// a literal block keeps its newlines and each line IS its own command.
const FOLDED_HEADER = /^([ \t]*)(?:-[ \t]+)?(?:[A-Za-z_][A-Za-z0-9_.-]*[ \t]*:[ \t]*)?>[+-]?[0-9]*[ \t]*$/;

/** @param {string} line */
function indentOf(line) {
	return /^[ \t]*/.exec(line)[0].length;
}

/// The file's physical lines as the commands a shell would actually run, each
/// tagged with the 1-based line its FIRST physical line sits on.
///
/// A blank line inside a folded scalar is a paragraph break — YAML turns it
/// into a newline, not a space — so folding across one would invent a command
/// nothing runs. Backslash continuation is applied afterwards because that is
/// the order the two layers happen in: YAML hands the shell a string, and the
/// shell then joins its continuations.
/**
 * @param {string} text
 * @returns {{ line: number, text: string }[]}
 */
export function logicalLines(text) {
	const lines = text.split('\n');
	/** @type {{ line: number, text: string }[]} */
	const folded = [];
	for (let i = 0; i < lines.length; i++) {
		const header = FOLDED_HEADER.exec(lines[i]);
		if (header === null) {
			folded.push({ line: i + 1, text: lines[i] });
			continue;
		}
		folded.push({ line: i + 1, text: lines[i] });
		const base = header[1].length;
		let j = i + 1;
		/** @type {string[]} */
		let run = [];
		let runStart = j + 1;
		const flush = () => {
			if (run.length > 0) folded.push({ line: runStart, text: run.join(' ') });
			run = [];
		};
		while (j < lines.length && (lines[j].trim() === '' || indentOf(lines[j]) > base)) {
			if (lines[j].trim() === '') flush();
			else {
				if (run.length === 0) runStart = j + 1;
				run.push(lines[j].trim());
			}
			j++;
		}
		flush();
		i = j - 1;
	}

	/** @type {{ line: number, text: string }[]} */
	const out = [];
	for (let i = 0; i < folded.length; i++) {
		let { line, text: acc } = folded[i];
		while (/\\[ \t]*$/.test(acc) && i + 1 < folded.length) {
			acc = `${acc.replace(/\\[ \t]*$/, '')} ${folded[i + 1].text.trim()}`;
			i++;
		}
		out.push({ line, text: acc });
	}
	return out;
}

/**
 * @param {readonly SourceFile[]} files
 * @returns {Invocation[]}
 */
export function parseInvocations(files) {
	/** @type {Invocation[]} */
	const found = [];
	for (const { name, text } of files) {
		for (const { line, text: command } of logicalLines(text)) {
			for (const match of command.matchAll(RUNNER)) {
				const bin = binaryOf(match[2]);
				if (bin === null) continue;
				found.push({
					file: name,
					line,
					runner: match[1].replace(/\s+/g, ' '),
					bin,
				});
			}
		}
	}
	return found;
}

/// Every package name this repo declares as a dependency of anything, read off
/// the root manifest and each workspace it lists.
/**
 * @param {string} rootManifestText
 * @param {(workspaceDir: string) => string} readWorkspaceManifest
 * @returns {Set<string>}
 */
export function declaredPackages(rootManifestText, readWorkspaceManifest) {
	/** @type {Set<string>} */
	const declared = new Set();
	/** @param {string} text */
	const absorb = (text) => {
		/** @type {Record<string, unknown>} */
		const manifest = JSON.parse(text);
		for (const field of ['dependencies', 'devDependencies', 'optionalDependencies']) {
			const block = manifest[field];
			if (block && typeof block === 'object') for (const name of Object.keys(block)) declared.add(name);
		}
		return manifest;
	};
	const root = absorb(rootManifestText);
	const workspaces = root['workspaces'];
	if (Array.isArray(workspaces)) {
		for (const dir of workspaces) if (typeof dir === 'string') absorb(readWorkspaceManifest(dir));
	}
	return declared;
}

/**
 * @param {readonly SourceFile[]} files
 * @param {ReadonlySet<string>} declared
 * @returns {{ errors: string[], ok: string[], invocations: Invocation[] }}
 */
export function checkWorkflowBinaries(files, declared) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	const invocations = parseInvocations(files);
	/** @type {Set<string>} */
	const used = new Set();

	for (const { file, line, runner, bin } of invocations) {
		const where = `${file}:${line}`;
		if (bin === DYNAMIC) {
			errors.push(
				`${where} — \`${runner}\` is handed a binary an expression decides at run ` +
					`time, so nothing static can say whether the repo installs it. Name the ` +
					`program literally, or run it through an \`npm run\` script this repo owns.`,
			);
			continue;
		}
		const provider = PROVIDERS.get(bin);
		if (provider === undefined) {
			errors.push(
				`${where} — \`${runner} ${bin}\` runs a binary this guard has never been ` +
					`told about, so nothing here knows whether the repo installs it or the ` +
					`registry does. Add \`${bin}\` to PROVIDERS in ` +
					`scripts/check_workflow_binaries.mjs naming the package that provides ` +
					`it (and declare that package), or stop invoking it through a package ` +
					`runner.`,
			);
			continue;
		}
		used.add(bin);
		if (!declared.has(provider)) {
			errors.push(
				`${where} — \`${runner} ${bin}\` resolves nothing locally: \`${provider}\` ` +
					`is declared by no package.json in this repo, so the runner downloads an ` +
					`unpinned copy from the registry at run time and executes it against this ` +
					`checkout. Add \`${provider}\` to the dependencies of the package that ` +
					`runs it and commit both lockfiles.`,
			);
			continue;
		}
		ok.push(`${where} -> ${runner} ${bin} resolves from the declared ${provider}`);
	}

	if (invocations.length === 0) {
		errors.push(
			`no package-runner invocation (npx / npm exec / pnpm exec / dlx) found in any ` +
				`workflow or composite action. Either every one was removed, or the runners ` +
				`were reworded and this check now enforces nothing.`,
		);
	}

	for (const [bin, provider] of PROVIDERS) {
		if (used.has(bin)) continue;
		errors.push(
			`PROVIDERS maps \`${bin}\` to \`${provider}\`, but no workflow or composite ` +
				`action runs \`${bin}\` through a package runner any more. Drop the entry ` +
				`rather than leaving it reading nothing.`,
		);
	}

	return { errors, ok, invocations };
}

/**
 * @param {string} dir
 * @returns {SourceFile[]}
 */
export function readWorkflows(dir) {
	return readdirSync(dir)
		.filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
		.sort()
		.map((name) => ({ name, text: readFileSync(join(dir, name), 'utf-8') }));
}

/// Composite actions live one directory down, each as its own `action.yml`.
/**
 * @param {string} dir
 * @returns {SourceFile[]}
 */
export function readCompositeActions(dir) {
	/** @type {SourceFile[]} */
	const files = [];
	let entries;
	try {
		entries = readdirSync(dir).sort();
	} catch {
		return files;
	}
	for (const entry of entries) {
		const path = join(dir, entry);
		if (!statSync(path).isDirectory()) continue;
		for (const candidate of ['action.yml', 'action.yaml']) {
			const full = join(path, candidate);
			try {
				files.push({ name: `${entry}/${candidate}`, text: readFileSync(full, 'utf-8') });
			} catch {
				// The other extension; a directory with neither is not an action.
			}
		}
	}
	return files;
}

function main() {
	const files = [...readWorkflows(WORKFLOW_DIR), ...readCompositeActions(ACTION_DIR)];
	const declared = declaredPackages(readFileSync(ROOT_MANIFEST, 'utf-8'), (dir) =>
		readFileSync(join(REPO_ROOT, dir, 'package.json'), 'utf-8'),
	);
	const { errors, ok, invocations } = checkWorkflowBinaries(files, declared);

	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);

	if (errors.length > 0) {
		console.error(`\n${errors.length} run-time binary download(s) in CI.`);
		return 1;
	}
	console.log(
		`\n${invocations.length} package-runner invocation(s) across ${files.length} ` +
			`workflow/action file(s) name a binary from a declared package; none is fetched ` +
			`at run time.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
