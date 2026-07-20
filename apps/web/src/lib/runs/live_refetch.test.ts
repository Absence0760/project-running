import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CoalescingRefetcher, DEFAULT_REFETCH_DEBOUNCE_MS } from './live_refetch';

/// A hand-driven timer seam so the debounce fires only when the test says so.
function fakeTimers() {
	let seq = 0;
	const pending = new Map<number, () => void>();
	return {
		setTimeoutFn: (fn: () => void, _ms: number) => {
			const id = ++seq;
			pending.set(id, fn);
			return id as unknown as ReturnType<typeof setTimeout>;
		},
		clearTimeoutFn: (h: ReturnType<typeof setTimeout>) => {
			pending.delete(h as unknown as number);
		},
		/// Fire every timer still scheduled (the trailing debounce leaves at
		/// most one, since each trigger clears the prior).
		flushTimers: () => {
			const fns = [...pending.values()];
			pending.clear();
			for (const fn of fns) fn();
		},
		pendingCount: () => pending.size
	};
}

const tick = () => new Promise((r) => setImmediate(r));

test('a burst of N triggers coalesces to a single fetch', async () => {
	const t = fakeTimers();
	let fetchCount = 0;
	let applied = 0;
	const r = new CoalescingRefetcher<number>({
		fetch: async () => ++fetchCount,
		apply: () => (applied += 1),
		setTimeoutFn: t.setTimeoutFn,
		clearTimeoutFn: t.clearTimeoutFn
	});

	for (let i = 0; i < 100; i++) r.trigger();
	// Each trigger cleared the prior timer, so exactly one is scheduled.
	assert.equal(t.pendingCount(), 1, 'a burst leaves one trailing timer');

	t.flushTimers();
	await tick();

	assert.equal(fetchCount, 1, '100 pings coalesced to one fetch');
	assert.equal(applied, 1, 'state applied exactly once for the burst');
});

test('an in-flight fetch is not stacked; a trigger during it owes exactly one re-run', async () => {
	const t = fakeTimers();
	let fetchCount = 0;
	const gates: Array<() => void> = [];
	const r = new CoalescingRefetcher<number>({
		fetch: () =>
			new Promise<number>((resolve) => {
				const n = ++fetchCount;
				gates.push(() => resolve(n));
			}),
		apply: () => {},
		setTimeoutFn: t.setTimeoutFn,
		clearTimeoutFn: t.clearTimeoutFn
	});

	// First burst -> one flush -> fetch #1 starts and hangs.
	r.trigger();
	t.flushTimers();
	await tick();
	assert.equal(fetchCount, 1, 'first fetch started');

	// Triggers arriving WHILE fetch #1 is in flight must not stack a second
	// concurrent fetch — they collapse into a single owed re-run.
	r.trigger();
	r.trigger();
	t.flushTimers();
	await tick();
	assert.equal(fetchCount, 1, 'no concurrent fetch stacked while one is in flight');

	// Resolve fetch #1 -> the single owed re-run fires.
	gates[0]();
	await tick();
	assert.equal(fetchCount, 2, 'exactly one owed re-run after the in-flight fetch settled');

	gates[1]();
	await tick();
	assert.equal(fetchCount, 2, 'no further fetch once the queue drains');
});

test('an out-of-order stale resolution does not overwrite fresher state', async () => {
	let resolveOld: (v: string) => void = () => {};
	let resolveNew: (v: string) => void = () => {};
	let call = 0;
	const applied: string[] = [];
	const r = new CoalescingRefetcher<string>({
		fetch: () =>
			new Promise<string>((resolve) => {
				call += 1;
				if (call === 1) resolveOld = resolve;
				else resolveNew = resolve;
			}),
		apply: (v) => applied.push(v)
	});

	// Force two concurrent fetches via runNow (the guard must hold even if the
	// in-flight latch is bypassed). seq1 is older, seq2 is newer.
	const p1 = r.runNow();
	const p2 = r.runNow();

	// The NEWER fetch resolves first and is applied.
	resolveNew('fresh');
	await p2;
	assert.deepEqual(applied, ['fresh'], 'newest resolution applied');

	// The older fetch resolves LATE — it must be discarded, not applied over
	// the fresher snapshot.
	resolveOld('stale');
	await p1;
	assert.deepEqual(applied, ['fresh'], 'stale resolution discarded by the sequence guard');
});

test('a stale rejection is swallowed; only the newest fetch reports an error', async () => {
	let rejectOld: (e: unknown) => void = () => {};
	let resolveNew: (v: string) => void = () => {};
	let call = 0;
	const errors: unknown[] = [];
	const applied: string[] = [];
	const r = new CoalescingRefetcher<string>({
		fetch: () =>
			new Promise<string>((resolve, reject) => {
				call += 1;
				if (call === 1) rejectOld = reject;
				else resolveNew = resolve;
			}),
		apply: (v) => applied.push(v),
		onError: (e) => errors.push(e)
	});

	const p1 = r.runNow();
	const p2 = r.runNow();

	resolveNew('fresh');
	await p2;
	rejectOld(new Error('boom'));
	await p1;

	assert.deepEqual(applied, ['fresh']);
	assert.equal(errors.length, 0, 'a superseded rejection never surfaces over fresher state');
});

test('the default debounce matches the ~5s ping cadence budget', () => {
	assert.equal(DEFAULT_REFETCH_DEBOUNCE_MS, 750);
});
