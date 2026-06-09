import 'dart:typed_data';

/// Strip the APP1 segment (EXIF + XMP) from a JPEG byte buffer.
///
/// Phone-camera photos embed GPS coordinates in the EXIF APP1 segment
/// (and sometimes XMP, also APP1). The `run-photos` Storage bucket has a
/// server-side worker that strips metadata, but that runs *after* upload
/// — leaving a window where the raw, geotagged original sits in the
/// bucket. Stripping client-side before the upload closes that window so
/// a precise home/route location never leaves the device. Persona-hunt
/// family-club #52.
///
/// This is a lossless marker-walk: it removes only APP1 (`0xFFE1`) and
/// copies every other segment — including the JFIF header (APP0) and any
/// ICC colour profile (APP2) — and the compressed scan data verbatim, so
/// image quality and colour are untouched. Non-JPEG input (PNG, etc.) is
/// returned unchanged; PNGs don't carry camera GPS and the server-side
/// strip remains the backstop for any format this doesn't handle.
Uint8List stripJpegExif(Uint8List input) {
  // Must start with SOI (FFD8) to be a JPEG.
  if (input.length < 4 || input[0] != 0xFF || input[1] != 0xD8) return input;

  final out = BytesBuilder(copy: false);
  out.add(Uint8List.fromList([0xFF, 0xD8])); // SOI

  var i = 2;
  var strippedAny = false;
  while (i + 1 < input.length) {
    if (input[i] != 0xFF) {
      // Misaligned (corrupt / unexpected) — copy the remainder verbatim
      // rather than risk dropping image data.
      out.add(input.sublist(i));
      break;
    }
    final marker = input[i + 1];

    // Standalone markers carry no length payload.
    if (marker == 0xD9) {
      // EOI — emit and copy any trailing bytes.
      out.add(input.sublist(i));
      break;
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      out.add(Uint8List.fromList([0xFF, marker]));
      i += 2;
      continue;
    }
    if (marker == 0xDA) {
      // Start of Scan — the rest is entropy-coded image data. Copy
      // verbatim to the end.
      out.add(input.sublist(i));
      break;
    }

    // Length-bearing segment: 2-byte big-endian length (includes itself).
    if (i + 3 >= input.length) {
      out.add(input.sublist(i));
      break;
    }
    final len = (input[i + 2] << 8) | input[i + 3];
    final segEnd = i + 2 + len;
    if (len < 2 || segEnd > input.length) {
      out.add(input.sublist(i));
      break;
    }
    if (marker == 0xE1) {
      // APP1 — EXIF (with GPS) and/or XMP. Drop it.
      strippedAny = true;
    } else {
      out.add(input.sublist(i, segEnd));
    }
    i = segEnd;
  }

  // If we never found an APP1 segment, return the original buffer so we
  // don't pay an allocation for a no-op.
  if (!strippedAny) return input;
  return out.toBytes();
}
