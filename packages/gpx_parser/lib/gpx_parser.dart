/// GPX, KML, GeoJSON, TCX and FIT parsing into Route objects.
///
/// NOT KMZ. A KMZ is a zip and this package has no archive dependency and no
/// code that opens one; the web importer unzips with JSZip and hands the
/// inner document to its own KML path. A caller that wants KMZ here has to
/// unzip first and call [RouteParser.fromKml].
library gpx_parser;

export 'src/fit_parser.dart';
export 'src/route_parser.dart';
