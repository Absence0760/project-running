import { test } from 'node:test';
import assert from 'node:assert/strict';

import { supabaseErrorFields } from './supabase_error';

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
