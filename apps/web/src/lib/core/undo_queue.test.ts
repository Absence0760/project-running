import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	createUndoQueue,
	undoWindowSFromPref,
	DEFAULT_UNDO_WINDOW_S,
	UNDO_WINDOW_CHOICES_S,
	type PendingUndo,
} from './undo_queue.js';

/// Deterministic clock + timer pair. `advance` fires every timer whose
/// deadline has passed, in deadline order, so a re-armed timer created
/// mid-advance still lands correctly.
function harness(windowMs = 8000) {
	let clock = 0;
	let nextHandle = 1;
	const timers = new Map<number, { at: number; cb: () => void }>();
	const published: (PendingUndo | null)[] = [];
	let currentWindowMs = windowMs;

	const queue = createUndoQueue({
		windowMs: () => currentWindowMs,
		setTimer: (cb, ms) => {
			const handle = nextHandle++;
			timers.set(handle, { at: clock + ms, cb });
			return handle;
		},
		clearTimer: (handle) => {
			timers.delete(handle as number);
		},
		now: () => clock,
		onChange: (pending) => published.push(pending),
	});

	async function advance(ms: number) {
		const target = clock + ms;
		for (;;) {
			let due: [number, { at: number; cb: () => void }] | null = null;
			for (const entry of timers) {
				if (entry[1].at <= target && (due === null || entry[1].at < due[1].at)) due = entry;
			}
			if (due === null) break;
			clock = due[1].at;
			timers.delete(due[0]);
			due[1].cb();
			// Let the awaited commit() inside flush() settle.
			await Promise.resolve();
			await Promise.resolve();
		}
		clock = target;
	}

	return {
		queue,
		published,
		advance,
		armedTimers: () => timers.size,
		setWindowMs: (ms: number) => {
			currentWindowMs = ms;
		},
		tick: (ms: number) => {
			clock += ms;
		},
	};
}

function spy() {
	const calls: unknown[][] = [];
	const fn = (...args: unknown[]) => {
		calls.push(args);
	};
	return { fn, calls, get count() { return calls.length; } };
}

// ---------------------------------------------------------------------------
// The central contract: nothing is destroyed while undo is on offer
// ---------------------------------------------------------------------------

test('defer holds the mutation — commit has not run when the bar appears', () => {
	const h = harness();
	const commit = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: () => {} });
	assert.equal(commit.count, 0);
	assert.equal(h.queue.hasPending(), true);
	assert.deepEqual(h.published.at(-1), { id: 1, message: 'Removed', windowMs: 8000, paused: false });
});

test('undo cancels the pending mutation entirely — commit never runs, restore does', () => {
	const h = harness();
	const commit = spy();
	const restore = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: restore.fn });
	h.queue.undo();
	assert.equal(commit.count, 0);
	assert.equal(restore.count, 1);
	assert.equal(h.queue.hasPending(), false);
	assert.equal(h.published.at(-1), null);
	assert.equal(h.armedTimers(), 0);
});

test('the window elapsing commits, and does NOT restore', async () => {
	const h = harness();
	const commit = spy();
	const restore = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: restore.fn });
	await h.advance(7999);
	assert.equal(commit.count, 0);
	await h.advance(1);
	assert.equal(commit.count, 1);
	assert.equal(restore.count, 0);
	assert.equal(h.queue.hasPending(), false);
});

test('a failed commit restores the caller state and reports the error', async () => {
	const h = harness();
	const restore = spy();
	const onCommitError = spy();
	const boom = new Error('23503');
	h.queue.defer({
		message: 'Removed',
		commit: async () => {
			throw boom;
		},
		restore: restore.fn,
		onCommitError: onCommitError.fn,
	});
	await h.advance(8000);
	assert.equal(restore.count, 1);
	assert.deepEqual(onCommitError.calls, [[boom]]);
});

// ---------------------------------------------------------------------------
// One slot
// ---------------------------------------------------------------------------

test('a second destruction commits the first immediately and takes the slot', async () => {
	const h = harness();
	const firstCommit = spy();
	const secondCommit = spy();
	const firstRestore = spy();
	h.queue.defer({ message: 'One', commit: async () => firstCommit.fn(), restore: firstRestore.fn });
	h.queue.defer({ message: 'Two', commit: async () => secondCommit.fn(), restore: () => {} });
	await Promise.resolve();
	assert.equal(firstCommit.count, 1, 'the displaced entry commits');
	assert.equal(firstRestore.count, 0, 'and is not restored — the user did not undo it');
	assert.equal(secondCommit.count, 0);
	assert.equal((h.published.at(-1) as PendingUndo).message, 'Two');
	assert.equal(h.armedTimers(), 1, 'the displaced timer was disarmed');
});

test('undo after the window closed is a no-op — a stale click cannot double-fire', async () => {
	const h = harness();
	const commit = spy();
	const restore = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: restore.fn });
	await h.advance(8000);
	h.queue.undo();
	assert.equal(commit.count, 1);
	assert.equal(restore.count, 0, 'the row is genuinely gone — undo must not claim otherwise');
});

test('flush is idempotent and a no-op with nothing pending', async () => {
	const h = harness();
	const commit = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: () => {} });
	await h.queue.flush();
	await h.queue.flush();
	assert.equal(commit.count, 1);
});

// ---------------------------------------------------------------------------
// WCAG 2.2.1 — pause while the bar has hover/focus, and turn the limit off
// ---------------------------------------------------------------------------

test('pause disarms the timer; resume re-arms with only the remaining time', async () => {
	const h = harness();
	const commit = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: () => {} });
	await h.advance(3000);
	h.queue.pause();
	assert.equal(h.armedTimers(), 0);
	assert.equal((h.published.at(-1) as PendingUndo).paused, true);

	// A long hover must not consume any of the window.
	h.tick(60_000);
	assert.equal(commit.count, 0);

	h.queue.resume();
	assert.equal((h.published.at(-1) as PendingUndo).paused, false);
	await h.advance(4999);
	assert.equal(commit.count, 0, '5 s of the 8 s window remained');
	await h.advance(1);
	assert.equal(commit.count, 1);
});

test('pause/resume keep the published id and windowMs stable so the bar animation does not restart', async () => {
	const h = harness();
	h.queue.defer({ message: 'Removed', commit: async () => {}, restore: () => {} });
	await h.advance(2000);
	h.queue.pause();
	h.queue.resume();
	const ids = h.published.filter((p) => p !== null).map((p) => (p as PendingUndo).id);
	assert.deepEqual(ids, [1, 1, 1]);
	for (const p of h.published) {
		if (p !== null) assert.equal(p.windowMs, 8000);
	}
});

test('a zero window arms no timer at all — the limit is off until dismiss or undo', async () => {
	const h = harness();
	h.setWindowMs(0);
	const commit = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: () => {} });
	assert.equal(h.armedTimers(), 0);
	assert.equal((h.published.at(-1) as PendingUndo).windowMs, 0);
	await h.advance(10 * 60_000);
	assert.equal(commit.count, 0, 'ten minutes later it is still undoable');
	await h.queue.flush();
	assert.equal(commit.count, 1);
});

test('pause and resume are inert when there is no time limit to pause', () => {
	const h = harness();
	h.setWindowMs(0);
	h.queue.defer({ message: 'Removed', commit: async () => {}, restore: () => {} });
	h.queue.pause();
	h.queue.resume();
	assert.equal((h.published.at(-1) as PendingUndo).paused, false);
});

test('a negative window is clamped to no-limit rather than firing instantly', () => {
	const h = harness();
	h.setWindowMs(-5000);
	const commit = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: () => {} });
	assert.equal(h.armedTimers(), 0);
	assert.equal(commit.count, 0);
});

// ---------------------------------------------------------------------------
// undoWindowSFromPref — the stored preference
// ---------------------------------------------------------------------------

test('undoWindowSFromPref: every offered choice round-trips', () => {
	for (const choice of UNDO_WINDOW_CHOICES_S) {
		assert.equal(undoWindowSFromPref(choice), choice);
	}
});

test('undoWindowSFromPref: absent or corrupt values fall back to the default, never to no-limit', () => {
	for (const raw of [undefined, null, '8', '', {}, [], NaN, Infinity, 7, -1, 3600]) {
		assert.equal(undoWindowSFromPref(raw), DEFAULT_UNDO_WINDOW_S);
	}
});
