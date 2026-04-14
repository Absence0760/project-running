import 'dart:math' as math;

import 'package:core_models/core_models.dart';
import 'package:xml/xml.dart';

/// Parses GPX, KML, and GeoJSON files into [Route] objects.
///
/// All methods are pure file parsing — no network calls.
class RouteParser {
  /// Parse a GPX XML string into a [Route]. Reads `<trkpt>` and `<rtept>` nodes.
  static Route fromGpx(String xmlString) {
    final doc = XmlDocument.parse(xmlString);

    final name = doc
            .findAllElements('name')
            .firstOrNull
            ?.innerText
            .trim() ??
        'Imported route';

    final points = <Waypoint>[];
    // Track points
    for (final pt in doc.findAllElements('trkpt')) {
      final w = _waypointFromGpxNode(pt);
      if (w != null) points.add(w);
    }
    // Route points (fallback)
    if (points.isEmpty) {
      for (final pt in doc.findAllElements('rtept')) {
        final w = _waypointFromGpxNode(pt);
        if (w != null) points.add(w);
      }
    }
    // Plain waypoints (last resort)
    if (points.isEmpty) {
      for (final pt in doc.findAllElements('wpt')) {
        final w = _waypointFromGpxNode(pt);
        if (w != null) points.add(w);
      }
    }

    return _buildRoute(name, points);
  }

  /// Parse a KML XML string into a [Route]. Reads `<coordinates>` from
  /// the first `<LineString>`.
  static Route fromKml(String xmlString) {
    final doc = XmlDocument.parse(xmlString);

    final name = doc
            .findAllElements('name')
            .firstOrNull
            ?.innerText
            .trim() ??
        'Imported route';

    final coordsNode = doc.findAllElements('coordinates').firstOrNull;
    if (coordsNode == null) {
      return Route(id: _id(), name: name, waypoints: const [], distanceMetres: 0);
    }

    final points = <Waypoint>[];
    final raw = coordsNode.innerText.trim().split(RegExp(r'\s+'));
    for (final triple in raw) {
      final parts = triple.split(',');
      if (parts.length >= 2) {
        final lng = double.tryParse(parts[0]);
        final lat = double.tryParse(parts[1]);
        final ele = parts.length >= 3 ? double.tryParse(parts[2]) : null;
        if (lat != null && lng != null) {
          points.add(Waypoint(lat: lat, lng: lng, elevationMetres: ele));
        }
      }
    }

    return _buildRoute(name, points);
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
      if (lat == null || lng == null) continue;

      final eleNode = pt.findElements('AltitudeMeters').firstOrNull;
      final ele = eleNode != null ? double.tryParse(eleNode.innerText) : null;

      final timeNode = pt.findElements('Time').firstOrNull;
      final time = timeNode != null ? DateTime.tryParse(timeNode.innerText) : null;

      points.add(Waypoint(
        lat: lat,
        lng: lng,
        elevationMetres: ele,
        timestamp: time,
      ));
    }

    return _buildRoute(name, points);
  }

  /// Parse a GeoJSON map into a [Route]. Expects a `LineString` geometry.
  static Route fromGeoJson(Map<String, dynamic> json) {
    final name = (json['properties'] as Map?)?['name'] as String? ?? 'Imported route';

    final geometry = json['geometry'] as Map<String, dynamic>?;
    final coords = geometry?['coordinates'] as List?;
    if (coords == null) {
      return Route(id: _id(), name: name, waypoints: const [], distanceMetres: 0);
    }

    final points = <Waypoint>[];
    for (final c in coords) {
      if (c is List && c.length >= 2) {
        final lng = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        final ele = c.length >= 3 ? (c[2] as num).toDouble() : null;
        points.add(Waypoint(lat: lat, lng: lng, elevationMetres: ele));
      }
    }

    return _buildRoute(name, points);
  }

  static Waypoint? _waypointFromGpxNode(XmlElement node) {
    final lat = double.tryParse(node.getAttribute('lat') ?? '');
    final lng = double.tryParse(node.getAttribute('lon') ?? '');
    if (lat == null || lng == null) return null;

    final eleNode = node.findElements('ele').firstOrNull;
    final ele = eleNode != null ? double.tryParse(eleNode.innerText) : null;

    return Waypoint(lat: lat, lng: lng, elevationMetres: ele);
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
        elevationGain += curr - prev;
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
