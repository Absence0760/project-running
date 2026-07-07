import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createReadyGate, isAuthSettled } from './auth_ready.js';

// ---------------------------------------------------------------------------
// isAuthSettled — the terminal-state predicate
// ---------------------------------------------------------------------------

test('isAuthSettled: still loading is never settled', () => {
	assert.equal(isAuthSettled({ loading: true, user: null, loggedIn: false }), false);
	assert.equal(isAuthSettled({ loading: true, user: { id: 'x' }, loggedIn: true }), false);
});

test('isAuthSettled: loaded with a user row is settled', () => {
	assert.equal(isAuthSettled({ loading: false, user: { id: 'x' }, loggedIn: true }), true);
});

test('isAuthSettled: loaded + definitively anon is settled', () => {
	assert.equal(isAuthSettled({ loading: false, user: null, loggedIn: false }), true);
});

test('isAuthSettled: logged-in but profile not yet hydrated is NOT settled', () => {
	// The exact auth-race window the poll loop was guarding: the session
	// check finished (loading=false, loggedIn=true) but fetchUser hasn't
	// populated `user` yet.
	assert.equal(isAuthSettled({ loading: false, user: null, loggedIn: true }), false);
});

// ---------------------------------------------------------------------------
// createReadyGate — resolves on settle, falls back on timeout
// ---------------------------------------------------------------------------

test('ready(): resolves immediately when already settled', async () => {
	const gate = createReadyGate({ isSettled: () => true, timeoutMs: 9999, setTimeoutFn: () => 0 });
	await gate.ready();
});

test('ready(): a waiter resolves once markSettled flips settled', async () => {
	let settled = false;
	const gate = createReadyGate({
		isSettled: () => settled,
		timeoutMs: 9999,
		setTimeoutFn: () => 0, // disable the timeout fallback for this test
	});

	let resolved = false;
	const p = gate.ready().then(() => {
		resolved = true;
	});

	// Not settled yet → the waiter is still pending.
	await Promise.resolve();
	assert.equal(resolved, false);

	// markSettled while still unsettled is a no-op (re-checks isSettled).
	gate.markSettled();
	await Promise.resolve();
	assert.equal(resolved, false);

	// Flip to settled, then signal — the waiter must resolve.
	settled = true;
	gate.markSettled();
	await p;
	assert.equal(resolved, true);
});

test('ready(): resolves via the timeout fallback if settle never fires', async () => {
	let fired: (() => void) | null = null;
	const gate = createReadyGate({
		isSettled: () => false, // never settles
		timeoutMs: 1234,
		setTimeoutFn: (cb, ms) => {
			assert.equal(ms, 1234);
			fired = cb;
			return 0;
		},
	});

	let resolved = false;
	const p = gate.ready().then(() => {
		resolved = true;
	});

	await Promise.resolve();
	assert.equal(resolved, false);
	assert.notEqual(fired, null);

	// Trip the timeout — the waiter resolves even though it never settled.
	fired!();
	await p;
	assert.equal(resolved, true);
});

test('ready(): an unsettled lifecycle event extends the deadline instead of bailing', async () => {
	let settled = false;
	const timers: Array<() => void> = [];
	const gate = createReadyGate({
		isSettled: () => settled,
		timeoutMs: 1000,
		setTimeoutFn: (cb) => {
			timers.push(cb);
			return 0;
		},
	});

	let resolved = false;
	const p = gate.ready().then(() => {
		resolved = true;
	});
	await Promise.resolve();
	assert.equal(timers.length, 1);

	// A lifecycle event lands while still unsettled (session known, profile
	// fetch in flight) — progress, not settlement.
	gate.markSettled();

	// The armed timer fires: because progress happened since it was armed,
	// the waiter re-arms rather than resolving unsettled.
	timers[0]();
	await Promise.resolve();
	assert.equal(resolved, false);
	assert.equal(timers.length, 2);

	// Settlement arrives before the re-armed timer — the waiter resolves
	// via flush, and the stale timer firing later is a no-op.
	settled = true;
	gate.markSettled();
	await p;
	assert.equal(resolved, true);
	timers[1]();
});

test('ready(): a quiet gap after progress still hits the timeout bound', async () => {
	const timers: Array<() => void> = [];
	const gate = createReadyGate({
		isSettled: () => false,
		timeoutMs: 1000,
		setTimeoutFn: (cb) => {
			timers.push(cb);
			return 0;
		},
	});

	let resolved = false;
	const p = gate.ready().then(() => {
		resolved = true;
	});
	await Promise.resolve();

	gate.markSettled(); // progress while unsettled
	timers[0](); // extended once
	await Promise.resolve();
	assert.equal(resolved, false);

	// No further events: the re-armed timer fires with an unchanged epoch
	// and the waiter bails — a wedged init still can't hang the page.
	timers[1]();
	await p;
	assert.equal(resolved, true);
});
