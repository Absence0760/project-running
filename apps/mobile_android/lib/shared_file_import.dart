import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:gpx_parser/gpx_parser.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'local_route_store.dart';

/// Route-file formats importable from another app, and the file-picker's
/// allowlist — the two entry points offer exactly the same set.
///
/// KMZ is a CONTAINER rather than a route format — a zip whose payload is a
/// KML — so it is unwrapped by [routeTextFromImportedBytes] on the way in and
/// the dispatch below never sees it. That is why the pipeline reads BYTES and
/// decodes per format: `readAsString` throws on a zip before any parser is
/// reached, which is what kept KMZ out until now (decisions § 1015).
const Set<String> kSupportedRouteImportExtensions = {
  'gpx',
  'kml',
  'kmz',
  'geojson',
  'tcx',
};

/// Filename extensions that name a supported format under another spelling.
/// A GeoJSON route is routinely saved as `.json`, which web's own `accept`
/// list has always taken.
const Map<String, String> kRouteImportExtensionAliases = <String, String>{
  'json': 'geojson',
};

/// The picker's `allowedExtensions`, derived so it cannot drift from what the
/// dispatch below can actually parse.
final List<String> kRouteImportPickerExtensions = <String>[
  ...kSupportedRouteImportExtensions,
  ...kRouteImportExtensionAliases.keys,
];

/// Pure format dispatch shared by the file-picker import (routes_screen)
/// and the OS "Open with" / share import ([SharedFileImportService]) — the
/// single source of truth for which parser a route file goes through.
cm.Route routeFromImportedFile({
  required String format,
  required String content,
}) {
  final all = routesFromImportedFile(format: format, content: content);
  if (all.isNotEmpty) return all.first;
  // The single-route parsers reach shapes the multi-route ones do not — a GPX
  // `<rte>` rather than a `<trk>`, a KML `<Placemark>` with bare coordinates.
  switch (format) {
    case 'kml':
      return RouteParser.fromKml(content);
    case 'geojson':
      return RouteParser.fromGeoJson(_geoJsonDocument(content));
    case 'tcx':
      return RouteParser.fromTcx(content);
    default:
      return RouteParser.fromGpx(content);
  }
}

/// Every route a file contains — one per GPX `<trk>` / KML `<LineString>`.
///
/// A multi-track file used to import as ONE route whose polyline jumped
/// between the tracks, so a file holding two city loops produced a route with
/// a transatlantic leg. Callers that can present more than one route should
/// use this; [routeFromImportedFile] keeps the first for the single-route
/// callers.
List<cm.Route> routesFromImportedFile({
  required String format,
  required String content,
}) {
  switch (format) {
    case 'kml':
      return RouteParser.routesFromKml(content);
    case 'geojson':
      return RouteParser.routesFromGeoJson(_geoJsonDocument(content));
    case 'tcx':
      return <cm.Route>[RouteParser.fromTcx(content)];
    default:
      return RouteParser.routesFromGpx(content);
  }
}

/// A GeoJSON document is always a JSON object — a FeatureCollection, a
/// Feature, or a bare geometry. Anything else throws, which every caller
/// already treats as an unreadable file.
Map<String, dynamic> _geoJsonDocument(String content) =>
    jsonDecode(content) as Map<String, dynamic>;

/// A zip's local-file-header magic. A KMZ has no other reliable signature —
/// the extension is often absent on an OS share, and the payload is binary, so
/// the text sniff `detectRouteFormat` does cannot run on it at all.
const List<int> _zipMagic = [0x50, 0x4b, 0x03, 0x04];

bool _looksLikeZip(Uint8List bytes) {
  if (bytes.length < _zipMagic.length) return false;
  for (var i = 0; i < _zipMagic.length; i++) {
    if (bytes[i] != _zipMagic[i]) return false;
  }
  return true;
}

/// The text a route file's bytes carry, and the format that text is in.
///
/// Every format but KMZ is UTF-8 already. A KMZ is a zip: the KML inside it is
/// `doc.kml` by the OGC spec, but a real-world archive from Google Earth or a
/// GPS unit may name it anything, so the FIRST `.kml` entry wins and the
/// spec-named one is preferred when both exist. Returns null when the bytes
/// are not decodable as any route file — an image, a PDF, a zip with no KML.
({String format, String content})? routeTextFromImportedBytes({
  String? extension,
  required Uint8List bytes,
}) {
  if (_looksLikeZip(bytes)) {
    final kml = _kmlFromKmz(bytes);
    return kml == null ? null : (format: 'kml', content: kml);
  }
  final String text;
  try {
    text = utf8.decode(bytes, allowMalformed: false);
  } on FormatException catch (e) {
    // Binary that is not a zip either. Reporting it as an unreadable route is
    // the honest answer; letting `allowMalformed` through would hand the
    // parsers replacement characters and fail further downstream.
    debugPrint('route import: bytes are not UTF-8 text: $e');
    return null;
  }
  final format = detectRouteFormat(extension: extension, content: text);
  return format == null ? null : (format: format, content: text);
}

/// The KML document inside a KMZ, or null when the archive holds none.
String? _kmlFromKmz(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? chosen;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (!file.name.toLowerCase().endsWith('.kml')) continue;
      // `doc.kml` is the OGC-specified entry name; prefer it, but do not
      // require it — plenty of exporters name the document after the route.
      if (file.name.toLowerCase() == 'doc.kml') return utf8.decode(file.content);
      chosen ??= file;
    }
    if (chosen == null) return null;
    return utf8.decode(chosen.content);
  } catch (e) {
    debugPrint('route import: KMZ could not be unzipped: $e');
    return null;
  }
}

/// Resolve the route format from a filename extension, falling back to a
/// cheap root-element sniff when the extension is missing or unknown.
/// WhatsApp shares a `.gpx` as `application/octet-stream` and the cached
/// copy the OS hands over can arrive without a usable extension, so the
/// content probe is what makes those imports work. Returns null when
/// neither the extension nor the content looks like a route file.
String? detectRouteFormat({String? extension, required String content}) {
  final ext = extension?.toLowerCase();
  if (ext != null) {
    if (kSupportedRouteImportExtensions.contains(ext)) return ext;
    final alias = kRouteImportExtensionAliases[ext];
    if (alias != null) return alias;
  }
  final head = content.trimLeft();
  final probe = head.length > 2048 ? head.substring(0, 2048) : head;
  // KML checked first: a KMZ-unzipped-to-text edge case can contain a
  // `<gpx>` string in a description, but a real GPX never contains `<kml`.
  if (probe.contains('<kml')) return 'kml';
  if (probe.contains('<TrainingCenterDatabase')) return 'tcx';
  if (probe.contains('<gpx')) return 'gpx';
  if (probe.startsWith('{') && probe.contains('"type"')) return 'geojson';
  return null;
}

/// Outcome of an OS-driven route import, surfaced to `HomeScreen` via
/// [incomingRouteImport]. Success carries the saved route (so the UI can
/// open it); every failure mode collapses to [SharedRouteImport.failure]
/// behind one generic banner.
class SharedRouteImport {
  final cm.Route? route;
  const SharedRouteImport.success(cm.Route this.route);
  const SharedRouteImport.failure() : route = null;
  bool get ok => route != null;
}

/// Cross-boot handoff for a GPX/KML file the OS handed the app via
/// "Open with" (ACTION_VIEW) or share (ACTION_SEND) on Android, or a
/// document open on iOS. [SharedFileImportService] sets it; `HomeScreen`
/// listens and drains it (banner + open the route). Global, mirroring the
/// `pendingStartWorkout` handoff in main.dart — every launch path lands on
/// HomeScreen, so one notifier centralises the handoff rather than
/// threading it through the widget tree.
final ValueNotifier<SharedRouteImport?> incomingRouteImport =
    ValueNotifier<SharedRouteImport?>(null);

/// Receives GPX/KML files handed to the app by another app and imports them
/// into the route library. The OS-registration side lives in the native
/// projects: the AndroidManifest ACTION_VIEW/ACTION_SEND intent-filters and
/// the iOS Info.plist CFBundleDocumentTypes / UTImportedTypeDeclarations.
///
/// The plugin surface ([ReceiveSharingIntent]) is injectable so unit tests
/// exercise [importPath] with a temp file and never open a MethodChannel.
class SharedFileImportService {
  SharedFileImportService({
    required this.routeStore,
    Stream<List<SharedMediaFile>>? mediaStream,
    Future<List<SharedMediaFile>> Function()? initialMedia,
    void Function()? reset,
  })  : _mediaStream =
            mediaStream ?? ReceiveSharingIntent.instance.getMediaStream(),
        _initialMedia =
            initialMedia ?? ReceiveSharingIntent.instance.getInitialMedia,
        _reset = reset ?? ReceiveSharingIntent.instance.reset;

  final LocalRouteStore routeStore;
  final Stream<List<SharedMediaFile>> _mediaStream;
  final Future<List<SharedMediaFile>> Function() _initialMedia;
  final void Function() _reset;
  StreamSubscription<List<SharedMediaFile>>? _sub;

  /// Listen for files shared while the app is already running (delivered to
  /// the running activity via onNewIntent). Idempotent.
  void start() {
    _sub ??= _mediaStream.listen(
      _handleFiles,
      onError: (Object e) => debugPrint('shared-file stream error: $e'),
    );
  }

  /// Drain the file (if any) that cold-launched the app from a closed state.
  Future<void> processInitial() async {
    try {
      await _handleFiles(await _initialMedia());
    } catch (e) {
      debugPrint('shared-file initial import failed: $e');
    }
  }

  Future<void> _handleFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    // The route library imports one file at a time and Open-with hands over
    // a single document; import the first that parses, but still report a
    // lone bad file's failure so the user isn't left with silent nothing.
    SharedRouteImport? outcome;
    for (final f in files) {
      outcome = await importPath(f.path);
      if (outcome.ok) break;
    }
    if (outcome != null) incomingRouteImport.value = outcome;
    // Clear the plugin's cached intent so the same file isn't re-delivered
    // on the next getInitialMedia / resume.
    _reset();
  }

  /// Read, parse, and save a single file path as a route. Plugin-free so a
  /// unit test can drive it with a temp file. Every failure — unreadable
  /// file, unknown format, unparseable content — collapses to
  /// [SharedRouteImport.failure]; the caller shows one generic banner.
  Future<SharedRouteImport> importPath(String path) async {
    Uint8List bytes;
    try {
      // BYTES, not text: a KMZ is a zip and `readAsString` throws on one
      // before any dispatch is reached (decisions § 1015).
      bytes = await File(path).readAsBytes();
    } catch (e) {
      debugPrint('shared-file read failed: $e');
      return const SharedRouteImport.failure();
    }
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1) : null;
    try {
      final route = await compute(
        _parseSharedRouteFile,
        _SharedParseRequest(ext, bytes),
      );
      if (route == null) return const SharedRouteImport.failure();
      await routeStore.save(route);
      return SharedRouteImport.success(route);
    } catch (e) {
      debugPrint('shared-file parse failed: $e');
      return const SharedRouteImport.failure();
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

class _SharedParseRequest {
  final String? ext;
  final Uint8List bytes;
  const _SharedParseRequest(this.ext, this.bytes);
}

/// The unzip runs in the isolate too — a KMZ of a long route is exactly the
/// file that would block the UI thread if it did not.
cm.Route? _parseSharedRouteFile(_SharedParseRequest r) {
  final decoded =
      routeTextFromImportedBytes(extension: r.ext, bytes: r.bytes);
  if (decoded == null) return null;
  return routeFromImportedFile(
      format: decoded.format, content: decoded.content);
}
