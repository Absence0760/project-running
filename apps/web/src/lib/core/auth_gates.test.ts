import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MIN_PASSWORD_LENGTH, checkPasswordPair, checkSignUpGates } from './auth_gates.js';

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

// --- checkPasswordPair -------------------------------------------------
//
// The pair check is the only thing standing between a mistyped password
// and an account its owner can never sign into, so the cases below pin
// the contract fairly hard: precedence, exactness, and the boundary.

test('MIN_PASSWORD_LENGTH is 6, matching GoTrue\'s default', () => {
	// config.toml sets no minimum_password_length, so GoTrue's default
	// of 6 governs. The sign-up input's minlength and /auth/reset both
	// hard-code 6 too; if this constant moves, those move with it or a
	// password this helper accepts gets rejected by the auth server.
	assert.equal(MIN_PASSWORD_LENGTH, 6);
});

test('matching passwords over the minimum → ok', () => {
	assert.deepEqual(checkPasswordPair('correct horse', 'correct horse'), { ok: true });
});

test('matching passwords at exactly the minimum → ok (boundary is inclusive)', () => {
	const at = 'a'.repeat(MIN_PASSWORD_LENGTH);
	assert.deepEqual(checkPasswordPair(at, at), { ok: true });
});

test('matching passwords one short of the minimum → too_short', () => {
	const under = 'a'.repeat(MIN_PASSWORD_LENGTH - 1);
	assert.deepEqual(checkPasswordPair(under, under), { ok: false, reason: 'too_short' });
});

test('both fields empty → too_short', () => {
	// The empty pair matches, so without the length check first this
	// would sail through as ok.
	assert.deepEqual(checkPasswordPair('', ''), { ok: false, reason: 'too_short' });
});

test('differing passwords, both long enough → mismatch', () => {
	assert.deepEqual(
		checkPasswordPair('longenough1', 'longenough2'),
		{ ok: false, reason: 'mismatch' },
	);
});

test('too short AND mismatched → too_short wins (length is checked first)', () => {
	// Reporting "passwords do not match" to someone whose real problem
	// is a 3-character password sends them round the loop again. Pins
	// the precedence.
	assert.deepEqual(checkPasswordPair('abc', 'xyz'), { ok: false, reason: 'too_short' });
});

test('valid password, empty confirmation → mismatch', () => {
	// The submit-time shape when the user tabs past the second field.
	assert.deepEqual(checkPasswordPair('longenough', ''), { ok: false, reason: 'mismatch' });
});

test('empty password, filled confirmation → too_short (password is the field being minted)', () => {
	assert.deepEqual(checkPasswordPair('', 'longenough'), { ok: false, reason: 'too_short' });
});

test('comparison is case-sensitive', () => {
	// A stuck caps-lock on one field only is a real way to do this.
	assert.deepEqual(
		checkPasswordPair('Secret123', 'secret123'),
		{ ok: false, reason: 'mismatch' },
	);
});

test('trailing whitespace is significant — not trimmed', () => {
	// The headline reason this helper exists. A trailing space is a
	// real character in a password: trimming would call these equal and
	// then store whichever string the caller passed on, so the user's
	// saved password would differ from what they believe they typed.
	assert.deepEqual(
		checkPasswordPair('secret1 ', 'secret1'),
		{ ok: false, reason: 'mismatch' },
	);
});

test('leading whitespace is significant — not trimmed', () => {
	assert.deepEqual(
		checkPasswordPair(' secret1', 'secret1'),
		{ ok: false, reason: 'mismatch' },
	);
});

test('an all-whitespace password that matches and is long enough → ok', () => {
	// This helper validates the PAIR, not password quality. Strength
	// rules are GoTrue's business; inventing one here would reject a
	// password the auth server would have happily accepted.
	const spaces = ' '.repeat(MIN_PASSWORD_LENGTH);
	assert.deepEqual(checkPasswordPair(spaces, spaces), { ok: true });
});

test('a transposition typo is caught', () => {
	// The concrete real-world case: same characters, two swapped.
	assert.deepEqual(
		checkPasswordPair('runner123', 'runenr123'),
		{ ok: false, reason: 'mismatch' },
	);
});

test('matching non-ASCII passwords → ok, and near-misses still mismatch', () => {
	assert.deepEqual(checkPasswordPair('påssw0rd', 'påssw0rd'), { ok: true });
	assert.deepEqual(
		checkPasswordPair('påssw0rd', 'passw0rd'),
		{ ok: false, reason: 'mismatch' },
	);
});

test('length counts UTF-16 code units, so a short emoji password is accepted', () => {
	// '🏃🏃🏃' is 3 glyphs but 6 code units, so .length clears the
	// minimum. Documented rather than defended: GoTrue measures the
	// same way, so this helper and the auth server agree — which is the
	// property that actually matters.
	const emoji = '🏃🏃🏃';
	assert.equal(emoji.length, MIN_PASSWORD_LENGTH);
	assert.deepEqual(checkPasswordPair(emoji, emoji), { ok: true });
});

test('a long passphrase round-trips', () => {
	const long = 'a-very-long-passphrase-'.repeat(10);
	assert.deepEqual(checkPasswordPair(long, long), { ok: true });
	assert.deepEqual(
		checkPasswordPair(long, long + '!'),
		{ ok: false, reason: 'mismatch' },
	);
});
