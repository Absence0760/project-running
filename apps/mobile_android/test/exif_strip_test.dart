import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../lib/exif_strip.dart';

/// Helper: assemble a minimal JPEG byte stream from a list of segments.
Uint8List _jpeg(List<List<int>> segments) =>
    Uint8List.fromList(segments.expand((s) => s).toList());

/// A length-bearing segment: FF, marker, 2-byte big-endian length
/// (length counts the 2 length bytes + payload), then payload.
List<int> _seg(int marker, List<int> payload) {
  final len = payload.length + 2;
  return [0xFF, marker, (len >> 8) & 0xFF, len & 0xFF, ...payload];
}

void main() {
  final soi = [0xFF, 0xD8];
  final eoi = [0xFF, 0xD9];
  final sos = [0xFF, 0xDA, 0x00, 0x02]; // SOS header (len 2, no payload)
  final scan = [0x12, 0x34, 0x56]; // pretend entropy-coded data

  group('stripJpegExif', () {
    test('removes the APP1 (EXIF) segment, keeps everything else', () {
      // EXIF APP1 payload begins "Exif\0\0" then TIFF — content irrelevant
      // to the marker walk; use a recognisable filler.
      final exif = _seg(0xE1, [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0xDE, 0xAD]);
      final jfif = _seg(0xE0, [0x4A, 0x46, 0x49, 0x46, 0x00]); // APP0
      final dqt = _seg(0xDB, [0x00, 0x01, 0x02]);
      final input = _jpeg([soi, jfif, exif, dqt, sos, scan, eoi]);
      final out = stripJpegExif(input);

      // No FFE1 marker survives.
      var hasApp1 = false;
      for (var i = 0; i + 1 < out.length; i++) {
        if (out[i] == 0xFF && out[i + 1] == 0xE1) hasApp1 = true;
      }
      expect(hasApp1, isFalse, reason: 'APP1/EXIF must be stripped');
      // APP0 (JFIF) and the scan data survive.
      final expected = _jpeg([soi, jfif, dqt, sos, scan, eoi]);
      expect(out, equals(expected));
    });

    test('keeps the ICC colour profile (APP2) — only APP1 is stripped', () {
      final exif = _seg(0xE1, [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]);
      final icc = _seg(0xE2, [0x49, 0x43, 0x43, 0x5F]); // APP2
      final input = _jpeg([soi, exif, icc, sos, scan, eoi]);
      final out = stripJpegExif(input);
      var hasApp2 = false;
      for (var i = 0; i + 1 < out.length; i++) {
        if (out[i] == 0xFF && out[i + 1] == 0xE2) hasApp2 = true;
      }
      expect(hasApp2, isTrue, reason: 'ICC profile (APP2) must survive');
    });

    test('returns the same buffer unchanged when there is no APP1', () {
      final jfif = _seg(0xE0, [0x4A, 0x46, 0x49, 0x46, 0x00]);
      final input = _jpeg([soi, jfif, sos, scan, eoi]);
      final out = stripJpegExif(input);
      expect(identical(out, input), isTrue,
          reason: 'no-op should not reallocate');
    });

    test('non-JPEG input is returned unchanged (e.g. PNG signature)', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
      expect(identical(stripJpegExif(png), png), isTrue);
    });

    test('truncated / tiny buffers are returned unchanged', () {
      final tiny = Uint8List.fromList([0xFF, 0xD8]);
      expect(identical(stripJpegExif(tiny), tiny), isTrue);
    });

    test('does not run off the end on a declared length past EOF', () {
      // APP1 claims a huge length but the buffer ends — must not throw,
      // and must copy the remainder rather than dropping data.
      final input = Uint8List.fromList([...soi, 0xFF, 0xE1, 0xFF, 0xF0, 0x01]);
      final out = stripJpegExif(input);
      expect(out, equals(input)); // bail-safe: copy remainder verbatim
    });
  });

  List<int> cc(String s) => s.codeUnits;

  bool hasChunk(Uint8List out, String type) {
    final t = cc(type);
    for (var i = 0; i + 4 <= out.length; i++) {
      if (out[i] == t[0] && out[i + 1] == t[1] && out[i + 2] == t[2] && out[i + 3] == t[3]) {
        return true;
      }
    }
    return false;
  }

  final pngSig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  // [len(4 BE)][type(4)][data][crc(4)] — the stripper ignores the CRC value.
  List<int> pngChunk(String type, List<int> data) {
    final len = data.length;
    return [
      (len >> 24) & 0xFF, (len >> 16) & 0xFF, (len >> 8) & 0xFF, len & 0xFF,
      ...cc(type), ...data, 0, 0, 0, 0,
    ];
  }

  group('stripPngMetadata', () {
    test('removes the eXIf (GPS) chunk, keeps structural chunks', () {
      final input = Uint8List.fromList([
        ...pngSig,
        ...pngChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]),
        ...pngChunk('eXIf', [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0xDE, 0xAD]),
        ...pngChunk('IDAT', [0x78, 0x9C, 0x62, 0x00]),
        ...pngChunk('IEND', []),
      ]);
      final out = stripPngMetadata(input);
      expect(hasChunk(out, 'eXIf'), isFalse, reason: 'eXIf/GPS must be stripped');
      expect(hasChunk(out, 'IHDR'), isTrue);
      expect(hasChunk(out, 'IDAT'), isTrue);
      expect(hasChunk(out, 'IEND'), isTrue);
    });

    test('drops iTXt and no-ops when clean', () {
      final withText = Uint8List.fromList([
        ...pngSig,
        ...pngChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]),
        ...pngChunk('iTXt', [0x66, 0x6F, 0x6F]),
        ...pngChunk('IDAT', [0x78, 0x9C]),
        ...pngChunk('IEND', []),
      ]);
      expect(hasChunk(stripPngMetadata(withText), 'iTXt'), isFalse);

      final clean = Uint8List.fromList([
        ...pngSig,
        ...pngChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]),
        ...pngChunk('IDAT', [0x78, 0x9C]),
        ...pngChunk('IEND', []),
      ]);
      expect(identical(stripPngMetadata(clean), clean), isTrue,
          reason: 'no-op should not reallocate');
    });
  });

  List<int> webpChunk(String fourcc, List<int> data) {
    final size = data.length;
    return [
      ...cc(fourcc),
      size & 0xFF, (size >> 8) & 0xFF, (size >> 16) & 0xFF, (size >> 24) & 0xFF,
      ...data,
      if (size & 1 == 1) 0,
    ];
  }

  Uint8List webp(List<List<int>> chunks) {
    final body = chunks.expand((c) => c).toList();
    final size = 4 + body.length; // 'WEBP' + chunks
    return Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46,
      size & 0xFF, (size >> 8) & 0xFF, (size >> 16) & 0xFF, (size >> 24) & 0xFF,
      ...cc('WEBP'),
      ...body,
    ]);
  }

  group('stripWebpMetadata', () {
    test('removes EXIF, clears the VP8X flag, fixes the RIFF size', () {
      final vp8x = webpChunk('VP8X', [0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      final image = webpChunk('VP8 ', [0x11, 0x22, 0x33, 0x44]);
      final exif = webpChunk('EXIF', [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0xDE, 0xAD]);
      final input = webp([vp8x, image, exif]);
      final out = stripWebpMetadata(input);

      expect(hasChunk(out, 'EXIF'), isFalse, reason: 'EXIF chunk must be stripped');
      expect(hasChunk(out, 'VP8 '), isTrue, reason: 'image data must survive');
      var vpIdx = -1;
      final v = cc('VP8X');
      for (var i = 0; i + 4 <= out.length; i++) {
        if (out[i] == v[0] && out[i + 1] == v[1] && out[i + 2] == v[2] && out[i + 3] == v[3]) {
          vpIdx = i;
          break;
        }
      }
      expect(out[vpIdx + 8] & 0x08, 0, reason: 'EXIF feature flag must be cleared');
      final declared = out[4] | (out[5] << 8) | (out[6] << 16) | (out[7] << 24);
      expect(declared, out.length - 8);
    });
  });

  group('stripImageExif', () {
    test('dispatches by MIME and no-ops on an unknown type', () {
      final exifJpeg = Uint8List.fromList([
        ...soi,
        ..._seg(0xE1, [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]),
        ...sos,
        ...scan,
        ...eoi,
      ]);
      final cleaned = stripImageExif(exifJpeg, 'image/jpeg');
      var hasApp1 = false;
      for (var i = 0; i + 1 < cleaned.length; i++) {
        if (cleaned[i] == 0xFF && cleaned[i + 1] == 0xE1) hasApp1 = true;
      }
      expect(hasApp1, isFalse);
      final gif = Uint8List.fromList([0x47, 0x49, 0x46, 0x38]);
      expect(identical(stripImageExif(gif, 'image/gif'), gif), isTrue);
    });
  });
}
