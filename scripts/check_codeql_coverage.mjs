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
// The third half is the INTERPRETED legs, which this guard used to say nothing
// about at all. `javascript-typescript` and `actions` run `build-mode: none`,
// so no build step can narrow them — that is true of the BUILD and it was read
// as if it were true of the SCAN. It is not: an `init` step's `config` takes
// `paths` / `paths-ignore`, and the `actions` leg already carries a
// `query-filters` block dropping one rule by id. Either narrows the analysis
// exactly as the Kotlin `working-directory` did, and nothing read either, so a
// `paths-ignore` on the JS leg would have removed apps/web from the scan with
// no more signal than a green check. A coverage guard silent about half its
// subject reports more assurance than it has, which is the same defect one
// level up from the one it was written for.
//
// So every narrowing an interpreted leg DECLARES is read here and must earn
// itself: a reason in the comment lines directly above it (a scan hole costs at
// least MIN_REASON_CHARS of prose), and a target that still names something
// real — a path glob matching nothing in this tree has outlived whatever it
// excused, and a `query-filters` id whose language prefix this leg cannot
// produce filters nothing. `queries:` is read the same way, because selecting a
// suite narrower than the broadest available is narrowing the scan by another
// route. A `config-file:` is refused outright rather than followed: narrowing
// this guard cannot see is the state it exists to prevent.
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
 * Interpreted languages are deliberately absent from THIS table, because no
 * build step decides their scope. They are not unmeasured: `INTERPRETED` below
 * reads the narrowing their init steps declare instead.
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

/**
 * The interpreted languages, whose scope is the whole checkout until something
 * in the `init` step says otherwise.
 *
 * `broadestSuite` is the widest query suite the language ships, so anything
 * else in `queries:` is a narrowing that has to say why. `idPrefixes` is what
 * makes a `query-filters` entry checkable offline: CodeQL rule ids are
 * `<language-family>/<slug>`, and a filter whose family this leg cannot emit
 * excludes nothing — it reads as a scoped-down scan while being a no-op, which
 * is the more dangerous of the two failure directions.
 *
 * @typedef {{ language: string, broadestSuite: string, idPrefixes: string[] }} Interpreted
 */
/** @type {readonly Interpreted[]} */
export const INTERPRETED = [
	{
		language: 'javascript-typescript',
		broadestSuite: 'security-and-quality',
		idPrefixes: ['js', 'ts', 'javascript'],
	},
	{ language: 'actions', broadestSuite: 'security-and-quality', idPrefixes: ['actions'] },
];

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
 * The value of a plain `key: value` line inside a block, with the index of the
 * line it was read from — the index is what makes the reason above it readable.
 *
 * @param {string} block
 * @param {string} key
 * @returns {{ value: string, index: number } | null}
 */
export function scalarEntry(block, key) {
	const lines = block.split('\n');
	for (let i = 0; i < lines.length; i++) {
		const m = new RegExp(`^\\s*${key}:[ \\t]+(\\S.*?)\\s*$`).exec(lines[i]);
		if (m && m[1] !== '|' && m[1] !== '>') return { value: m[1], index: i };
	}
	return null;
}

/// A line that opens a mapping and carries no value of its own — `paths-ignore:`
/// or `- exclude:`. The ONLY thing a reason may be read across, because an entry
/// that is the first item under its own key has that key between it and the
/// comment written for it.
const CONTAINER_KEY = /^(?:-\s+)?[A-Za-z0-9_.-]+:$/;

/**
 * The reason written directly above line `i`: the contiguous run of `#` comment
 * lines, reached across at most ONE container key.
 *
 * Nothing else may be skipped, and the rule is not conservatism — it is the
 * difference between reading a reason and inventing one. Measured on this
 * repo's own file: a version that skipped any single line let `queries:` reach
 * over `build-mode: none` and adopt the comment written about the BUILD MODE as
 * its justification, so narrowing the query suite to `security` passed the
 * guard with a 91-character reason that said nothing about queries. A guard
 * that accepts a neighbour's sentence is a guard that cannot fail.
 *
 * @param {string[]} lines
 * @param {number} i
 * @returns {string}
 */
export function reasonAbove(lines, i) {
	/** @type {string[]} */
	const parts = [];
	let skipped = 0;
	for (let j = i - 1; j >= 0; j--) {
		const t = lines[j].trim();
		if (t.startsWith('#')) {
			parts.unshift(t.replace(/^#+\s*/, ''));
			continue;
		}
		if (parts.length === 0 && skipped < 1 && CONTAINER_KEY.test(t)) {
			skipped++;
			continue;
		}
		break;
	}
	return parts.join(' ').trim();
}

/**
 * Every narrowing an `init` step's inline `config` declares, with the reason
 * written above it.
 *
 * `paths` narrows as hard as `paths-ignore` — naming one directory removes
 * every other — so both are read, and so is each `query-filters` entry's own
 * selector.
 *
 * @param {string} configText
 * @returns {{ kind: 'paths' | 'paths-ignore' | 'query-filter', value: string, reason: string }[]}
 */
export function parseNarrowing(configText) {
	const lines = configText.split('\n');
	/** @type {{ kind: 'paths' | 'paths-ignore' | 'query-filter', value: string, reason: string }[]} */
	const out = [];
	/** @type {'paths' | 'paths-ignore' | null} */
	let pathKey = null;
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		const t = line.trim();
		if (t === '' || t.startsWith('#')) continue;
		const key = /^(paths|paths-ignore|query-filters):\s*$/.exec(t);
		if (key) {
			pathKey = key[1] === 'query-filters' ? null : /** @type {'paths' | 'paths-ignore'} */ (key[1]);
			continue;
		}
		const item = /^-\s+(\S.*?)\s*$/.exec(t);
		if (item && pathKey) {
			out.push({ kind: pathKey, value: item[1], reason: reasonAbove(lines, i) });
			continue;
		}
		const selector = /^(?:-\s+)?(?:id|tags):\s*(\S.*?)\s*$/.exec(t);
		if (selector) {
			// The reason belongs to the `- exclude:` / `- include:` line the
			// selector sits under, not to the selector: that is where a writer
			// puts it, and reading the selector's own line finds nothing.
			const anchorLine = /^-\s/.test(t) ? i : i - 1;
			out.push({ kind: 'query-filter', value: selector[1], reason: reasonAbove(lines, anchorLine) });
			pathKey = null;
		}
	}
	return out;
}

/**
 * Every repo-relative path under `root`, files and directories both, skipping
 * the vendored and generated trees. Walked lazily — nothing calls it until a
 * `paths` entry exists to measure.
 *
 * @param {string} root
 * @returns {string[]}
 */
export function walkPaths(root) {
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
		for (const e of entries) {
			const abs = join(dir, e.name);
			found.push(relative(root, abs).split(sep).join('/'));
			if (e.isDirectory() && !SKIP_DIRS.has(e.name)) visit(abs);
		}
	};
	visit(root);
	return found;
}

/**
 * Whether a CodeQL path glob still names something. A bare directory selects
 * everything beneath it, which is why a prefix counts as a match.
 *
 * @param {string} glob
 * @param {string[]} paths
 * @returns {boolean}
 */
export function globNamesSomething(glob, paths) {
	const clean = glob.replace(/^['"]|['"]$/g, '').replace(/^\.\//, '').replace(/\/+$/, '');
	if (clean === '') return false;
	const rx = new RegExp(
		'^' +
			clean
				.split(/(\*\*\/|\*\*|\*|\?)/)
				.map((part) => {
					if (part === '**/') return '(?:.*/)?';
					if (part === '**') return '.*';
					if (part === '*') return '[^/]*';
					if (part === '?') return '[^/]';
					return part.replace(/[.+^${}()|[\]\\]/g, '\\$&');
				})
				.join('') +
			'$',
	);
	return paths.some((p) => rx.test(p) || p === clean || p.startsWith(`${clean}/`));
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

	/** @type {string[] | null} */
	let allPaths = null;

	for (const leg of INTERPRETED) {
		const jobs = jobsDeclaring(text, leg.language);
		if (jobs.length !== 1) {
			errors.push(
				`${jobs.length} job(s) in ${WORKFLOW} declare \`languages: ${leg.language}\` ` +
					`(${jobs.join(', ') || 'none'}); expected exactly one. This guard reads the scan's ` +
					`declared narrowing out of that one job's init step, and cannot tell which of ` +
					`several is the scan whose scope it is measuring.`,
			);
			continue;
		}
		const block = jobBlock(text, jobs[0]) ?? '';
		const blockLines = block.split('\n');

		const buildMode = scalarEntry(block, 'build-mode');
		if (!buildMode || buildMode.value !== 'none') {
			errors.push(
				`the \`${jobs[0]}\` job does not declare \`build-mode: none\` for ${leg.language} ` +
					`(found ${buildMode ? `\`${buildMode.value}\`` : 'nothing'}). This guard treats the ` +
					`leg's scope as the whole checkout minus what the init step narrows; the moment a ` +
					`build decides the scope instead, that premise is false and the language belongs ` +
					`in SURFACES with its build step measured against the tree.`,
			);
			continue;
		}

		const configFile = scalarEntry(block, 'config-file');
		if (configFile) {
			errors.push(
				`the \`${jobs[0]}\` job narrows ${leg.language} through \`config-file: ` +
					`${configFile.value}\`, which this guard does not follow. Narrowing it cannot read ` +
					`is the state it exists to prevent, so this is refused rather than assumed ` +
					`harmless: move the \`paths\` / \`paths-ignore\` / \`query-filters\` inline under ` +
					`\`config:\`, or teach this guard to read the file.`,
			);
			continue;
		}

		const queries = scalarEntry(block, 'queries');
		if (!queries) {
			errors.push(
				`the \`${jobs[0]}\` job names no \`queries:\` suite for ${leg.language}, so it runs ` +
					`CodeQL's default set — which is narrower than \`${leg.broadestSuite}\` and says ` +
					`so nowhere. Name the suite; a scan's query set is as much its scope as its file ` +
					`set is.`,
			);
		} else if (queries.value !== leg.broadestSuite) {
			const reason = reasonAbove(blockLines, queries.index);
			if (reason.length < MIN_REASON_CHARS) {
				errors.push(
					`the \`${jobs[0]}\` job runs \`queries: ${queries.value}\` for ${leg.language} ` +
						`rather than \`${leg.broadestSuite}\`, with a ${reason.length}-character reason ` +
						`above it. Selecting a narrower suite drops whole query families from the ` +
						`analysis and the result reads exactly as clean; it costs at least ` +
						`${MIN_REASON_CHARS} characters saying which families and why.`,
				);
			}
		}

		const configText = blockScalar(block, 'config');
		const narrowing = configText === null ? [] : parseNarrowing(configText);
		const configLines = (configText ?? '').split('\n');
		for (const entry of narrowing) {
			if (entry.reason.length < MIN_REASON_CHARS) {
				errors.push(
					`the \`${jobs[0]}\` job's \`${entry.kind}\` entry \`${entry.value}\` carries a ` +
						`${entry.reason.length}-character reason. It narrows what CodeQL reports on ` +
						`${leg.language}, and a narrowing nobody explained is indistinguishable from ` +
						`one nobody meant; it costs at least ${MIN_REASON_CHARS} characters.`,
				);
			}
			if (entry.kind === 'query-filter') {
				const family = entry.value.split('/')[0].trim();
				if (!leg.idPrefixes.includes(family)) {
					errors.push(
						`the \`${jobs[0]}\` job filters \`${entry.value}\` out of the ${leg.language} ` +
							`analysis, but \`${family}/\` is not a rule family this leg emits ` +
							`(${leg.idPrefixes.map((x) => `${x}/`).join(', ')}). It therefore excludes ` +
							`nothing at all — which reads as a deliberately scoped scan while being a ` +
							`no-op, and hides the next filter that is not.`,
					);
				}
				continue;
			}
			if (allPaths === null) allPaths = walkPaths(root);
			if (!globNamesSomething(entry.value, allPaths)) {
				errors.push(
					`the \`${jobs[0]}\` job's \`${entry.kind}\` entry \`${entry.value}\` matches no ` +
						`path in this tree. An exclusion that has outlived the directory it excused is ` +
						`cover for nothing, and an INCLUSION that names nothing is worse — it is the ` +
						`whole scan, pointed at an empty set, reporting clean.`,
				);
			}
		}

		const includes = narrowing.filter((e) => e.kind === 'paths');
		if (configText !== null && includes.length > 0 && configLines.length > 0) {
			ok.push(
				`${leg.language}: the \`${jobs[0]}\` job scans only ${includes
					.map((e) => e.value)
					.join(', ')}, each declared with a reason and still naming something`,
			);
		} else {
			ok.push(
				`${leg.language}: the \`${jobs[0]}\` job scans the whole checkout` +
					(narrowing.length > 0
						? `, less ${narrowing.length} declared narrowing(s) (${narrowing
								.map((e) => e.value)
								.join(', ')})`
						: ''),
			);
		}
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
	console.log(
		`\n${SURFACES.length} compiled CodeQL language(s) build every tree the repo holds; ` +
			`${INTERPRETED.length} interpreted leg(s) narrow nothing that is not declared and real.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());

