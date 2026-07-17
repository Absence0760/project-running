/// Strip the APP1 segment (EXIF + XMP) from a JPEG byte buffer.
///
/// Phone-camera photos embed GPS coordinates in the EXIF APP1 segment
/// (and sometimes XMP, also APP1). The `run-photos` Storage bucket has a
/// server-side worker that strips metadata, but that runs *after* upload
/// — leaving a window where the raw, geotagged original sits in the
/// bucket. Stripping client-side before the upload closes that window so
/// a precise home/route location never leaves the device. Persona-hunt
/// woman / family-club #52 (web side; mirrors mobile `exif_strip.dart`).
///
/// This is a lossless marker-walk: it removes only APP1 (`0xFFE1`) and
/// copies every other segment — including the JFIF header (APP0) and any
/// ICC colour profile (APP2) — and the compressed scan data verbatim, so
/// image quality and colour are untouched. PNG and WebP carry GPS in their
/// own metadata chunks — handled by `stripPngMetadata` / `stripWebpMetadata`;
/// dispatch by MIME through `stripImageExif`. The avatars bucket has no
/// server-side strip worker, so this client strip is the *only* strip for a
/// PNG/WebP profile photo — an unstripped format there would leak a home
/// coordinate to the logged-out public profile.
///
/// TS↔Dart parity pair with `apps/mobile_android/lib/exif_strip.dart` —
/// keep the marker-walk logic in lockstep.
export function stripJpegExif(input: Uint8Array): Uint8Array {
	// Must start with SOI (FFD8) to be a JPEG.
	if (input.length < 4 || input[0] !== 0xff || input[1] !== 0xd8) return input;

	const out: number[] = [0xff, 0xd8]; // SOI

	let i = 2;
	let strippedAny = false;
	while (i + 1 < input.length) {
		if (input[i] !== 0xff) {
			// Misaligned (corrupt / unexpected) — copy the remainder verbatim
			// rather than risk dropping image data.
			pushRange(out, input, i, input.length);
			break;
		}
		const marker = input[i + 1];

		// Standalone markers carry no length payload.
		if (marker === 0xd9) {
			// EOI — emit and copy any trailing bytes.
			pushRange(out, input, i, input.length);
			break;
		}
		if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
			out.push(0xff, marker);
			i += 2;
			continue;
		}
		if (marker === 0xda) {
			// Start of Scan — the rest is entropy-coded image data. Copy
			// verbatim to the end.
			pushRange(out, input, i, input.length);
			break;
		}

		// Length-bearing segment: 2-byte big-endian length (includes itself).
		if (i + 3 >= input.length) {
			pushRange(out, input, i, input.length);
			break;
		}
		const len = (input[i + 2] << 8) | input[i + 3];
		const segEnd = i + 2 + len;
		if (len < 2 || segEnd > input.length) {
			pushRange(out, input, i, input.length);
			break;
		}
		if (marker === 0xe1) {
			// APP1 — EXIF (with GPS) and/or XMP. Drop it.
			strippedAny = true;
		} else {
			pushRange(out, input, i, segEnd);
		}
		i = segEnd;
	}

	// If we never found an APP1 segment, return the original buffer so we
	// don't pay an allocation for a no-op.
	if (!strippedAny) return input;
	return Uint8Array.from(out);
}

function pushRange(out: number[], src: Uint8Array, start: number, end: number): void {
	for (let j = start; j < end; j++) out.push(src[j]);
}

const PNG_SIG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
// PNG chunk types that can carry GPS / camera / free-text metadata.
const PNG_META_CHUNKS = new Set(['eXIf', 'tEXt', 'zTXt', 'iTXt']);

/// Strip metadata chunks (`eXIf`, `tEXt`, `zTXt`, `iTXt`) from a PNG buffer.
/// PNG has carried an `eXIf` chunk — routinely populated with GPS by phone
/// camera pipelines — since the 2017 spec update. This is a lossless
/// chunk-walk: every structural chunk (IHDR, PLTE, IDAT, IEND, …) is copied
/// verbatim, only the metadata chunks are dropped. Non-PNG input is returned
/// unchanged. Keep in lockstep with the Dart twin.
export function stripPngMetadata(input: Uint8Array): Uint8Array {
	if (input.length < 8) return input;
	for (let k = 0; k < 8; k++) if (input[k] !== PNG_SIG[k]) return input;

	const out: number[] = [];
	pushRange(out, input, 0, 8); // signature
	let i = 8;
	let strippedAny = false;
	while (i + 12 <= input.length) {
		const len = ((input[i] << 24) | (input[i + 1] << 16) | (input[i + 2] << 8) | input[i + 3]) >>> 0;
		const type = String.fromCharCode(input[i + 4], input[i + 5], input[i + 6], input[i + 7]);
		const chunkEnd = i + 12 + len; // length(4) + type(4) + data(len) + crc(4)
		if (chunkEnd > input.length) {
			pushRange(out, input, i, input.length);
			break;
		}
		if (PNG_META_CHUNKS.has(type)) {
			strippedAny = true;
		} else {
			pushRange(out, input, i, chunkEnd);
			if (type === 'IEND') break;
		}
		i = chunkEnd;
	}

	if (!strippedAny) return input;
	return Uint8Array.from(out);
}

/// Strip the `EXIF` and `XMP ` chunks from a WebP (RIFF) buffer, clearing the
/// matching VP8X feature-flag bits and fixing up the RIFF file-size field.
/// WebP carries a standard RIFF `EXIF` chunk that camera pipelines populate
/// with GPS. Lossless: image-data chunks (VP8/VP8L/ALPH/ANIM/…) are copied
/// verbatim. Non-WebP input is returned unchanged. Keep in lockstep with Dart.
export function stripWebpMetadata(input: Uint8Array): Uint8Array {
	if (input.length < 12) return input;
	// 'RIFF' .... 'WEBP'
	if (input[0] !== 0x52 || input[1] !== 0x49 || input[2] !== 0x46 || input[3] !== 0x46) return input;
	if (input[8] !== 0x57 || input[9] !== 0x45 || input[10] !== 0x42 || input[11] !== 0x50) return input;

	const out: number[] = [];
	pushRange(out, input, 0, 12); // 'RIFF' + size + 'WEBP'
	let i = 12;
	let strippedAny = false;
	let vp8xStart = -1;
	while (i + 8 <= input.length) {
		const fourcc = String.fromCharCode(input[i], input[i + 1], input[i + 2], input[i + 3]);
		const size = (input[i + 4] | (input[i + 5] << 8) | (input[i + 6] << 16) | (input[i + 7] * 0x1000000)) >>> 0;
		const chunkEnd = i + 8 + size + (size & 1); // chunks are padded to an even size
		if (chunkEnd > input.length) {
			pushRange(out, input, i, input.length);
			break;
		}
		if (fourcc === 'EXIF' || fourcc === 'XMP ') {
			strippedAny = true;
		} else {
			if (fourcc === 'VP8X') vp8xStart = out.length;
			pushRange(out, input, i, chunkEnd);
		}
		i = chunkEnd;
	}

	if (!strippedAny) return input;
	// Clear the EXIF (bit 3) + XMP (bit 2) feature flags in the VP8X payload so
	// a decoder doesn't go looking for chunks we removed.
	if (vp8xStart >= 0) out[vp8xStart + 8] &= ~0b0000_1100;
	// Rewrite the RIFF file size (LE, excludes the leading 'RIFF' + size field).
	const newSize = out.length - 8;
	out[4] = newSize & 0xff;
	out[5] = (newSize >>> 8) & 0xff;
	out[6] = (newSize >>> 16) & 0xff;
	out[7] = (newSize >>> 24) & 0xff;
	return Uint8Array.from(out);
}

/// Strip location-bearing metadata from an image buffer, dispatched by MIME.
/// JPEG → APP1 marker-walk, PNG → metadata-chunk walk, WebP → RIFF-chunk walk.
/// Any other type is returned unchanged.
export function stripImageExif(input: Uint8Array, mime: string): Uint8Array {
	switch (mime) {
		case 'image/jpeg':
			return stripJpegExif(input);
		case 'image/png':
			return stripPngMetadata(input);
		case 'image/webp':
			return stripWebpMetadata(input);
		default:
			return input;
	}
}

/// Run a picked image `File` through the format-appropriate metadata stripper
/// before it's uploaded. Returns the original `File` untouched when the strip
/// is a no-op (unhandled type, or no metadata present), so a clean image pays
/// only one buffer read. The returned `File` keeps the original name + MIME
/// type (the strippers are lossless + format-preserving) so the caller's
/// extension / content-type logic is intact.
export async function stripExifFromFile(file: File): Promise<File> {
	const original = new Uint8Array(await file.arrayBuffer());
	const stripped = stripImageExif(original, file.type);
	if (stripped === original) return file;
	const buf = new ArrayBuffer(stripped.byteLength);
	new Uint8Array(buf).set(stripped);
	return new File([buf], file.name, { type: file.type, lastModified: file.lastModified });
}
