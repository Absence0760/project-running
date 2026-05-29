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
}
