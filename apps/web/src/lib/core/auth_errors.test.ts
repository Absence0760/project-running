import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classifyAuthError, authErrorMessageKey } from './auth_errors.js';

/// Duck-typed stand-in for supabase-js's `AuthApiError` (carries `code`
/// + `status`) so the classifier can be exercised without importing the
/// supabase auth types. Mirrors `_FakeAuthException` in mobile's
/// auth_error_test.dart.
function authError(message: string, opts: { code?: string; status?: number } = {}) {
	return { message, code: opts.code, status: opts.status };
}

test('fetch failure → offline', () => {
	assert.equal(classifyAuthError(new TypeError('Failed to fetch')), 'offline');
	assert.equal(classifyAuthError(new TypeError('NetworkError when attempting to fetch')), 'offline');
	// Safari's wording for the same condition.
	assert.equal(classifyAuthError(new TypeError('Load failed')), 'offline');
});

test('invalid_credentials code → invalidCredentials', () => {
	assert.equal(
		classifyAuthError(authError('Invalid login credentials', { code: 'invalid_credentials', status: 400 })),
		'invalidCredentials'
	);
});

test('"Invalid login credentials" message (no code) → invalidCredentials', () => {
	assert.equal(classifyAuthError(authError('Invalid login credentials')), 'invalidCredentials');
});

test('status 429 → rateLimited', () => {
	assert.equal(classifyAuthError(authError('Too many requests', { status: 429 })), 'rateLimited');
});

test('over_email_send_rate_limit code → rateLimited', () => {
	assert.equal(
		classifyAuthError(
			authError('For security purposes, you can only request this after 60 seconds', {
				code: 'over_email_send_rate_limit'
			})
		),
		'rateLimited'
	);
});

test('user_already_exists code → emailExists', () => {
	assert.equal(
		classifyAuthError(authError('User already registered', { code: 'user_already_exists', status: 422 })),
		'emailExists'
	);
});

test('"already registered" message (no code) → emailExists', () => {
	assert.equal(classifyAuthError(authError('User already registered')), 'emailExists');
});

test('email_not_confirmed code → emailNotConfirmed', () => {
	assert.equal(
		classifyAuthError(authError('Email not confirmed', { code: 'email_not_confirmed', status: 400 })),
		'emailNotConfirmed'
	);
});

test('weak_password code → weakPassword', () => {
	assert.equal(
		classifyAuthError(
			authError('Password should be at least 8 characters', { code: 'weak_password', status: 422 })
		),
		'weakPassword'
	);
});

test('"password should be at least" message (no code) → weakPassword', () => {
	assert.equal(classifyAuthError(authError('Password should be at least 6 characters')), 'weakPassword');
});

test('unrecognised error → generic', () => {
	assert.equal(classifyAuthError(new Error('boom')), 'generic');
});

test('null / undefined / non-error values → generic, never throw', () => {
	assert.equal(classifyAuthError(null), 'generic');
	assert.equal(classifyAuthError(undefined), 'generic');
	assert.equal(classifyAuthError('boom'), 'generic');
});

test('every kind maps to a distinct message key', () => {
	const kinds = [
		'offline',
		'invalidCredentials',
		'rateLimited',
		'emailExists',
		'emailNotConfirmed',
		'weakPassword',
		'generic'
	] as const;
	const keys = kinds.map(authErrorMessageKey);
	assert.equal(new Set(keys).size, kinds.length);
	// No key resolves to the raw-jargon fallback path.
	for (const key of keys) assert.match(key, /^login\.error/);
});
