import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkSignUpGates } from './auth_gates.js';

test('sign-in mode: ok regardless of checkbox state', () => {
	assert.deepEqual(checkSignUpGates(false, false, false), { ok: true });
	assert.deepEqual(checkSignUpGates(false, true, false), { ok: true });
	assert.deepEqual(checkSignUpGates(false, false, true), { ok: true });
	assert.deepEqual(checkSignUpGates(false, true, true), { ok: true });
});

test('sign-up mode: both checkboxes ticked → ok', () => {
	assert.deepEqual(checkSignUpGates(true, true, true), { ok: true });
});

test('sign-up mode: adult checkbox unchecked → fails with adult reason', () => {
	const result = checkSignUpGates(true, false, true);
	assert.deepEqual(result, { ok: false, reason: 'adult' });
});

test('sign-up mode: terms checkbox unchecked → fails with terms reason '
	+ '(adult checked, so terms is the next failing gate)', () => {
	const result = checkSignUpGates(true, true, false);
	assert.deepEqual(result, { ok: false, reason: 'terms' });
});

test('sign-up mode: both unchecked → fails with adult reason first '
	+ '(short-circuit order matters for clear UX)', () => {
	// The user gets one error at a time; the adult gate is the first
	// thing the page checks so it should be what they see if both
	// gates fail. Pins the gate order against future reshuffles.
	const result = checkSignUpGates(true, false, false);
	assert.deepEqual(result, { ok: false, reason: 'adult' });
});
