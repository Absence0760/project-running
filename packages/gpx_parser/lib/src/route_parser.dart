import 'dart:math' as math;

import 'package:core_models/core_models.dart';
import 'package:xml/xml.dart';

/// Parses GPX, KML, and GeoJSON files into [Route] objects.
///
/// All methods are pure file parsing — no network calls.
class RouteParser {
  /// Parse a GPX XML string into a [Route] — the FIRST track in the file.
  /// Use [routesFromGpx] to get every track.
  static Route fromGpx(String xmlString) {
    final all = routesFromGpx(xmlString);
    if (all.isNotEmpty) return all.first;
    // A pointless file still surfaces the name it declared, so the caller can
    // say WHICH import came back empty.
    final doc = XmlDocument.parse(xmlString);
    return _buildRoute(
        _containerName(doc, const ['trk', 'metadata', 'rte']), const []);
  }

  /// Every route in a GPX file: one per `<trk>`, else one per `<rte>`, else a
  /// single route built from the loose `<wpt>`s.
  ///
  /// Scoped per container on purpose. Collecting `trkpt` document-wide joined
  /// unrelated tracks into ONE polyline, so a file holding a London loop and a
  /// New York loop imported as a single route with a 5,500 km transatlantic
  /// leg — poisoning its distance, elevation and map. Mirrors the web
  /// importer's one-route-per-track contract (`integrations/import.ts`).
  static List<Route> routesFromGpx(String xmlString) {
    final doc = XmlDocument.parse(xmlString);
    final docName = _containerName(doc, const ['metadata']);
    final routes = <Route>[];

    for (final trk in doc.findAllElements('trk')) {
      final points = _waypointsFrom(trk, 'trkpt');
      if (points.isNotEmpty) {
        routes.add(_buildRoute(_elementName(trk) ?? docName, points));
      }
    }
    if (routes.isEmpty) {
      for (final rte in doc.findAllElements('rte')) {
        final points = _waypointsFrom(rte, 'rtept');
        if (points.isNotEmpty) {
          routes.add(_buildRoute(_elementName(rte) ?? docName, points));
        }
      }
    }
    // Loose waypoints are a single ordered route — they have no container to
    // split on.
    if (routes.isEmpty) {
      final points = <Waypoint>[];
      for (final pt in doc.findAllElements('wpt')) {
        final w = _waypointFromGpxNode(pt);
        if (w != null) points.add(w);
      }
      if (points.isNotEmpty) routes.add(_buildRoute(docName, points));
    }
    return routes;
  }

  static const _fallbackName = 'Imported route';

  static String? _elementName(XmlElement el) {
    final n = el.findElements('name').firstOrNull?.innerText.trim();
    return (n == null || n.isEmpty) ? null : n;
  }

  static List<Waypoint> _waypointsFrom(XmlElement container, String tag) {
    final points = <Waypoint>[];
    for (final pt in container.findAllElements(tag)) {
      final w = _waypointFromGpxNode(pt);
      if (w != null) points.add(w);
    }
    return points;
  }

  /// Parse a KML XML string into a [Route] — the FIRST line in the file.
  /// Use [routesFromKml] to get every line.
  static Route fromKml(String xmlString) {
    final all = routesFromKml(xmlString);
    if (all.isNotEmpty) return all.first;
    final doc = XmlDocument.parse(xmlString);
    final name = doc.findAllElements('name').firstOrNull?.innerText.trim();
    return _buildRoute(
        (name == null || name.isEmpty) ? _fallbackName : name, const []);
  }

  /// Every route in a KML file: one per `<LineString>`.
  ///
  /// Scoped to LineStrings on purpose. Taking the first `<coordinates>`
  /// anywhere in the document meant a `<Point>` placemark — the "start pin" a
  /// Google My Maps export writes BEFORE the track — won the lookup, so the
  /// whole route imported as a single point with zero distance and the real
  /// line was dropped without a word.
  static List<Route> routesFromKml(String xmlString) {
    final doc = XmlDocument.parse(xmlString);
    final docName = doc
            .findAllElements('Document')
            .firstOrNull
            ?.findElements('name')
            .firstOrNull
            ?.innerText
            .trim() ??
        _fallbackName;

    final routes = <Route>[];
    for (final line in doc.findAllElements('LineString')) {
      final coordsNode = line.findElements('coordinates').firstOrNull;
      if (coordsNode == null) continue;
      final points = _kmlCoords(coordsNode.innerText);
      if (points.isEmpty) continue;
      // The name lives on the enclosing Placemark, not the LineString.
      final placemark = line.ancestors
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'Placemark')
          .firstOrNull;
      final name =
          (placemark == null ? null : _elementName(placemark)) ?? docName;
      routes.add(_buildRoute(name, points));
    }
    return routes;
  }

  static List<Waypoint> _kmlCoords(String raw) {
    final points = <Waypoint>[];
    for (final triple in raw.trim().split(RegExp(r'\s+'))) {
      final parts = triple.split(',');
      if (parts.length < 2) continue;
      final lng = double.tryParse(parts[0]);
      final lat = double.tryParse(parts[1]);
      final ele = _finiteOrNull(parts.length >= 3 ? double.tryParse(parts[2]) : null);
      if (_isUsableLat(lat) && _isUsableLng(lng)) {
        points.add(Waypoint(lat: lat!, lng: lng!, elevationMetres: ele));
      }
    }
    return points;
  }

  /// Parse a TCX (Training Center XML) string into a [Route]. Reads
  /// `<Trackpoint>` elements from the first activity and uses
  /// `<Position><LatitudeDegrees>` / `<LongitudeDegrees>` / `<AltitudeMeters>`.
  ///
  /// TCX is the format Garmin Connect, COROS, Suunto, and many fitness
  /// devices export to. It can also include heart rate and cadence streams,
  /// which we ignore here — we only care about the lat/lng/elevation track
  /// for route purposes.
  static Route fromTcx(String xmlString) {
    final doc = XmlDocument.parse(xmlString);

    final name = doc
            .findAllElements('Name')
            .firstOrNull
            ?.innerText
            .trim() ??
        doc.findAllElements('Notes').firstOrNull?.innerText.trim() ??
        'Imported route';

    final points = <Waypoint>[];
    for (final pt in doc.findAllElements('Trackpoint')) {
      final position = pt.findElements('Position').firstOrNull;
      if (position == null) continue;

      final latNode = position.findElements('LatitudeDegrees').firstOrNull;
      final lngNode = position.findElements('LongitudeDegrees').firstOrNull;
      if (latNode == null || lngNode == null) continue;

      final lat = double.tryParse(latNode.innerText);
      final lng = double.tryParse(lngNode.innerText);
      if (!_isUsableLat(lat) || !_isUsableLng(lng)) continue;

      final eleNode = pt.findElements('AltitudeMeters').firstOrNull;
      final ele = _finiteOrNull(
          eleNode != null ? double.tryParse(eleNode.innerText) : null);

      final timeNode = pt.findElements('Time').firstOrNull;
      final time = timeNode != null ? DateTime.tryParse(timeNode.innerText) : null;

      points.add(Waypoint(
        lat: lat!,
        lng: lng!,
        elevationMetres: ele,
        timestamp: time,
      ));
    }

    return _buildRoute(name, points);
  }

  /// Parse a GeoJSON document into a [Route] — the FIRST line in it. Use
  /// [routesFromGeoJson] to get every line.
  static Route fromGeoJson(Map<String, dynamic> json) {
    final all = routesFromGeoJson(json);
    if (all.isNotEmpty) return all.first;
    return _buildRoute(_geoJsonName(json, null), const []);
  }

  /// Every route a GeoJSON document describes: one per `LineString`, and one
  /// per member line of a `MultiLineString`.
  ///
  /// The document shape is the whole point. Only a bare `Feature` was ever
  /// read — `json['geometry']['coordinates']` and nothing else — so a
  /// `FeatureCollection`, which is what geojson.io, QGIS, Overpass turbo and
  /// most other exporters actually emit, found no `geometry` key and imported
  /// as a route with zero waypoints and zero distance. So did a bare geometry
  /// (`{type: LineString, coordinates: [...]}`) and a `MultiLineString`, whose
  /// coordinates are a list of LINES rather than of points. That is the same
  /// silent-empty failure the `<Point>`-wins-the-lookup bug produced on KML,
  /// and the web importer has read all four shapes since it was written.
  ///
  /// A `MultiLineString` becomes one route per member line rather than one
  /// polyline through all of them, for the reason [routesFromGpx] gives:
  /// joining unrelated lines invents a leg between them that poisons the
  /// route's distance, elevation and map.
  ///
  /// Every container read is shape-checked rather than cast. A cast threw a
  /// [TypeError] — an [Error], not an [Exception] — on a document whose
  /// `geometry` was a list or whose `properties` was a string, so a malformed
  /// file crashed the caller instead of coming back as an import that found
  /// nothing. The coordinate reads inside the line were hardened for exactly
  /// this a level down; the containers around them were not.
  static List<Route> routesFromGeoJson(Map<String, dynamic> json) {
    final routes = <Route>[];
    final docName = _geoJsonName(json, null);

    void addGeometry(Object? geometry, String name) {
      if (geometry is! Map) return;
      final type = geometry['type'];
      final coords = geometry['coordinates'];
      if (coords is! List) return;
      if (type == 'MultiLineString') {
        for (final line in coords) {
          final points = _geoJsonLine(line);
          if (points.isNotEmpty) routes.add(_buildRoute(name, points));
        }
        return;
      }
      // Anything else that carries a flat coordinate list reads as a line.
      // The `type` is deliberately not required: a hand-written document that
      // omits it still imported before this, and refusing it now would be a
      // regression dressed as strictness.
      final points = _geoJsonLine(coords);
      if (points.isNotEmpty) routes.add(_buildRoute(name, points));
    }

    final type = json['type'];
    final features = json['features'];
    if (type == 'FeatureCollection' && features is List) {
      for (final feature in features) {
        if (feature is! Map) continue;
        addGeometry(feature['geometry'], _geoJsonName(feature, docName));
      }
      return routes;
    }
    if (json.containsKey('geometry')) {
      addGeometry(json['geometry'], docName);
      return routes;
    }
    // A bare geometry object: the document IS the LineString.
    addGeometry(json, docName);
    return routes;
  }

  /// `properties.name` when it is a non-empty string, else [fallback], else
  /// the generic import name.
  static String _geoJsonName(Map<Object?, Object?> json, String? fallback) {
    final props = json['properties'];
    final name = props is Map ? props['name'] : null;
    if (name is String && name.trim().isNotEmpty) return name.trim();
    return fallback ?? _fallbackName;
  }

  /// One GeoJSON `LineString` coordinate array into waypoints.
  static List<Waypoint> _geoJsonLine(Object? coords) {
    final points = <Waypoint>[];
    if (coords is! List) return points;
    for (final c in coords) {
      if (c is! List || c.length < 2) continue;
      // GeoJSON from hand-edits or non-conformant exporters can carry
      // string / null coordinate elements. A blind `as num` cast threw
      // and aborted the entire import on the first bad point; skip the
      // point instead, matching the GPX/KML paths and the web twin.
      final lngRaw = c[0];
      final latRaw = c[1];
      if (lngRaw is! num || latRaw is! num) continue;
      final lat = latRaw.toDouble();
      final lng = lngRaw.toDouble();
      if (!_isUsableLat(lat) || !_isUsableLng(lng)) continue;
      final eleRaw = c.length >= 3 ? c[2] : null;
      final ele = _finiteOrNull(eleRaw is num ? eleRaw.toDouble() : null);
      points.add(Waypoint(lat: lat, lng: lng, elevationMetres: ele));
    }
    return points;
  }

  /// Whether a parsed latitude can be used as one. `double.tryParse`
  /// accepts the literals `NaN`, `Infinity` and `-Infinity`, so a
  /// null-check alone lets a non-finite coordinate into a [Waypoint] — and
  /// nothing downstream re-checks. One such point poisons the route's
  /// haversine distance to NaN, and, once the route is being run, collapses
  /// the recorder's off-route projection to a non-finite reading that the
  /// sustained-off-route detector had to be taught to refuse.
  ///
  /// Finite is not sufficient, which is why the bound is here rather than a
  /// bare `isFinite`: `lat="1e308"` is finite, clears every null and NaN
  /// check, and then overflows the haversine's `lat2 - lat1` to infinity —
  /// `sin(infinity)` is NaN, so the route lands with exactly the NaN
  /// `distanceMetres` the finiteness guard exists to prevent, one step
  /// later. A NaN there is not merely a wrong number: `Route.toJson` is
  /// written to disk through `jsonEncode`, which refuses a non-finite
  /// double outright, so the import parses "successfully" and then cannot
  /// be saved. The range is not a heuristic either — GPX's `latitudeType`,
  /// RFC 7946 and the KML spec all constrain latitude to ±90 and longitude
  /// to ±180, so a value outside it is a malformed file, not a place.
  static bool _isUsableLat(double? v) => v != null && v.isFinite && v.abs() <= 90;

  /// Longitude half of [_isUsableLat]. Separate bound, same contract.
  static bool _isUsableLng(double? v) =>
      v != null && v.isFinite && v.abs() <= 180;

  /// Elevation is optional, so an unusable one degrades to absent rather than
  /// dropping the whole point — the same choice the web importer makes.
  static double? _finiteOrNull(double? v) => v != null && v.isFinite ? v : null;

  /// First non-empty `<name>` that is a DIRECT child of one of the given
  /// container elements, tried in priority order. Avoids picking up a
  /// `<name>` nested inside an individual waypoint / point / style.
  static String _containerName(XmlDocument doc, List<String> containers) {
    for (final tag in containers) {
      final n = doc
          .findAllElements(tag)
          .firstOrNull
          ?.findElements('name')
          .firstOrNull
          ?.innerText
          .trim();
      if (n != null && n.isNotEmpty) return n;
    }
    return 'Imported route';
  }

  static Waypoint? _waypointFromGpxNode(XmlElement node) {
    final lat = double.tryParse(node.getAttribute('lat') ?? '');
    final lng = double.tryParse(node.getAttribute('lon') ?? '');
    if (!_isUsableLat(lat) || !_isUsableLng(lng)) return null;

    final eleNode = node.findElements('ele').firstOrNull;
    final ele = _finiteOrNull(
        eleNode != null ? double.tryParse(eleNode.innerText) : null);

    final timeNode = node.findElements('time').firstOrNull;
    final time = timeNode != null
        ? DateTime.tryParse(timeNode.innerText.trim())
        : null;

    return Waypoint(
      lat: lat!,
      lng: lng!,
      elevationMetres: ele,
      timestamp: time,
    );
  }

  static Route _buildRoute(String name, List<Waypoint> points) {
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
        // Each elevation is finite on its own ([_finiteOrNull]) yet their
        // difference need not be: `<ele>1e308</ele>` after `<ele>-1e308</ele>`
        // overflows to infinity, and an infinite `elevationGainMetres` is the
        // same unsaveable route a NaN distance is — `jsonEncode` refuses it.
        final gain = curr - prev;
        if (gain.isFinite) elevationGain += gain;
      }
    }
    return Route(
      id: _id(),
      name: name,
      waypoints: points,
      distanceMetres: distance,
      elevationGainMetres: elevationGain,
    );
  }

  static String _id() => DateTime.now().millisecondsSinceEpoch.toString();

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
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
