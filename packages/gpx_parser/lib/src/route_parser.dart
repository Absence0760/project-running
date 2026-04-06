import 'package:core_models/core_models.dart';

/// Parses GPX, KML, and GeoJSON files into [Route] objects.
///
/// All methods are pure file parsing — no network calls.
class RouteParser {
  /// Parses a GPX XML string into a [Route].
  static Route fromGpx(String xmlString) {
    // TODO: Implement GPX parsing
    throw UnimplementedError('GPX parsing not yet implemented');
  }

  /// Parses a KML XML string into a [Route].
  static Route fromKml(String xmlString) {
    // TODO: Implement KML parsing
    throw UnimplementedError('KML parsing not yet implemented');
  }

  /// Parses a GeoJSON map into a [Route].
  static Route fromGeoJson(Map<String, dynamic> json) {
    // TODO: Implement GeoJSON parsing
    throw UnimplementedError('GeoJSON parsing not yet implemented');
  }
}
