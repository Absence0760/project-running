import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { deleteRunsBounded, DELETE_RUNS_CONCURRENCY } from './bulk_delete';
import { stripComments } from './strip_comments';

function makeTracker(rejectIds: Set<string> = new Set()) {
	let inFlight = 0;
	let peak = 0;
	const calls: string[] = [];
	const fn = async (id: string): Promise<void> => {
		inFlight++;
		if (inFlight > peak) peak = inFlight;
		calls.push(id);
		await new Promise((r) => setTimeout(r, 5));
		inFlight--;
		if (rejectIds.has(id)) throw new Error(`boom ${id}`);
	};
	return { fn, calls, peak: () => peak };
}

const ids = (n: number) => Array.from({ length: n }, (_, i) => `run-${i}`);

test('deleteRunsBounded never exceeds the concurrency cap in flight', async () => {
	const t = makeTracker();
	const cap = 4;
	const all = ids(20);
	const { failed } = await deleteRunsBounded(all, t.fn, cap);
	// Peak simultaneous in-flight deletes must stay within the cap — the
	// whole point of issue #343 (an unbounded fan-out would peak at 20).
	assert.ok(t.peak() <= cap, `peak ${t.peak()} exceeded cap ${cap}`);
	// And the cap is actually saturated (waves fill), not accidentally
	// serialised — otherwise the bound would be vacuously true.
	assert.equal(t.peak(), cap);
	// Every id is still processed exactly once.
	assert.equal(t.calls.length, 20);
	assert.deepEqual([...t.calls].sort(), [...all].sort());
	assert.deepEqual(failed, []);
});

test('an UNBOUNDED fan-out peaks at N — proving the harness detects the bound', async () => {
	// Same instrumented fn, but fired all-at-once the way the old
	// `deleteRuns` did. This is the "fails before" sentinel: the peak
	// equals the id count, which the bounded test above forbids.
	const t = makeTracker();
	const all = ids(20);
	await Promise.allSettled(all.map((id) => t.fn(id)));
	assert.equal(t.peak(), 20);
});

test('deleteRunsBounded preserves allSettled semantics — one failure does not abort the rest', async () => {
	const all = ids(10);
	const rejects = new Set(['run-2', 'run-7']);
	const t = makeTracker(rejects);
	const { failed } = await deleteRunsBounded(all, t.fn, 3);
	// Every id was attempted despite the two rejections.
	assert.equal(t.calls.length, 10);
	assert.deepEqual([...failed].sort(), ['run-2', 'run-7']);
});

test('deleteRunsBounded handles an empty id list without calling deleteFn', async () => {
	const t = makeTracker();
	const { failed } = await deleteRunsBounded([], t.fn);
	assert.deepEqual(failed, []);
	assert.equal(t.calls.length, 0);
});

test('the shipped cap is a sane bounded value', () => {
	assert.ok(DELETE_RUNS_CONCURRENCY >= 1 && DELETE_RUNS_CONCURRENCY <= 16);
});

test('the /runs bulk delete reconciles the list against the ids it issued', () => {
	// `deleteRunsBounded` is deliberately slow-and-partial: waves of up to
	// DELETE_RUNS_CONCURRENCY, several round trips per run, `allSettled` so one
	// failure does not abort the rest. A 200-run delete therefore runs for many
	// seconds, and the /runs cards stay tappable the whole time — only the
	// Delete button is disabled. The page filtered its in-memory list against
	// the LIVE `selected` set, so a tap mid-flight rewrote the reconciliation:
	// un-selecting a run already gone from the server left a ghost card that
	// 404s on tap, and selecting another removed a run that still exists. The
	// captured `ids` are what the server was actually asked about.
	const page = stripComments(
		readFileSync(resolve(import.meta.dirname, '../../routes/runs/+page.svelte'), 'utf-8'),
	);
	const start = page.indexOf('async function handleBulkDelete(');
	assert.ok(start >= 0, 'handleBulkDelete moved — re-anchor this guard');
	const body = page.slice(start, page.indexOf('\n\t}', start));
	assert.match(
		body,
		/const ids = Array\.from\(selected\);/,
		'the selection is captured once, before the await',
	);
	assert.doesNotMatch(
		body,
		/runs\.filter\([^)]*selected\.has/,
		'the list must not be reconciled against the live selection — it can change mid-delete',
	);
	assert.match(
		body,
		/runs = runs\.filter\(\(r\) => failedSet\.has\(r\.id\) \|\| !requested\.has\(r\.id\)\);/,
		'reconcile against the captured ids, keeping only the ones that failed',
	);
});
