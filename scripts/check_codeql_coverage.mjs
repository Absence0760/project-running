#!/usr/bin/env node
// Guardrail: the set of trees CodeQL BUILDS is the set of trees that exist.
//
// CodeQL analyses whatever the build steps compile, for every compiled
// language. So for `go` and `java-kotlin` the build step is not a performance
// detail — it IS the scope of the scan, and a module or Gradle project nobody
// builds is source nobody scans. Nothing about the resulting database says so:
// one holding a single module looks exactly like one holding every module, and
// the analysis reports clean either way. A scanner that reports success over a
// path it never read is worse than no scanner, because it is believed.
//
// This has now happened on both compiled legs. `apps/graph_cycle` went
// unscanned for the whole of its life while a comment above the build step
// called `apps/job_worker` "our only Go module" (decisions § 1304), and the
// explicit build was itself what suppressed the `runAutobuildIfLegacyGoWorkflow`
// net that would have caught it. The Kotlin leg then turned out to carry the
// same shape: one `working-directory: apps/watch_wear/android`, a header
// claiming both Kotlin surfaces, and 11 files under `apps/mobile_android/android`
// — `MainActivity.kt`, `RunActionReceiver.kt`, the platform-channel bridges —
// that the java-kotlin analysis had never read (decisions § 1352). There is no
// Java/Kotlin analogue of the Go autobuild net, and `build-mode: none` cannot
// stand in for one: CodeQL's buildless Java extractor does not process Kotlin.
//
// Both were fixed by enumerating the trees from the filesystem instead of
// naming them. This is what keeps that honest, and the anchor is deliberate:
// it does not look for the WORDS of an enumeration, it lifts the workflow's own
// `find` expression out of the step and RUNS it, then compares the answer with
// an independent walk of the tree. A step that goes back to a hardcoded path,
// drops a `-name` alternative, or grows a `-not -path` that hides a directory
// all diverge from the walk and fail here. A guard keyed on the spelling would
// pass every one of those; a guard keyed on the answer cannot. (Same instrument
// as `edge_functions_typecheck_coverage.test.mjs`, which lifts the deno-check
// lane's own file-list expression out of ci.yml and runs it.)
//
// The second half is the exclusion. A tree the job cannot build yet is DECLARED
// in a `<LANG>_UNBUILT` env value carrying its reason, and the step's own loop
// reads that same value to decide what to skip — so the declaration is wiring,
// not documentation, and deleting it makes the job attempt the build rather
// than quietly widen the gap. Here it is re-measured: an entry naming a
// directory the walk does not find has outlived what it excused and fails, and
// an exclusion list that has grown to cover every tree fails too, because an
// analysis over nothing is the state this whole guard exists to make visible.
//
// Run: `node scripts/check_codeql_coverage.mjs`
// CI:  the `workflow-lint` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_codeql_coverage.test.mjs`

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/// Overridable so the whole script — exit code and all — can be pointed at a
/// mutated copy of the tree, which is how a guard is shown to fail.
export const ROOT = process.env.CODEQL_COVERAGE_ROOT ?? REPO_ROOT;

export const WORKFLOW = join('.github', 'workflows', 'security.yml');

/**
 * The compiled languages whose scan scope is decided by a build step, and the
 * file that marks one of their trees.
 *
 * `minSurfaces` is a floor under the WALK, not under the workflow: a walk that
 * stopped matching would otherwise agree with a step whose `find` had stopped
 * matching in exactly the same way, and two broken halves would pass by
 * agreeing with each other. The numbers are what the repo holds today and are
 * meant to be raised, never lowered — lowering one is how a deleted module
 * stops being noticed.
 *
 * Interpreted languages are deliberately absent. `javascript-typescript` and
 * `actions` run `build-mode: none`, so their scope is the checkout and no build
 * step can narrow it.
 *
 * @typedef {{ language: string, marker: (name: string) => boolean, envKey: string | null, minSurfaces: number, label: string }} Surface
 */
/** @type {readonly Surface[]} */
export const SURFACES = [
	{
		language: 'go',
		marker: (name) => name === 'go.mod',
		envKey: null,
		minSurfaces: 2,
		label: 'Go module',
	},
	{
		language: 'java-kotlin',
		marker: (name) => name === 'settings.gradle' || name === 'settings.gradle.kts',
		envKey: 'CODEQL_KOTLIN_UNBUILT',
		minSurfaces: 2,
		label: 'Gradle project',
	},
];

/// A reason short enough to be a placeholder is not a reason. The exclusions
/// this guard admits are gaps in a security scan; "TODO" must not buy one.
export const MIN_REASON_CHARS = 40;

const SKIP_DIRS = new Set(['node_modules', '.git', 'build', '.dart_tool', 'target']);

/**
 * Every directory under `root` holding a file the marker accepts, repo-relative
 * and POSIX-separated. Deliberately independent of the workflow: this is the
 * answer the workflow's own expression is measured against.
 *
 * @param {string} root
 * @param {(name: string) => boolean} marker
 * @returns {string[]}
 */
export function walkSurfaces(root, marker) {
	/** @type {string[]} */
	const found = [];
	/** @param {string} dir */
	const visit = (dir) => {
		/** @type {import('node:fs').Dirent[]} */
		let entries;
		try {
			entries = readdirSync(dir, { withFileTypes: true });
		} catch {
			return;
		}
		if (entries.some((e) => e.isFile() && marker(e.name))) {
			const rel = relative(root, dir).split(sep).join('/');
			found.push(rel === '' ? '.' : rel);
		}
		for (const e of entries) {
			if (!e.isDirectory() || SKIP_DIRS.has(e.name)) continue;
			visit(join(dir, e.name));
		}
	};
	visit(root);
	return found.sort();
}

/**
 * Slice one job out of a workflow's `jobs:` mapping, by its two-space-indented
 * key. Text rather than a YAML parse because `workflow-lint` runs with no
 * `npm ci` — every guard in that job reads its inputs as text.
 *
 * @param {string} text
 * @param {string} name
 * @returns {string | null}
 */
export function jobBlock(text, name) {
	const lines = text.split('\n');
	const start = lines.findIndex((l) => l === `  ${name}:`);
	if (start < 0) return null;
	let end = lines.length;
	for (let i = start + 1; i < lines.length; i++) {
		if (/^ {2}\S/.test(lines[i])) {
			end = i;
			break;
		}
	}
	return lines.slice(start, end).join('\n');
}

/**
 * The name of the job whose `init` step declares `languages: <language>`.
 *
 * @param {string} text
 * @param {string} language
 * @returns {string[]}
 */
export function jobsDeclaring(text, language) {
	const lines = text.split('\n');
	/** @type {string[]} */
	const names = [];
	let current = null;
	for (const line of lines) {
		const m = /^ {2}([A-Za-z0-9_-]+):\s*$/.exec(line);
		if (m) current = m[1];
		if (current && new RegExp(`^\\s*languages:\\s*${language}\\s*$`).test(line)) {
			if (!names.includes(current)) names.push(current);
		}
	}
	return names;
}

/**
 * Lift the `<VAR>=$( … )` command substitution containing a `find` out of a
 * job's steps, un-indented so a shell can run it verbatim.
 *
 * Paren matching is balanced rather than lazy: `find . \( -name a -o -name b \)`
 * carries escaped parens that a `[\s\S]*?\)` would stop at, which is how a
 * regex-shaped version of this read half an expression and compared it against
 * the whole tree.
 *
 * @param {string} block
 * @returns {{ variable: string, script: string } | null}
 */
export function findExpression(block) {
	const runs = runScripts(block);
	for (const script of runs) {
		const m = /(^|\n)([A-Za-z_][A-Za-z0-9_]*)=\$\(/.exec(script);
		if (!m) continue;
		const variable = m[2];
		const open = m.index + m[0].length; // first char inside `$(`
		let depth = 1;
		let i = open;
		for (; i < script.length && depth > 0; i++) {
			const c = script[i];
			if (c === '\\') {
				i++;
				continue;
			}
			if (c === '(') depth++;
			else if (c === ')') depth--;
		}
		if (depth !== 0) continue;
		const body = script.slice(open, i - 1);
		if (!/\bfind\b/.test(body)) continue;
		return { variable, script: `${variable}=$(${body})` };
	}
	return null;
}

/**
 * Every `run:` block scalar in a step list, un-indented.
 *
 * @param {string} block
 * @returns {string[]}
 */
export function runScripts(block) {
	const lines = block.split('\n');
	/** @type {string[]} */
	const out = [];
	for (let i = 0; i < lines.length; i++) {
		// A step may spell its own key as the first entry of the list item
		// (`- run: |`) or under a `- name:` above it. Both are legal, both occur,
		// and a regex that only reads the second form finds no script at all in
		// the first — which reads exactly like a job that runs no build.
		const m = /^(\s*)(?:-\s+)?run:\s*\|\s*$/.exec(lines[i]);
		if (!m) continue;
		const indent = lines[i].indexOf('run:') + 2;
		/** @type {string[]} */
		const body = [];
		for (let j = i + 1; j < lines.length; j++) {
			if (lines[j].trim() !== '' && !lines[j].startsWith(' '.repeat(indent))) break;
			body.push(lines[j].slice(indent));
		}
		out.push(body.join('\n'));
	}
	return out;
}

/**
 * The `<KEY>: |` block scalar's value, un-indented.
 *
 * @param {string} block
 * @param {string} key
 * @returns {string | null}
 */
export function blockScalar(block, key) {
	const lines = block.split('\n');
	for (let i = 0; i < lines.length; i++) {
		const m = new RegExp(`^(\\s*)${key}:\\s*\\|\\s*$`).exec(lines[i]);
		if (!m) continue;
		const indent = m[1].length + 2;
		/** @type {string[]} */
		const body = [];
		for (let j = i + 1; j < lines.length; j++) {
			if (lines[j].trim() === '') break;
			if (!lines[j].startsWith(' '.repeat(indent))) break;
			body.push(lines[j].slice(indent));
		}
		return body.join('\n');
	}
	return null;
}

/**
 * Run the workflow's own enumeration and report what it names, repo-relative.
 *
 * @param {{ variable: string, script: string }} expr
 * @param {string} root
 * @returns {string[]}
 */
export function runEnumeration(expr, root) {
	const out = execFileSync(
		'/bin/sh',
		['-c', `${expr.script}\nprintf '%s\\n' "$${expr.variable}"`],
		{ cwd: root, encoding: 'utf-8' },
	);
	return out
		.split('\n')
		.map((l) => l.trim())
		.filter((l) => l !== '')
		.map((l) => (l.startsWith('./') ? l.slice(2) : l))
		.sort();
}

/**
 * @param {string} declaration
 * @returns {{ entries: { path: string, reason: string }[], malformed: string[] }}
 */
export function parseUnbuilt(declaration) {
	/** @type {{ path: string, reason: string }[]} */
	const entries = [];
	/** @type {string[]} */
	const malformed = [];
	for (const raw of declaration.split('\n')) {
		const line = raw.trim();
		if (line === '') continue;
		const eq = line.indexOf('=');
		if (eq <= 0) {
			malformed.push(line);
			continue;
		}
		const path = line.slice(0, eq).trim().replace(/^\.\//, '');
		entries.push({ path, reason: line.slice(eq + 1).trim() });
	}
	return { entries, malformed };
}

/**
 * @param {{ root?: string, workflowText?: string }} [opts]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function check(opts = {}) {
	const root = opts.root ?? ROOT;
	const workflowPath = join(root, WORKFLOW);
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];

	if (opts.workflowText === undefined && !existsSync(workflowPath)) {
		return { errors: [`${WORKFLOW} does not exist; nothing declares what CodeQL scans.`], ok };
	}
	const text = opts.workflowText ?? readFileSync(workflowPath, 'utf-8');

	for (const surface of SURFACES) {
		const walked = walkSurfaces(root, surface.marker);
		if (walked.length < surface.minSurfaces) {
			errors.push(
				`the tree holds ${walked.length} ${surface.label}(s) and this guard's floor is ` +
					`${surface.minSurfaces}. Either a walk stopped matching — in which case it agrees ` +
					`with a workflow whose own walk broke the same way, and two broken halves pass by ` +
					`agreeing — or a ${surface.label} was deleted, in which case lower the floor in ` +
					`SURFACES deliberately.`,
			);
			continue;
		}

		const jobs = jobsDeclaring(text, surface.language);
		if (jobs.length !== 1) {
			errors.push(
				`${jobs.length} job(s) in ${WORKFLOW} declare \`languages: ${surface.language}\` ` +
					`(${jobs.join(', ') || 'none'}); expected exactly one. CodeQL scopes the scan to ` +
					`what that job's build steps compile, so this guard cannot tell which build to ` +
					`measure.`,
			);
			continue;
		}
		const block = jobBlock(text, jobs[0]) ?? '';
		const expr = findExpression(block);
		if (!expr) {
			errors.push(
				`the \`${jobs[0]}\` job builds ${surface.label}s from a fixed path rather than from ` +
					`the tree: no \`VAR=$(find …)\` enumeration in any of its \`run:\` steps. A named ` +
					`path covers the ${surface.label}s that existed when someone last edited this ` +
					`file, and CodeQL reports clean over every one that has landed since ` +
					`(decisions § 1304, § 1352).`,
			);
			continue;
		}

		/** @type {string[]} */
		let enumerated;
		try {
			enumerated = runEnumeration(expr, root);
		} catch (e) {
			errors.push(
				`the \`${jobs[0]}\` job's ${surface.label} enumeration does not run: ` +
					`${e instanceof Error ? e.message : String(e)}. Lifted verbatim from the step, so ` +
					`what fails here fails in CI.`,
			);
			continue;
		}

		const missed = walked.filter((p) => !enumerated.includes(p));
		const extra = enumerated.filter((p) => !walked.includes(p));
		if (missed.length > 0 || extra.length > 0) {
			errors.push(
				`the \`${jobs[0]}\` job's own enumeration disagrees with the tree. ` +
					(missed.length > 0
						? `It does not name ${missed.join(', ')} — CodeQL would extract none of ` +
							`that source and report clean over it. `
						: '') +
					(extra.length > 0 ? `It names ${extra.join(', ')}, which is not a ${surface.label}. ` : '') +
					`The expression was run, not read: \`${expr.script.replace(/\s+/g, ' ')}\`.`,
			);
			continue;
		}

		const declaration = surface.envKey ? blockScalar(block, surface.envKey) : null;
		const { entries, malformed } = parseUnbuilt(declaration ?? '');
		for (const line of malformed) {
			errors.push(
				`\`${surface.envKey}\` carries \`${line}\`, which is not \`<path>=<reason>\`. The ` +
					`step's own skip loop matches on \`<path>=\`, so a line in any other shape ` +
					`excludes nothing and the build it was meant to skip runs anyway.`,
			);
		}
		for (const entry of entries) {
			if (!walked.includes(entry.path)) {
				errors.push(
					`\`${surface.envKey}\` excludes \`${entry.path}\`, which is not a ${surface.label} ` +
						`in this tree. An exclusion that has outlived the directory it excused is cover ` +
						`for nothing and hides the next one; delete it, or point it at where the ` +
						`${surface.label} moved to.`,
				);
			}
			if (entry.reason.length < MIN_REASON_CHARS) {
				errors.push(
					`\`${surface.envKey}\` excludes \`${entry.path}\` with a ${entry.reason.length}-character ` +
						`reason. An exclusion here is a hole in a security scan, so it costs at least ` +
						`${MIN_REASON_CHARS} characters saying what would have to change to close it.`,
				);
			}
		}

		const scanned = walked.filter((p) => !entries.some((e) => e.path === p));
		if (scanned.length === 0) {
			errors.push(
				`every ${surface.label} is excluded from the \`${jobs[0]}\` job, so the ` +
					`${surface.language} analysis runs over no source at all — and a CodeQL database ` +
					`with nothing extracted reports exactly as clean as one with everything. Build at ` +
					`least one, or drop the language from the init step.`,
			);
			continue;
		}

		ok.push(
			`${surface.language}: the \`${jobs[0]}\` job enumerates all ${walked.length} ` +
				`${surface.label}(s) from the tree; ${scanned.length} scanned` +
				(entries.length > 0
					? `, ${entries.length} declared unbuilt (${entries.map((e) => e.path).join(', ')})`
					: ''),
		);
	}

	return { errors, ok };
}

function main() {
	const { errors, ok } = check();
	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);
	if (errors.length > 0) {
		console.error(`\n${errors.length} CodeQL build-coverage problem(s).`);
		return 1;
	}
	console.log(`\n${SURFACES.length} compiled CodeQL language(s) build every tree the repo holds.`);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());

