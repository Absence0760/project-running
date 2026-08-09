import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	stripJpegExif,
	stripPngMetadata,
	stripWebpMetadata,
	stripImageExif,
	canStripImageExif,
	detectImageMime,
	UnstrippableImageError,
	STRIPPABLE_IMAGE_MIME_TYPES,
} from './exif_strip';

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

// --- PNG ---

const pngSig = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const cc = (s: string): number[] => [...s].map((c) => c.charCodeAt(0));
// [len(4 BE)][type(4)][data][crc(4)] — the stripper ignores the CRC value.
const pngChunk = (type: string, data: number[]): number[] => {
	const len = data.length;
	return [(len >>> 24) & 0xff, (len >>> 16) & 0xff, (len >>> 8) & 0xff, len & 0xff, ...cc(type), ...data, 0, 0, 0, 0];
};
const hasChunk = (out: Uint8Array, type: string): boolean => {
	const t = cc(type);
	for (let i = 0; i + 4 <= out.length; i++) {
		if (out[i] === t[0] && out[i + 1] === t[1] && out[i + 2] === t[2] && out[i + 3] === t[3]) return true;
	}
	return false;
};

test('stripPngMetadata — removes the eXIf (GPS) chunk, keeps structural chunks', () => {
	const input = Uint8Array.from([
		...pngSig,
		...pngChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]),
		...pngChunk('eXIf', [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0xde, 0xad]), // GPS EXIF
		...pngChunk('IDAT', [0x78, 0x9c, 0x62, 0x00]),
		...pngChunk('IEND', [])
	]);
	const out = stripPngMetadata(input);
	assert.equal(hasChunk(out, 'eXIf'), false, 'eXIf/GPS must be stripped');
	assert.equal(hasChunk(out, 'IHDR'), true);
	assert.equal(hasChunk(out, 'IDAT'), true);
	assert.equal(hasChunk(out, 'IEND'), true);
});

test('stripPngMetadata — also drops tEXt/iTXt/zTXt and no-ops when clean', () => {
	const withText = Uint8Array.from([
		...pngSig,
		...pngChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]),
		...pngChunk('iTXt', [0x66, 0x6f, 0x6f]),
		...pngChunk('IDAT', [0x78, 0x9c]),
		...pngChunk('IEND', [])
	]);
	assert.equal(hasChunk(stripPngMetadata(withText), 'iTXt'), false);

	const clean = Uint8Array.from([
		...pngSig,
		...pngChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]),
		...pngChunk('IDAT', [0x78, 0x9c]),
		...pngChunk('IEND', [])
	]);
	assert.equal(stripPngMetadata(clean), clean, 'no-op should not reallocate');
});

// --- WebP ---

const webpChunk = (fourcc: string, data: number[]): number[] => {
	const size = data.length;
	return [...cc(fourcc), size & 0xff, (size >>> 8) & 0xff, (size >>> 16) & 0xff, (size >>> 24) & 0xff, ...data, ...(size & 1 ? [0] : [])];
};
const webp = (chunks: number[][]): Uint8Array => {
	const body = chunks.flat();
	const size = 4 + body.length; // 'WEBP' + chunks
	return Uint8Array.from([0x52, 0x49, 0x46, 0x46, size & 0xff, (size >>> 8) & 0xff, (size >>> 16) & 0xff, (size >>> 24) & 0xff, ...cc('WEBP'), ...body]);
};

test('stripWebpMetadata — removes EXIF, clears the VP8X flag, fixes the RIFF size', () => {
	// VP8X payload: flags byte with the EXIF bit (0x08) set + 9 more bytes.
	const vp8x = webpChunk('VP8X', [0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
	const image = webpChunk('VP8 ', [0x11, 0x22, 0x33, 0x44]);
	const exif = webpChunk('EXIF', [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0xde, 0xad]);
	const input = webp([vp8x, image, exif]);
	const out = stripWebpMetadata(input);

	assert.equal(hasChunk(out, 'EXIF'), false, 'EXIF chunk must be stripped');
	assert.equal(hasChunk(out, 'VP8 '), true, 'image data must survive');
	// The VP8X flags byte is the first byte after 'VP8X'(4) + size(4).
	const vpIdx = [...out].findIndex((_, i) => hasChunk(out.slice(i, i + 4), 'VP8X'));
	assert.equal(out[vpIdx + 8] & 0x08, 0, 'EXIF feature flag must be cleared');
	// RIFF size field must equal total length - 8.
	const declared = out[4] | (out[5] << 8) | (out[6] << 16) | (out[7] * 0x1000000);
	assert.equal(declared, out.length - 8);
});

test('stripImageExif — dispatches by MIME', () => {
	const exifJpeg = Uint8Array.from([...soi, ...seg(0xe1, [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]), ...sos, ...scan, ...eoi]);
	assert.equal(hasChunk(stripImageExif(exifJpeg, 'image/jpeg'), 'Exif'), false);
});

test('stripImageExif — throws on a format it cannot clean, never passes it through', () => {
	// A HEIC straight off an iPhone carries GPS in an ISO-BMFF `Exif` item
	// that none of the three walkers understand, and the Go worker's
	// StripJPEG can't clean it either. Returning the input here uploaded the
	// geotagged original verbatim into a gallery other people can read.
	const heic = Uint8Array.from([
		0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63,
	]);
	assert.throws(() => stripImageExif(heic, 'image/heic'), UnstrippableImageError);
	assert.throws(() => stripImageExif(heic, 'image/heif'), UnstrippableImageError);
	assert.throws(() => stripImageExif(heic, 'image/gif'), UnstrippableImageError);
	assert.throws(() => stripImageExif(heic, ''), UnstrippableImageError);
});

test('detectImageMime sniffs the bytes and refuses anything else', () => {
	assert.equal(detectImageMime(Uint8Array.from([0xff, 0xd8, 0xff, 0xe0])), 'image/jpeg');
	assert.equal(
		detectImageMime(Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
		'image/png',
	);
	assert.equal(
		detectImageMime(
			Uint8Array.from([
				0x52, 0x49, 0x46, 0x46, 0x10, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
			]),
		),
		'image/webp',
	);
	// `ftypheic` — an iPhone HEIC. Named `.jpg` it still must not be accepted.
	const heic = Uint8Array.from([
		0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63,
	]);
	assert.equal(detectImageMime(heic), null);
	assert.equal(detectImageMime(Uint8Array.from([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])), null);
	assert.equal(detectImageMime(Uint8Array.from([])), null);
});

test('canStripImageExif agrees with what stripImageExif actually handles', () => {
	for (const mime of STRIPPABLE_IMAGE_MIME_TYPES) {
		assert.equal(canStripImageExif(mime), true, mime);
		// Each strippable type must survive a buffer it does not recognise
		// rather than throwing — only the dispatcher's default arm throws.
		assert.doesNotThrow(() => stripImageExif(Uint8Array.from([0x00, 0x01]), mime), mime);
	}
	assert.equal(canStripImageExif('image/heic'), false);
	assert.equal(canStripImageExif('image/heif'), false);
});
