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
/// image quality and colour are untouched. PNG and WebP carry GPS in their
/// own metadata chunks — handled by [stripPngMetadata] / [stripWebpMetadata];
/// dispatch by MIME through [stripImageExif]. The avatars bucket has no
/// server-side strip worker, so this client strip is the *only* strip for a
/// PNG/WebP profile photo — an unstripped format there would leak a home
/// coordinate to the logged-out public profile.
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

const _pngSig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _pngMetaChunks = {'eXIf', 'tEXt', 'zTXt', 'iTXt'};

/// Strip metadata chunks (`eXIf`, `tEXt`, `zTXt`, `iTXt`) from a PNG buffer.
/// PNG has carried an `eXIf` chunk — routinely populated with GPS by phone
/// camera pipelines — since the 2017 spec update. Lossless chunk-walk: every
/// structural chunk (IHDR, PLTE, IDAT, IEND, …) is copied verbatim, only the
/// metadata chunks are dropped. Non-PNG input is returned unchanged. Keep in
/// lockstep with the web twin.
Uint8List stripPngMetadata(Uint8List input) {
  if (input.length < 8) return input;
  for (var k = 0; k < 8; k++) {
    if (input[k] != _pngSig[k]) return input;
  }

  final out = BytesBuilder(copy: false);
  out.add(input.sublist(0, 8)); // signature
  var i = 8;
  var strippedAny = false;
  while (i + 12 <= input.length) {
    final len =
        (input[i] << 24) | (input[i + 1] << 16) | (input[i + 2] << 8) | input[i + 3];
    final type = String.fromCharCodes(input.sublist(i + 4, i + 8));
    final chunkEnd = i + 12 + len; // length(4) + type(4) + data(len) + crc(4)
    if (len < 0 || chunkEnd > input.length) {
      out.add(input.sublist(i));
      break;
    }
    if (_pngMetaChunks.contains(type)) {
      strippedAny = true;
    } else {
      out.add(input.sublist(i, chunkEnd));
      if (type == 'IEND') break;
    }
    i = chunkEnd;
  }

  if (!strippedAny) return input;
  return out.toBytes();
}

/// Strip the `EXIF` and `XMP ` chunks from a WebP (RIFF) buffer, clearing the
/// matching VP8X feature-flag bits and fixing up the RIFF file-size field.
/// WebP carries a standard RIFF `EXIF` chunk that camera pipelines populate
/// with GPS. Lossless: image-data chunks (VP8/VP8L/ALPH/ANIM/…) are copied
/// verbatim. Non-WebP input is returned unchanged. Keep in lockstep with web.
Uint8List stripWebpMetadata(Uint8List input) {
  if (input.length < 12) return input;
  // 'RIFF' .... 'WEBP'
  if (input[0] != 0x52 || input[1] != 0x49 || input[2] != 0x46 || input[3] != 0x46) {
    return input;
  }
  if (input[8] != 0x57 || input[9] != 0x45 || input[10] != 0x42 || input[11] != 0x50) {
    return input;
  }

  final out = <int>[];
  out.addAll(input.sublist(0, 12)); // 'RIFF' + size + 'WEBP'
  var i = 12;
  var strippedAny = false;
  var vp8xStart = -1;
  while (i + 8 <= input.length) {
    final fourcc = String.fromCharCodes(input.sublist(i, i + 4));
    final size =
        input[i + 4] | (input[i + 5] << 8) | (input[i + 6] << 16) | (input[i + 7] << 24);
    final chunkEnd = i + 8 + size + (size & 1); // chunks pad to an even size
    if (size < 0 || chunkEnd > input.length) {
      out.addAll(input.sublist(i));
      break;
    }
    if (fourcc == 'EXIF' || fourcc == 'XMP ') {
      strippedAny = true;
    } else {
      if (fourcc == 'VP8X') vp8xStart = out.length;
      out.addAll(input.sublist(i, chunkEnd));
    }
    i = chunkEnd;
  }

  if (!strippedAny) return input;
  // Clear the EXIF (bit 3) + XMP (bit 2) feature flags in the VP8X payload so
  // a decoder doesn't go looking for chunks we removed.
  if (vp8xStart >= 0) out[vp8xStart + 8] &= ~0x0C;
  // Rewrite the RIFF file size (LE, excludes the leading 'RIFF' + size field).
  final newSize = out.length - 8;
  out[4] = newSize & 0xff;
  out[5] = (newSize >> 8) & 0xff;
  out[6] = (newSize >> 16) & 0xff;
  out[7] = (newSize >> 24) & 0xff;
  return Uint8List.fromList(out);
}

/// The image formats this module can actually clean. An upload surface must
/// accept nothing outside this set — see [stripImageExif].
const List<String> kStrippableImageMimeTypes = <String>[
  'image/jpeg',
  'image/png',
  'image/webp',
];

bool canStripImageExif(String mime) => kStrippableImageMimeTypes.contains(mime);

/// Storage extension for a sniffed image MIME. Derived from the bytes, never
/// from the picked filename, so the stored object's extension and its
/// Content-Type can't disagree.
String imageExtensionForMime(String mime) {
  switch (mime) {
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    default:
      return 'jpg';
  }
}

/// Identify an image buffer from its magic bytes, returning null for anything
/// outside [kStrippableImageMimeTypes].
///
/// The dispatch must not trust a filename-derived MIME: the picker reports
/// whatever the camera roll named the file, so `IMG_0001.HEIC` and a `.jpg`
/// holding HEIC bytes both mislead it, and a buffer handed to the wrong walker
/// fails its signature check and is returned — and uploaded — unstripped.
String? detectImageMime(Uint8List input) {
  if (input.length >= 3 &&
      input[0] == 0xFF &&
      input[1] == 0xD8 &&
      input[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (input.length >= 8) {
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    var isPng = true;
    for (var i = 0; i < png.length; i++) {
      if (input[i] != png[i]) {
        isPng = false;
        break;
      }
    }
    if (isPng) return 'image/png';
  }
  if (input.length >= 12 &&
      String.fromCharCodes(input.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(input.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}

class UnstrippableImageException implements Exception {
  const UnstrippableImageException(this.mime);
  final String mime;
  @override
  String toString() =>
      'Cannot strip metadata from ${mime.isEmpty ? 'unknown image type' : mime}';
}

/// Strip location-bearing metadata from an image buffer, dispatched by MIME.
/// JPEG → APP1 marker-walk, PNG → metadata-chunk walk, WebP → RIFF-chunk walk.
///
/// Anything else throws. Returning the input unchanged would upload a
/// geotagged original verbatim, which is the exact leak this module exists to
/// prevent — and no later layer catches it: the Go worker's `StripJPEG`
/// returns early on any non-JPEG too.
Uint8List stripImageExif(Uint8List input, String mime) {
  switch (mime) {
    case 'image/jpeg':
      return stripJpegExif(input);
    case 'image/png':
      return stripPngMetadata(input);
    case 'image/webp':
      return stripWebpMetadata(input);
    default:
      throw UnstrippableImageException(mime);
  }
}
