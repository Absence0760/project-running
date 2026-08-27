#!/usr/bin/env node
// Guardrail: a CI failure names what actually failed.
//
// Two rules, both from the same incident. `parity-types` ended in a bare
// `- if: failure()` step that printed "database.types.ts is out of sync with
// the Supabase schema" and told the reader to run `npm run gen:types`. A step
// condition of `failure()` is true for a failure ANYWHERE earlier in the job,
// so a web source-guard failure five steps above printed that message — a
// confident statement about a migration and a generated file, neither of which
// was involved, which is where the first look went.
//
//   1. No step conditioned on `failure()` may print an `::error::` annotation
//      unless its condition also names a specific step's outcome. This is the
//      shape of the bug, and it is repo-wide: an artifact upload behind
//      `if: failure()` is fine (it claims nothing), a DIAGNOSIS behind one is
//      a claim the condition cannot support.
//   2. Every check step of a BUNDLED job carries its own `::error::`. Rule 1
//      alone would be satisfied by deleting the trailing step and saying
//      nothing at all; the reason that job needs per-step diagnoses is that it
//      bundles unrelated checks — migration guards, a CHECK-vs-TS-union guard,
//      the whole web unit suite, and the type-drift check — under one job name,
//      so the job name cannot say which one broke and each step has to say it
//      for itself.
//
// Which jobs those are is DERIVED, not listed. It used to be listed, and the
// list is what failed: `parity-matrix` has bundled four unrelated registry
// guards since the day it was written, was never added, and its absence was
// filed and deferred twice before anyone reached it — while `workflow-lint`
// (five guards) and env-isolation's `unit` (two) were never noticed at all.
// A job that runs more than one of this repo's own guards is bundled by that
// fact; nothing has to remember to say so (decisions § 764). DIAGNOSING_JOBS
// survives for the bundles the derivation cannot see — `edge-functions` runs
// `deno test`, not a guard script — and a listed job that no longer exists
// still fails rather than reading nothing.
//
// Not applied to every `run:` step in the file: most jobs run one thing, and
// their name already says what it was. A single-guard job like
// `watch-ble-uuids` is exactly that case, and is deliberately untouched.
//
// Line-based rather than YAML-parsed on purpose: the `workflow-lint` job runs
// `node` against a bare checkout with no `npm ci`, so only the stdlib is
// available. Same constraint check_toolchain_pins.mjs works under.
//
// Run: `node scripts/check_ci_diagnostics.mjs`
// CI:  the `workflow-lint` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_ci_diagnostics.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const WORKFLOW_DIR = join(REPO_ROOT, '.github', 'workflows');

/// Bundled jobs the derivation below cannot see, and why the job name cannot
/// diagnose for them. Anything running two or more of this repo's own guards
/// is picked up without an entry here; these are the ones whose checks are
/// something else.
export const DIAGNOSING_JOBS = new Map([
	[
		'parity-types',
		'it bundles the migration guards, the CHECK-vs-TS-union guard, the web ' +
			'unit suite and the type-drift check under one job name',
	],
	// ^ derived as well — it runs seven guards. Listed anyway because it is the
	// incident this whole file came from, and an entry that stops matching is
	// itself reported.
	[
		'edge-functions',
		'it bundles a dependency prefetch, the `deno check` typecheck, a live ' +
			'function-host boot and two unrelated test suites under one job name',
	],
]);

export const ANNOTATION = '::error::';

/**
 * @typedef {{ name: string, text: string }} WorkflowFile
 * @typedef {{ job: string, line: number, lines: string[] }} RawStep
 * @typedef {{ job: string, line: number, name: string | null, if: string | null, hasRun: boolean, body: string }} Step
 */

/// Every step of every job in one workflow file, as `{ job, name, if, body }`.
/// `body` is the step's own lines joined — comments between steps belong to no
/// step, so a `::error::` mentioned in prose above one is not read as a
/// diagnosis it prints.
/**
 * @param {string} text
 * @returns {Step[]}
 */
export function parseSteps(text) {
	const lines = text.split('\n');
	/** @type {RawStep[]} */
	const steps = [];
	/** @type {string | null} */
	let job = null;
	/// The `steps:` list being read. Its job travels with it, so every step
	/// this loop opens has one — a step attributed to no job is unreportable.
	/** @type {{ job: string, indent: number } | null} */
	let list = null;
	/** @type {RawStep | null} */
	let current = null;

	const close = () => {
		if (current) steps.push(current);
		current = null;
	};

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		const trimmed = line.trim();
		const indent = line.length - line.trimStart().length;

		if (!trimmed) {
			if (current) current.lines.push(line);
			continue;
		}

		// A job key sits at two spaces under the file's `jobs:` mapping.
		const jobKey = line.match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
		if (jobKey) {
			close();
			job = jobKey[1];
			list = null;
			continue;
		}

		if (job && list === null) {
			if (/^ {4}steps:\s*$/.test(line)) list = { job, indent: -1 }; // awaiting the first `- `
			continue;
		}
		if (list === null) continue;

		if (list.indent === -1) {
			const first = line.match(/^(\s*)-\s/);
			if (!first) continue;
			list.indent = first[1].length;
		}

		if (indent < list.indent) {
			// Back out to the job (or workflow) level: the steps list is over.
			close();
			list = null;
			job = null;
			// Re-read this line as a possible job key.
			i--;
			continue;
		}

		if (indent === list.indent) {
			close();
			if (!/^\s*-\s/.test(line)) continue; // a comment between two steps
			current = { job: list.job, line: i + 1, lines: [line] };
			continue;
		}

		if (current) current.lines.push(line);
	}
	close();

	return steps.map((s) => {
		const body = s.lines.join('\n');
		const cond = body.match(/^\s*(?:-\s+)?if:\s*(.*?)\s*$/m);
		const name = body.match(/^\s*(?:-\s+)?name:\s*(.*?)\s*$/m);
		return {
			job: s.job,
			line: s.line,
			name: name ? name[1] : null,
			if: cond ? cond[1] : null,
			hasRun: /^\s*(?:-\s+)?run:/m.test(body),
			body,
		};
	});
}

/// Rule 1 — a diagnosis behind an unscoped `failure()` speaks for every step
/// above it. `steps.<id>.` in the condition is what scopes it to one.
/**
 * @param {readonly WorkflowFile[]} files
 * @returns {{ errors: string[], ok: string[], conditioned: number }}
 */
export function checkFailureScoping(files) {
	const errors = [];
	const ok = [];
	let conditioned = 0;

	for (const { name, text } of files) {
		for (const step of parseSteps(text)) {
			if (!step.if || !step.if.includes('failure()')) continue;
			conditioned++;
			if (!step.body.includes(ANNOTATION)) continue;
			const where = `${name}:${step.line}`;
			if (step.if.includes('steps.')) {
				ok.push(`${where} -> diagnosis scoped to ${step.if}`);
				continue;
			}
			errors.push(
				`${where} — this step prints an \`${ANNOTATION}\` diagnosis under ` +
					`\`if: ${step.if}\`, which is true for a failure anywhere earlier in ` +
					`the job, so the message is asserted over failures it knows nothing ` +
					`about. Either move the diagnosis into the step it describes (the ` +
					`\`if ! cmd; then echo "${ANNOTATION}…"; exit 1; fi\` form used ` +
					`throughout ci.yml), or scope the condition with ` +
					`\`steps.<id>.outcome == 'failure'\`.`,
			);
		}
	}

	if (conditioned === 0) {
		errors.push(
			`no \`failure()\`-conditioned steps found in any workflow. Either every ` +
				`on-failure step was removed, or the condition was reworded and this ` +
				`check now enforces nothing.`,
		);
	}

	return { errors, ok, conditioned };
}

/// What makes a `run:` step a CHECK rather than setup: it invokes one of this
/// repo's own guards. `npm ci`, `flutter precache` and `cargo build` fail over
/// the environment or the code as a whole; a guard's failure is a verdict about
/// one named file, and "which file" is exactly what a bundled job's name cannot
/// say.
export const GUARD_INVOCATION = /check_[a-z0-9_]+|--test\b|:check\b|\.test\.mjs/;

/// A step's `run:` block alone. Matching against the whole step would let a
/// step NAMED "check_production_env tests" count as a guard invocation on the
/// strength of its label rather than its command.
/** @param {Step} step */
export function runBody(step) {
	const at = step.body.search(/^\s*(?:-\s+)?run:/m);
	return at === -1 ? '' : step.body.slice(at);
}

/** @param {Step} step */
export function isGuardStep(step) {
	return step.hasRun && GUARD_INVOCATION.test(runBody(step));
}

/// A job bundles when it runs more than one guard, so its name names a
/// category rather than a check. Two is the threshold because one guard IS the
/// job — `watch-ble-uuids` red says precisely what drifted.
export const BUNDLE_THRESHOLD = 2;

/// Every bundled job, derived. Keyed by job name; the value is the guard count
/// that made it one, so the error message can quote a fact rather than a
/// sentence someone has to keep true.
/**
 * @param {readonly WorkflowFile[]} files
 * @returns {Map<string, number>}
 */
export function derivedBundles(files) {
	/** @type {Map<string, number>} */
	const guards = new Map();
	for (const { text } of files) {
		for (const step of parseSteps(text)) {
			if (isGuardStep(step)) guards.set(step.job, (guards.get(step.job) ?? 0) + 1);
		}
	}
	for (const [job, count] of guards) if (count < BUNDLE_THRESHOLD) guards.delete(job);
	return guards;
}

/// Rule 2 — in a job whose name cannot say which check broke, every check
/// says it for itself.
///
/// The steps asked are the named `run:` steps plus any guard step, named or
/// not: `parity-matrix`'s Dart matrix check was unnamed, which under a
/// names-only rule would have made "delete the name" a way to escape the
/// requirement. Unnamed setup — `npm ci`, `go install`, a `cp` — runs nothing
/// this rule can ask to diagnose itself and is left alone.
/**
 * @param {readonly WorkflowFile[]} files
 * @returns {{ errors: string[], ok: string[], bundles: Map<string, number> }}
 */
export function checkStepDiagnoses(files) {
	const errors = [];
	const ok = [];
	const derived = derivedBundles(files);
	/** @type {Map<string, number>} */
	const seen = new Map();

	for (const { name, text } of files) {
		for (const step of parseSteps(text)) {
			const listed = DIAGNOSING_JOBS.has(step.job);
			if (!listed && !derived.has(step.job)) continue;
			if (!step.hasRun) continue;
			if (listed && step.name) seen.set(step.job, (seen.get(step.job) ?? 0) + 1);
			if (!step.name && !isGuardStep(step)) continue;
			const where = `${name}:${step.line}`;
			const label = step.name ?? runBody(step).split('\n')[0].replace(/^\s*(?:-\s+)?run:\s*/, '');
			if (step.body.includes(ANNOTATION)) {
				ok.push(`${where} -> "${label}" diagnoses itself`);
				continue;
			}
			const why = listed
				? DIAGNOSING_JOBS.get(step.job)
				: `it runs ${derived.get(step.job)} of this repo's guards under one job name`;
			errors.push(
				`${where} — step "${label}" in job \`${step.job}\` prints no ` +
					`\`${ANNOTATION}\` of its own. That job needs one per step because ` +
					`${why}, so a reader who sees it red learns ` +
					`nothing from the job name. Wrap the command as ` +
					`\`if ! cmd; then echo "${ANNOTATION}<what broke>"; echo "<how to fix ` +
					`it>"; exit 1; fi\`.`,
			);
		}
	}

	for (const [job, why] of DIAGNOSING_JOBS) {
		const count = seen.get(job) ?? 0;
		if (count >= 2) continue;
		errors.push(
			`job \`${job}\` was expected to hold several named \`run:\` steps (${why}) ` +
				`but ${count} were found. Either it was renamed or restructured — update ` +
				`DIAGNOSING_JOBS, or drop the entry rather than leaving it reading nothing.`,
		);
	}

	if (derived.size === 0) {
		errors.push(
			`no job was derived as bundled from any workflow. Either every job now runs ` +
				`at most one guard, or the guard invocations were reworded past ` +
				`GUARD_INVOCATION and this rule now enforces nothing beyond the ` +
				`${DIAGNOSING_JOBS.size} listed job(s).`,
		);
	}

	return { errors, ok, bundles: derived };
}

/** @param {readonly WorkflowFile[]} files */
export function checkAll(files) {
	const scoping = checkFailureScoping(files);
	const diagnoses = checkStepDiagnoses(files);
	return {
		errors: [...scoping.errors, ...diagnoses.errors],
		ok: [...scoping.ok, ...diagnoses.ok],
		scoping,
		diagnoses,
	};
}

/**
 * @param {string} dir
 * @returns {WorkflowFile[]}
 */
export function readWorkflows(dir) {
	return readdirSync(dir)
		.filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
		.sort()
		.map((name) => ({ name, text: readFileSync(join(dir, name), 'utf-8') }));
}

function main() {
	const files = readWorkflows(WORKFLOW_DIR);
	const { errors, ok, diagnoses } = checkAll(files);

	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);

	if (files.length < 5) {
		console.error(`[FAIL] only ${files.length} workflow file(s) read from ${WORKFLOW_DIR}`);
		return 1;
	}
	if (errors.length > 0) {
		console.error(`\n${errors.length} misattributable CI diagnosis(es).`);
		return 1;
	}
	console.log(
		`\nNo \`failure()\`-conditioned diagnosis speaks for a step it cannot see; ` +
			`${diagnoses.ok.length} step(s) across ${diagnoses.bundles.size} derived + ` +
			`${DIAGNOSING_JOBS.size} listed bundled job(s) diagnose themselves.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
