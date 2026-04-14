import 'package:json_annotation/json_annotation.dart';

part 'waypoint.g.dart';

@JsonSerializable()
class Waypoint {
  final double lat;
  final double lng;
  final double? elevationMetres;
  final DateTime? timestamp;

  const Waypoint({
    required this.lat,
    required this.lng,
    this.elevationMetres,
    this.timestamp,
  });

  factory Waypoint.fromJson(Map<String, dynamic> json) =>
      _$WaypointFromJson(json);

  Map<String, dynamic> toJson() => _$WaypointToJson(this);
}
