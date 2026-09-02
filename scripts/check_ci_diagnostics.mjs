#!/usr/bin/env node
// Guardrail: a CI failure is seen, and names what actually failed.
//
// Rules 1 and 2 come from one incident; rule 3 is the floor underneath them —
// a diagnosis nobody is shown is worth no more than a misattributed one. `parity-types` ended in a bare
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
// That last job is now ci.yml's `env-isolation` — the workflow it lived in was
// folded in and deleted (decisions § 862), which is also why rule 3 below can
// reach it.
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
//   3. Every job in ci.yml is named in the `CI gate` aggregator's `needs:`
//      list. That aggregator is the single required status check, and it
//      passes when every job it needs passed OR was skipped — so a job absent
//      from the list is a check whose RED does not block a merge and shows up
//      only as one more green-looking row among thirty. Nothing enforced this:
//      the list was complete by hand, and a job is added to this file far more
//      often than anyone re-reads the bottom of it. A `needs:` entry naming no
//      job fails too, because a deleted job leaves a name the aggregator will
//      never hear from.
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
		'it bundles a dependency prefetch, the `deno check` typecheck, the suite ' +
			'vacuity guard, a live function-host boot and two unrelated test suites ' +
			'under one job name',
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
 * @returns {{ errors: string[], ok: string[], exempt: string[], bundles: Map<string, number> }}
 */
export function checkStepDiagnoses(files) {
	const errors = [];
	const ok = [];
	/// The unnamed non-guard `run:` steps inside a bundled job — the rule's
	/// blind spot, named rather than only described. Reporting it costs nothing
	/// and is the whole of what a widening would have to justify: measured over
	/// the committed workflows it is TWO steps, `npm ci` and a `go install`,
	/// which is exactly the setup § 764 declined to demand a diagnosis from.
	/// Widening the SUBJECT to "an unnamed step naming a repo-local path" would
	/// newly catch none of them; widening `isGuardStep` instead — the obvious
	/// implementation, since it is also what decides bundling — takes the
	/// bundled set from 6 jobs to 15 and the subject from 31 steps to 127, 89
	/// of which print no `::error::` today (decisions § 770).
	const exempt = [];
	const derived = derivedBundles(files);
	/** @type {Map<string, number>} */
	const seen = new Map();

	for (const { name, text } of files) {
		for (const step of parseSteps(text)) {
			const listed = DIAGNOSING_JOBS.has(step.job);
			if (!listed && !derived.has(step.job)) continue;
			if (!step.hasRun) continue;
			if (listed && step.name) seen.set(step.job, (seen.get(step.job) ?? 0) + 1);
			if (!step.name && !isGuardStep(step)) {
				exempt.push(
					`${name}:${step.line} — job \`${step.job}\` runs \`${runBody(step)
						.split('\n')[0]
						.replace(/^\s*(?:-\s+)?run:\s*/, '')
						.trim()
						.slice(0, 60)}\` unnamed, so rule 2 does not ask it to diagnose itself`,
				);
				continue;
			}
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

	return { errors, ok, exempt, bundles: derived };
}

/// The aggregator every branch-protection rule points at.
export const GATE_JOB = 'ci-gate';

/// Every job key in a workflow, in file order. A job key sits at two spaces
/// under the file's TOP-LEVEL `jobs:` mapping — the qualifier matters, because
/// `on:` holds two-space keys of its own and a workflow triggered by
/// `push`/`pull_request` would otherwise report two jobs the gate must wait
/// for that do not exist.
/**
 * @param {string} text
 * @returns {string[]}
 */
export function parseJobKeys(text) {
	/** @type {string[]} */
	const jobs = [];
	let inJobs = false;
	for (const line of text.split('\n')) {
		const top = line.match(/^([A-Za-z0-9_-]+):/);
		if (top) {
			inJobs = top[1] === 'jobs';
			continue;
		}
		if (!inJobs) continue;
		const key = line.match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
		if (key) jobs.push(key[1]);
	}
	return jobs;
}

/// One job's `needs:`, in every spelling GitHub accepts: a bare scalar, a flow
/// sequence, or a block list. `null` when the job declares none at all, which
/// is a different thing from declaring an empty one.
/**
 * @param {string} text
 * @param {string} job
 * @returns {string[] | null}
 */
export function parseNeeds(text, job) {
	const lines = text.split('\n');
	/** @type {string | null} */
	let current = null;
	let inJobs = false;
	for (let i = 0; i < lines.length; i++) {
		const top = lines[i].match(/^([A-Za-z0-9_-]+):/);
		if (top) {
			inJobs = top[1] === 'jobs';
			current = null;
			continue;
		}
		if (!inJobs) continue;
		const key = lines[i].match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
		if (key) {
			current = key[1];
			continue;
		}
		if (current !== job) continue;
		const needs = lines[i].match(/^ {4}needs:\s*(.*)$/);
		if (!needs) continue;
		const inline = needs[1].trim();
		if (inline.startsWith('[')) {
			return inline
				.replace(/^\[|\]$/g, '')
				.split(',')
				.map((n) => n.trim())
				.filter(Boolean);
		}
		if (inline !== '') return [inline];
		/** @type {string[]} */
		const listed = [];
		for (let j = i + 1; j < lines.length; j++) {
			const item = lines[j].match(/^ {6}-\s*(\S+)\s*$/);
			if (item) {
				listed.push(item[1]);
				continue;
			}
			if (lines[j].trim() === '' || lines[j].startsWith('      #')) continue;
			break;
		}
		return listed;
	}
	return null;
}

/// Rule 3 — the required check answers for every job in the file.
/**
 * @param {readonly WorkflowFile[]} files
 * @returns {{ errors: string[], ok: string[], covered: number }}
 */
export function checkGateCoverage(files) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	let covered = 0;

	const hosts = files.filter(({ text }) => parseJobKeys(text).includes(GATE_JOB));
	if (hosts.length === 0) {
		errors.push(
			`no workflow defines a \`${GATE_JOB}\` job. Either the required status check ` +
				`was renamed — update GATE_JOB — or it is gone, and nothing now aggregates ` +
				`the jobs a merge depends on.`,
		);
		return { errors, ok, covered };
	}

	for (const { name, text } of hosts) {
		const jobs = parseJobKeys(text);
		const needs = parseNeeds(text, GATE_JOB);
		if (needs === null || needs.length === 0) {
			errors.push(
				`${name} — \`${GATE_JOB}\` declares no \`needs:\`, so it passes without ` +
					`waiting for anything and the required check is green whatever the rest ` +
					`of the file does.`,
			);
			continue;
		}
		const listed = new Set(needs);
		for (const job of jobs) {
			if (job === GATE_JOB) continue;
			if (listed.has(job)) {
				covered++;
				continue;
			}
			errors.push(
				`${name} — job \`${job}\` is in no \`needs:\` entry of \`${GATE_JOB}\`, so its ` +
					`failure does not block a merge: the aggregator never waits for it and the ` +
					`PR shows one more row nobody is gated on. Add \`- ${job}\` to that list.`,
			);
		}
		const defined = new Set(jobs);
		for (const need of listed) {
			if (defined.has(need)) continue;
			errors.push(
				`${name} — \`${GATE_JOB}\` needs \`${need}\`, which is not a job in this file. ` +
					`A name the aggregator will never hear from is a dependency it cannot ` +
					`report on; drop it or fix the spelling.`,
			);
		}
		ok.push(`${name} -> ${GATE_JOB} needs all ${covered} other job(s) in the file`);
	}

	return { errors, ok, covered };
}

/** @param {readonly WorkflowFile[]} files */
export function checkAll(files) {
	const scoping = checkFailureScoping(files);
	const diagnoses = checkStepDiagnoses(files);
	const gate = checkGateCoverage(files);
	return {
		errors: [...scoping.errors, ...diagnoses.errors, ...gate.errors],
		ok: [...scoping.ok, ...diagnoses.ok, ...gate.ok],
		scoping,
		diagnoses,
		gate,
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
	const { errors, ok, diagnoses, gate } = checkAll(files);

	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of diagnoses.exempt) console.log(`[SKIP] ${line}`);
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
			`${DIAGNOSING_JOBS.size} listed bundled job(s) diagnose themselves, with ` +
			`${diagnoses.exempt.length} unnamed non-guard step(s) outside the rule; ` +
			`\`${GATE_JOB}\` waits for all ${gate.covered} of them.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
