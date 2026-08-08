import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// A surface that renders ANOTHER user's row must land the viewer somewhere
// that actually renders it. `fetchRunById` filters `.eq('user_id', userId)`,
// so for years opening a followed runner's run on `/runs/[id]` loaded null and
// the page rendered its "Run not found" empty state — a real, public run
// presented as deleted.
//
// The social feed shipped that on both its card body and its comment pill while
// the lift card beside them already used /share/workout/[id] and mobile already
// routed to PublicRunScreen, so the fix direction was never in question. The
// same assumption reached the notification worker, whose `run_completed` deep
// link (fired at a followee's FOLLOWERS) pointed at /runs/{id} too; that side is
// pinned in apps/job_worker/internal/mailer_test.go.
//
// Those links stay on the public /share/* surfaces — they are anon-reachable
// and indexable, which /runs/[id] is not (the layout auth-gate bounces anon to
// /login). What issue #666 closed is the OTHER half: /runs/[id] itself now has
// a non-owner branch, so a pasted in-app URL renders the run instead of
// claiming it is gone. The guards below pin both halves.
//
// Owner-only surfaces (/history, /runs, /dashboard, PeriodSummary) list the
// viewer's own runs and are deliberately not covered here.

const read = (p: string) => readFileSync(resolve(p), 'utf-8');

test('SocialFeed links other runners rows to public surfaces, not owner-scoped ones', () => {
	const src = read('src/lib/components/SocialFeed.svelte');
	assert.doesNotMatch(
		src,
		/href="\/runs\/\{/,
		'SocialFeed renders other users runs — /share/run/{id} is the anon-reachable, indexable surface for them; /runs/[id] is behind the auth gate.',
	);
	assert.match(src, /href="\/share\/run\/\{entry\.id\}"/, 'the feed run card must open the public run page');
	assert.match(src, /href="\/share\/workout\/\{entry\.id\}"/, 'the feed lift card must open the public workout page');
});

test('/runs/[id] renders a non-owner branch for a publicly readable run', () => {
	// Reason: issue #666. `fetchRunById` is owner-scoped by design (it is the
	// only path that downloads the UNCLIPPED track), so a non-owner read has
	// to come from somewhere else. The page resolves entitlement through
	// `fetchPublicRunAttribution` — a `public_runs` hit, i.e. is_public = true —
	// and mounts RunShareView, which is the component that routes a non-owner
	// track through the clip-public-track Edge Function (decisions §33).
	//
	// A refactor that dropped either half would silently restore the bug:
	// without the attribution call the page 404s a public run again; without
	// RunShareView some future hand-rolled non-owner renderer would be one
	// `fetchTrackByPath` away from serving an unclipped trace.
	const src = read('src/routes/runs/[id]/+page.svelte');
	assert.match(
		src,
		/fetchPublicRunAttribution/,
		'/runs/[id] must resolve non-owner entitlement via fetchPublicRunAttribution (public_runs = is_public) — see issue #666.',
	);
	assert.match(
		src,
		/<RunShareView\s+runId=/,
		'/runs/[id] non-owner branch must render RunShareView — it owns the clip-public-track path for a non-owner track (decisions §33).',
	);
});

test('/runs/[id] keeps every owner-only control out of the non-owner branch', () => {
	// Reason: the non-owner branch must carry no edit / delete / visibility
	// affordance. The structural invariant that makes that true is that the
	// non-owner branch is a SIBLING of the owner branch in the same {#if}
	// chain, and that the non-owner row is never assigned to `run` (the state
	// the owner template keys off). Pin both: the `otherRunOwner` branch has
	// to appear before the `!run` not-found branch, and only `fetchRunById`
	// may ever write `run`.
	const src = read('src/routes/runs/[id]/+page.svelte');
	const otherBranch = src.indexOf('{:else if otherRunOwner}');
	const notFoundBranch = src.indexOf('{:else if !run}');
	assert.ok(otherBranch > 0, 'expected an {:else if otherRunOwner} non-owner branch');
	assert.ok(notFoundBranch > 0, 'expected the {:else if !run} not-found branch');
	assert.ok(
		otherBranch < notFoundBranch,
		'the non-owner branch must precede the not-found branch or a public run 404s again',
	);
	// Local owner-side edits re-spread the row (`run = { ...run, … }`); those
	// can't introduce a foreign row, so only the fresh sources matter.
	const runSources = [...src.matchAll(/^\s*run = (.+);$/gm)]
		.map((m) => m[1])
		.filter((rhs) => !rhs.startsWith('{ ...run'));
	assert.deepEqual(
		runSources,
		['ownRun'],
		'`run` drives the whole owner template (edit / delete / visibility / gear / rematch). ' +
			'Only the owner-scoped fetchRunById may source it — assigning a public_runs row there ' +
			'would render owner controls to a non-owner. Got: ' +
			JSON.stringify(runSources),
	);
	// …and `ownRun` may only ever come from that fetch. fetchRunById reports
	// its transport error separately (a failed read must not read as
	// "Run not found"), so the row arrives destructured rather than assigned.
	assert.ok(
		src.includes('const { run: ownRun, error: runError } = await fetchRunById(pageData.id);'),
		'`ownRun` must be destructured directly from the owner-scoped fetchRunById call.',
	);
});

test('fetchPublicRunAttribution returns no run fields', () => {
	// Reason: the helper exists to answer "may this viewer see it, and whose
	// is it" — nothing else. If it started returning the row, a caller would
	// eventually render `row.track_url` / `row.metadata` from it and bypass
	// RunShareView's clip branch. Pin the projection to `user_id` only.
	const src = read('src/lib/core/data.ts');
	const fn = src.slice(
		src.indexOf('export async function fetchPublicRunAttribution'),
	);
	const body = fn.slice(0, fn.indexOf('\n}\n') + 2);
	assert.match(
		body,
		/\.from\('public_runs'\)\s*\n\s*\.select\('user_id'\)/,
		'fetchPublicRunAttribution must select only user_id from public_runs — widening the projection ' +
			'invites a non-owner render path that skips the privacy-zone clip (decisions §33).',
	);
	assert.doesNotMatch(
		body,
		/track/,
		'fetchPublicRunAttribution must never touch a track — that is fetchClippedTrackForRun’s job.',
	);
});
