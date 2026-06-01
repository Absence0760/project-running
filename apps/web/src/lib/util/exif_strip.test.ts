import { test } from 'node:test';
import assert from 'node:assert/strict';
import { stripJpegExif } from './exif_strip';

/// Helper: assemble a minimal JPEG byte stream from a list of segments.
const jpeg = (segments: number[][]): Uint8Array =>
	Uint8Array.from(segments.flat());

/// A length-bearing segment: FF, marker, 2-byte big-endian length
/// (length counts the 2 length bytes + payload), then payload.
const seg = (marker: number, payload: number[]): number[] => {
	const len = payload.length + 2;
	return [0xff, marker, (len >> 8) & 0xff, len & 0xff, ...payload];
};

const soi = [0xff, 0xd8];
const eoi = [0xff, 0xd9];
const sos = [0xff, 0xda, 0x00, 0x02]; // SOS header (len 2, no payload)
const scan = [0x12, 0x34, 0x56]; // pretend entropy-coded data

const hasMarker = (out: Uint8Array, m: number): boolean => {
	for (let i = 0; i + 1 < out.length; i++) {
		if (out[i] === 0xff && out[i + 1] === m) return true;
	}
	return false;
};

test('stripJpegExif — removes the APP1 (EXIF) segment, keeps everything else', () => {
	const exif = seg(0xe1, [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0xde, 0xad]);
	const jfif = seg(0xe0, [0x4a, 0x46, 0x49, 0x46, 0x00]); // APP0
	const dqt = seg(0xdb, [0x00, 0x01, 0x02]);
	const input = jpeg([soi, jfif, exif, dqt, sos, scan, eoi]);
	const out = stripJpegExif(input);

	assert.equal(hasMarker(out, 0xe1), false, 'APP1/EXIF must be stripped');
	const expected = jpeg([soi, jfif, dqt, sos, scan, eoi]);
	assert.deepEqual([...out], [...expected]);
});

test('stripJpegExif — keeps the ICC colour profile (APP2), only APP1 is stripped', () => {
	const exif = seg(0xe1, [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]);
	const icc = seg(0xe2, [0x49, 0x43, 0x43, 0x5f]); // APP2
	const input = jpeg([soi, exif, icc, sos, scan, eoi]);
	const out = stripJpegExif(input);
	assert.equal(hasMarker(out, 0xe2), true, 'ICC profile (APP2) must survive');
	assert.equal(hasMarker(out, 0xe1), false, 'APP1 must be stripped');
});

test('stripJpegExif — returns the same buffer unchanged when there is no APP1', () => {
	const jfif = seg(0xe0, [0x4a, 0x46, 0x49, 0x46, 0x00]);
	const input = jpeg([soi, jfif, sos, scan, eoi]);
	const out = stripJpegExif(input);
	assert.equal(out, input, 'no-op should not reallocate');
});

test('stripJpegExif — non-JPEG input is returned unchanged (PNG signature)', () => {
	const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]);
	assert.equal(stripJpegExif(png), png);
});

test('stripJpegExif — truncated / tiny buffers are returned unchanged', () => {
	const tiny = Uint8Array.from([0xff, 0xd8]);
	assert.equal(stripJpegExif(tiny), tiny);
});

test('stripJpegExif — does not run off the end on a declared length past EOF', () => {
	const input = Uint8Array.from([...soi, 0xff, 0xe1, 0xff, 0xf0, 0x01]);
	const out = stripJpegExif(input);
	assert.deepEqual([...out], [...input]); // bail-safe: copy remainder verbatim
});
