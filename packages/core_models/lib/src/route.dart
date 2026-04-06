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

  const Route({
    required this.id,
    required this.name,
    required this.waypoints,
    required this.distanceMetres,
    this.elevationGainMetres = 0,
    this.isPublic = false,
    this.createdAt,
  });

  factory Route.fromJson(Map<String, dynamic> json) => _$RouteFromJson(json);

  Map<String, dynamic> toJson() => _$RouteToJson(this);
}
