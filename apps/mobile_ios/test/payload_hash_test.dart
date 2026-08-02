import 'package:flutter_test/flutter_test.dart';

import '../lib/payload_hash.dart';

// Vectors are the canonical SHA-256 digests (FIPS 180-4 / `shasum -a
// 256`) of the UTF-8 bytes, mirroring the web twin's
// payload_hash.test.ts. The multi-byte case pins that hashing runs over
// encoded bytes, not UTF-16 code units.

void main() {
  test('empty body hashes to the canonical empty-string digest', () {
    expect(
      payloadSha256Hex(''),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('ascii body matches the FIPS "abc" vector', () {
    expect(
      payloadSha256Hex('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('json body hashes byte-for-byte', () {
    expect(
      payloadSha256Hex('{"messages":[]}'),
      '5e4ce7b36ba37b78a5d5f9fd08e6b7b54ba6879d651aa46ec9e1d6fa24ebe30a',
    );
  });

  test('multi-byte utf-8 hashes over encoded bytes', () {
    expect(
      payloadSha256Hex('pacé'),
      '1802cef992c15cc39955bca82817681141cbf1660eb6f9cbdbbe58c8a26d9159',
    );
  });

  test('digest is lowercase hex, 64 chars', () {
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(payloadSha256Hex('anything')),
        isTrue);
  });
}
