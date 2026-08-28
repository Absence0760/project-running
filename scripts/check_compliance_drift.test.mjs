import test from 'node:test';
import assert from 'node:assert/strict';

import {
	collectFindings,
	newOutboundHostsInDiff,
	personalDataTablesInDiff,
	renderReport,
} from './check_compliance_drift.mjs';

/**
 * @param {Partial<{ files: string[], added: string[], diffs: Record<string, string> }>} spec
 */
function run(spec) {
	const diffs = spec.diffs ?? {};
	return collectFindings({
		files: spec.files ?? [],
		added: new Set(spec.added ?? []),
		diffFor: (path) => diffs[path] ?? '',
	});
}

const NEW_FN_DIFF = [
	'diff --git a/apps/backend/supabase/functions/new-fn/index.ts b/apps/backend/supabase/functions/new-fn/index.ts',
	'new file mode 100644',
	'--- /dev/null',
	'+++ b/apps/backend/supabase/functions/new-fn/index.ts',
	'@@ -0,0 +1,3 @@',
	'+const a = 1;',
	'+const b = 2;',
	'+const c = 3;',
].join('\n');

// The shape the `/^@@.*\+1\b/m` detector could not tell apart from the one
// above: a hunk header starting at line 1 of a file that already existed.
// Measured over the last 2000 commits, 22 of its 28 firings were this.
const TOP_EDIT_DIFF = [
	'diff --git a/apps/backend/supabase/functions/existing-fn/index.ts b/apps/backend/supabase/functions/existing-fn/index.ts',
	'index 022fe64..b62a8e4 100644',
	'--- a/apps/backend/supabase/functions/existing-fn/index.ts',
	'+++ b/apps/backend/supabase/functions/existing-fn/index.ts',
	'@@ -1,3 +1,4 @@',
	'+// a header comment',
	' const a = 1;',
	' const b = 2;',
	' const c = 3;',
].join('\n');

test('an edit to the top of an existing Edge Function is not a new one', () => {
	const path = 'apps/backend/supabase/functions/existing-fn/index.ts';
	assert.match(TOP_EDIT_DIFF, /^@@.*\+1\b/m); // the old detector's premise
	assert.deepEqual(run({ files: [path], added: [], diffs: { [path]: TOP_EDIT_DIFF } }), []);
});

test('a genuinely added Edge Function without a sub-processor update is reported', () => {
	const path = 'apps/backend/supabase/functions/new-fn/index.ts';
	const findings = run({ files: [path], added: [path], diffs: { [path]: NEW_FN_DIFF } });
	assert.equal(findings.length, 1);
	assert.equal(findings[0].rule, 'sub-processors');
	assert.match(findings[0].file, /new-fn/);
});

test('an added Edge Function alongside a sub-processor update is fine', () => {
	const path = 'apps/backend/supabase/functions/new-fn/index.ts';
	assert.deepEqual(
		run({
			files: [path, 'docs/compliance/sub-processors.md'],
			added: [path],
			diffs: { [path]: NEW_FN_DIFF },
		}),
		[],
	);
});

test('an added file elsewhere in a function directory is not the entrypoint', () => {
	const path = 'apps/backend/supabase/functions/new-fn/lib.ts';
	assert.deepEqual(run({ files: [path], added: [path], diffs: { [path]: NEW_FN_DIFF } }), []);
});

test('personalDataTablesInDiff reads added lines only, and only known prefixes', () => {
	const diff = [
		'@@ -0,0 +1,4 @@',
		'+create table if not exists public.run_photos (',
		'+alter table user_profiles add column x int;',
		'-alter table runs add column removed int;',
		'+create table public.widgets (',
	].join('\n');
	assert.deepEqual(personalDataTablesInDiff(diff), ['run_photos', 'user_profiles']);
});

test('a personal-data migration raises all three rules, and each is satisfiable', () => {
	const m = 'apps/backend/supabase/migrations/29990101_001_x.sql';
	const diff = '@@ -0,0 +1,1 @@\n+alter table runs add column x int;';
	assert.deepEqual(
		run({ files: [m], diffs: { [m]: diff } }).map((f) => f.rule),
		['retention', 'data-export', 'delete-account'],
	);
	assert.deepEqual(
		run({
			files: [
				m,
				'docs/compliance/retention.md',
				'apps/job_worker/internal/dataexport/export.go',
				'apps/backend/supabase/functions/delete-account/index.ts',
			],
			diffs: { [m]: diff },
		}),
		[],
	);
});

test('newOutboundHostsInDiff skips known sub-processors and local addresses', () => {
	const diff = [
		'@@ -0,0 +1,4 @@',
		"+await fetch('https://api.example-tracker.com/v1/ping');",
		"+await fetch('https://api.stripe.com/v1/charges');",
		"+await fetch('http://localhost:54321/rest');",
		"-await fetch('https://removed.example.org/x');",
	].join('\n');
	assert.deepEqual(newOutboundHostsInDiff(diff), ['api.example-tracker.com']);
});

test('renderReport names every finding and stays advisory', () => {
	const report = renderReport([{ file: 'a.sql', rule: 'retention', detail: 'because.' }]);
	assert.match(report, /Compliance drift detected/);
	assert.match(report, /\*\*retention\*\* in `a\.sql` — because\./);
	assert.match(report, /advisory/);
});
