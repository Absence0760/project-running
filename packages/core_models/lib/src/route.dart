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

  /// Free-form labels ("5k", "loop", "hill", "parkrun_course",
  /// "beginner"). Owner-editable, filterable on /explore.
  final List<String> tags;

  /// Editor's-pick flag. Curated (admin-set for now) to surface high-
  /// quality public routes on the Explore page.
  final bool featured;

  /// Cached count of `runs.route_id = this.id` rows. Maintained by a DB
  /// trigger, read-only from the client's perspective.
  final int runCount;

  const Route({
    required this.id,
    required this.name,
    required this.waypoints,
    required this.distanceMetres,
    this.elevationGainMetres = 0,
    this.isPublic = false,
    this.createdAt,
    this.surface,
    this.tags = const [],
    this.featured = false,
    this.runCount = 0,
  });

  factory Route.fromJson(Map<String, dynamic> json) => _$RouteFromJson(json);

  Map<String, dynamic> toJson() => _$RouteToJson(this);
}
