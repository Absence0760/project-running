import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	COACH_BODY_LIMIT_BYTES,
	checkBodyByteLimit,
	decodeLambdaBody,
} from './coach/body';

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
