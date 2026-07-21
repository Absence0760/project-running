import { test } from 'node:test';
import assert from 'node:assert/strict';
import { changePassword, type PasswordChangeDeps } from './password_change.js';

/// Every case records whether the account's password was actually
/// written, because the whole point of the helper is that a rotation
/// can't happen without a positive proof of the current password.
function spyDeps(overrides: Partial<PasswordChangeDeps> = {}) {
	const calls: { verified: string[]; updated: string[] } = { verified: [], updated: [] };
	const deps: PasswordChangeDeps = {
		verifyCurrentPassword: async (current) => {
			calls.verified.push(current);
			return current === 'currentpw123';
		},
		updatePassword: async (next) => {
			calls.updated.push(next);
			return { error: null };
		},
		...overrides,
	};
	return { deps, calls };
}

test('correct current password → password is updated', async () => {
	const { deps, calls } = spyDeps();
	const result = await changePassword(
		{ currentPassword: 'currentpw123', newPassword: 'brandnewpw', confirmPassword: 'brandnewpw' },
		deps,
	);
	assert.deepEqual(result, { ok: true });
	assert.deepEqual(calls.verified, ['currentpw123']);
	assert.deepEqual(calls.updated, ['brandnewpw']);
});

test('wrong current password → rejected and nothing is written', async () => {
	const { deps, calls } = spyDeps();
	const result = await changePassword(
		{ currentPassword: 'notmypassword', newPassword: 'brandnewpw', confirmPassword: 'brandnewpw' },
		deps,
	);
	assert.deepEqual(result, { ok: false, reason: 'current_invalid' });
	assert.deepEqual(calls.updated, []);
});

test('empty current password → rejected before any verification call', async () => {
	const { deps, calls } = spyDeps();
	const result = await changePassword(
		{ currentPassword: '', newPassword: 'brandnewpw', confirmPassword: 'brandnewpw' },
		deps,
	);
	assert.deepEqual(result, { ok: false, reason: 'current_missing' });
	assert.deepEqual(calls.verified, []);
	assert.deepEqual(calls.updated, []);
});

test('a verification that throws fails closed — no update', async () => {
	// Offline, a 500 from GoTrue, a rate-limit rejection: none of those
	// are proof, so none of them may fall through to the write.
	const { deps, calls } = spyDeps({
		verifyCurrentPassword: async () => {
			throw new Error('Failed to fetch');
		},
	});
	const result = await changePassword(
		{ currentPassword: 'currentpw123', newPassword: 'brandnewpw', confirmPassword: 'brandnewpw' },
		deps,
	);
	assert.deepEqual(result, { ok: false, reason: 'current_invalid' });
	assert.deepEqual(calls.updated, []);
});

test('mismatched new entries are rejected before the current password is sent', async () => {
	// The pair check is free and local; running it first keeps a typo in
	// the new field from burning a sign-in attempt against the rate limit.
	const { deps, calls } = spyDeps();
	const result = await changePassword(
		{ currentPassword: 'currentpw123', newPassword: 'brandnewpw', confirmPassword: 'brandnewpx' },
		deps,
	);
	assert.deepEqual(result, { ok: false, reason: 'mismatch' });
	assert.deepEqual(calls.verified, []);
});

test('a too-short new password reports length, not mismatch', async () => {
	const { deps } = spyDeps();
	const result = await changePassword(
		{ currentPassword: 'currentpw123', newPassword: 'abc', confirmPassword: 'xyz' },
		deps,
	);
	assert.deepEqual(result, { ok: false, reason: 'too_short' });
});

test('a failed update surfaces the provider message', async () => {
	const { deps } = spyDeps({
		updatePassword: async () => ({ error: 'New password should be different from the old password.' }),
	});
	const result = await changePassword(
		{ currentPassword: 'currentpw123', newPassword: 'brandnewpw', confirmPassword: 'brandnewpw' },
		deps,
	);
	assert.deepEqual(result, {
		ok: false,
		reason: 'update_failed',
		detail: 'New password should be different from the old password.',
	});
});
