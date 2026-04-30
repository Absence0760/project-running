/// One candidate row returned by the `routes_intersecting_track`
/// RPC (migration `20260610_001_routes_intersecting_track.sql`).
/// Pure data — the caller scores against `startOffsetM`,
/// `endOffsetM`, and `distanceM` to decide whether to surface a
/// "Looks like you ran X — link?" prompt or stay silent.
class RouteMatchCandidate {
  final String id;
  final String name;
  final double distanceM;
  final double startOffsetM;
  final double endOffsetM;

  const RouteMatchCandidate({
    required this.id,
    required this.name,
    required this.distanceM,
    required this.startOffsetM,
    required this.endOffsetM,
  });

  factory RouteMatchCandidate.fromJson(Map<String, dynamic> json) =>
      RouteMatchCandidate(
        id: json['id'] as String,
        name: json['name'] as String,
        distanceM: (json['distance_m'] as num).toDouble(),
        startOffsetM: (json['start_offset_m'] as num).toDouble(),
        endOffsetM: (json['end_offset_m'] as num).toDouble(),
      );
}
