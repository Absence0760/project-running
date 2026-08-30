import test from 'node:test';
import assert from 'node:assert/strict';

import { stripComments } from './comment_strip.mjs';
import {
	DART_CODEC,
	MAGICS,
	PAIRS,
	RUST_CODEC,
	SOLO,
	blocksIn,
	check,
	usesCodec,
	vectorAt,
	vectorsIn,
} from './check_watch_wire_vectors.mjs';

const CRS1 = MAGICS.CRS1;

test('the live tree agrees on every registered wire vector', () => {
	const { errors, checked } = check();
	assert.deepEqual(errors, []);
	assert.equal(checked, PAIRS.length);
});

test('every registered pair names a distinct id', () => {
	assert.equal(new Set(PAIRS.map((p) => p.id)).size, PAIRS.length);
});

test('a rust hex golden is read out of its own fn, continuations and all', () => {
	const src = [
		'    #[test]',
		'    fn golden_frame_is_stable() {',
		'        let frame = encode_vec(&sim_points());',
		'        assert_eq!(',
		'            hex_of(&frame).as_str(),',
		`            "${CRS1}0303\\`,
		'             0000",',
		'            "wire format changed"',
		'        );',
		'    }',
	].join('\n');
	const found = vectorAt(src, 'fn:golden_frame_is_stable', 'rust', 'x.rs');
	assert.equal(found.hex, `${CRS1}03030000`);
});

test('a rust byte-array golden is read as bytes, not as its neighbours', () => {
	const src = [
		'    fn golden_vector_tz_only() {',
		'        let s = WatchSettings { tz_offset_min: Some(-570) };',
		'        let n = s.encode(&mut buf).unwrap();',
		'        assert_eq!(',
		'            &buf[..n],',
		'            &[0x53, 0x45, 0x54, 0x31, 0x08, 0x00, 0x01, 0x00, 0xc6, 0xfd]',
		'        );',
		'    }',
	].join('\n');
	const found = vectorAt(src, 'fn:golden_vector_tz_only', 'rust', 'x.rs');
	assert.equal(found.hex, '5345543108000100c6fd');
});

test('a dart const golden concatenates its adjacent literals', () => {
	const src = [
		"const _goldenHex =",
		`    '${CRS1}0303'`,
		"    '0000';",
		'void main() {',
		"  test('t', () { expect(encodeCourse(pts), _hex(_goldenHex)); });",
		'}',
	].join('\n');
	const found = vectorAt(src, 'const:_goldenHex', 'dart', 'x.dart');
	assert.equal(found.hex, `${CRS1}03030000`);
});

test('two vectors in one dart test stay two vectors', () => {
	const src = [
		'void main() {',
		"  test('autoLap', () {",
		`    expect(a.encode(), _hex('${MAGICS.SET1}' '08' '01'));`,
		`    expect(b.encode(), _hex('${MAGICS.SET1}' '08' '07'));`,
		'  });',
		'}',
	].join('\n');
	assert.equal(vectorAt(src, 'test:autoLap#0', 'dart', 'x.dart').hex, `${MAGICS.SET1}0801`);
	assert.equal(vectorAt(src, 'test:autoLap#1', 'dart', 'x.dart').hex, `${MAGICS.SET1}0807`);
});

test('a bare magic is not a vector, so a header assertion is not a rail', () => {
	const src = "expect(frame.sublist(0, 4), [0x57, 0x4b, 0x54, 0x31]);";
	assert.deepEqual(vectorsIn(src, 0, src.length), []);
});

test('a format string inside the fn does not end the block early', () => {
	const src = [
		'    fn golden_blob_is_stable() {',
		'        let hex = blob.iter().fold(String::new(), |mut s, b| {',
		'            let _ = core::fmt::write(&mut s, format_args!("{:02x}", b));',
		'            s',
		'        });',
		`        assert_eq!(hex.as_str(), "${MAGICS.TRK1}0401");`,
		'    }',
	].join('\n');
	const found = vectorAt(src, 'fn:golden_blob_is_stable', 'rust', 'x.rs');
	assert.equal(found.hex, `${MAGICS.TRK1}0401`);
});

test('a vector commented out is not read as live', () => {
	const src = [
		'    fn golden_frame_is_stable() {',
		`        // was "${CRS1}0202"`,
		'        let frame = encode_vec(&pts);',
		`        assert_eq!(hex_of(&frame).as_str(), "${CRS1}0303");`,
		'    }',
	].join('\n');
	const found = vectorAt(src, 'fn:golden_frame_is_stable', 'rust', 'x.rs');
	assert.equal(found.hex, `${CRS1}0303`);
});

test('a missing anchor throws rather than reporting agreement', () => {
	assert.throws(
		() => vectorAt('fn other() {}', 'fn:golden_frame_is_stable', 'rust', 'x.rs'),
		/no fn:golden_frame_is_stable/,
	);
});

test('an anchor holding no vector throws rather than returning nothing', () => {
	assert.throws(
		() => vectorAt('fn golden() { assert!(true); }', 'fn:golden', 'rust', 'x.rs'),
		/holds 0 vector/,
	);
});

test('usesCodec rejects a fn that compares two literals', () => {
	const decorated = [
		'    fn golden_frame_is_stable() {',
		`        assert_eq!("${CRS1}0303", "${CRS1}0303");`,
		'    }',
	].join('\n');
	assert.equal(
		usesCodec(decorated, 'fn:golden_frame_is_stable', 'rust', RUST_CODEC),
		false,
	);
	const live = decorated.replace(
		`assert_eq!("${CRS1}0303"`,
		'assert_eq!(hex_of(&encode_vec(&pts)).as_str()',
	);
	assert.equal(usesCodec(live, 'fn:golden_frame_is_stable', 'rust', RUST_CODEC), true);
});

test('usesCodec judges a dart const by its USE sites, not by the whole file', () => {
	const declOnly = [
		`const _goldenHex = '${CRS1}0303';`,
		'void main() {',
		"  test('unrelated', () { expect(encodeCourse(pts), isNotNull); });",
		"  test('t', () { expect(_hex(_goldenHex), hasLength(4)); });",
		'}',
	].join('\n');
	assert.equal(usesCodec(declOnly, 'const:_goldenHex', 'dart', DART_CODEC), false);
	const live = declOnly.replace(
		'expect(_hex(_goldenHex), hasLength(4))',
		'expect(encodeCourse(pts), _hex(_goldenHex))',
	);
	assert.equal(usesCodec(live, 'const:_goldenHex', 'dart', DART_CODEC), true);
});

test('blocksIn nests, so a vector is attributed to its innermost declaration', () => {
	const src = [
		'void main() {',
		"  group('g', () {",
		"    test('inner', () {",
		`      expect(s.encode(), _hex('${MAGICS.SET1}0800'));`,
		'    });',
		'  });',
		'}',
	].join('\n');
	const code = stripComments(src, 'dart');
	const blocks = blocksIn(code, 'dart');
	assert.ok(blocks.some((b) => b.name === 'test:inner'));
	const [found] = vectorsIn(code, 0, code.length);
	const host = blocks
		.filter((b) => found.at >= b.from && found.at < b.to)
		.sort((a, b) => a.to - a.from - (b.to - b.from))[0];
	assert.equal(host.name, 'test:inner');
});

test('every SOLO row carries a reason, so an excuse is never silent', () => {
	for (const s of SOLO) {
		assert.ok(s.why.length > 20, `${s.file} ${s.anchor} needs a real reason`);
		assert.ok(s.anchor.includes(':'), `${s.file} ${s.anchor} is not an anchor`);
	}
});
