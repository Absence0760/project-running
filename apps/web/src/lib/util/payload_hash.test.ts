import { test } from 'node:test';
import assert from 'node:assert/strict';
import { payloadSha256Hex } from './payload_hash';

// Vectors are the canonical SHA-256 digests (FIPS 180-4 / `shasum -a
// 256`) of the UTF-8 bytes. The multi-byte case pins that hashing runs
// over encoded bytes, not UTF-16 code units — a body with an accented
// character must produce the same digest CloudFront's origin sees.

test('empty body hashes to the canonical empty-string digest', async () => {
	assert.equal(
		await payloadSha256Hex(''),
		'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
	);
});

test('ascii body matches the FIPS "abc" vector', async () => {
	assert.equal(
		await payloadSha256Hex('abc'),
		'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
	);
});

test('json body hashes byte-for-byte', async () => {
	assert.equal(
		await payloadSha256Hex('{"messages":[]}'),
		'5e4ce7b36ba37b78a5d5f9fd08e6b7b54ba6879d651aa46ec9e1d6fa24ebe30a',
	);
});

test('multi-byte utf-8 hashes over encoded bytes', async () => {
	assert.equal(
		await payloadSha256Hex('pacé'),
		'1802cef992c15cc39955bca82817681141cbf1660eb6f9cbdbbe58c8a26d9159',
	);
});

test('digest is lowercase hex, 64 chars', async () => {
	const hex = await payloadSha256Hex('anything');
	assert.match(hex, /^[0-9a-f]{64}$/);
});
