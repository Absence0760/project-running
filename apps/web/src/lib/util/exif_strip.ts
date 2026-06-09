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
/// image quality and colour are untouched. Non-JPEG input (PNG, etc.) is
/// returned unchanged; PNGs don't carry camera GPS and the server-side
/// strip remains the backstop for any format this doesn't handle.
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

/// Run a picked image `File` through `stripJpegExif` before it's uploaded.
/// Returns the original `File` untouched when it isn't a JPEG or carries no
/// APP1 segment (the strip is a no-op), so non-JPEG formats and already-clean
/// JPEGs pay only one buffer read. The returned `File` keeps the original
/// name + MIME type so the caller's extension / content-type logic is intact.
export async function stripExifFromFile(file: File): Promise<File> {
	if (file.type !== 'image/jpeg') return file;
	const original = new Uint8Array(await file.arrayBuffer());
	const stripped = stripJpegExif(original);
	if (stripped === original) return file;
	const buf = new ArrayBuffer(stripped.byteLength);
	new Uint8Array(buf).set(stripped);
	return new File([buf], file.name, { type: file.type, lastModified: file.lastModified });
}
