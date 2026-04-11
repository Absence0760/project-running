import 'package:json_annotation/json_annotation.dart';

import 'waypoint.dart';

part 'route.g.dart';

@JsonSerializable()
class Route {
  final String id;
  final String name;
  final List<Waypoint> waypoints;
  final double distanceMetres;
  final double elevationGainMetres;
  final bool isPublic;
  final DateTime? createdAt;

  /// Predominant ground type: `road`, `trail`, or `mixed`. Web's route
  /// builder populates this; mobile imports preserve whatever the backend
  /// returns and default to null for GPX/KML imports that don't know.
  final String? surface;

  const Route({
    required this.id,
    required this.name,
    required this.waypoints,
    required this.distanceMetres,
    this.elevationGainMetres = 0,
    this.isPublic = false,
    this.createdAt,
    this.surface,
  });

  factory Route.fromJson(Map<String, dynamic> json) => _$RouteFromJson(json);

  Map<String, dynamic> toJson() => _$RouteToJson(this);
}
