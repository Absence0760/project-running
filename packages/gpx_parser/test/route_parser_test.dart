import 'dart:typed_data';

import 'package:gpx_parser/gpx_parser.dart';
import 'package:test/test.dart';

const _equatorOneThousandthDeg = 111.1949;

void main() {
  group('RouteParser.fromGpx', () {
    test('parses trkpt nodes with elevation, summing distance', () {
      const gpx = '''<?xml version="1.0"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>Morning Run</name></metadata>
  <trk><trkseg>
    <trkpt lat="0.0" lon="0.0"><ele>10.0</ele></trkpt>
    <trkpt lat="0.0" lon="0.001"><ele>15.0</ele></trkpt>
    <trkpt lat="0.0" lon="0.002"><ele>12.0</ele></trkpt>
  </trkseg></trk>
</gpx>''';

      final r = RouteParser.fromGpx(gpx);

      expect(r.name, 'Morning Run');
      expect(r.waypoints, hasLength(3));
      expect(r.waypoints[0].lat, 0.0);
      expect(r.waypoints[0].lng, 0.0);
      expect(r.waypoints[0].elevationMetres, 10.0);
      expect(r.distanceMetres, closeTo(2 * _equatorOneThousandthDeg, 0.01));
      expect(r.elevationGainMetres, 5.0);
    });

    test('falls back to rtept when no trkpt is present', () {
      const gpx = '''<?xml version="1.0"?>
<gpx><rte>
  <name>Planned Loop</name>
  <rtept lat="0.0" lon="0.0"/>
  <rtept lat="0.0" lon="0.001"/>
</rte></gpx>''';

      final r = RouteParser.fromGpx(gpx);

      expect(r.name, 'Planned Loop');
      expect(r.waypoints, hasLength(2));
      expect(r.distanceMetres, closeTo(_equatorOneThousandthDeg, 0.01));
    });

    test('falls back to wpt when no trkpt or rtept', () {
      const gpx = '''<?xml version="1.0"?>
<gpx>
  <wpt lat="0.0" lon="0.0"/>
  <wpt lat="0.0" lon="0.001"/>
</gpx>''';

      final r = RouteParser.fromGpx(gpx);

      expect(r.waypoints, hasLength(2));
      expect(r.distanceMetres, closeTo(_equatorOneThousandthDeg, 0.01));
    });

    test('skips trkpt with non-numeric lat or lon', () {
      const gpx = '''<?xml version="1.0"?>
<gpx><trk><trkseg>
  <trkpt lat="0.0" lon="0.0"/>
  <trkpt lat="bad" lon="0.001"/>
  <trkpt lat="0.0" lon="0.002"/>
</trkseg></trk></gpx>''';

      final r = RouteParser.fromGpx(gpx);

      expect(r.waypoints, hasLength(2));
      expect(r.waypoints[1].lng, 0.002);
    });

    test('defaults name to "Imported route" when no <name> tag exists', () {
      const gpx = '''<?xml version="1.0"?>
<gpx><trk><trkseg>
  <trkpt lat="0.0" lon="0.0"/>
</trkseg></trk></gpx>''';

      final r = RouteParser.fromGpx(gpx);

      expect(r.name, 'Imported route');
    });

    test('uses the track name, not a <wpt> label appearing earlier in the doc', () {
      // The bug: the route name was the first <name> ANYWHERE, so a
      // waypoint label that precedes the track shadowed the real name.
      const gpx = '''<?xml version="1.0"?>
<gpx>
  <wpt lat="0.0" lon="0.0"><name>Start Flag</name></wpt>
  <trk><name>Saturday Long Run</name><trkseg>
    <trkpt lat="0.0" lon="0.0"/>
    <trkpt lat="0.0" lon="0.001"/>
  </trkseg></trk>
</gpx>''';

      final r = RouteParser.fromGpx(gpx);

      expect(r.name, 'Saturday Long Run');
      expect(r.waypoints, hasLength(2));
    });

    test('ignores a per-trkpt <name> when the track itself has no name', () {
      const gpx = '''<?xml version="1.0"?>
<gpx><trk><trkseg>
  <trkpt lat="0.0" lon="0.0"><name>Mile 1 marker</name></trkpt>
  <trkpt lat="0.0" lon="0.001"/>
</trkseg></trk></gpx>''';

      final r = RouteParser.fromGpx(gpx);

      expect(r.name, 'Imported route');
    });

    test('elevationGain ignores descents — only positive deltas counted', () {
      const gpx = '''<?xml version="1.0"?>
<gpx><trk><trkseg>
  <trkpt lat="0.0" lon="0.0"><ele>100</ele></trkpt>
  <trkpt lat="0.0" lon="0.001"><ele>110</ele></trkpt>
  <trkpt lat="0.0" lon="0.002"><ele>50</ele></trkpt>
  <trkpt lat="0.0" lon="0.003"><ele>70</ele></trkpt>
</trkseg></trk></gpx>''';

      final r = RouteParser.fromGpx(gpx);

      expect(r.elevationGainMetres, closeTo(30.0, 1e-9));
    });

    test('parses <time> on each trkpt into Waypoint.timestamp', () {
      const gpx = '''<?xml version="1.0"?>
<gpx version="1.1"><trk><trkseg>
  <trkpt lat="0" lon="0"><time>2026-04-09T07:30:00Z</time></trkpt>
  <trkpt lat="0" lon="0.001"><time>2026-04-09T07:30:30Z</time></trkpt>
</trkseg></trk></gpx>''';

      final r = RouteParser.fromGpx(gpx);

      expect(r.waypoints[0].timestamp, DateTime.utc(2026, 4, 9, 7, 30, 0));
      expect(r.waypoints[1].timestamp, DateTime.utc(2026, 4, 9, 7, 30, 30));
    });

    test('trkpt without <time> leaves timestamp null', () {
      const gpx = '''<?xml version="1.0"?>
<gpx><trk><trkseg>
  <trkpt lat="0" lon="0"><ele>10</ele></trkpt>
</trkseg></trk></gpx>''';

      final r = RouteParser.fromGpx(gpx);
      expect(r.waypoints.single.timestamp, isNull);
    });

    test('returns empty waypoint list when GPX has no points at all', () {
      const gpx = '''<?xml version="1.0"?>
<gpx><metadata><name>Empty</name></metadata></gpx>''';

      final r = RouteParser.fromGpx(gpx);

      expect(r.name, 'Empty');
      expect(r.waypoints, isEmpty);
      expect(r.distanceMetres, 0.0);
      expect(r.elevationGainMetres, 0.0);
    });
  });

  group('RouteParser.fromKml', () {
    test('parses LineString coordinates with elevation', () {
      const kml = '''<?xml version="1.0"?>
<kml><Document><name>KML Run</name><Placemark>
  <LineString><coordinates>
    0.0,0.0,10
    0.001,0.0,15
    0.002,0.0,12
  </coordinates></LineString>
</Placemark></Document></kml>''';

      final r = RouteParser.fromKml(kml);

      expect(r.name, 'KML Run');
      expect(r.waypoints, hasLength(3));
      expect(r.waypoints[0].lat, 0.0);
      expect(r.waypoints[0].lng, 0.0);
      expect(r.waypoints[0].elevationMetres, 10.0);
      expect(r.distanceMetres, closeTo(2 * _equatorOneThousandthDeg, 0.01));
      expect(r.elevationGainMetres, 5.0);
    });

    test('returns empty Route when no <coordinates> element present', () {
      const kml = '''<?xml version="1.0"?>
<kml><Document><name>No coords</name></Document></kml>''';

      final r = RouteParser.fromKml(kml);

      expect(r.name, 'No coords');
      expect(r.waypoints, isEmpty);
      expect(r.distanceMetres, 0.0);
    });

    test('silently drops triples with non-numeric values', () {
      const kml = '''<?xml version="1.0"?>
<kml><Placemark><LineString><coordinates>
  0.0,0.0
  bad,0.0
  0.001,0.0
</coordinates></LineString></Placemark></kml>''';

      final r = RouteParser.fromKml(kml);

      expect(r.waypoints, hasLength(2));
      expect(r.waypoints[1].lng, 0.001);
    });

    test('handles coordinates without elevation — null on every waypoint', () {
      const kml = '''<?xml version="1.0"?>
<kml><Placemark><LineString><coordinates>
  0.0,0.0
  0.001,0.0
</coordinates></LineString></Placemark></kml>''';

      final r = RouteParser.fromKml(kml);

      expect(r.waypoints, hasLength(2));
      expect(r.waypoints[0].elevationMetres, isNull);
      expect(r.elevationGainMetres, 0.0);
    });
  });

  group('RouteParser.fromTcx', () {
    test('parses Trackpoint Position with altitude and timestamp', () {
      const tcx = '''<?xml version="1.0"?>
<TrainingCenterDatabase><Activities><Activity><Lap><Track>
  <Trackpoint>
    <Time>2026-04-10T10:00:00Z</Time>
    <Position><LatitudeDegrees>0.0</LatitudeDegrees><LongitudeDegrees>0.0</LongitudeDegrees></Position>
    <AltitudeMeters>10.0</AltitudeMeters>
  </Trackpoint>
  <Trackpoint>
    <Time>2026-04-10T10:00:30Z</Time>
    <Position><LatitudeDegrees>0.0</LatitudeDegrees><LongitudeDegrees>0.001</LongitudeDegrees></Position>
    <AltitudeMeters>15.0</AltitudeMeters>
  </Trackpoint>
</Track></Lap></Activity></Activities></TrainingCenterDatabase>''';

      final r = RouteParser.fromTcx(tcx);

      expect(r.waypoints, hasLength(2));
      expect(r.waypoints[0].timestamp, DateTime.utc(2026, 4, 10, 10, 0, 0));
      expect(r.waypoints[1].timestamp, DateTime.utc(2026, 4, 10, 10, 0, 30));
      expect(r.waypoints[0].elevationMetres, 10.0);
      expect(r.distanceMetres, closeTo(_equatorOneThousandthDeg, 0.01));
      expect(r.elevationGainMetres, 5.0);
    });

    test('skips Trackpoint with no Position element', () {
      const tcx = '''<?xml version="1.0"?>
<TrainingCenterDatabase><Activities><Activity><Lap><Track>
  <Trackpoint><Time>2026-04-10T10:00:00Z</Time></Trackpoint>
  <Trackpoint>
    <Position><LatitudeDegrees>0.0</LatitudeDegrees><LongitudeDegrees>0.0</LongitudeDegrees></Position>
  </Trackpoint>
</Track></Lap></Activity></Activities></TrainingCenterDatabase>''';

      final r = RouteParser.fromTcx(tcx);

      expect(r.waypoints, hasLength(1));
    });

    test('falls back to <Notes> when <Name> is absent', () {
      const tcx = '''<?xml version="1.0"?>
<TrainingCenterDatabase><Activities><Activity>
  <Notes>Tempo intervals</Notes>
  <Lap><Track>
    <Trackpoint>
      <Position><LatitudeDegrees>0.0</LatitudeDegrees><LongitudeDegrees>0.0</LongitudeDegrees></Position>
    </Trackpoint>
  </Track></Lap>
</Activity></Activities></TrainingCenterDatabase>''';

      final r = RouteParser.fromTcx(tcx);

      expect(r.name, 'Tempo intervals');
    });
  });

  group('RouteParser.fromGeoJson', () {
    test('parses LineString with [lng, lat, ele] coordinate order', () {
      final geojson = {
        'type': 'Feature',
        'properties': {'name': 'Geo Run'},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [0.0, 0.0, 10.0],
            [0.001, 0.0, 15.0],
            [0.002, 0.0, 8.0],
          ],
        },
      };

      final r = RouteParser.fromGeoJson(geojson);

      expect(r.name, 'Geo Run');
      expect(r.waypoints, hasLength(3));
      expect(r.waypoints[0].lat, 0.0);
      expect(r.waypoints[0].lng, 0.0);
      expect(r.waypoints[1].lng, 0.001);
      expect(r.waypoints[0].elevationMetres, 10.0);
      expect(r.distanceMetres, closeTo(2 * _equatorOneThousandthDeg, 0.01));
      expect(r.elevationGainMetres, 5.0);
    });

    test('handles 2D coordinates (no elevation)', () {
      final geojson = {
        'properties': {'name': 'Flat'},
        'geometry': {
          'coordinates': [
            [0.0, 0.0],
            [0.001, 0.0],
          ],
        },
      };

      final r = RouteParser.fromGeoJson(geojson);

      expect(r.waypoints, hasLength(2));
      expect(r.waypoints[0].elevationMetres, isNull);
      expect(r.elevationGainMetres, 0.0);
    });

    test('returns empty Route when geometry is missing', () {
      final geojson = {
        'properties': {'name': 'Headless'},
      };

      final r = RouteParser.fromGeoJson(geojson);

      expect(r.name, 'Headless');
      expect(r.waypoints, isEmpty);
      expect(r.distanceMetres, 0.0);
    });

    test('defaults name to "Imported route" when properties.name is absent', () {
      final geojson = {
        'geometry': {
          'coordinates': [
            [0.0, 0.0],
            [0.001, 0.0],
          ],
        },
      };

      final r = RouteParser.fromGeoJson(geojson);

      expect(r.name, 'Imported route');
    });

    test('skips coordinate entries that are not 2-element lists', () {
      final geojson = {
        'geometry': {
          'coordinates': [
            [0.0, 0.0],
            [0.001],
            [0.002, 0.0],
          ],
        },
      };

      final r = RouteParser.fromGeoJson(geojson);

      expect(r.waypoints, hasLength(2));
      expect(r.waypoints[1].lng, 0.002);
    });
  });

  group('FitParser', () {
    test('throws FormatException when bytes are too short', () {
      expect(
        () => FitParser.parse(Uint8List(8)),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when signature is not ".FIT"', () {
      final bytes = Uint8List(14);
      bytes[0] = 14;
      bytes[8] = 0x42;
      bytes[9] = 0x41;
      bytes[10] = 0x44;
      bytes[11] = 0x21;

      expect(
        () => FitParser.parse(bytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when header size is not 12 or 14', () {
      final bytes = Uint8List(20);
      bytes[0] = 16;
      expect(
        () => FitParser.parse(bytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses valid empty FIT file (just the header) into empty route', () {
      final bytes = Uint8List(14);
      bytes[0] = 14;
      bytes[1] = 0x10;
      bytes[2] = 0x00;
      bytes[3] = 0x00;
      bytes[4] = 0;
      bytes[5] = 0;
      bytes[6] = 0;
      bytes[7] = 0;
      bytes[8] = 0x2E;
      bytes[9] = 0x46;
      bytes[10] = 0x49;
      bytes[11] = 0x54;

      final r = FitParser.parse(bytes);
      expect(r.waypoints, isEmpty);
      expect(r.distanceMetres, 0.0);
      expect(r.name, 'FIT activity');
    });

    test('decodes lat/lng from compressed-timestamp record messages', () {
      // Synthetic FIT file: one record definition (lat field 0 + lng field 1,
      // both sint32, no timestamp field) followed by two data records that use
      // the *compressed-timestamp* record header (bit 7 set). Before this fix
      // these records were skipped, so the file parsed to zero waypoints.
      const semicirclesPerDegree = (1 << 31) / 180.0;
      int sc(double deg) => (deg * semicirclesPerDegree).round();

      int4le(int v) {
        final u = v < 0 ? v + 0x100000000 : v;
        return u;
      }

      void addSint32LE(List<int> out, double deg) {
        final u = int4le(sc(deg));
        out.add(u & 0xFF);
        out.add((u >> 8) & 0xFF);
        out.add((u >> 16) & 0xFF);
        out.add((u >> 24) & 0xFF);
      }

      final body = <int>[];

      // Definition message, local type 0:
      //   header 0x40, reserved, arch (0 = LE), global mesg num 20 (record),
      //   2 fields: (num 0, size 4, baseType 0x85=sint32), (num 1, size 4, 0x85)
      body.addAll([
        0x40, // definition message, local type 0
        0x00, // reserved
        0x00, // little-endian
        20, 0, // global mesg num = 20 (record), LE
        2, // num fields
        0, 4, 0x85, // field 0 (lat), 4 bytes, sint32
        1, 4, 0x85, // field 1 (lng), 4 bytes, sint32
      ]);

      // Compressed-timestamp data record, local type 0, time offset 5.
      //   header = 0x80 | (localType << 5) | timeOffset = 0x80 | 0x00 | 0x05.
      body.add(0x85);
      addSint32LE(body, 51.5);
      addSint32LE(body, -0.12);

      // A second compressed-timestamp record with a later time offset.
      body.add(0x87);
      addSint32LE(body, 51.6);
      addSint32LE(body, -0.13);

      final dataSize = body.length;
      final bytes = Uint8List(14 + dataSize);
      bytes[0] = 14; // header size
      bytes[1] = 0x10; // protocol version
      bytes[2] = 0x00; // profile version LE
      bytes[3] = 0x00;
      bytes[4] = dataSize & 0xFF;
      bytes[5] = (dataSize >> 8) & 0xFF;
      bytes[6] = (dataSize >> 16) & 0xFF;
      bytes[7] = (dataSize >> 24) & 0xFF;
      bytes[8] = 0x2E; // '.'
      bytes[9] = 0x46; // 'F'
      bytes[10] = 0x49; // 'I'
      bytes[11] = 0x54; // 'T'
      // bytes 12-13 = header CRC, left zero (parser doesn't verify it).
      for (var i = 0; i < dataSize; i++) {
        bytes[14 + i] = body[i];
      }

      final r = FitParser.parse(bytes);
      expect(r.waypoints, hasLength(2));
      expect(r.waypoints[0].lat, closeTo(51.5, 1e-4));
      expect(r.waypoints[0].lng, closeTo(-0.12, 1e-4));
      expect(r.waypoints[1].lat, closeTo(51.6, 1e-4));
      expect(r.waypoints[1].lng, closeTo(-0.13, 1e-4));
    });
  });
}
