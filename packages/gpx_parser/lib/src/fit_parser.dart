import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_models/core_models.dart';

/// Minimal FIT file parser that extracts GPS trackpoints from activity files.
///
/// The FIT (Flexible and Interoperable Data Transfer) protocol is Garmin's
/// binary format used by Garmin, Wahoo, COROS, Hammerhead, and most cycling
/// computers. Strava data exports include FIT files for activities originally
/// recorded on these devices.
///
/// This parser reads just enough of the FIT spec to extract lat/lng/altitude/
/// timestamp from "record" messages (global message number 20). It ignores
/// every other message type (session, lap, device info, etc.).
class FitParser {
  /// FIT epoch: December 31, 1989, 00:00:00 UTC.
  static final _fitEpoch = DateTime.utc(1989, 12, 31);

  /// Semicircles to degrees conversion factor.
  static const _semicirclesToDegrees = 180.0 / (1 << 31);

  /// Record message global number in the FIT profile.
  static const _recordMesgNum = 20;

  // Field definition numbers for record messages.
  static const _fieldPositionLat = 0;
  static const _fieldPositionLng = 1;
  static const _fieldAltitude = 2;
  static const _fieldTimestamp = 253;
  static const _fieldEnhancedAltitude = 78;

  /// Parse a FIT binary file into a [Route].
  ///
  /// Throws [FormatException] if the file is not a valid FIT file.
  static Route parse(Uint8List bytes) {
    if (bytes.length < 14) {
      throw const FormatException('FIT file too short');
    }

    // -- File header --
    final headerSize = bytes[0];
    if (headerSize != 12 && headerSize != 14) {
      throw FormatException('Invalid FIT header size: $headerSize');
    }
    // Bytes 4-7: data size (little-endian)
    final dataSize = _readUint32LE(bytes, 4);
    // Bytes 8-11: ".FIT" signature
    final sig = String.fromCharCodes(bytes.sublist(8, 12));
    if (sig != '.FIT') {
      throw FormatException('Not a FIT file (signature: $sig)');
    }

    final dataStart = headerSize;
    final dataEnd = dataStart + dataSize;
    if (dataEnd > bytes.length) {
      throw const FormatException('FIT data extends past end of file');
    }

    // -- Parse data records --
    // Track definition messages so we know how to decode data messages.
    final definitions = <int, _FieldDefinition>{};
    final waypoints = <Waypoint>[];
    var offset = dataStart;

    while (offset < dataEnd) {
      final recordHeader = bytes[offset++];
      final isCompressedTimestamp = (recordHeader & 0x80) != 0;

      if (isCompressedTimestamp) {
        // Compressed timestamp header: bits 5-6 = local message type,
        // bits 0-4 = time offset.
        final localType = (recordHeader >> 5) & 0x03;
        final def = definitions[localType];
        if (def == null) {
          break; // can't decode without a definition
        }
        // Skip the data fields — we only care about normal record messages.
        offset += def.totalFieldSize;
        continue;
      }

      final isDefinition = (recordHeader & 0x40) != 0;
      final localType = recordHeader & 0x0F;

      if (isDefinition) {
        // Definition message.
        if (offset + 5 > dataEnd) break;
        offset++; // reserved byte
        final architecture = bytes[offset++]; // 0 = little-endian, 1 = big
        final bigEndian = architecture == 1;
        final globalMesgNum = bigEndian
            ? _readUint16BE(bytes, offset)
            : _readUint16LE(bytes, offset);
        offset += 2;
        final numFields = bytes[offset++];

        final fields = <_Field>[];
        var totalSize = 0;
        for (var f = 0; f < numFields; f++) {
          if (offset + 3 > dataEnd) break;
          final fieldNum = bytes[offset++];
          final size = bytes[offset++];
          final baseType = bytes[offset++];
          fields.add(_Field(fieldNum, size, baseType));
          totalSize += size;
        }

        // Handle developer fields (bit 5 of record header).
        if ((recordHeader & 0x20) != 0) {
          if (offset < dataEnd) {
            final numDevFields = bytes[offset++];
            for (var d = 0; d < numDevFields; d++) {
              if (offset + 3 > dataEnd) break;
              offset++; // field number
              final size = bytes[offset++];
              offset++; // dev data index
              totalSize += size;
            }
          }
        }

        definitions[localType] = _FieldDefinition(
          globalMesgNum: globalMesgNum,
          bigEndian: bigEndian,
          fields: fields,
          totalFieldSize: totalSize,
        );
      } else {
        // Data message.
        final def = definitions[localType];
        if (def == null) {
          break;
        }

        if (def.globalMesgNum == _recordMesgNum) {
          final wp = _parseRecordMessage(bytes, offset, def);
          if (wp != null) waypoints.add(wp);
        }
        offset += def.totalFieldSize;
      }
    }

    return _buildRoute(waypoints);
  }

  static Waypoint? _parseRecordMessage(
      Uint8List bytes, int startOffset, _FieldDefinition def) {
    int? rawLat;
    int? rawLng;
    int? rawAltitude;
    int? rawEnhancedAlt;
    int? rawTimestamp;

    var offset = startOffset;
    for (final field in def.fields) {
      if (offset + field.size > bytes.length) break;

      switch (field.fieldNum) {
        case _fieldPositionLat:
          if (field.size >= 4) {
            rawLat = def.bigEndian
                ? _readSint32BE(bytes, offset)
                : _readSint32LE(bytes, offset);
            if (rawLat == 0x7FFFFFFF) rawLat = null; // invalid sentinel
          }
        case _fieldPositionLng:
          if (field.size >= 4) {
            rawLng = def.bigEndian
                ? _readSint32BE(bytes, offset)
                : _readSint32LE(bytes, offset);
            if (rawLng == 0x7FFFFFFF) rawLng = null;
          }
        case _fieldAltitude:
          if (field.size >= 2) {
            final v = def.bigEndian
                ? _readUint16BE(bytes, offset)
                : _readUint16LE(bytes, offset);
            if (v != 0xFFFF) rawAltitude = v;
          }
        case _fieldEnhancedAltitude:
          if (field.size >= 4) {
            final v = def.bigEndian
                ? _readUint32BE(bytes, offset)
                : _readUint32LE(bytes, offset);
            if (v != 0xFFFFFFFF) rawEnhancedAlt = v;
          }
        case _fieldTimestamp:
          if (field.size >= 4) {
            final v = def.bigEndian
                ? _readUint32BE(bytes, offset)
                : _readUint32LE(bytes, offset);
            if (v != 0xFFFFFFFF) rawTimestamp = v;
          }
      }
      offset += field.size;
    }

    if (rawLat == null || rawLng == null) return null;

    final lat = rawLat * _semicirclesToDegrees;
    final lng = rawLng * _semicirclesToDegrees;

    double? elevation;
    if (rawEnhancedAlt != null) {
      elevation = rawEnhancedAlt / 5.0 - 500.0;
    } else if (rawAltitude != null) {
      elevation = rawAltitude / 5.0 - 500.0;
    }

    DateTime? timestamp;
    if (rawTimestamp != null) {
      timestamp = _fitEpoch.add(Duration(seconds: rawTimestamp));
    }

    return Waypoint(
      lat: lat,
      lng: lng,
      elevationMetres: elevation,
      timestamp: timestamp,
    );
  }

  static Route _buildRoute(List<Waypoint> points) {
    double distance = 0;
    double elevationGain = 0;
    for (int i = 1; i < points.length; i++) {
      distance += _haversine(
        points[i - 1].lat,
        points[i - 1].lng,
        points[i].lat,
        points[i].lng,
      );
      final prev = points[i - 1].elevationMetres;
      final curr = points[i].elevationMetres;
      if (prev != null && curr != null && curr > prev) {
        elevationGain += curr - prev;
      }
    }
    return Route(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'FIT activity',
      waypoints: points,
      distanceMetres: distance,
      elevationGainMetres: elevationGain,
    );
  }

  // -- Binary readers --

  static int _readUint16LE(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _readUint16BE(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
  static int _readUint32LE(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
  static int _readUint32BE(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _readSint32LE(Uint8List b, int o) {
    final v = _readUint32LE(b, o);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  static int _readSint32BE(Uint8List b, int o) {
    final v = _readUint32BE(b, o);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  static double _haversine(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}

class _FieldDefinition {
  final int globalMesgNum;
  final bool bigEndian;
  final List<_Field> fields;
  final int totalFieldSize;

  const _FieldDefinition({
    required this.globalMesgNum,
    required this.bigEndian,
    required this.fields,
    required this.totalFieldSize,
  });
}

class _Field {
  final int fieldNum;
  final int size;
  final int baseType;

  const _Field(this.fieldNum, this.size, this.baseType);
}
