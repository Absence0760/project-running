import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../lib/local_route_store.dart';
import '../lib/shared_file_import.dart';

const _gpx = '''<?xml version="1.0"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>Shared Route</name></metadata>
  <trk><trkseg>
    <trkpt lat="0.0" lon="0.0"><ele>10.0</ele></trkpt>
    <trkpt lat="0.0" lon="0.001"><ele>12.0</ele></trkpt>
    <trkpt lat="0.0" lon="0.002"><ele>11.0</ele></trkpt>
  </trkseg></trk>
</gpx>''';

const _kml = '''<?xml version="1.0"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document><name>Shared KML</name>
    <Placemark><LineString><coordinates>
      0.0,0.0,10 0.001,0.0,12 0.002,0.0,11
    </coordinates></LineString></Placemark>
  </Document>
</kml>''';

const _tcx = '''<?xml version="1.0"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Courses><Course><Name>Shared TCX</Name><Track>
    <Trackpoint><Position><LatitudeDegrees>0.0</LatitudeDegrees><LongitudeDegrees>0.0</LongitudeDegrees></Position></Trackpoint>
    <Trackpoint><Position><LatitudeDegrees>0.0</LatitudeDegrees><LongitudeDegrees>0.001</LongitudeDegrees></Position></Trackpoint>
    <Trackpoint><Position><LatitudeDegrees>0.0</LatitudeDegrees><LongitudeDegrees>0.002</LongitudeDegrees></Position></Trackpoint>
  </Track></Course></Courses>
</TrainingCenterDatabase>''';

const _geojson = '''{"type":"FeatureCollection","features":[{"type":"Feature",
  "properties":{"name":"Shared GeoJSON"},
  "geometry":{"type":"LineString","coordinates":[[0.0,0.0],[0.001,0.0],[0.002,0.0]]}}]}''';

// Build the service with an inert plugin surface so a test never opens the
// receive_sharing_intent MethodChannel — importPath is exercised directly.
SharedFileImportService _service(LocalRouteStore store) =>
    SharedFileImportService(
      routeStore: store,
      mediaStream: const Stream<List<SharedMediaFile>>.empty(),
      initialMedia: () async => const <SharedMediaFile>[],
      reset: () {},
    );

void main() {
  group('detectRouteFormat', () {
    test('honours a known extension', () {
      expect(detectRouteFormat(extension: 'gpx', content: ''), 'gpx');
      expect(detectRouteFormat(extension: 'kml', content: ''), 'kml');
    });
    test('is case-insensitive on the extension', () {
      expect(detectRouteFormat(extension: 'GPX', content: ''), 'gpx');
      expect(detectRouteFormat(extension: 'KML', content: ''), 'kml');
    });
    test('sniffs GPX content when the extension is missing or unknown', () {
      expect(detectRouteFormat(extension: null, content: _gpx), 'gpx');
      expect(detectRouteFormat(extension: 'bin', content: _gpx), 'gpx');
    });
    test('sniffs KML content when the extension is missing or unknown', () {
      expect(detectRouteFormat(extension: null, content: _kml), 'kml');
      expect(detectRouteFormat(extension: 'dat', content: _kml), 'kml');
    });
    test('returns null for a non-route file', () {
      expect(detectRouteFormat(extension: 'txt', content: 'hello world'), isNull);
      expect(detectRouteFormat(extension: null, content: '{"a":1}'), isNull);
    });
  });

  group('every promised format is actually offered and parsed', () {
    test('the picker allowlist is exactly the formats plus their aliases', () {
      // The screen used to hand FilePicker a hardcoded `['gpx', 'kml']` while
      // the empty-state copy promised more, so a `.geojson` or `.tcx` chosen
      // through the OS share sheet was parsed as GPX and failed.
      expect(kSupportedRouteImportExtensions,
          {'gpx', 'kml', 'geojson', 'tcx'});
      expect(kRouteImportPickerExtensions,
          containsAll(<String>['gpx', 'kml', 'geojson', 'json', 'tcx']));
      expect(kSupportedRouteImportExtensions.contains('kmz'), isFalse,
          reason: 'a KMZ is a zip and this pipeline is string-typed');
    });

    test('a .geojson extension resolves and parses', () {
      expect(detectRouteFormat(extension: 'geojson', content: _geojson),
          'geojson');
      final r = routeFromImportedFile(format: 'geojson', content: _geojson);
      expect(r.name, 'Shared GeoJSON');
      expect(r.waypoints, hasLength(3));
    });

    test('a GeoJSON saved as .json resolves through the alias', () {
      expect(detectRouteFormat(extension: 'json', content: _geojson),
          'geojson');
    });

    test('a .tcx extension resolves and parses', () {
      expect(detectRouteFormat(extension: 'tcx', content: _tcx), 'tcx');
      final r = routeFromImportedFile(format: 'tcx', content: _tcx);
      expect(r.name, 'Shared TCX');
      expect(r.waypoints, hasLength(3));
    });

    test('content is sniffed when the extension is missing', () {
      expect(detectRouteFormat(extension: null, content: _tcx), 'tcx');
      expect(detectRouteFormat(extension: null, content: _geojson), 'geojson');
      expect(detectRouteFormat(extension: 'bin', content: _geojson), 'geojson');
    });

    test('every locale names exactly the formats the picker offers', () {
      // The promise and the picker drifted apart once already: the screen
      // comment said five formats, the copy said three, and the picker took
      // two. Format names are not translated, so the same assertion holds in
      // every catalogue.
      const labels = <String, String>{
        'gpx': 'GPX',
        'kml': 'KML',
        'geojson': 'GeoJSON',
        'tcx': 'TCX',
      };
      expect(labels.keys.toSet(), kSupportedRouteImportExtensions,
          reason: 'a format added to the picker needs a label here');
      for (final arb in Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))) {
        final body = (jsonDecode(arb.readAsStringSync())
            as Map<String, dynamic>)['routesEmptyBody'] as String;
        for (final label in labels.values) {
          expect(body, contains(label), reason: '${arb.path} omits $label');
        }
        expect(body.contains('KMZ'), isFalse,
            reason: '${arb.path} promises a format nothing can open');
      }
    });

    test('routesFromImportedFile returns every line of each format', () {
      expect(routesFromImportedFile(format: 'geojson', content: _geojson),
          hasLength(1));
      expect(routesFromImportedFile(format: 'tcx', content: _tcx),
          hasLength(1));
    });
  });

  group('routeFromImportedFile', () {
    test('parses a GPX body', () {
      final r = routeFromImportedFile(format: 'gpx', content: _gpx);
      expect(r.name, 'Shared Route');
      expect(r.waypoints, hasLength(3));
    });
    test('parses a KML body', () {
      final r = routeFromImportedFile(format: 'kml', content: _kml);
      expect(r.name, 'Shared KML');
      expect(r.waypoints, hasLength(3));
    });
  });

  group('SharedFileImportService.importPath', () {
    late Directory tmp;
    late LocalRouteStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('shared_import_test');
      store = LocalRouteStore();
    });
    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    testWidgets('imports a .gpx file and saves it to the store',
        (tester) async {
      await tester.runAsync(() async {
        await store.init(overrideDirectory: tmp);
        final f = File('${tmp.path}/shared.gpx')..writeAsStringSync(_gpx);
        final outcome = await _service(store).importPath(f.path);
        expect(outcome.ok, isTrue);
        expect(outcome.route!.name, 'Shared Route');
        expect(store.routes.any((r) => r.id == outcome.route!.id), isTrue);
      });
    });

    testWidgets('imports a .kml file', (tester) async {
      await tester.runAsync(() async {
        await store.init(overrideDirectory: tmp);
        final f = File('${tmp.path}/shared.kml')..writeAsStringSync(_kml);
        final outcome = await _service(store).importPath(f.path);
        expect(outcome.ok, isTrue);
        expect(outcome.route!.name, 'Shared KML');
      });
    });

    testWidgets('imports a GPX body handed over with a wrong extension',
        (tester) async {
      await tester.runAsync(() async {
        await store.init(overrideDirectory: tmp);
        // WhatsApp caches a shared .gpx as octet-stream; the copy the OS
        // hands over can arrive without a usable .gpx extension.
        final f = File('${tmp.path}/document.bin')..writeAsStringSync(_gpx);
        final outcome = await _service(store).importPath(f.path);
        expect(outcome.ok, isTrue);
        expect(outcome.route!.waypoints, hasLength(3));
      });
    });

    testWidgets('fails a non-route file', (tester) async {
      await tester.runAsync(() async {
        await store.init(overrideDirectory: tmp);
        final f = File('${tmp.path}/notes.txt')
          ..writeAsStringSync('just some text');
        final outcome = await _service(store).importPath(f.path);
        expect(outcome.ok, isFalse);
        expect(store.routes, isEmpty);
      });
    });

    testWidgets('fails a .gpx with unparseable content', (tester) async {
      await tester.runAsync(() async {
        await store.init(overrideDirectory: tmp);
        final f = File('${tmp.path}/broken.gpx')
          ..writeAsStringSync('<gpx><trkpt');
        final outcome = await _service(store).importPath(f.path);
        expect(outcome.ok, isFalse);
      });
    });

    testWidgets('fails a missing file', (tester) async {
      await tester.runAsync(() async {
        await store.init(overrideDirectory: tmp);
        final outcome = await _service(store).importPath('${tmp.path}/nope.gpx');
        expect(outcome.ok, isFalse);
      });
    });
  });
}
