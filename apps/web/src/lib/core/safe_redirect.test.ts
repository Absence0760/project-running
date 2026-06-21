import { test } from 'node:test';
import assert from 'node:assert/strict';
import { safeReturnTo, DEFAULT_RETURN_TO } from './safe_redirect.js';

test('null / undefined / empty falls back to /dashboard', () => {
	assert.equal(safeReturnTo(null), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo(undefined), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo(''), DEFAULT_RETURN_TO);
});

test('plain internal paths pass through unchanged', () => {
	assert.equal(safeReturnTo('/dashboard'), '/dashboard');
	assert.equal(safeReturnTo('/runs/abc-123'), '/runs/abc-123');
	assert.equal(safeReturnTo('/settings/account'), '/settings/account');
});

test('preserves query string and hash', () => {
	assert.equal(safeReturnTo('/social?tab=feed'), '/social?tab=feed');
	assert.equal(safeReturnTo('/u/me?tab=notifications#top'), '/u/me?tab=notifications#top');
});

test('open-redirect: protocol-relative // is rejected', () => {
	assert.equal(safeReturnTo('//evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('//evil.com/phish'), DEFAULT_RETURN_TO);
});

test('open-redirect: backslash confusion is rejected', () => {
	// Browsers normalise '\' to '/', so '/\evil.com' resolves off-origin.
	assert.equal(safeReturnTo('/\\evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('/\\/evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('\\\\evil.com'), DEFAULT_RETURN_TO);
});

test('open-redirect: absolute URLs are rejected', () => {
	assert.equal(safeReturnTo('https://evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('http://evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('javascript:alert(1)'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('data:text/html,<script>'), DEFAULT_RETURN_TO);
});

test('open-redirect: a non-slash relative path is rejected', () => {
	// 'evil.com' resolves to https://internal.invalid/evil.com which is
	// same-origin, but it is not a root-relative path the app would ever
	// emit — reject it to keep the contract "must start with /".
	assert.equal(safeReturnTo('evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('dashboard'), DEFAULT_RETURN_TO);
});

test('custom fallback is honoured', () => {
	assert.equal(safeReturnTo(null, '/login'), '/login');
	assert.equal(safeReturnTo('//evil.com', '/login'), '/login');
});
