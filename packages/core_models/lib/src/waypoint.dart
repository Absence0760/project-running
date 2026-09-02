import 'package:json_annotation/json_annotation.dart';

part 'waypoint.g.dart';

@JsonSerializable()
class Waypoint {
  final double lat;
  final double lng;
  final double? elevationMetres;
  final DateTime? timestamp;

  /// Per-point heart rate in BPM when the recorder captured HR samples
  /// alongside GPS. Optional: most historical runs only carry the scalar
  /// `metadata.avg_bpm`; per-point values arrive from Strava streams,
  /// FIT/TCX importers, and watch recorders. See `docs/backend/metadata.md`.
  final int? bpm;

  const Waypoint({
    required this.lat,
    required this.lng,
    this.elevationMetres,
    this.timestamp,
    this.bpm,
  });

  factory Waypoint.fromJson(Map<String, dynamic> json) =>
      _$WaypointFromJson(json);

  Map<String, dynamic> toJson() => _$WaypointToJson(this);
}

/// The waypoints of [track] that are actually locations, with any non-finite
/// elevation dropped to null.
///
/// Two reasons, and the second is the one that loses a run. A non-finite
/// latitude or longitude is not a coordinate but the absence of one
/// (decisions § 954). And `jsonEncode` REFUSES a non-finite double: it throws
/// `JsonUnsupportedObjectError`, an `Error` rather than an `Exception`, so a
/// single such point makes the whole track unencodable — the run cannot be
/// written to the local store and cannot be uploaded, on every retry forever,
/// with nothing in the failure to say it will never succeed.
///
/// Dropping the point removes nothing real, which is why this is a filter and
/// not a refusal: the alternative is a four-day effort that never leaves the
/// phone. Every other boundary in the tree already answers this way — the
/// recorder refuses to append a non-finite fix (§ 956) and the four route
/// importers drop one (§ 954); this is the same rule at the two serializers
/// the producers those guards do not cover all pass through.
///
/// Returns the input list itself when nothing needed dropping, so the common
/// path allocates nothing.
List<Waypoint> finiteWaypoints(List<Waypoint> track) {
  var needsFilter = false;
  for (final w in track) {
    if (!w.lat.isFinite ||
        !w.lng.isFinite ||
        (w.elevationMetres != null && !w.elevationMetres!.isFinite)) {
      needsFilter = true;
      break;
    }
  }
  if (!needsFilter) return track;
  return <Waypoint>[
    for (final w in track)
      if (w.lat.isFinite && w.lng.isFinite)
        Waypoint(
          lat: w.lat,
          lng: w.lng,
          elevationMetres: (w.elevationMetres?.isFinite ?? false)
              ? w.elevationMetres
              : null,
          timestamp: w.timestamp,
          bpm: w.bpm,
        ),
  ];
}
