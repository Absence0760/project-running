import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	SettingsWriteError,
	classifyWriteFailure,
	drainQueue,
	failureOf,
	pushOrQueue,
} from './settings_write';

// postgrest-js's fetch catch: no code, status 0, the message prefixed
// with the thrown error's name.
const OFFLINE = {
	error: { message: 'TypeError: Failed to fetch', code: '' },
	status: 0,
};
const RLS_DENIED = {
	error: {
		message: 'new row violates row-level security policy for table "user_settings"',
		code: '42501',
	},
	status: 403,
};
const CHECK_VIOLATION = {
	error: { message: 'new row for relation "user_settings" violates check constraint', code: '23514' },
	status: 400,
};

test('a fetch failure is a transport failure', () => {
	assert.equal(classifyWriteFailure(OFFLINE), 'transport');
	assert.equal(
		classifyWriteFailure({ error: { message: 'FetchError: network timeout' }, status: 0 }),
		'transport',
	);
});

test('a proxy that answered with an unparseable body is still the server rejecting', () => {
	assert.equal(
		classifyWriteFailure({ error: { message: '<html>502 Bad Gateway</html>' }, status: 502 }),
		'rejected',
	);
});

test('every structured PostgREST refusal is a rejection', () => {
	assert.equal(classifyWriteFailure(RLS_DENIED), 'rejected');
	assert.equal(classifyWriteFailure(CHECK_VIOLATION), 'rejected');
	assert.equal(
		classifyWriteFailure({ error: { message: 'JWT expired', code: 'PGRST301' }, status: 401 }),
		'rejected',
	);
});

test('SettingsWriteError carries the server message and its classification', () => {
	const err = new SettingsWriteError(RLS_DENIED);
	assert.equal(err.failure, 'rejected');
	assert.equal(err.code, '42501');
	assert.match(err.message, /row-level security/);
	assert.ok(err instanceof Error);
});

test('an unclassified throw is treated as a rejection, not as being offline', () => {
	assert.equal(failureOf(new Error('boom')), 'rejected');
	assert.equal(failureOf(undefined), 'rejected');
	assert.equal(failureOf(new SettingsWriteError(OFFLINE)), 'transport');
});

test('a transport failure queues the change and resolves', async () => {
	let queued = 0;
	let rolledBack = 0;
	await pushOrQueue({
		push: () => Promise.reject(new SettingsWriteError(OFFLINE)),
		queue: () => (queued += 1),
		rollback: () => (rolledBack += 1),
	});
	assert.equal(queued, 1);
	assert.equal(rolledBack, 0);
});

test('a rejected write rolls back the optimistic cache write, never queues, and rethrows', async () => {
	let queued = 0;
	let rolledBack = 0;
	await assert.rejects(
		pushOrQueue({
			push: () => Promise.reject(new SettingsWriteError(RLS_DENIED)),
			queue: () => (queued += 1),
			rollback: () => (rolledBack += 1),
		}),
		/row-level security/,
	);
	assert.equal(queued, 0, 'a doomed write must not enter the pending queue');
	assert.equal(rolledBack, 1, 'the local bag must not keep a value the server refused');
});

test('a successful write neither queues nor rolls back', async () => {
	let queued = 0;
	let rolledBack = 0;
	await pushOrQueue({
		push: () => Promise.resolve(),
		queue: () => (queued += 1),
		rollback: () => (rolledBack += 1),
	});
	assert.equal(queued, 0);
	assert.equal(rolledBack, 0);
});

test('draining a queue that all lands clears it', async () => {
	const sent: string[] = [];
	const unsent = await drainQueue(['a', 'b', 'c'], async (c) => {
		sent.push(c);
	});
	assert.deepEqual(sent, ['a', 'b', 'c']);
	assert.deepEqual(unsent, []);
});

test('a transport failure mid-drain keeps that entry and everything after it, in order', async () => {
	const sent: string[] = [];
	const unsent = await drainQueue(['a', 'b', 'c'], async (c) => {
		if (c === 'b') throw new SettingsWriteError(OFFLINE);
		sent.push(c);
	});
	assert.deepEqual(sent, ['a']);
	assert.deepEqual(unsent, ['b', 'c']);
});

test('a rejected entry is dropped so it cannot block the queue behind it forever', async () => {
	const sent: string[] = [];
	const unsent = await drainQueue(['a', 'b', 'c'], async (c) => {
		if (c === 'b') throw new SettingsWriteError(RLS_DENIED);
		sent.push(c);
	});
	assert.deepEqual(sent, ['a', 'c']);
	assert.deepEqual(unsent, []);
});
