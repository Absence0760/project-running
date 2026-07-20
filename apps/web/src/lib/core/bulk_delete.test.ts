import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { deleteRunsBounded, DELETE_RUNS_CONCURRENCY } from './bulk_delete';

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
