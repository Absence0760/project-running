import 'package:json_annotation/json_annotation.dart';

import 'run_source.dart';
import 'waypoint.dart';

part 'run.g.dart';

@JsonSerializable()
class Run {
  final String id;
  final DateTime startedAt;
  final Duration duration;
  final double distanceMetres;
  final List<Waypoint> track;
  final String? routeId;
  final RunSource source;
  final String? externalId;
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;

  const Run({
    required this.id,
    required this.startedAt,
    required this.duration,
    required this.distanceMetres,
    this.track = const [],
    this.routeId,
    required this.source,
    this.externalId,
    this.metadata,
    this.createdAt,
  });

  factory Run.fromJson(Map<String, dynamic> json) => _$RunFromJson(json);

  /// Always encodable.
  ///
  /// `jsonEncode` refuses a non-finite double with a `JsonUnsupportedObjectError`
  /// — an `Error`, so `on Exception` does not see it — and the generated
  /// serializer would hand it one straight from a track point or from
  /// [distanceMetres]. Every writer of a run goes through here: the local
  /// store's five encode sites and the backup archive, so a run that carries a
  /// value that is not a number is still saveable rather than permanently
  /// stuck. A non-finite distance resolves to zero, which is what the column's
  /// own `runs_distance_m_check` would demand anyway (decisions § 986) and
  /// which — unlike a NaN — cannot poison the local index every other run
  /// shares.
  Map<String, dynamic> toJson() {
    final json = _$RunToJson(this);
    final usable = finiteWaypoints(track);
    if (!identical(usable, track)) {
      json['track'] = <Map<String, dynamic>>[
        for (final w in usable) w.toJson(),
      ];
    }
    if (!distanceMetres.isFinite) json['distanceMetres'] = 0.0;
    return json;
  }
}
