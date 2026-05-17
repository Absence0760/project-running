import 'package:json_annotation/json_annotation.dart';

import 'waypoint.dart';

part 'route.g.dart';

@JsonSerializable()
class Route {
  final String id;
  /// Owner of the route. Required for the privacy-zone clipping path —
  /// non-owner viewers must route through `clip_route_for_viewer`
  /// (decisions §33). Sourced from `routes.user_id` on the row.
  final String userId;
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

  /// User-curated "what I actually run" flag. Drives the watch's
  /// route picker (starred-only) so the runner doesn't scroll
  /// through every saved route on a 1.4-inch screen. Owner-editable
  /// from web / mobile; read-only on the watch.
  final bool isStarred;

  /// Club this route belongs to, if any. Owned routes can be
  /// transferred into a club's library or detached back to personal
  /// via `SocialService.setRouteClub`. `null` means personal. See
  /// `decisions.md § 30` (club-owned routes) and migration
  /// `20260520_001_club_owned_routes.sql`.
  final String? clubId;

  /// Free-form description set in the route builder's Save modal.
  /// Migration `20260902_001_routes_description.sql`. Rendered below
  /// the title on the route detail surfaces.
  final String? description;

  const Route({
    required this.id,
    required this.name,
    required this.waypoints,
    required this.distanceMetres,
    this.userId = '',
    this.elevationGainMetres = 0,
    this.isPublic = false,
    this.createdAt,
    this.surface,
    this.tags = const [],
    this.featured = false,
    this.runCount = 0,
    this.isStarred = false,
    this.clubId,
    this.description,
  });

  factory Route.fromJson(Map<String, dynamic> json) => _$RouteFromJson(json);

  Map<String, dynamic> toJson() => _$RouteToJson(this);
}
