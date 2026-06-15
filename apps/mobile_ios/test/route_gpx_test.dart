import 'package:flutter_test/flutter_test.dart';
import '../lib/route_gpx.dart';

const coords3 = [
  [8.54, 47.37],
  [8.541, 47.371],
  [8.542, 47.372],
];
const elevs3 = [400.0, 410.0, 420.0];

RouteGpxMarker _marker({
  String label = 'Aid 1',
  double lat = 47.371,
  double lng = 8.541,
  String kind = 'aid_station',
  Map<String, dynamic> meta = const {},
}) {
  return RouteGpxMarker(label: label, lat: lat, lng: lng, kind: kind, meta: meta);
}

void main() {
  test('toRouteGpxWithMarkers — has GPX 1.1 namespace + creator', () {
    final xml = toRouteGpxWithMarkers('Loop', coords3, elevs3, []);
    expect(xml, contains('<gpx version="1.1" creator="Threkir"'));
    expect(xml, contains('xmlns="http://www.topografix.com/GPX/1/1"'));
  });

  test('toRouteGpxWithMarkers — emits one wpt per marker with lat/lon/name/type', () {
    final markers = [
      _marker(label: 'Aid 2', lat: 47.37, lng: 8.54, kind: 'aid_station'),
      _marker(label: 'Cut 1', lat: 47.372, lng: 8.542, kind: 'cutoff'),
    ];
    final xml = toRouteGpxWithMarkers('Loop', coords3, elevs3, markers);
    expect('<wpt '.allMatches(xml).length, 2);
    expect(xml, contains('<wpt lat="47.37" lon="8.54"><name>Aid 2</name><type>aid_station</type>'));
    expect(xml, contains('<wpt lat="47.372" lon="8.542"><name>Cut 1</name><type>cutoff</type>'));
  });

  test('toRouteGpxWithMarkers — cutoff clock + elapsed + services land in desc', () {
    final xml = toRouteGpxWithMarkers('Loop', coords3, elevs3, [
      _marker(kind: 'aid_station', meta: {
        'cutoff_clock': '14:30',
        'cutoff_elapsed_s': 16200,
        'services': ['water', 'food', 'medical'],
      }),
    ]);
    expect(
      xml,
      contains('<desc>Cutoff 14:30 | Cutoff 4h30m elapsed | Services: water, food, medical</desc>'),
    );
  });

  test('toRouteGpxWithMarkers — elapsed minutes are zero-padded', () {
    final xml = toRouteGpxWithMarkers('Loop', coords3, elevs3, [
      _marker(kind: 'cutoff', meta: {'cutoff_elapsed_s': 3660}),
    ]);
    expect(xml, contains('<desc>Cutoff 1h01m elapsed</desc>'));
  });

  test('toRouteGpxWithMarkers — no desc when no cutoff and no services', () {
    final xml = toRouteGpxWithMarkers('Loop', coords3, elevs3, [
      _marker(kind: 'note', meta: {}),
    ]);
    expect(xml.contains('<desc>'), isFalse);
  });

  test('toRouteGpxWithMarkers — maps kind to a Garmin sym, omits for custom/unknown', () {
    const cases = <List<String?>>[
      ['aid_station', 'Water Source'],
      ['cutoff', 'Danger Area'],
      ['crew_access', 'Parking Area'],
      ['hazard', 'Danger Area'],
      ['note', 'Information'],
      ['climb', 'Summit'],
      ['custom', null],
      ['gas_station', null],
    ];
    for (final c in cases) {
      final kind = c[0]!;
      final sym = c[1];
      final xml = toRouteGpxWithMarkers('Loop', coords3, elevs3, [
        _marker(kind: kind, meta: {}),
      ]);
      if (sym == null) {
        expect(xml.contains('<sym>'), isFalse, reason: 'no <sym> for kind $kind');
      } else {
        expect(xml, contains('<sym>$sym</sym>'), reason: 'kind $kind -> $sym');
      }
    }
  });

  test('toRouteGpxWithMarkers — escapes XML metacharacters in name and desc', () {
    final xml = toRouteGpxWithMarkers('Loop', coords3, elevs3, [
      _marker(
        label: 'Tom & "Jerry" <aid>',
        kind: 'aid_station',
        meta: {
          'services': ['water & ice'],
        },
      ),
    ]);
    expect(xml.contains('<aid>'), isFalse);
    expect(xml, contains('<name>Tom &amp; &quot;Jerry&quot; &lt;aid&gt;</name>'));
    expect(xml, contains('<desc>Services: water &amp; ice</desc>'));
  });

  test('toRouteGpxWithMarkers — empty marker list still emits the line + zero wpt', () {
    final xml = toRouteGpxWithMarkers('Loop', coords3, elevs3, []);
    expect('<wpt '.allMatches(xml).length, 0);
    expect('<trkpt '.allMatches(xml).length, 3);
    expect(xml, contains('<trkpt lat="47.37" lon="8.54"><ele>400.0</ele>'));
  });

  test('toRouteGpxWithMarkers — missing elevation falls back to 0', () {
    final xml = toRouteGpxWithMarkers('Loop', [
      [8.54, 47.37],
    ], [], []);
    expect(xml, contains('<ele>0</ele>'));
  });

  test('toRouteGpxWithMarkers — wpt elements precede the trk (GPX 1.1 order)', () {
    final xml = toRouteGpxWithMarkers('Loop', coords3, elevs3, [
      _marker(kind: 'aid_station', meta: {}),
    ]);
    final wptIdx = xml.indexOf('<wpt ');
    final trkIdx = xml.indexOf('<trk>');
    expect(wptIdx > -1 && trkIdx > -1, isTrue);
    expect(wptIdx < trkIdx, isTrue);
  });
}
