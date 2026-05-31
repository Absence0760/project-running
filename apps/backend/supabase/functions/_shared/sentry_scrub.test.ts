import {
	assert,
	assertEquals,
	assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { sanitizeErrorForCapture } from './sentry_scrub.ts';

Deno.test('PostgREST-shaped error is reduced to message + code, dropping details/hint', () => {
	const pgErr = {
		message: 'duplicate key value violates unique constraint "users_email_key"',
		code: '23505',
		details: 'Key (email)=(secret@user.com) already exists.',
		hint: 'some hint with row data',
	};
	const out = sanitizeErrorForCapture(pgErr);
	assert(out instanceof Error, 'should be wrapped in an Error');
	const text = `${(out as Error).name}: ${(out as Error).message}`;
	// Message + SQLSTATE survive for triage.
	assertStringIncludes((out as Error).message, 'duplicate key value');
	assertStringIncludes((out as Error).message, '[23505]');
	// The row-bearing details/hint must NOT appear anywhere on the
	// sanitized error.
	assert(
		!text.includes('secret@user.com'),
		'row value from details must be stripped',
	);
	assert(
		!JSON.stringify(out).includes('secret@user.com'),
		'row value must not survive serialization',
	);
});

Deno.test('a real Error instance passes through unchanged (its stack is the triage value, no row data)', () => {
	const e = new Error('boom');
	assertEquals(sanitizeErrorForCapture(e), e);
});

Deno.test('an arbitrary object without postgrest fields passes through unchanged', () => {
	const o = { foo: 'bar' };
	assertEquals(sanitizeErrorForCapture(o), o);
});

Deno.test('a plain string passes through unchanged', () => {
	assertEquals(sanitizeErrorForCapture('nope'), 'nope');
});

Deno.test('postgrest error with only a code (no details/hint) is still sanitized to a fresh Error', () => {
	const out = sanitizeErrorForCapture({ message: 'permission denied', code: '42501' });
	assert(out instanceof Error);
	assertStringIncludes((out as Error).message, 'permission denied [42501]');
});

Deno.test('postgrest error with details but NO code → message only, no spurious code bracket, details stripped', () => {
	const out = sanitizeErrorForCapture({
		message: 'duplicate key value violates unique constraint',
		details: 'Key (email)=(secret@user.com) already exists.',
	});
	assert(out instanceof Error);
	assertStringIncludes((out as Error).message, 'duplicate key value');
	assert(!(out as Error).message.includes('['), 'no spurious code bracket when code is absent');
	assert(
		!JSON.stringify(out).includes('secret@user.com'),
		'details row value must be stripped',
	);
});
