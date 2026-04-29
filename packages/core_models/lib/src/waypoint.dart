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
  /// FIT/TCX importers, and watch recorders. See `docs/metadata.md`.
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
