import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	changePasswordWithReauth,
	requestReauthNonce,
	type ReauthPasswordClient,
} from './password_change.js';

/// A fake `supabase.auth` that records every call. `updateUser` fails the
/// test if invoked before a step-up nonce is supplied — the whole point is
/// that a password change never reaches GoTrue without one.
function fakeClient(overrides?: {
	updateError?: string | null;
	reauthError?: string | null;
}): ReauthPasswordClient & {
	updateCalls: { password: string; nonce: string }[];
	reauthCalls: number;
} {
	const updateCalls: { password: string; nonce: string }[] = [];
	let reauthCalls = 0;
	return {
		updateCalls,
		get reauthCalls() {
			return reauthCalls;
		},
		async reauthenticate() {
			reauthCalls++;
			return { error: overrides?.reauthError ? { message: overrides.reauthError } : null };
		},
		async updateUser(attrs) {
			updateCalls.push(attrs);
			return { error: overrides?.updateError ? { message: overrides.updateError } : null };
		},
	};
}

test('rejects a too-short pair before any step-up or update', async () => {
	const client = fakeClient();
	const res = await changePasswordWithReauth(client, {
		newPassword: 'short',
		confirmPassword: 'short',
		nonce: '123456',
	});
	assert.deepEqual(res, { ok: false, reason: 'pair', pairReason: 'too_short' });
	assert.equal(client.updateCalls.length, 0);
});

test('rejects a mismatched pair before any update', async () => {
	const client = fakeClient();
	const res = await changePasswordWithReauth(client, {
		newPassword: 'longenough1',
		confirmPassword: 'longenough2',
		nonce: '123456',
	});
	assert.deepEqual(res, { ok: false, reason: 'pair', pairReason: 'mismatch' });
	assert.equal(client.updateCalls.length, 0);
});

test('FAIL-CLOSED: a valid pair with NO nonce never calls updateUser', async () => {
	const client = fakeClient();
	const res = await changePasswordWithReauth(client, {
		newPassword: 'longenough1',
		confirmPassword: 'longenough1',
		nonce: '',
	});
	assert.deepEqual(res, { ok: false, reason: 'nonce_required' });
	assert.equal(client.updateCalls.length, 0);
});

test('FAIL-CLOSED: a whitespace-only nonce is treated as absent', async () => {
	const client = fakeClient();
	const res = await changePasswordWithReauth(client, {
		newPassword: 'longenough1',
		confirmPassword: 'longenough1',
		nonce: '   ',
	});
	assert.deepEqual(res, { ok: false, reason: 'nonce_required' });
	assert.equal(client.updateCalls.length, 0);
});

test('with a nonce, updateUser is called with the password + trimmed nonce', async () => {
	const client = fakeClient();
	const res = await changePasswordWithReauth(client, {
		newPassword: 'longenough1',
		confirmPassword: 'longenough1',
		nonce: ' 123456 ',
	});
	assert.deepEqual(res, { ok: true });
	assert.equal(client.updateCalls.length, 1);
	assert.deepEqual(client.updateCalls[0], { password: 'longenough1', nonce: '123456' });
});

test('a GoTrue update error (e.g. bad nonce) surfaces and does not report success', async () => {
	const client = fakeClient({ updateError: 'Reauthentication needs a valid nonce' });
	const res = await changePasswordWithReauth(client, {
		newPassword: 'longenough1',
		confirmPassword: 'longenough1',
		nonce: '000000',
	});
	assert.deepEqual(res, {
		ok: false,
		reason: 'update_failed',
		message: 'Reauthentication needs a valid nonce',
	});
	assert.equal(client.updateCalls.length, 1);
});

test('requestReauthNonce succeeds and calls reauthenticate once', async () => {
	const client = fakeClient();
	const res = await requestReauthNonce(client);
	assert.deepEqual(res, { ok: true });
	assert.equal(client.reauthCalls, 1);
});

test('requestReauthNonce surfaces a send error', async () => {
	const client = fakeClient({ reauthError: 'rate limited' });
	const res = await requestReauthNonce(client);
	assert.deepEqual(res, { ok: false, message: 'rate limited' });
});
