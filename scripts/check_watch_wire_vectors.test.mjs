// Unit tests for the watch-rail wire-vector guard's parsers and registries.
//
// The guard is only as good as what it reads out of each rail, and every one
// of these cases is a way an earlier draft of it could have reported agreement
// it had not checked: a brace walk that a format string unbalances stops at the
// wrong `}` and finds no vector at all (which the "exactly one" rule turns into
// a loud failure rather than a silent pass, but only if the rule holds); a
// `const`-only Dart scan misses the `final _goldenBlob = _hex(…)` third copy of
// the run blob; a re-arm read as a bare literal reports agreement on a rail
// that has stopped deriving it.
//
// Run: `node --test scripts/check_watch_wire_vectors.test.mjs`

import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { stripComments } from './comment_strip.mjs';
import {
  CONSTANT_ROWS,
  DART_ONLY,
  RUST_ONLY,
  VECTOR_PAIRS,
  dartConstHex,
  dartHexConsts,
  halfOf,
  minettiFit,
  only,
  rustConstHex,
  rustFnBody,
  rustGoldenFns,
  rustMagics,
  rustVectors,
} from './check_watch_wire_vectors.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

test('a hex string literal folds its backslash line continuations away', () => {
  const src = `
    assert_eq!(
        hex_of(&frame).as_str(),
        "435253310303\\
         000083ed",
        "wire format changed — update BOTH this vector and the Dart mirror",
    );
  `;
  assert.deepEqual(rustVectors(src), ['435253310303000083ed']);
});

test('a prose assert message is not mistaken for a vector', () => {
  assert.deepEqual(rustVectors('assert_eq!(a, b, "deadbeef cafe decade");'), []);
});

test('a byte array is read in declaration order', () => {
  const src = 'let v = &[0x53, 0x45, 0x54, 0x31, 0x08, 0x00, 0x40, 0x00, 0x30];';
  assert.deepEqual(rustVectors(src), ['5345543108004000 30'.replace(' ', '')]);
});

test('a buffer declaration is not a vector', () => {
  assert.deepEqual(rustVectors('let mut buf = [0u8; MAX_SETTINGS_LEN];'), []);
});

test('a short hex string is not a vector', () => {
  assert.deepEqual(rustVectors('let x = "0102";'), []);
});

test('the fn body walk is not unbalanced by a format string or a char literal', () => {
  const src = `
    fn golden_frame_is_stable() {
        let _ = write!(hex, "{b:02x}");
        let _ = '}';
        let v = "0102030405060708";
    }
    fn after() { let v = "aabbccddeeff0011"; }
  `;
  const body = rustFnBody(src, 'golden_frame_is_stable');
  assert.ok(body !== null);
  assert.deepEqual(rustVectors(body), ['0102030405060708']);
});

test('an unknown fn name yields no body rather than the wrong one', () => {
  assert.equal(rustFnBody('fn a() {}', 'b'), null);
});

test('a named hex const inside a fn body is addressable on its own', () => {
  const body = `
        const V1_HEX: &str = "54524b3101000000";
        const V2_HEX: &str = "54524b3102000000";
  `;
  assert.equal(rustConstHex(body, 'V1_HEX'), '54524b3101000000');
  assert.equal(rustConstHex(body, 'V2_HEX'), '54524b3102000000');
  assert.equal(rustConstHex(body, 'V3_HEX'), null);
});

test('the firmware magics are read from their declarations', () => {
  const src = `
    pub const COURSE_MAGIC: [u8; 4] = *b"CRS1";
    const PUSH_STATUS_MAGIC: [u8; 4] = *b"PSH1";
  `;
  assert.deepEqual(rustMagics(src), ['43525331', '50534831']);
});

test('a Dart const concatenates its adjacent parts across an interleaved comment', () => {
  const src = stripComments(
    [
      'const _goldenHex =',
      "    '53455431' '08' 'ffff03'",
      '    // ice: holder / blood, each NUL-padded',
      "    '414c455800' '2800';",
      '',
    ].join('\n'),
    'dart',
  );
  assert.equal(dartConstHex(src, '_goldenHex'), '5345543108ffff03414c4558002800');
});

test('a Dart const that is not all hex is not a vector', () => {
  assert.equal(dartConstHex("const _x = 'not hex at all here';", '_x'), null);
});

test('the sweep sees `final … = _hex(…)`, not only `const`', () => {
  const src = [
    "const _a = '54524b3101000000';",
    "final _b = _hex(",
    "  '54524b3102000000'",
    ");",
    "const _notAVector = 'hello';",
  ].join('\n');
  assert.deepEqual(
    [...dartHexConsts(src).entries()],
    [
      ['_a', '54524b3101000000'],
      ['_b', '54524b3102000000'],
    ],
  );
});

test('every fn whose name mentions golden is enumerated', () => {
  const src = 'fn golden_vector() {} fn v7_golden_vector_still_decodes() {} fn other() {}';
  assert.deepEqual(rustGoldenFns(src), ['golden_vector', 'v7_golden_vector_still_decodes']);
});

test('only() refuses both no match and more than one', () => {
  assert.equal(only('a = 1;', /a = (\d+);/, 'x'), '1');
  assert.throws(() => only('', /a = (\d+);/, 'x'), /no match/);
  assert.throws(() => only('a = 1; a = 2;', /a = (\d+);/, 'x'), /matched 2 times/);
});

test('a re-arm must still be DERIVED from its threshold', () => {
  assert.equal(halfOf('THRESH / 2.0', 'THRESH', 40), 20);
  assert.equal(halfOf('Self.thresholdMetres / 2', 'thresholdMetres', 40), 20);
  assert.throws(() => halfOf('20.0', 'thresholdMetres', 40), /stopped deriving/);
  assert.throws(() => halfOf('thresholdMetres / 3', 'thresholdMetres', 40), /stopped deriving/);
});

test('the Minetti fit normalises across the four rails’ spellings', () => {
  const rust = '        155.4 * i5 - 30.4 * i4 + 46.3 * i2 + 3.6\n';
  const dart = '  return 155.4 * i5   -   30.4 * i4 + 46.3 * i2 + 3.6;\n';
  assert.equal(minettiFit(rust, 'rs'), minettiFit(dart, 'dart'));
});

test('the Minetti reader refuses a file with none or several fit lines', () => {
  assert.throws(() => minettiFit('let i5 = i4 * i;\n', 'x'), /found 0/);
  assert.throws(() => minettiFit('1 * i5 + 2 * i2\n3 * i5 + 4 * i2\n', 'x'), /found 2/);
});

test('no vector is registered twice on either rail', () => {
  const rustKeys = VECTOR_PAIRS.map((p) => `${p.rust.file}::${p.rust.fn}::${p.rust.const ?? ''}`);
  const dartKeys = VECTOR_PAIRS.map((p) => `${p.dart.file}::${p.dart.const}`);
  assert.equal(new Set(rustKeys).size, rustKeys.length);
  assert.equal(new Set(dartKeys).size, dartKeys.length);
  assert.equal(new Set(VECTOR_PAIRS.map((p) => p.name)).size, VECTOR_PAIRS.length);
});

test('every rail-local entry carries a reason', () => {
  for (const e of [...RUST_ONLY, ...DART_ONLY]) {
    assert.ok(e.why.trim().length > 5, `${JSON.stringify(e)} needs a reason, not a label`);
  }
});

test('every constant row names at least two rails and says why it matters', () => {
  for (const row of CONSTANT_ROWS) {
    assert.ok(row.rails.length >= 2, `${row.name} is not a cross-rail duplicate`);
    assert.ok(row.why.trim().length > 5, `${row.name} needs a reason`);
  }
  assert.equal(new Set(CONSTANT_ROWS.map((r) => r.name)).size, CONSTANT_ROWS.length);
});

test('every file the registries name exists', () => {
  const files = new Set([
    ...VECTOR_PAIRS.flatMap((p) => [p.rust.file, p.dart.file]),
    ...RUST_ONLY.map((r) => r.file),
    ...DART_ONLY.map((d) => d.file),
    ...CONSTANT_ROWS.flatMap((r) => r.rails.map((rail) => rail.file)),
  ]);
  for (const f of files) {
    assert.ok(existsSync(join(REPO_ROOT, f)), `${f} is named by the registry but does not exist`);
  }
});

test('an unterminated hex run is parsed in linear time, not exponential', () => {
  // The first draft nested two quantifiers over overlapping input
  // (`(?:[0-9a-fA-F]+|\\\s*)+`), so a long hex run with no closing quote
  // backtracked exponentially: measured at 703 ms for 24 characters, which is
  // minutes by 32 and a hung CI job on any Rust file the guard cannot parse.
  // 200 chars is far past where the old pattern stopped returning at all.
  const src = `let s = "${'a'.repeat(200)};`;
  const started = Date.now();
  const out = rustVectors(src);
  assert.ok(
    Date.now() - started < 1000,
    'rustVectors backtracked on an unterminated hex run',
  );
  assert.deepEqual(out, []);
});

test('a line-continued hex vector still reads as one value', () => {
  const src = `const V: &str = "0011223344556677\\\n     8899aabbccddeeff";`;
  assert.deepEqual(rustVectors(src), ['00112233445566778899aabbccddeeff']);
});
