import 'package:flutter_test/flutter_test.dart';

// Mirror of _fitCrc from widgets/run_share_card.dart. Keep in sync.
int fitCrc(int crc, int byte) {
  const table = [
    0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
    0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
  ];
  var tmp = table[crc & 0xF] ^ table[byte & 0xF];
  crc = (crc >> 4) & 0x0FFF;
  crc = crc ^ tmp ^ table[(byte >> 4) & 0xF];
  return crc;
}

int computeCrc(List<int> bytes, {required int startOffset}) {
  var crc = 0;
  for (var i = startOffset; i < bytes.length; i++) {
    crc = fitCrc(crc, bytes[i]);
  }
  return crc;
}

void main() {
  group('FIT export CRC', () {
    // A synthetic 20-byte buffer: 14-byte file header + 6 bytes of record data.
    // The FIT spec requires the data CRC to cover only bytes [14, end).
    final buffer = [
      // 14-byte FIT file header (bytes 0–13)
      0x0E, 0x10, 0xD9, 0x07, // header size, protocol, profile version
      0x06, 0x00, 0x00, 0x00, // data size (6 bytes)
      0x2E, 0x46, 0x49, 0x54, // ".FIT"
      0x00, 0x00,             // header CRC (zeroed)
      // 6 bytes of record data (bytes 14–19)
      0x40, 0x00, 0x00, 0x04, 0x00, 0x01,
    ];

    test('CRC over data-only bytes [14..end) is non-zero and deterministic', () {
      final crc = computeCrc(buffer, startOffset: 14);
      // The exact value is deterministic for this input; verify it is non-zero
      // and stable across invocations.
      expect(crc, isNonZero);
      expect(crc, computeCrc(buffer, startOffset: 14));
    });

    test('CRC over all bytes [0..end) differs from the spec-correct [14..end)', () {
      final crcFromZero = computeCrc(buffer, startOffset: 0);
      final crcFromHeader = computeCrc(buffer, startOffset: 14);
      // Including the header shifts the CRC — parsers that validate the data
      // CRC will reject files computed from offset 0.
      expect(crcFromZero, isNot(equals(crcFromHeader)));
    });

    test('CRC of empty data range is zero (accumulator starts at 0)', () {
      // Verifies the accumulator identity: no data → CRC stays 0.
      final crc = computeCrc(buffer, startOffset: buffer.length);
      expect(crc, 0);
    });
  });
}
