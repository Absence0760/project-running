import 'package:core_models/core_models.dart';

/// Parses GPX, KML, and GeoJSON files into [Route] objects.
///
/// All methods are pure file parsing — no network calls.
class RouteParser {
  /// Parses a GPX XML string into a [Route].
  static Route fromGpx(String xmlString) {
    // TODO: Implement GPX parsing
    return const Route(id: 'gpx', name: 'Imported GPX Route', waypoints: [], distanceMetres: 0);
  }

  /// Parses a KML XML string into a [Route].
  static Route fromKml(String xmlString) {
    // TODO: Implement KML parsing
    return const Route(id: 'kml', name: 'Imported KML Route', waypoints: [], distanceMetres: 0);
  }

  /// Parses a GeoJSON map into a [Route].
  static Route fromGeoJson(Map<String, dynamic> json) {
    // TODO: Implement GeoJSON parsing
    return const Route(id: 'geojson', name: 'Imported GeoJSON Route', waypoints: [], distanceMetres: 0);
  }
}
