import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// A surface that renders ANOTHER user's row must not link to an owner-scoped
// route. `/runs/[id]` calls fetchRunById, which filters `.eq('user_id', userId)`,
// so opening a followed runner's run there loads null and the page renders its
// "Run not found" empty state — a real, public run presented as deleted.
//
// The social feed shipped that on both its card body and its comment pill while
// the lift card beside them already used /share/workout/[id] and mobile already
// routed to PublicRunScreen, so the fix direction was never in question. The
// same assumption reached the notification worker, whose `run_completed` deep
// link (fired at a followee's FOLLOWERS) pointed at /runs/{id} too; that side is
// pinned in apps/job_worker/internal/mailer_test.go.
//
// Owner-only surfaces (/history, /runs, /dashboard, PeriodSummary) list the
// viewer's own runs and are deliberately not covered here.

const read = (p: string) => readFileSync(resolve(p), 'utf-8');

test('SocialFeed links other runners rows to public surfaces, not owner-scoped ones', () => {
	const src = read('src/lib/components/SocialFeed.svelte');
	assert.doesNotMatch(
		src,
		/href="\/runs\/\{/,
		'SocialFeed renders other users runs — /runs/[id] is owner-scoped and would render "Run not found". Link to /share/run/{id}.',
	);
	assert.match(src, /href="\/share\/run\/\{entry\.id\}"/, 'the feed run card must open the public run page');
	assert.match(src, /href="\/share\/workout\/\{entry\.id\}"/, 'the feed lift card must open the public workout page');
});
