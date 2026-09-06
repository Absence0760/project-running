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
//   4. That aggregator's own verdict is derived from the jobs it waits for.
//      Rule 3 is only half of what makes a merge blocked and the other half
//      lived in a shell block nothing read: drop the job's `if: always()` and
//      GitHub skips the gate on exactly the runs where something failed (a
//      skipped required check holds nothing); stop reading the `needs` context
//      and the gate passes over a red job; read every result and never exit
//      non-zero and the failure is printed as text on a green check. All three
//      leave rule 3 satisfied, so all three were reachable (decisions § 909).
//
//   5. No message a step prints hands part of itself to the shell to run. A
//      backtick inside a double-quoted word is command substitution, and this
//      repo's prose quotes identifiers in backticks everywhere, so the two
//      habits meet inside an `::error::` string and bash deletes exactly the
//      identifier the sentence exists to name. Measured on the committed
//      workflows: `parity-matrix` told the reader a cell held "a symbol outside
//      , a  with no Notes" and printed two "command not found" lines beside it.
//      Rules 1-4 all passed on it — the annotation fired, from the right step,
//      in a job the gate waits for. They are about whether a diagnosis is
//      ATTRIBUTED correctly; this one is about whether it is DELIVERED.
//
// THE SUBJECT IS PER RULE, and stated in the output. For this file's whole
// life every rule read `.github/workflows` and nothing else, so the two
// composite actions under `.github/actions` were outside all of them at once
// — `check_workflow_binaries.mjs` and `check_toolchain_pins.mjs` both read that
// directory, and this one silently did not. Rules 1 and 5 read a step's `if:`
// and its shell, which an action step has, so they read both directories; rules
// 2, 3 and 4 are about JOBS — bundling, the gate's `needs:`, the gate's own
// verdict — and an action has none, so widening them would have been a claim
// about nothing. `RULE_SUBJECTS` records which is which with the reason, and
// the guard prints the split rather than leaving a reader to infer it. An empty
// action list is a FAILURE, not a quiet skip, because "covered workflows only"
// is precisely the state that went unnoticed (decisions § 1215).
//
// Line-based rather than YAML-parsed on purpose: the `workflow-lint` job runs
// `node` against a bare checkout with no `npm ci`, so only the stdlib is
// available. Same constraint check_toolchain_pins.mjs works under.
//
// Reads: `.github/workflows/*.yml` (every rule) + `.github/actions/*/action.yml`
//        (rules 1 and 5 — see RULE_SUBJECTS).
//
// Run: `node scripts/check_ci_diagnostics.mjs`
// CI:  the `workflow-lint` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_ci_diagnostics.test.mjs`

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const WORKFLOW_DIR = join(REPO_ROOT, '.github', 'workflows');
export const ACTION_DIR = join(REPO_ROOT, '.github', 'actions');
export const ORIENTATION_DOC = join(REPO_ROOT, 'CLAUDE.md');

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

/// One `steps:` list, from the line after the `steps:` key. Shared by the
/// workflow reader and the composite-action reader so the two cannot answer
/// differently about the same YAML shape — `runs.steps` in an action is the
/// same list `jobs.<id>.steps` is, at a different indent under a different key.
///
/// Stops at the first non-blank line indented less than the list's own `- `,
/// and reports where, so the caller can re-read that line as whatever it is.
/**
 * @param {readonly string[]} lines
 * @param {number} from index of the first line AFTER the `steps:` key
 * @param {string} owner the job name, or the composite action's directory
 * @returns {{ steps: RawStep[], next: number }}
 */
function collectStepList(lines, from, owner) {
	/** @type {RawStep[]} */
	const steps = [];
	/** @type {RawStep | null} */
	let current = null;
	let listIndent = -1;
	let i = from;

	const close = () => {
		if (current) steps.push(current);
		current = null;
	};

	for (; i < lines.length; i++) {
		const line = lines[i];
		if (!line.trim()) {
			if (current) current.lines.push(line);
			continue;
		}
		const indent = line.length - line.trimStart().length;

		if (listIndent === -1) {
			const first = line.match(/^(\s*)-\s/);
			if (!first) continue; // awaiting the first `- `
			listIndent = first[1].length;
		}
		if (indent < listIndent) break;
		if (indent === listIndent) {
			close();
			if (!/^\s*-\s/.test(line)) continue; // a comment between two steps
			current = { job: owner, line: i + 1, lines: [line] };
			continue;
		}
		if (current) current.lines.push(line);
	}

	close();
	return { steps, next: i };
}

/** @param {RawStep} s @returns {Step} */
function toStep(s) {
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
}

/// Every step of every job in one workflow, as `{ job, name, if, body }`.
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

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		if (!line.trim()) continue;

		// A job key sits at two spaces under the file's `jobs:` mapping.
		const jobKey = line.match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
		if (jobKey) {
			job = jobKey[1];
			continue;
		}
		if (job === null || !/^ {4}steps:\s*$/.test(line)) continue;

		const found = collectStepList(lines, i + 1, job);
		steps.push(...found.steps);
		// The line the list stopped at is unread — it is usually the next job
		// key, so hand it back to this loop rather than consuming it here.
		i = found.next - 1;
		job = null;
	}

	return steps.map(toStep);
}

/// Every step of a COMPOSITE ACTION's `runs.steps`, in `parseSteps`' shape.
///
/// An action has no jobs, so `job` carries the action's own directory name
/// instead — enough for a message to name the subject, and deliberately not a
/// job, because the rules that are ABOUT jobs must not be handed one of these.
/**
 * @param {string} text
 * @param {string} owner the action's directory name
 * @returns {Step[]}
 */
export function parseActionSteps(text, owner) {
	const lines = text.split('\n');
	let inRuns = false;
	for (let i = 0; i < lines.length; i++) {
		if (/^runs:\s*$/.test(lines[i])) {
			inRuns = true;
			continue;
		}
		if (/^\S/.test(lines[i])) inRuns = false;
		if (!inRuns || !/^ {2}steps:\s*$/.test(lines[i])) continue;
		return collectStepList(lines, i + 1, owner).steps.map(toStep);
	}
	return [];
}

/// Which rules have a subject inside a composite action, and which do not.
///
/// Stated as data rather than left implicit, because "this guard reads
/// `.github/workflows` and not `.github/actions`" was true of every rule at
/// once for the file's whole life and nothing said so — the omission was
/// invisible in exactly the way rule 5's own defect was. Two rules read a
/// step's shell and its condition, which an action step has; three are about
/// jobs, which an action does not have at all.
export const RULE_SUBJECTS = [
	{
		rule: 1,
		what: 'a `failure()`-conditioned diagnosis is scoped to a step',
		actions: true,
		why: "an action's step takes an `if:` and prints `::error::` like any other, and `failure()` there is true for a failure anywhere earlier in the CALLING job",
	},
	{
		rule: 2,
		what: "every check step of a bundled job carries its own `::error::`",
		actions: false,
		why: 'bundling is a property of a JOB name that cannot say which check broke, and an action has no jobs',
	},
	{
		rule: 3,
		what: "every job is named in the gate's `needs:`",
		actions: false,
		why: "nothing inside an action can be named in a `needs:` list",
	},
	{
		rule: 4,
		what: "the gate derives its verdict from the jobs it waits for",
		actions: false,
		why: 'it is one job in one workflow',
	},
	{
		rule: 5,
		what: 'a message reaches the reader whole',
		actions: true,
		why: "the shell runs an action's `run:` block exactly as it runs a job's, and an action step's text is further from the job that reports it than any other",
	},
];

/// The workflows and the composite actions as one list of step lists, so the
/// two rules that apply to both read them the same way.
/**
 * @param {readonly WorkflowFile[]} files
 * @param {readonly WorkflowFile[]} actions
 * @returns {{ name: string, kind: 'workflow' | 'action', steps: Step[] }[]}
 */
export function stepSources(files, actions) {
	return [
		...files.map((f) => ({
			name: f.name,
			kind: /** @type {'workflow'} */ ('workflow'),
			steps: parseSteps(f.text),
		})),
		...actions.map((a) => ({
			name: a.name,
			kind: /** @type {'action'} */ ('action'),
			steps: parseActionSteps(a.text, a.name.split('/')[0]),
		})),
	];
}

/// Rule 1 — a diagnosis behind an unscoped `failure()` speaks for every step
/// above it. `steps.<id>.` in the condition is what scopes it to one.
/**
 * @param {readonly WorkflowFile[]} files
 * @param {readonly WorkflowFile[]} [actions]
 * @returns {{ errors: string[], ok: string[], conditioned: number }}
 */
export function checkFailureScoping(files, actions = []) {
	const errors = [];
	const ok = [];
	let conditioned = 0;

	for (const { name, steps } of stepSources(files, actions)) {
		for (const step of steps) {
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
			`no \`failure()\`-conditioned steps found in any workflow or composite ` +
				`action. Either every on-failure step was removed, or the condition was ` +
				`reworded and this check now enforces nothing.`,
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

/// One job's whole block, from its key to the next job key (or the end of the
/// `jobs:` mapping). Job-level keys — `if:`, `needs:`, `runs-on:` — sit at four
/// spaces inside it, which is what separates them from a step's own.
/**
 * @param {string} text
 * @param {string} job
 * @returns {string | null}
 */
export function parseJobBlock(text, job) {
	const lines = text.split('\n');
	let inJobs = false;
	let start = -1;
	for (let i = 0; i < lines.length; i++) {
		const top = lines[i].match(/^([A-Za-z0-9_-]+):/);
		if (top) {
			if (start !== -1) return lines.slice(start, i).join('\n');
			inJobs = top[1] === 'jobs';
			continue;
		}
		if (!inJobs) continue;
		const key = lines[i].match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
		if (!key) continue;
		if (start !== -1) return lines.slice(start, i).join('\n');
		if (key[1] === job) start = i;
	}
	return start === -1 ? null : lines.slice(start).join('\n');
}

/// A job's own `if:`, read from the block ABOVE its `steps:` so a step's
/// condition is never mistaken for the job's.
/**
 * @param {string} text
 * @param {string} job
 * @returns {string | null}
 */
export function parseJobIf(text, job) {
	const block = parseJobBlock(text, job);
	if (block === null) return null;
	const lines = block.split('\n');
	const at = lines.findIndex((l) => /^ {4}steps:\s*$/.test(l));
	for (const line of at === -1 ? lines : lines.slice(0, at)) {
		const m = line.match(/^ {4}if:\s*(.*?)\s*$/);
		if (m) return m[1];
	}
	return null;
}

/// `always()` — without it GitHub SKIPS a job whose `needs:` did not all
/// succeed, and a skipped required check does not hold a merge.
export const ALWAYS_CONDITION = /\balways\s*\(\s*\)/;
/// `toJSON(needs)` — one read that covers every needed job at once.
export const WHOLE_NEEDS_READ = /toJSON\s*\(\s*needs\s*\)/;
/// `needs.<job>.result` / `.outcome` — a read that covers exactly one.
export const PER_JOB_NEEDS_READ = /needs\.([A-Za-z0-9_-]+)\.(?:result|outcome)\b/g;
/// A non-zero exit. A gate that reads every result and then exits 0 whatever
/// they say reports the same green as one that read nothing.
export const FAILING_EXIT = /\bexit\s+[1-9]/;

/// Rule 4 — the aggregator's own verdict is derived from the jobs it waits for.
///
/// Rule 3 asserts the gate NEEDS every job; that is only half of what makes a
/// merge blocked, and the other half lives in a shell block nothing read. All
/// three ways it breaks leave rule 3 green: drop `if: always()` and the gate is
/// skipped on exactly the runs where a job failed; stop reading `needs` and it
/// passes over a red one; read every result and never exit non-zero and it
/// prints the failure as text on a green check.
/**
 * @param {readonly WorkflowFile[]} files
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkGateVerdict(files) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];

	for (const { name, text } of files) {
		if (!parseJobKeys(text).includes(GATE_JOB)) continue;

		const cond = parseJobIf(text, GATE_JOB);
		if (cond === null || !ALWAYS_CONDITION.test(cond)) {
			errors.push(
				`${name} — \`${GATE_JOB}\` carries ${cond === null ? 'no job-level `if:`' : `\`if: ${cond}\``}, ` +
					`so GitHub skips it on any run where a needed job did not succeed — which is ` +
					`every run it exists to block. A skipped required check does not hold a merge. ` +
					`Restore \`if: always()\`.`,
			);
		}

		const steps = parseSteps(text).filter((s) => s.job === GATE_JOB && s.hasRun);
		if (steps.length === 0) {
			errors.push(
				`${name} — \`${GATE_JOB}\` runs no command at all, so it reports success as ` +
					`soon as its runner starts, whatever the jobs it needs did.`,
			);
			continue;
		}
		/// The whole step, not just its `run:`. A workflow that injects the
		/// context through the step's `env:` — `NEEDS_JSON: ${{ toJSON(needs) }}`,
		/// which is how you read it without interpolating into the shell — reads
		/// `needs` above the `run:` line, not inside it.
		const body = steps.map((s) => s.body).join('\n');
		const commands = steps.map((s) => runBody(s)).join('\n');

		const needs = parseNeeds(text, GATE_JOB) ?? [];
		if (WHOLE_NEEDS_READ.test(body)) {
			ok.push(`${name} -> ${GATE_JOB} reads the whole \`needs\` context`);
		} else {
			const named = new Set([...body.matchAll(PER_JOB_NEEDS_READ)].map((m) => m[1]));
			const unread = needs.filter((job) => !named.has(job));
			if (named.size === 0) {
				errors.push(
					`${name} — \`${GATE_JOB}\` never reads the \`needs\` context, so its exit ` +
						`status cannot depend on whether the ${needs.length} job(s) it waits for ` +
						`passed. It is then a green row that means nothing, and rule 3 above — which ` +
						`only asserts the \`needs:\` list is complete — stays satisfied. Read every ` +
						`result (\`toJSON(needs)\`) and fail on any that is neither success nor skipped.`,
				);
			} else if (unread.length > 0) {
				errors.push(
					`${name} — \`${GATE_JOB}\` waits for ${needs.length} job(s) but its verdict reads ` +
						`only ${named.size} of them; ${unread.join(', ')} could fail with the gate still ` +
						`green. Read the whole context with \`toJSON(needs)\` rather than naming jobs one ` +
						`by one, or the next job added is silently unjudged.`,
				);
			} else {
				ok.push(`${name} -> ${GATE_JOB} reads all ${needs.length} needed result(s) by name`);
			}
		}

		if (!FAILING_EXIT.test(commands)) {
			errors.push(
				`${name} — \`${GATE_JOB}\` has no non-zero \`exit\` on any path, so a failed ` +
					`upstream job is at most printed. A required check that reports the failure ` +
					`as text on a green run blocks nothing.`,
			);
		} else {
			ok.push(`${name} -> ${GATE_JOB} exits non-zero on a bad result`);
		}
	}

	return { errors, ok };
}

/// Whether a line hands a backtick to the shell as command substitution: one
/// that is unescaped and inside a double-quoted word. Single quotes make a
/// backtick literal, which is how a Markdown fence is echoed.
/**
 * @param {string} line
 * @returns {boolean}
 */
export function hasShellSubstitutionBacktick(line) {
	let single = false;
	let double = false;
	for (let i = 0; i < line.length; i++) {
		const c = line[i];
		if (c === '\\' && !single) {
			i++;
			continue;
		}
		if (c === "'" && !double) single = !single;
		else if (c === '"' && !single) double = !double;
		else if (c === '`' && double) return true;
	}
	return false;
}

/// Rule 5 — a diagnosis reaches the reader whole.
///
/// A backtick inside a double-quoted shell word is command substitution, so a
/// message that quotes an identifier the way this repo's prose everywhere else
/// does hands that identifier to bash to RUN. Measured on the committed
/// workflows: `parity-matrix`'s malformed-table annotation named the legal
/// symbol set and the `Partial` keyword in backticks, so bash printed two
/// "command not found" lines to stderr and substituted the empty result — the
/// reader was shown "a symbol outside , a  with no Notes", with both of the
/// things the sentence exists to name deleted out of it. The `::error::` still
/// fires and the step still exits 1, which is exactly why four rules about
/// whether a diagnosis is ATTRIBUTED correctly never noticed that this one was
/// not DELIVERED.
///
/// Comment lines are skipped: a backtick in one reaches no shell.
/**
 * @param {readonly WorkflowFile[]} files
 * @param {readonly WorkflowFile[]} [actions]
 * @returns {{ errors: string[], ok: string[], scanned: number }}
 */
export function checkShellSafeDiagnoses(files, actions = []) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	let scanned = 0;

	for (const { name, kind, steps } of stepSources(files, actions)) {
		for (const step of steps) {
			if (!step.hasRun) continue;
			const lines = step.body.split('\n');
			for (let i = 0; i < lines.length; i++) {
				const line = lines[i];
				if (line.trim().startsWith('#')) continue;
				scanned++;
				if (!hasShellSubstitutionBacktick(line)) continue;
				errors.push(
					`${name}:${step.line + i} — ${kind === 'action' ? 'composite action' : 'job'} ` +
						`\`${step.job}\` prints a message carrying a ` +
						'backtick inside double quotes, so the shell runs what it quotes and splices the ' +
						'empty result in: the reader is shown the sentence with exactly the identifier it ' +
						'was naming cut out of it. Escape it (\\`) or single-quote the message.',
				);
			}
		}
	}

	if (scanned === 0) {
		errors.push(
			'no shell line was read out of any `run:` block in any workflow or composite ' +
				'action, so this rule passed over nothing.',
		);
	} else if (errors.length === 0) {
		ok.push(`${scanned} shell line(s) print what they say, with no backtick for bash to run`);
	}

	return { errors, ok, scanned };
}

/// What each rule was applied to, said out loud, plus the vacuity guard on the
/// subject itself: a rule that reads an empty file list enforces nothing, and
/// the composite-action list is the one that was empty for this file's whole
/// life without anything noticing.
/**
 * @param {readonly WorkflowFile[]} files
 * @param {readonly WorkflowFile[]} actions
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkRuleSubjects(files, actions) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];

	if (files.length === 0) {
		errors.push(`no workflow file was read from ${WORKFLOW_DIR} — every rule below read nothing.`);
	}
	if (actions.length === 0) {
		errors.push(
			`no composite action was read from ${ACTION_DIR}, so rules ` +
				`${RULE_SUBJECTS.filter((r) => r.actions)
					.map((r) => r.rule)
					.join(' + ')} covered workflows only. That is the state this whole subject ` +
				'split exists to make visible, so it is a failure rather than a quiet skip.',
		);
	}

	const applied = RULE_SUBJECTS.filter((r) => r.actions).map((r) => r.rule);
	const jobsOnly = RULE_SUBJECTS.filter((r) => !r.actions).map((r) => r.rule);
	ok.push(
		`rule(s) ${applied.join(' + ')} read ${files.length} workflow(s) AND ${actions.length} ` +
			`composite action(s); rule(s) ${jobsOnly.join(' + ')} read workflows only, having no ` +
			'subject in an action (it has no jobs)',
	);
	for (const r of RULE_SUBJECTS.filter((rr) => !rr.actions)) {
		ok.push(`rule ${r.rule} (${r.what}) is workflow-only: ${r.why}`);
	}

	return { errors, ok };
}

/// Rule 6. The job count the root `CLAUDE.md` states is the job count `ci.yml`
/// holds, and the number the gate is said to wait for is the length of its own
/// `needs:` list.
///
/// Both figures are transcriptions of something this file already parses, and
/// nothing had ever compared them: the count was wrong after most rounds that
/// added a job, was corrected by hand twice, and drifted again each time
/// (decisions § 1260). The claims are matched by PHRASE, and a phrase that
/// matches NOTHING is a hard error rather than a pass — a reworded sentence
/// must fail loudly instead of silently checking nothing, which is the one way
/// a prose guard reads as complete while covering none of its subject.
/// A sweep beside it fails any OTHER number written next to "CI jobs", so a
/// second claim cannot be added in a form the templates do not read.
/**
 * @param {readonly WorkflowFile[]} files
 * @param {string} doc the root orientation document's text
 * @returns {{ errors: string[], ok: string[], stated: number }}
 */
export function checkStatedJobCount(files, doc) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	const ci = files.find((f) => f.name === 'ci.yml');
	if (!ci) {
		return { errors: ['ci.yml was not read, so its job count cannot be compared'], ok, stated: 0 };
	}
	const jobs = parseJobKeys(ci.text);
	const needs = parseNeeds(ci.text, GATE_JOB) ?? [];
	// The block wraps across lines in the layout diagram, so a sentence is read
	// with its indentation folded away rather than line by line.
	const prose = doc.replace(/\n\s+/g, ' ');

	/** @type {Array<{ re: RegExp, want: number, what: string }>} */
	const claims = [
		{ re: /the same (\d+) CI jobs/g, want: jobs.length, what: 'job keys in ci.yml' },
		{
			re: /needs: every one of the other (\d+)/g,
			want: needs.length,
			what: `entries in \`${GATE_JOB}\`'s needs: list`,
		},
	];

	/** @type {Array<[number, number]>} spans a registered claim accounted for */
	const claimed = [];
	let matched = 0;
	for (const { re, want, what } of claims) {
		let hits = 0;
		for (const m of prose.matchAll(re)) {
			hits++;
			matched++;
			claimed.push([m.index, m.index + m[0].length]);
			const got = Number(m[1]);
			if (got === want) continue;
			errors.push(
				`CLAUDE.md states ${got} where ci.yml has ${want} ${what}. The workflow is the ` +
					'fact; the sentence is the transcription.',
			);
		}
		if (hits === 0) {
			errors.push(
				`CLAUDE.md holds no sentence matching /${re.source}/, so that rule checks ` +
					'nothing. Restore the phrasing, or re-anchor the rule on the sentence that ' +
					'replaced it.',
			);
		}
	}

	// The other direction: a number written next to "CI jobs" that no claim
	// read. Without it the templates would read as complete while covering only
	// the sentence someone remembered to register.
	for (const m of prose.matchAll(/\d+ CI jobs/g)) {
		const a = m.index;
		const b = a + m[0].length;
		if (claimed.some(([x, y]) => a < y && x < b)) continue;
		errors.push(
			`CLAUDE.md writes "${m[0]}", which no template in checkStatedJobCount reads. ` +
				'Register it against the workflow, or write the sentence count-free.',
		);
	}

	if (errors.length === 0) {
		ok.push(
			`the root CLAUDE.md's ${matched} CI-shape figure(s) match ci.yml: ${jobs.length} ` +
				`job key(s), ${needs.length} of them in \`${GATE_JOB}\`'s needs: list`,
		);
	}
	return { errors, ok, stated: matched };
}

/**
 * @param {readonly WorkflowFile[]} files
 * @param {readonly WorkflowFile[]} [actions]
 */
export function checkAll(files, actions = []) {
	const scoping = checkFailureScoping(files, actions);
	const diagnoses = checkStepDiagnoses(files);
	const gate = checkGateCoverage(files);
	const verdict = checkGateVerdict(files);
	const delivery = checkShellSafeDiagnoses(files, actions);
	const subjects = checkRuleSubjects(files, actions);
	const stated = checkStatedJobCount(files, readFileSync(ORIENTATION_DOC, 'utf-8'));
	return {
		errors: [
			...subjects.errors,
			...scoping.errors,
			...diagnoses.errors,
			...gate.errors,
			...verdict.errors,
			...delivery.errors,
			...stated.errors,
		],
		ok: [
			...subjects.ok,
			...scoping.ok,
			...diagnoses.ok,
			...gate.ok,
			...verdict.ok,
			...delivery.ok,
			...stated.ok,
		],
		scoping,
		diagnoses,
		gate,
		verdict,
		delivery,
		subjects,
		stated,
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

/// Every composite action's `action.yml`, named `<dir>/action.yml` so a
/// reported line points at a path rather than at a bare filename two of them
/// share.
/**
 * @param {string} dir
 * @returns {WorkflowFile[]}
 */
export function readActions(dir) {
	/** @type {WorkflowFile[]} */
	const out = [];
	/** @type {string[]} */
	let entries;
	try {
		entries = readdirSync(dir);
	} catch {
		return out;
	}
	for (const entry of entries.sort()) {
		for (const file of ['action.yml', 'action.yaml']) {
			const path = join(dir, entry, file);
			if (!existsSync(path)) continue;
			out.push({ name: `${entry}/${file}`, text: readFileSync(path, 'utf-8') });
		}
	}
	return out;
}

function main() {
	const files = readWorkflows(WORKFLOW_DIR);
	const actions = readActions(ACTION_DIR);
	const { errors, ok, diagnoses, gate, delivery } = checkAll(files, actions);

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
			`\`${GATE_JOB}\` waits for all ${gate.covered} of them, and derives its own ` +
			`exit status from every one. ${delivery.scanned} shell line(s) across ` +
			`${files.length} workflow(s) + ${actions.length} composite action(s) print what ` +
			`they say.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
