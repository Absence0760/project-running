#!/usr/bin/env node
// Advisory: a diff that moves personal data should move the compliance docs
// and the DSAR endpoints with it.
//
// Everything this file decides is a pure function of {changed files, added
// files, per-file diff}, and `main()` is the only part that talks to git. It
// was one top-level script with no exports and no tests until the
// new-Edge-Function detector was found reading a hunk header as a claim about
// a file's existence: `/^@@.*\+1\b/m` matches `@@ -1,3 +1,4 @@` — an edit to
// the top of a file that has been there for a year — as readily as it matches
// `@@ -0,0 +1,120 @@`. Measured over the last 2000 commits: it fires 28 times
// on 6 genuinely new Edge Functions, so 22 of its 28 claims are wrong. git
// already knows the answer and is asked for it directly now
// (`--diff-filter=A`), which is not a heuristic at all.
//
// Run: `node scripts/check_compliance_drift.mjs`
// CI:  the `compliance-drift` job in .github/workflows/compliance-drift.yml,
//      advisory by default (COMPLIANCE_DRIFT_MODE=warn).
// Unit tests: `node --test scripts/check_compliance_drift.test.mjs`

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

export const PERSONAL_DATA_TABLE_HINTS = [
	'user_',
	'runs',
	'routes',
	'run_',
	'route_',
	'coach_messages',
	'live_run_pings',
	'route_history',
	'race_',
	'event_',
	'club_',
	'segment_',
	'notifications',
	'integrations',
	'device_tokens',
	'fitness_snapshots',
	'personal_records',
	'gear',
];

export const KNOWN_DOMAIN_SUBSTRINGS = [
	'supabase',
	'maptiler',
	'sentry',
	'anthropic',
	'openai',
	'revenuecat',
	'stripe',
	'strava',
	'parkrun',
	'garmin',
	'open-meteo',
	'apple.com',
	'googleapis.com',
	'firebase',
	'fcm',
	'apns',
	'amazonaws.com',
	'cloudfront',
	'fly.io',
	'fly.dev',
];

/**
 * @typedef {{ file: string, rule: string, detail: string }} Finding
 * @typedef {{
 *   files: readonly string[],
 *   added: ReadonlySet<string>,
 *   diffFor: (path: string) => string,
 * }} DriftInput
 */

/// The personal-data tables a migration's ADDED lines create or alter.
/**
 * @param {string} diff
 * @returns {string[]}
 */
export function personalDataTablesInDiff(diff) {
	const created =
		diff.match(/^\+\s*create\s+table\s+(?:if\s+not\s+exists\s+)?(?:\w+\.)?(\w+)\s*\(/gim) ?? [];
	const altered = diff.match(/^\+\s*alter\s+table\s+(?:\w+\.)?(\w+)/gim) ?? [];
	/** @type {Set<string>} */
	const candidates = new Set();
	for (const hit of [...created, ...altered]) {
		const name = (hit.match(
			/(?:create|alter)\s+table\s+(?:if\s+not\s+exists\s+)?(?:\w+\.)?(\w+)/i,
		) ?? [])[1];
		if (!name) continue;
		const lower = name.toLowerCase();
		if (PERSONAL_DATA_TABLE_HINTS.some((h) => lower.startsWith(h) || lower === h)) {
			candidates.add(lower);
		}
	}
	return [...candidates].sort();
}

/// The hosts an ADDED line reaches that no known sub-processor covers.
/**
 * @param {string} diff
 * @returns {string[]}
 */
export function newOutboundHostsInDiff(diff) {
	/** @type {Set<string>} */
	const hosts = new Set();
	for (const line of diff.split('\n')) {
		if (!line.startsWith('+')) continue;
		const matches = line.match(/https?:\/\/([a-z0-9.-]+\.[a-z]{2,})/gi);
		if (!matches) continue;
		for (const url of matches) {
			const host = url.replace(/^https?:\/\//i, '').toLowerCase();
			if (host.includes('localhost') || host.startsWith('127.') || host.startsWith('10.')) continue;
			if (KNOWN_DOMAIN_SUBSTRINGS.some((sub) => host.includes(sub))) continue;
			hosts.add(host);
		}
	}
	return [...hosts];
}

/**
 * @param {DriftInput} input
 * @returns {Finding[]}
 */
export function collectFindings({ files, added, diffFor }) {
	/** @type {Finding[]} */
	const findings = [];

	const touchedRetention = files.includes('docs/compliance/retention.md');
	const touchedSubProcessors = files.includes('docs/compliance/sub-processors.md');
	const touchedAuditExportCmd = files.some((f) =>
		f.startsWith('.claude/commands/audit/data-export-completeness.md'),
	);
	const touchedAuditDeleteCmd = files.some((f) =>
		f.startsWith('.claude/commands/audit/account-deletion-completeness.md'),
	);
	const touchedDataExport = files.some((f) => f.startsWith('apps/job_worker/internal/dataexport/'));
	const touchedDeleteAccount = files.some((f) =>
		f.startsWith('apps/backend/supabase/functions/delete-account/'),
	);

	const migrationFiles = files.filter(
		(f) => f.startsWith('apps/backend/supabase/migrations/') && f.endsWith('.sql'),
	);

	for (const m of migrationFiles) {
		const tables = personalDataTablesInDiff(diffFor(m)).join(', ');
		if (tables === '') continue;
		if (!touchedRetention) {
			findings.push({
				file: m,
				rule: 'retention',
				detail: `Migration touches personal-data table(s) (${tables}) but docs/compliance/retention.md was not updated.`,
			});
		}
		if (!touchedDataExport && !touchedAuditExportCmd) {
			findings.push({
				file: m,
				rule: 'data-export',
				detail: `Migration touches personal-data table(s) (${tables}) but apps/job_worker/internal/dataexport/ was not updated. Confirm the export still covers every new column.`,
			});
		}
		if (!touchedDeleteAccount && !touchedAuditDeleteCmd) {
			findings.push({
				file: m,
				rule: 'delete-account',
				detail: `Migration touches personal-data table(s) (${tables}) but apps/backend/supabase/functions/delete-account/ was not updated. Confirm delete-account drains every new table / column.`,
			});
		}
	}

	// An Edge Function is new when git says the file was ADDED, not when its
	// diff happens to carry a hunk that starts at line 1.
	const newEdgeFunctions = files.filter(
		(f) =>
			f.startsWith('apps/backend/supabase/functions/') && f.endsWith('/index.ts') && added.has(f),
	);
	if (newEdgeFunctions.length > 0 && !touchedSubProcessors) {
		findings.push({
			file: newEdgeFunctions.join(', '),
			rule: 'sub-processors',
			detail:
				'New Edge Function added without updating docs/compliance/sub-processors.md. Add any new outbound providers it calls to the sub-processor table.',
		});
	}

	const codeFiles = files.filter(
		(f) =>
			(f.endsWith('.ts') || f.endsWith('.tsx') || f.endsWith('.dart') || f.endsWith('.go')) &&
			!f.includes('test') &&
			!f.endsWith('.d.ts'),
	);
	/** @type {Set<string>} */
	const newOutboundDomains = new Set();
	for (const f of codeFiles) {
		for (const host of newOutboundHostsInDiff(diffFor(f))) newOutboundDomains.add(host);
	}
	if (newOutboundDomains.size > 0 && !touchedSubProcessors) {
		findings.push({
			file: 'multiple',
			rule: 'sub-processors',
			detail: `New outbound domain(s) added (${[...newOutboundDomains].join(', ')}) but docs/compliance/sub-processors.md was not updated. Add any new sub-processor + the data sent / region / DPA.`,
		});
	}

	return findings;
}

/**
 * @param {readonly Finding[]} findings
 * @returns {string}
 */
export function renderReport(findings) {
	const lines = [
		'## Compliance drift detected',
		'',
		'Items in this PR look like they need a matching compliance-doc or DSAR-endpoint update.',
		'This check is advisory — if your judgement says the doc does not apply, push back in the PR comment and the reviewer can override.',
		'',
	];
	for (const f of findings) lines.push(`- **${f.rule}** in \`${f.file}\` — ${f.detail}`);
	lines.push('');
	lines.push('References:');
	lines.push('- `/audit/gdpr` — overall GDPR posture');
	lines.push('- `/audit/data-export-completeness` — every personal-data column reaches the export');
	lines.push(
		'- `/audit/account-deletion-completeness` — every personal-data table is drained by delete-account',
	);
	lines.push('- `/audit/third-party-data-flows` — sub-processor inventory');
	return lines.join('\n');
}

function main() {
	const baseRef = process.env.GITHUB_BASE_REF
		? `origin/${process.env.GITHUB_BASE_REF}`
		: 'origin/main';
	const mode = (process.env.COMPLIANCE_DRIFT_MODE ?? 'warn').toLowerCase();

	/**
	 * `execFileSync` rather than a shell string: a path is one argument here,
	 * where `git diff … -- ${path}` splits a filename containing a space into
	 * two pathspecs and reads a diff of neither.
	 * @param {string[]} args
	 * @returns {string}
	 */
	const git = (args) => execFileSync('git', args, { encoding: 'utf8' });

	/** @type {string[] | null} */
	let files = null;
	/** @type {Set<string>} */
	let added = new Set();
	try {
		files = git(['diff', '--name-only', `${baseRef}...HEAD`]).split('\n').filter(Boolean);
		added = new Set(
			git(['diff', '--name-only', '--diff-filter=A', `${baseRef}...HEAD`])
				.split('\n')
				.filter(Boolean),
		);
	} catch {
		// A missing base ref (a shallow clone, an unfetched `origin/<base>`) used
		// to read as "no changed files" and pass every rule.
		files = null;
	}

	if (files === null) {
		console.log(
			`::warning::Could not diff against ${baseRef} — the compliance-drift check did NOT run. ` +
				'Fetch the base ref (actions/checkout with fetch-depth: 0) and re-run.',
		);
		process.exit(mode === 'fail' ? 1 : 0);
	}
	if (files.length === 0) {
		console.log(`No changed files vs ${baseRef} — skipping compliance-drift check.`);
		process.exit(0);
	}

	// Deliberately not caught: `git diff --name-only` has just named this path,
	// so a failure reading its diff is a broken repository, and a rule that
	// silently sees an empty diff reports the tree clean over a file nobody read.
	const findings = collectFindings({
		files,
		added,
		diffFor: (path) => git(['diff', `${baseRef}...HEAD`, '--', path]),
	});

	if (findings.length === 0) {
		console.log('Compliance-drift check passed — no doc updates required for this diff.');
		process.exit(0);
	}

	const report = renderReport(findings);
	console.log(report);
	if (process.env.GITHUB_STEP_SUMMARY) {
		try {
			fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, report + '\n');
		} catch {}
	}
	process.exit(mode === 'fail' ? 1 : 0);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
