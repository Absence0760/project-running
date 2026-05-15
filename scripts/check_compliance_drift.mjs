#!/usr/bin/env node
import { execSync } from 'node:child_process';
import fs from 'node:fs';

const baseRef = process.env.GITHUB_BASE_REF
	? `origin/${process.env.GITHUB_BASE_REF}`
	: 'origin/main';

function changedFiles() {
	try {
		const out = execSync(`git diff --name-only ${baseRef}...HEAD`, { encoding: 'utf8' });
		return out.split('\n').filter(Boolean);
	} catch {
		return [];
	}
}

function readChangedSource(path) {
	try {
		return execSync(`git diff ${baseRef}...HEAD -- ${path}`, { encoding: 'utf8' });
	} catch {
		return '';
	}
}

const files = changedFiles();
if (files.length === 0) {
	console.log('No changed files vs ' + baseRef + ' — skipping compliance-drift check.');
	process.exit(0);
}

const findings = [];

const touchedRetention = files.some((f) => f === 'docs/compliance/retention.md');
const touchedSubProcessors = files.some((f) => f === 'docs/compliance/sub-processors.md');
const touchedAuditExportCmd = files.some((f) =>
	f.startsWith('.claude/commands/audit/data-export-completeness.md'),
);
const touchedAuditDeleteCmd = files.some((f) =>
	f.startsWith('.claude/commands/audit/account-deletion-completeness.md'),
);
const touchedDataExport = files.some((f) =>
	f.startsWith('apps/job_worker/internal/dataexport/'),
);
const touchedDeleteAccount = files.some((f) =>
	f.startsWith('apps/backend/supabase/functions/delete-account/'),
);

const migrationFiles = files.filter(
	(f) => f.startsWith('apps/backend/supabase/migrations/') && f.endsWith('.sql'),
);

const PERSONAL_DATA_TABLE_HINTS = [
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

for (const m of migrationFiles) {
	const diff = readChangedSource(m);
	const created = diff.match(/^\+\s*create\s+table\s+(?:if\s+not\s+exists\s+)?(?:\w+\.)?(\w+)\s*\(/gim) ?? [];
	const altered = diff.match(/^\+\s*alter\s+table\s+(?:\w+\.)?(\w+)/gim) ?? [];
	const candidates = new Set();
	for (const m of [...created, ...altered]) {
		const name = (m.match(/(?:create|alter)\s+table\s+(?:if\s+not\s+exists\s+)?(?:\w+\.)?(\w+)/i) ?? [])[1];
		if (!name) continue;
		const lower = name.toLowerCase();
		if (PERSONAL_DATA_TABLE_HINTS.some((h) => lower.startsWith(h) || lower === h)) {
			candidates.add(lower);
		}
	}
	if (candidates.size === 0) continue;
	const tables = [...candidates].sort().join(', ');
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

const newEdgeFunctions = files.filter((f) => {
	if (!f.startsWith('apps/backend/supabase/functions/')) return false;
	if (!f.endsWith('/index.ts')) return false;
	try {
		const diff = readChangedSource(f);
		return /^@@.*\+1\b/m.test(diff);
	} catch {
		return false;
	}
});
if (newEdgeFunctions.length > 0 && !touchedSubProcessors) {
	findings.push({
		file: newEdgeFunctions.join(', '),
		rule: 'sub-processors',
		detail: 'New Edge Function added without updating docs/compliance/sub-processors.md. Add any new outbound providers it calls to the sub-processor table.',
	});
}

const codeFiles = files.filter(
	(f) =>
		(f.endsWith('.ts') || f.endsWith('.tsx') || f.endsWith('.dart') || f.endsWith('.go')) &&
		!f.includes('test') &&
		!f.endsWith('.d.ts'),
);
const newOutboundDomains = new Set();
const KNOWN_DOMAIN_SUBSTRINGS = [
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
for (const f of codeFiles) {
	let diff = '';
	try {
		diff = readChangedSource(f);
	} catch {
		continue;
	}
	for (const line of diff.split('\n')) {
		if (!line.startsWith('+')) continue;
		const matches = line.match(/https?:\/\/([a-z0-9.-]+\.[a-z]{2,})/gi);
		if (!matches) continue;
		for (const url of matches) {
			const host = url.replace(/^https?:\/\//i, '').toLowerCase();
			if (host.includes('localhost') || host.startsWith('127.') || host.startsWith('10.')) continue;
			if (KNOWN_DOMAIN_SUBSTRINGS.some((sub) => host.includes(sub))) continue;
			newOutboundDomains.add(host);
		}
	}
}
if (newOutboundDomains.size > 0 && !touchedSubProcessors) {
	findings.push({
		file: 'multiple',
		rule: 'sub-processors',
		detail: `New outbound domain(s) added (${[...newOutboundDomains].join(', ')}) but docs/compliance/sub-processors.md was not updated. Add any new sub-processor + the data sent / region / DPA.`,
	});
}

if (findings.length === 0) {
	console.log('Compliance-drift check passed — no doc updates required for this diff.');
	process.exit(0);
}

const lines = [];
lines.push('## Compliance drift detected');
lines.push('');
lines.push('Items in this PR look like they need a matching compliance-doc or DSAR-endpoint update.');
lines.push('This check is advisory — if your judgement says the doc does not apply, push back in the PR comment and the reviewer can override.');
lines.push('');
for (const f of findings) {
	lines.push(`- **${f.rule}** in \`${f.file}\` — ${f.detail}`);
}
lines.push('');
lines.push('References:');
lines.push('- `/audit/gdpr` — overall GDPR posture');
lines.push('- `/audit/data-export-completeness` — every personal-data column reaches the export');
lines.push('- `/audit/account-deletion-completeness` — every personal-data table is drained by delete-account');
lines.push('- `/audit/third-party-data-flows` — sub-processor inventory');
const report = lines.join('\n');

console.log(report);

if (process.env.GITHUB_STEP_SUMMARY) {
	try {
		fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, report + '\n');
	} catch {}
}

const mode = (process.env.COMPLIANCE_DRIFT_MODE ?? 'warn').toLowerCase();
if (mode === 'fail') process.exit(1);
process.exit(0);
