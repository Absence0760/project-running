/// Course-waypoint GPX export: the route line as a `<trk>` plus one `<wpt>`
/// per course marker (aid station, cutoff, crew access, hazard, …). Imported
/// by every Garmin/Coros/Suunto so the runner sees "Aid 2 in 1.3 km" on the
/// wrist mid-race.
///
/// Pure + deterministic (no `DateTime.now()`): the GPX `<metadata>` carries
/// only a `<name>`, so the output is byte-stable for tests. GPX 1.1 schema
/// requires `<wpt>` elements BEFORE `<trk>`, so waypoints are emitted first.
///
/// Twin of `apps/web/src/lib/routes/route_gpx.ts` — keep the element order,
/// `<sym>` mapping, `<desc>` construction, escaping, and test count in
/// lockstep.

import 'route_markers.dart';

class RouteGpxMarker {
  final String label;
  final double lat;
  final double lng;

  /// RouteMarkerKind value.
  final String kind;

  /// Carries cutoff_clock / cutoff_elapsed_s / services.
  final Map<String, dynamic> meta;

  const RouteGpxMarker({
    required this.label,
    required this.lat,
    required this.lng,
    required this.kind,
    required this.meta,
  });
}

/// Garmin-recognised `<sym>` name per marker kind; absent → no `<sym>`.
const Map<String, String> _symByKind = {
  'aid_station': 'Water Source',
  'cutoff': 'Danger Area',
  'crew_access': 'Parking Area',
  'hazard': 'Danger Area',
  'note': 'Information',
  'climb': 'Summit',
};

/// Generate a GPX 1.1 document for a route line plus its course markers.
/// [coordinates] are `[lng, lat]` pairs (same order as the web `toGpx`).
String toRouteGpxWithMarkers(
  String name,
  List<List<double>> coordinates,
  List<double> elevations,
  List<RouteGpxMarker> markers,
) {
  final waypoints = markers.map(_renderWaypoint).join('\n');

  final trackpoints = <String>[];
  for (var i = 0; i < coordinates.length; i++) {
    final lng = coordinates[i][0];
    final lat = coordinates[i][1];
    final ele = i < elevations.length ? elevations[i] : 0;
    trackpoints.add('      <trkpt lat="$lat" lon="$lng"><ele>$ele</ele></trkpt>');
  }

  return '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Threkir"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
  <metadata>
    <name>${_escapeXml(name)}</name>
  </metadata>
${waypoints.isNotEmpty ? '$waypoints\n' : ''}  <trk>
    <name>${_escapeXml(name)}</name>
    <trkseg>
${trackpoints.join('\n')}
    </trkseg>
  </trk>
</gpx>''';
}

String _renderWaypoint(RouteGpxMarker m) {
  final parts = <String>[
    '  <wpt lat="${m.lat}" lon="${m.lng}">',
    '<name>${_escapeXml(m.label)}</name>',
    '<type>${_escapeXml(m.kind)}</type>',
  ];
  final sym = _symByKind[m.kind];
  if (sym != null) parts.add('<sym>$sym</sym>');
  final desc = _buildDesc(m.meta);
  if (desc.isNotEmpty) parts.add('<desc>${_escapeXml(desc)}</desc>');
  parts.add('</wpt>');
  return parts.join('');
}

/// Locale-agnostic canonical-English `<desc>` built purely from `meta`.
String _buildDesc(Map<String, dynamic> meta) {
  final segments = <String>[];

  final cutoff = parseCutoff(meta);
  if (cutoff != null) {
    if (cutoff.clock != null) segments.add('Cutoff ${cutoff.clock}');
    if (cutoff.elapsedS != null) {
      final h = cutoff.elapsedS! ~/ 3600;
      final m = (cutoff.elapsedS! % 3600) ~/ 60;
      segments.add('Cutoff ${h}h${m.toString().padLeft(2, '0')}m elapsed');
    }
  }

  final services = meta['services'];
  if (services is List) {
    final named = services.whereType<String>().toList();
    if (named.isNotEmpty) segments.add('Services: ${named.join(', ')}');
  }

  return segments.join(' | ');
}

String _escapeXml(String str) {
  return str
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
