import { test } from 'node:test';
import assert from 'node:assert/strict';

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { supabaseErrorFields, isDuplicateKeyError } from './supabase_error';
import { stripComments } from './strip_comments';

test('supabaseErrorFields keeps only code + message, drops details/hint', () => {
	// Reason: the server handlers log Supabase errors on paths carrying
	// Art 9 health/injury chat (coach) and precise location (routes). A
	// raw PostgrestError carries `.details` and `.hint`, which can echo
	// row fragments — the caller's chat content, emails, injury free
	// text — straight into CloudWatch. This helper is the scrub every
	// log site routes through; pin that it never carries the leaky
	// fields through. /audit/pii-in-logs.
	const raw = {
		code: '23505',
		message: 'duplicate key value violates unique constraint',
		details: "Key (user_id, content)=(uuid, 'left knee ITB flare, DNF at mile 62') already exists.",
		hint: 'runner@example.com',
	};
	const safe = supabaseErrorFields(raw);
	assert.deepEqual(safe, {
		code: '23505',
		message: 'duplicate key value violates unique constraint',
	});
	// The scrubbed object, serialised the way console.error would emit
	// it, must not carry any PII fragment from details/hint.
	const serialised = JSON.stringify(safe);
	assert.doesNotMatch(serialised, /ITB flare/);
	assert.doesNotMatch(serialised, /runner@example\.com/);
	assert.doesNotMatch(serialised, /details|hint/);
});

test('supabaseErrorFields tolerates null / undefined / empty errors', () => {
	assert.deepEqual(supabaseErrorFields(null), { code: undefined, message: undefined });
	assert.deepEqual(supabaseErrorFields(undefined), { code: undefined, message: undefined });
	assert.deepEqual(supabaseErrorFields({}), { code: undefined, message: undefined });
});

test('isDuplicateKeyError matches 23505 and nothing else', () => {
	// Reason: this is the predicate that turns a double-tapped Join into a
	// no-op. Widening it would swallow a real failure — 23503 is a dangling
	// FK, 23514 a CHECK the row genuinely violates, 42501 an RLS refusal —
	// and each of those must still reach the caller as a failure.
	assert.equal(isDuplicateKeyError({ code: '23505' }), true);
	for (const code of ['23503', '23514', '23502', '42501', 'PGRST116', '', '2350']) {
		assert.equal(
			isDuplicateKeyError({ code }),
			false,
			`${code} is not a unique violation and must not be absorbed`,
		);
	}
	assert.equal(isDuplicateKeyError(null), false);
	assert.equal(isDuplicateKeyError(undefined), false);
	assert.equal(isDuplicateKeyError({}), false);
	assert.equal(isDuplicateKeyError({ code: null }), false);
});

test('every join-shaped write in data.ts absorbs a duplicate through the one predicate', () => {
	// Reason: five writes hand-rolled `error.code !== '23505'` and a sixth —
	// joinChallenge — never got it, so the (challenge_id, user_id) primary key
	// turned a double-tap on Join into a raw failure toast for the state the
	// user had already reached. A comparison copied to each site is a
	// comparison that can be missed at a site; there is now one predicate, and
	// no site may restate the literal.
	const source = readFileSync(resolve('src/lib/core/data.ts'), 'utf-8');
	const stripped = stripComments(source);
	assert.doesNotMatch(
		stripped,
		/'23505'/,
		"data.ts must test for a duplicate through isDuplicateKeyError, not by restating '23505'",
	);
	for (const fn of [
		'bookmarkRoute',
		'joinClub',
		'followUser',
		'joinChallenge',
	]) {
		const start = stripped.indexOf(`export async function ${fn}(`);
		assert.ok(start > 0, `${fn} not found — rename it here too.`);
		const body = stripped.slice(start, stripped.indexOf('\nexport ', start + 1));
		assert.match(
			body,
			/isDuplicateKeyError\(/,
			`${fn} must absorb a duplicate insert — re-pressing it is the success case restated.`,
		);
	}
});
