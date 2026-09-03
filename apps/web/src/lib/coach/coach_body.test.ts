import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	COACH_BODY_LIMIT_BYTES,
	checkBodyByteLimit,
	decodeLambdaBody,
} from './body';

test('decodeLambdaBody — plain ASCII body under the cap passes', () => {
	const result = decodeLambdaBody('{"hello":"world"}', false);
	assert.equal(result.ok, true);
	if (result.ok) {
		assert.equal(result.body, '{"hello":"world"}');
	}
});

test('decodeLambdaBody — base64-encoded body decodes to UTF-8', () => {
	const original = '{"x":"y"}';
	const encoded = Buffer.from(original, 'utf8').toString('base64');
	const result = decodeLambdaBody(encoded, true);
	assert.equal(result.ok, true);
	if (result.ok) assert.equal(result.body, original);
});

test('decodeLambdaBody — null body decodes to empty string', () => {
	const result = decodeLambdaBody(null, false);
	assert.equal(result.ok, true);
	if (result.ok) assert.equal(result.body, '');
});

test('decodeLambdaBody — body exactly at the cap is accepted', () => {
	const ascii = 'x'.repeat(COACH_BODY_LIMIT_BYTES);
	const result = decodeLambdaBody(ascii, false);
	assert.equal(result.ok, true);
});

test('decodeLambdaBody — body one byte over the cap is rejected with 413', () => {
	const ascii = 'x'.repeat(COACH_BODY_LIMIT_BYTES + 1);
	const result = decodeLambdaBody(ascii, false);
	assert.equal(result.ok, false);
	if (!result.ok) {
		assert.equal(result.status, 413);
		assert.equal(result.error, 'request too large');
	}
});

test(
	'decodeLambdaBody — multi-byte UTF-8 payload is rejected by byte count, ' +
		'not code-unit count (regression: audit/auth May 2026)',
	() => {
		// U+0800–U+FFFF is three UTF-8 bytes per code point but one
		// UTF-16 code unit per character. A payload of ~90K such chars
		// has String#length ~= 90K (under the 256 KB cap if we used
		// .length) but the actual byte size is ~270 KB, well over the cap.
		const triByteChar = 'ࠀ';
		const codeUnits = 90 * 1024;
		const payload = triByteChar.repeat(codeUnits);
		assert.equal(
			payload.length < COACH_BODY_LIMIT_BYTES,
			true,
			'guard: this test only catches a regression when the JS ' +
				'string length is under the cap',
		);
		const utf8Bytes = Buffer.byteLength(payload, 'utf8');
		assert.equal(
			utf8Bytes > COACH_BODY_LIMIT_BYTES,
			true,
			'guard: this test only catches a regression when the UTF-8 ' +
				'byte count is over the cap',
		);
		const result = decodeLambdaBody(payload, false);
		assert.equal(result.ok, false);
		if (!result.ok) assert.equal(result.status, 413);
	},
);

test('decodeLambdaBody — base64 body whose decoded size > cap is rejected', () => {
	// A base64 string of ~340 KB decodes to ~256+ KB binary, exceeding
	// the cap. The check must happen against the *decoded* byte count,
	// not the base64 string length.
	const bin = Buffer.alloc(COACH_BODY_LIMIT_BYTES + 1, 0x41); // 'A'
	const encoded = bin.toString('base64');
	const result = decodeLambdaBody(encoded, true);
	assert.equal(result.ok, false);
	if (!result.ok) assert.equal(result.status, 413);
});

test('decodeLambdaBody — custom limit override is honoured', () => {
	const result = decodeLambdaBody('hello', false, 4);
	assert.equal(result.ok, false);
	if (!result.ok) assert.equal(result.status, 413);
});

test('checkBodyByteLimit — ArrayBuffer at limit accepted', () => {
	const buf = new ArrayBuffer(COACH_BODY_LIMIT_BYTES);
	assert.equal(checkBodyByteLimit(buf).ok, true);
});

test('checkBodyByteLimit — ArrayBuffer over limit returns 413', () => {
	const buf = new ArrayBuffer(COACH_BODY_LIMIT_BYTES + 1);
	const result = checkBodyByteLimit(buf);
	assert.equal(result.ok, false);
	if (!result.ok) assert.equal(result.status, 413);
});

test('checkBodyByteLimit — Uint8Array path mirrors ArrayBuffer path', () => {
	const arr = new Uint8Array(COACH_BODY_LIMIT_BYTES + 1);
	const result = checkBodyByteLimit(arr);
	assert.equal(result.ok, false);
	if (!result.ok) assert.equal(result.status, 413);
});

test('a malformed base64 body is decoded, not refused — the 400 branch is not for that', () => {
	// The filing behind decisions § 968 read the `400 invalid body encoding`
	// branch as dead code, on the grounds that `Buffer.from(s, 'base64')`
	// ignores invalid characters rather than throwing. The first half is right
	// and is measured here: no STRING reaches the branch, whatever it contains.
	for (const raw of ['!!!!not base64!!!!', 'a', 'aGVsbG8', '\0\0', '\uD800', '\u{1F600}ࠀ']) {
		const result = decodeLambdaBody(raw, true);
		assert.equal(result.ok, true, `${JSON.stringify(raw)} was refused as unreadable`);
	}
});

test('a body that is not a string at all IS refused 400, and does not throw', () => {
	// The second half of that filing — "so delete it" — is wrong. The branch is
	// unreachable only through the DECLARED type; the values it defends against
	// are the ones a Lambda event can really carry, because an event body is
	// parsed JSON and nothing at runtime enforces the `string | null` signature.
	// `Buffer.from(123, 'base64')` throws a TypeError, and without the catch it
	// escapes to the wrapper's outer envelope: a client-side malformation
	// answered as a generic 503, logged as `unhandled_error`.
	for (const raw of [123, true, {}, Symbol('x')] as unknown[]) {
		const result = decodeLambdaBody(raw as string, true);
		assert.equal(result.ok, false, `${String(raw)} was accepted as a body`);
		assert.equal(result.ok === false && result.status, 400);
		assert.equal(result.ok === false && result.error, 'invalid body encoding');
	}

	// An ARRAY is the exception and is not a gap: `Buffer.from` reads one as a
	// byte array, so it decodes rather than throwing. Nothing on this path can
	// send one — a Function URL body is a string — and reading `[65, 66]` as
	// `AB` is a defined answer, not a swallowed error.
	assert.equal(decodeLambdaBody([] as unknown as string, true).ok, true);
});
