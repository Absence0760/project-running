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
//   2. Every named `run:` step in the jobs listed in DIAGNOSING_JOBS carries
//      its own `::error::`. Rule 1 alone would be satisfied by deleting the
//      trailing step and saying nothing at all; the reason that job needs
//      per-step diagnoses is that it bundles unrelated checks — migration
//      guards, a CHECK-vs-TS-union guard, the whole web unit suite, and the
//      type-drift check — under one job name, so the job name cannot say
//      which one broke and each step has to say it for itself.
//
// Scoped to those jobs rather than applied to every `run:` step in the file:
// most jobs run one thing, and their name already says what it was.
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

/// Jobs whose steps must each diagnose themselves, and why the job name
/// cannot do it for them.
export const DIAGNOSING_JOBS = new Map([
	[
		'parity-types',
		'it bundles the migration guards, the CHECK-vs-TS-union guard, the web ' +
			'unit suite and the type-drift check under one job name',
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

/// Rule 2 — in a job whose name cannot say which check broke, every check
/// says it for itself.
/**
 * @param {readonly WorkflowFile[]} files
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkStepDiagnoses(files) {
	const errors = [];
	const ok = [];
	/** @type {Map<string, number>} */
	const seen = new Map();

	for (const { name, text } of files) {
		for (const step of parseSteps(text)) {
			if (!DIAGNOSING_JOBS.has(step.job)) continue;
			if (!step.hasRun || !step.name) continue;
			seen.set(step.job, (seen.get(step.job) ?? 0) + 1);
			const where = `${name}:${step.line}`;
			if (step.body.includes(ANNOTATION)) {
				ok.push(`${where} -> "${step.name}" diagnoses itself`);
				continue;
			}
			errors.push(
				`${where} — step "${step.name}" in job \`${step.job}\` prints no ` +
					`\`${ANNOTATION}\` of its own. That job needs one per step because ` +
					`${DIAGNOSING_JOBS.get(step.job)}, so a reader who sees it red learns ` +
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

	return { errors, ok };
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
			`${diagnoses.ok.length} step(s) across ${DIAGNOSING_JOBS.size} bundled job(s) ` +
			`diagnose themselves.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
