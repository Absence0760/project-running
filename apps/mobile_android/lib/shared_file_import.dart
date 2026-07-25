import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:gpx_parser/gpx_parser.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'local_route_store.dart';

/// Route-file formats importable from another app. Matches the Routes
/// screen file-picker (`allowedExtensions: ['gpx', 'kml']`); KMZ/TCX/GeoJSON
/// are parseable by [RouteParser] but deliberately not offered here so the
/// two import entry points stay in lockstep.
const Set<String> kSupportedRouteImportExtensions = {'gpx', 'kml'};

/// Pure format dispatch shared by the file-picker import (routes_screen)
/// and the OS "Open with" / share import ([SharedFileImportService]) — the
/// single source of truth for which parser a route file goes through.
cm.Route routeFromImportedFile({
  required String format,
  required String content,
}) {
  final all = routesFromImportedFile(format: format, content: content);
  return all.isEmpty
      ? (format == 'kml'
          ? RouteParser.fromKml(content)
          : RouteParser.fromGpx(content))
      : all.first;
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
  return format == 'kml'
      ? RouteParser.routesFromKml(content)
      : RouteParser.routesFromGpx(content);
}

/// Resolve the route format from a filename extension, falling back to a
/// cheap XML root-element sniff when the extension is missing or unknown.
/// WhatsApp shares a `.gpx` as `application/octet-stream` and the cached
/// copy the OS hands over can arrive without a usable extension, so the
/// content probe is what makes those imports work. Returns null when
/// neither the extension nor the content looks like a GPX/KML route.
String? detectRouteFormat({String? extension, required String content}) {
  final ext = extension?.toLowerCase();
  if (ext != null && kSupportedRouteImportExtensions.contains(ext)) return ext;
  final head = content.trimLeft();
  final probe = head.length > 2048 ? head.substring(0, 2048) : head;
  // KML checked first: a KMZ-unzipped-to-text edge case can contain a
  // `<gpx>` string in a description, but a real GPX never contains `<kml`.
  if (probe.contains('<kml')) return 'kml';
  if (probe.contains('<gpx')) return 'gpx';
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
    String content;
    try {
      content = await File(path).readAsString();
    } catch (e) {
      debugPrint('shared-file read failed: $e');
      return const SharedRouteImport.failure();
    }
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1) : null;
    final format = detectRouteFormat(extension: ext, content: content);
    if (format == null) return const SharedRouteImport.failure();
    try {
      final route = await compute(
        _parseSharedRouteFile,
        _SharedParseRequest(format, content),
      );
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
  final String format;
  final String content;
  const _SharedParseRequest(this.format, this.content);
}

cm.Route _parseSharedRouteFile(_SharedParseRequest r) =>
    routeFromImportedFile(format: r.format, content: r.content);
