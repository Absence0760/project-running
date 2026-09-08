#!/usr/bin/env node
// Guardrail: `docs/compliance/retention.md`'s "Auto-deletion / purge jobs"
// table is the migration tree's own `cron.schedule` / `cron.unschedule` set,
// re-derived rather than transcribed.
//
// Why this exists: decisions.md § 1507. `20270709000001` ran
// `cron.unschedule('cleanup-stale-export-blobs')` and the register went on
// advertising it as a nightly sweep for nine migrations, while omitting the two
// live retention jobs that had landed in the meantime. Nothing compared the two,
// which is the whole reason a `cron.unschedule` could land without touching a
// document whose purpose is to be the answer to a regulator.
//
// Every fact in that table is mechanically derivable, so none of it is checked
// against a phrase:
//
//   * The live set is the LAST operation per job name, in the order Supabase
//     applies migrations (version = the filename up to its first `_`). A name
//     whose last operation is a schedule is live; one whose last is an
//     unschedule is not.
//   * A row's schedule cell is compared against the live cron expression, not
//     against a list of allowed wordings: a backticked cron token must match the
//     expression field for field (an abbreviation is legal only where the fields
//     it drops are `*`), and the human phrase is DERIVED from the expression —
//     `*/N * * * *` must read as N minutes, a fixed minute with a wildcard hour
//     as hourly, a fixed minute and hour as that zero-padded UTC clock time. An
//     expression in a shape this guard cannot describe must state itself in
//     backticks rather than be waved through.
//   * The unscheduled row is the one shape that can only be a claim in prose, so
//     it is read as one — and symmetrically, which is what stops a reword from
//     escaping the guard: a row marked NOT SCHEDULED whose job is live fails, and
//     a row not marked whose job is unscheduled fails.
//
// The population is what cannot be escaped. Every live job is either a row of
// the table or a name in `EXCLUDED_JOBS` below, so a new schedule that is
// neither fails rather than being silently absent — the § 1507 failure exactly.
// Each exclusion must itself still be live, so a job that is dropped cannot be
// left behind in the list (`refresh-mv-weekly-mileage` was, in the prose, for
// three months after `20270530_001` unscheduled it).
//
// Run: `node scripts/check_retention_cron_register.mjs`
// CI:  the `workflow-lint` job in .github/workflows/ci.yml.
// Unit tests: `node --test scripts/check_retention_cron_register.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Overridable so the whole script — exit code and all — can be pointed at a
// mutated copy of the tree, which is how a guard is shown to fail.
export const ROOT = process.env.RETENTION_REGISTER_ROOT ?? REPO_ROOT;

export const REGISTER = 'docs/compliance/retention.md';
export const MIGRATIONS = 'apps/backend/supabase/migrations';

/**
 * The live `pg_cron` schedules that are NOT retention jobs. Declared by name,
 * with the reason, because the guard's population is "every live job", and an
 * unnamed one has to fail rather than fall through a category that admits
 * anything. Each must still be live — an exclusion cannot outlive its job.
 * @type {Array<{ name: string, reason: string }>}
 */
export const EXCLUDED_JOBS = [
	{ name: 'enqueue-token-refresh', reason: 'Enqueues integration token refreshes; deletes nothing.' },
	{ name: 'enqueue-event-reminders', reason: 'Enqueues reminder emails; deletes nothing.' },
	{ name: 'enqueue-weekly-digest', reason: 'Enqueues the weekly digest email; deletes nothing.' },
	{ name: 'enqueue-lifecycle-drip', reason: 'Enqueues lifecycle emails; deletes nothing.' },
	{
		name: 'enqueue-safety-overdue-emails',
		reason: 'Enqueues the overdue-runner escalation; deletes nothing.',
	},
	{
		name: 'sweep-challenge-completions',
		reason: 'Awards challenge completions; writes rows, removes none.',
	},
	{ name: 'jobs-stuck-alert', reason: 'Operational alert on the jobs queue; reads only.' },
	{ name: 'jobs-failed-alert', reason: 'Operational alert on the jobs queue; reads only.' },
	{ name: 'jobs-backlog-alert', reason: 'Operational alert on the jobs queue; reads only.' },
	{
		name: 'export-retention-overrun-alert',
		reason: 'Alerts when the Art 20 window is overrun; the reap job is what deletes.',
	},
];

/** A pg_cron job name as this repo writes them: lowercase words joined by `-`. */
export const JOB_NAME = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)+$/;

/** The heading whose table this guard reads. */
export const JOBS_HEADING = '## Auto-deletion / purge jobs';

/**
 * Supabase applies a migration by the version its filename carries before the
 * first `_`, so `20270708_001_x.sql` (version `20270708`) applies before
 * `20270708000010_y.sql`, which a plain filename sort gets backwards.
 * @param {string} file
 * @returns {string}
 */
export function migrationVersion(file) {
	const cut = file.indexOf('_');
	return cut === -1 ? file : file.slice(0, cut);
}

/**
 * Every `cron.schedule` / `cron.unschedule` in the migration tree, in apply order.
 * @param {string} root
 * @returns {Array<{ file: string, op: 'schedule' | 'unschedule', name: string, expr?: string }>}
 */
export function readCronOps(root) {
	const dir = join(root, MIGRATIONS);
	const files = readdirSync(dir)
		.filter((f) => f.endsWith('.sql'))
		.sort((a, b) => {
			const va = migrationVersion(a);
			const vb = migrationVersion(b);
			return va === vb ? a.localeCompare(b) : va.localeCompare(vb);
		});
	/** @type {Array<{ file: string, op: 'schedule' | 'unschedule', name: string, expr?: string }>} */
	const ops = [];
	for (const file of files) {
		const sql = readFileSync(join(dir, file), 'utf-8');
		for (const m of sql.matchAll(/cron\.schedule\s*\(\s*'([^']+)'\s*,\s*'([^']+)'/g)) {
			ops.push({ file, op: 'schedule', name: m[1], expr: m[2] });
		}
		for (const m of sql.matchAll(/cron\.unschedule\s*\(\s*'([^']+)'\s*\)/g)) {
			ops.push({ file, op: 'unschedule', name: m[1] });
		}
	}
	return ops;
}

/**
 * Last operation wins, which is what `cron.schedule`'s own idempotency-on-name
 * and `cron.unschedule` between them mean.
 * @param {ReturnType<typeof readCronOps>} ops
 * @returns {Map<string, { live: boolean, expr: string, file: string }>}
 */
export function liveCronState(ops) {
	/** @type {Map<string, { live: boolean, expr: string, file: string }>} */
	const state = new Map();
	for (const op of ops) {
		state.set(op.name, { live: op.op === 'schedule', expr: op.expr ?? '', file: op.file });
	}
	return state;
}

/**
 * The jobs table and the paragraph under it. The paragraph is everything
 * between the table and the next heading, so it is located structurally.
 * @param {string} markdown
 * @returns {{ rows: Array<{ job: string, schedule: string, deletes: string, migration: string }>, prose: string }}
 */
export function parseRegister(markdown) {
	const start = markdown.indexOf(JOBS_HEADING);
	if (start === -1) throw new Error(`${REGISTER} has no "${JOBS_HEADING}" section`);
	const after = markdown.slice(start + JOBS_HEADING.length);
	const end = after.search(/\n## /);
	const section = end === -1 ? after : after.slice(0, end);
	const lines = section.split('\n');
	/** @type {Array<{ job: string, schedule: string, deletes: string, migration: string }>} */
	const rows = [];
	const prose = [];
	for (const line of lines) {
		const t = line.trim();
		if (t.startsWith('|')) {
			const cells = t.slice(1, t.endsWith('|') ? -1 : undefined).split('|');
			if (cells.length < 4) continue;
			const job = firstJobName(cells[0]);
			if (job === null) continue;
			rows.push({
				job,
				schedule: cells[1].trim(),
				deletes: cells[2].trim(),
				migration: cells[3].trim(),
			});
			continue;
		}
		prose.push(line);
	}
	return { rows, prose: prose.join('\n') };
}

/**
 * The first backticked token in a cell that is shaped like a job name.
 * @param {string} cell
 * @returns {string | null}
 */
export function firstJobName(cell) {
	for (const m of cell.matchAll(/`([^`]+)`/g)) {
		if (JOB_NAME.test(m[1])) return m[1];
	}
	return null;
}

/** @param {string} text @returns {string[]} */
export function backtickedJobNames(text) {
	/** @type {string[]} */
	const found = [];
	for (const m of text.matchAll(/`([^`]+)`/g)) {
		if (JOB_NAME.test(m[1]) && !found.includes(m[1])) found.push(m[1]);
	}
	return found;
}

/**
 * A five-field cron expression, or null when it is not one this guard can read.
 * @param {string} expr
 * @returns {string[] | null}
 */
export function cronFields(expr) {
	const fields = expr.trim().split(/\s+/);
	return fields.length === 5 ? fields : null;
}

/**
 * What a five-field expression says in words, or null for a shape this guard
 * does not describe (weekly, monthly, step-hours...). The caller then demands
 * the raw expression instead of a phrase it cannot verify.
 * @param {string[]} fields
 * @returns {{ kind: 'minutes', marker: string } | { kind: 'hourly', marker: string } | { kind: 'daily', marker: string } | null}
 */
export function describeCron(fields) {
	const [minute, hour, dom, mon, dow] = fields;
	if (dom !== '*' || mon !== '*' || dow !== '*') return null;
	const step = /^\*\/(\d+)$/.exec(minute);
	if (step && hour === '*') return { kind: 'minutes', marker: step[1] };
	if (/^\d+$/.test(minute) && hour === '*') return { kind: 'hourly', marker: 'hourly' };
	if (/^\d+$/.test(minute) && /^\d+$/.test(hour)) {
		return {
			kind: 'daily',
			marker: `${hour.padStart(2, '0')}:${minute.padStart(2, '0')}`,
		};
	}
	return null;
}

/**
 * Does a schedule cell agree with the expression the migrations schedule?
 * @param {string} cell
 * @param {string} expr
 * @returns {string | null} the disagreement, or null when they agree
 */
export function scheduleDisagreement(cell, expr) {
	const fields = cronFields(expr);
	if (fields === null) return `the migration schedules \`${expr}\`, which is not five cron fields`;

	for (const m of cell.matchAll(/`([^`]+)`/g)) {
		const token = m[1].trim();
		if (!/^[\d*/,\-]+(?:\s+[\d*/,\-]+)*$/.test(token)) continue;
		if (!token.includes('*') && !token.includes('/')) continue;
		const stated = token.split(/\s+/);
		if (stated.length > fields.length) {
			return `states \`${token}\`, which has more fields than the scheduled \`${expr}\``;
		}
		for (let i = 0; i < fields.length; i++) {
			const want = i < stated.length ? stated[i] : '*';
			if (want !== fields[i]) {
				return `states \`${token}\` but the migration schedules \`${expr}\`` +
					(i >= stated.length
						? ' (an abbreviated expression may only drop fields that are `*`)'
						: '');
			}
		}
	}

	const described = describeCron(fields);
	if (described === null) {
		if (!cell.includes(`\`${expr}\``)) {
			return `is scheduled \`${expr}\`, a shape this guard cannot put into words — state the expression in backticks so the cell is checkable`;
		}
		return null;
	}
	if (described.kind === 'minutes') {
		const re = new RegExp(`\\b${described.marker}\\s*(?:min|minute)`, 'i');
		if (!re.test(cell)) {
			return `is scheduled \`${expr}\` — every ${described.marker} minutes — which the cell does not say`;
		}
		return null;
	}
	if (!cell.toLowerCase().includes(described.marker.toLowerCase())) {
		return `is scheduled \`${expr}\`, which the cell does not say (expected it to name "${described.marker}")`;
	}
	return null;
}

/** English for the counts the prose states in words. */
const NUMBER_WORDS = [
	'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten',
	'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen',
	'nineteen', 'twenty', 'twenty-one', 'twenty-two', 'twenty-three', 'twenty-four',
	'twenty-five', 'twenty-six', 'twenty-seven', 'twenty-eight', 'twenty-nine', 'thirty',
];

/** @param {string} prose @param {number} n @returns {boolean} */
export function statesCount(prose, n) {
	const lower = prose.toLowerCase();
	if (new RegExp(`\\b${n}\\b`).test(lower)) return true;
	const word = NUMBER_WORDS[n];
	return word !== undefined && new RegExp(`\\b${word}\\b`).test(lower);
}

/**
 * @param {{ state: Map<string, { live: boolean, expr: string, file: string }>, register: ReturnType<typeof parseRegister>, excluded: typeof EXCLUDED_JOBS }} input
 * @returns {{ errors: string[], ok: string[] }}
 */
export function check({ state, register, excluded }) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	const excludedNames = new Set(excluded.map((e) => e.name));
	const rowByJob = new Map(register.rows.map((r) => [r.job, r]));

	if (register.rows.length === 0) {
		errors.push(`${REGISTER}: the "${JOBS_HEADING}" table has no job rows at all`);
		return { errors, ok };
	}

	for (const { name, reason } of excluded) {
		const live = state.get(name);
		if (live === undefined || !live.live) {
			errors.push(
				`EXCLUDED_JOBS names \`${name}\` ("${reason}") but no migration leaves it scheduled — ` +
					'drop the exclusion, or the guard is excusing a job that no longer exists',
			);
		}
		if (rowByJob.has(name)) {
			errors.push(
				`\`${name}\` is both a row of the retention table and an EXCLUDED_JOBS entry — it is ` +
					'either a retention job or it is not',
			);
		}
	}

	for (const [name, s] of state) {
		if (!s.live) continue;
		if (rowByJob.has(name) || excludedNames.has(name)) continue;
		errors.push(
			`\`${name}\` is scheduled by ${s.file} (\`${s.expr}\`) and appears neither in the ` +
				`${REGISTER} jobs table nor in EXCLUDED_JOBS. A retention job belongs in the table; ` +
				'anything else belongs in the exclusion list, with its reason',
		);
	}

	let liveRows = 0;
	for (const row of register.rows) {
		const s = state.get(row.job);
		if (s === undefined) {
			errors.push(
				`${REGISTER} lists \`${row.job}\`, which no migration schedules or unschedules ` +
					'under that name',
			);
			continue;
		}
		const marked = /not\s+scheduled/i.test(row.schedule);
		if (s.live && marked) {
			errors.push(
				`${REGISTER} marks \`${row.job}\` as not scheduled, but ${s.file} leaves it live on ` +
					`\`${s.expr}\``,
			);
			continue;
		}
		if (!s.live && !marked) {
			errors.push(
				`${REGISTER} states a live schedule for \`${row.job}\`, but ${s.file} unschedules it. ` +
					'Mark the row NOT SCHEDULED (keeping it, so nobody re-derives the job as missing) ' +
					'or remove it',
			);
			continue;
		}
		if (!s.live) continue;
		liveRows += 1;
		const disagreement = scheduleDisagreement(row.schedule, s.expr);
		if (disagreement !== null) {
			errors.push(`${REGISTER}'s \`${row.job}\` row ${disagreement}`);
		}
	}

	for (const name of backtickedJobNames(register.prose)) {
		if (!state.has(name)) {
			errors.push(
				`${REGISTER}'s closing paragraph names \`${name}\`, which no migration schedules or ` +
					'unschedules under that name',
			);
		}
	}
	for (const { name } of excluded) {
		if (!register.prose.includes(`\`${name}\``)) {
			errors.push(
				`${REGISTER}'s closing paragraph does not name the excluded schedule \`${name}\` — ` +
					'the list of what is deliberately outside the register is part of the register',
			);
		}
	}
	if (!statesCount(register.prose, liveRows)) {
		errors.push(
			`${REGISTER}'s closing paragraph does not state that ${liveRows} retention jobs are live`,
		);
	}
	if (!statesCount(register.prose, excluded.length)) {
		errors.push(
			`${REGISTER}'s closing paragraph does not state that ${excluded.length} live schedules ` +
				'are excluded as non-retention',
		);
	}

	if (errors.length === 0) {
		ok.push(
			`${liveRows} live retention job(s) and ${excluded.length} excluded schedule(s) match the ` +
				'migration tree',
		);
	}
	return { errors, ok };
}

const invokedDirectly = process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
if (invokedDirectly) {
	const state = liveCronState(readCronOps(ROOT));
	const register = parseRegister(readFileSync(join(ROOT, REGISTER), 'utf-8'));
	const { errors, ok } = check({ state, register, excluded: EXCLUDED_JOBS });
	for (const line of ok) console.log(`[OK] check_retention_cron_register: ${line}`);
	for (const line of errors) console.error(`::error::check_retention_cron_register: ${line}`);
	if (errors.length > 0) {
		console.error(
			`\ncheck_retention_cron_register: ${errors.length} disagreement(s). The migrations are ` +
				'the fact; the register is the transcription.',
		);
		process.exit(1);
	}
}
