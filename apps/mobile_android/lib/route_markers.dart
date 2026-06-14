/// Course markers on a route — aid stations, cutoffs, crew/parking access,
/// hazards, notes, climbs (migration 20270129_001, route_markers table).
///
/// Pure, locale- and unit-agnostic logic shared by the map layer and the
/// course-schedule list: the kind catalogue (one source of truth for pin
/// colour + which detail fields a kind carries), schedule ordering, the
/// aid-service vocabulary, and cutoff parse/validation.
///
/// Distance formatting is deliberately NOT here — the render layer formats
/// `positionM` through the viewer's km/mi preference. The per-platform icon
/// glyph is also chosen at the render layer; this catalogue carries only the
/// shared hex colour + i18n label key so a pin looks the same on both
/// platforms.
///
/// Twin of `apps/web/src/lib/routes/route_markers.ts` — keep the kind set,
/// colours, service vocabulary, ordering, cutoff rules, edge cases, and test
/// count in lockstep.

/// Which optional detail fields a kind's `meta` bag carries.
class RouteMarkerKindSpec {
  final String kind;

  /// i18n key under `routeMarker.kind.*`.
  final String labelKey;

  /// Shared pin colour (hex) so the map looks identical across platforms.
  final String color;

  /// Aid services checklist (water / food / …) applies.
  final bool hasServices;

  /// A cutoff time (clock and/or elapsed) applies.
  final bool hasCutoff;

  const RouteMarkerKindSpec({
    required this.kind,
    required this.labelKey,
    required this.color,
    required this.hasServices,
    required this.hasCutoff,
  });
}

const List<RouteMarkerKindSpec> routeMarkerKinds = [
  RouteMarkerKindSpec(kind: 'aid_station', labelKey: 'routeMarker.kind.aid_station', color: '#0e9f6e', hasServices: true, hasCutoff: false),
  RouteMarkerKindSpec(kind: 'cutoff', labelKey: 'routeMarker.kind.cutoff', color: '#e02424', hasServices: false, hasCutoff: true),
  RouteMarkerKindSpec(kind: 'crew_access', labelKey: 'routeMarker.kind.crew_access', color: '#3f83f8', hasServices: false, hasCutoff: false),
  RouteMarkerKindSpec(kind: 'hazard', labelKey: 'routeMarker.kind.hazard', color: '#ff5a1f', hasServices: false, hasCutoff: false),
  RouteMarkerKindSpec(kind: 'note', labelKey: 'routeMarker.kind.note', color: '#9061f9', hasServices: false, hasCutoff: false),
  RouteMarkerKindSpec(kind: 'climb', labelKey: 'routeMarker.kind.climb', color: '#c27803', hasServices: false, hasCutoff: false),
  RouteMarkerKindSpec(kind: 'custom', labelKey: 'routeMarker.kind.custom', color: '#6b7280', hasServices: false, hasCutoff: false),
];

final Map<String, RouteMarkerKindSpec> _kindByKey = {
  for (final k in routeMarkerKinds) k.kind: k,
};

/// Spec for a kind, falling back to `custom` for an unknown value.
RouteMarkerKindSpec kindSpec(String kind) =>
    _kindByKey[kind] ?? _kindByKey['custom']!;

/// Aid-station service vocabulary (stored in `meta.services`).
const List<String> aidServices = ['water', 'food', 'medical', 'toilets', 'drop_bag'];

/// Minimal shape the ordering helpers need.
abstract class MarkerLike {
  double? get positionM;
  DateTime get createdAt;
}

/// Course-schedule order: by distance along the route (nulls — markers on a
/// route with no geom yet — sort last), then by insertion time so two markers
/// at the same point keep a stable order.
List<T> sortMarkers<T extends MarkerLike>(List<T> markers) {
  final out = List<T>.from(markers);
  out.sort((a, b) {
    final ap = a.positionM;
    final bp = b.positionM;
    if (ap == null && bp == null) {
      return a.createdAt.compareTo(b.createdAt);
    }
    if (ap == null) return 1;
    if (bp == null) return -1;
    if (ap != bp) return ap.compareTo(bp);
    return a.createdAt.compareTo(b.createdAt);
  });
  return out;
}

/// Parsed cutoff: a wall-clock "HH:MM" and/or an elapsed-from-start seconds.
class CutoffParts {
  final String? clock;
  final int? elapsedS;
  const CutoffParts({this.clock, this.elapsedS});

  @override
  bool operator ==(Object other) =>
      other is CutoffParts && other.clock == clock && other.elapsedS == elapsedS;

  @override
  int get hashCode => Object.hash(clock, elapsedS);
}

final RegExp _clockRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

/// Validate + normalise a marker's cutoff `meta` into [CutoffParts]. Returns
/// null when neither a valid clock nor a valid elapsed is present, so callers
/// render a cutoff chip only for a real cutoff. Both platforms must agree on
/// what counts as valid so a cutoff shows identically.
CutoffParts? parseCutoff(dynamic meta) {
  if (meta is! Map) return null;

  String? clock;
  final rawClock = meta['cutoff_clock'];
  if (rawClock is String && _clockRe.hasMatch(rawClock)) {
    clock = rawClock;
  }

  int? elapsedS;
  final rawElapsed = meta['cutoff_elapsed_s'];
  if (rawElapsed is num && rawElapsed.isFinite && rawElapsed >= 0) {
    elapsedS = rawElapsed.floor();
  }

  if (clock == null && elapsedS == null) return null;
  return CutoffParts(clock: clock, elapsedS: elapsedS);
}
