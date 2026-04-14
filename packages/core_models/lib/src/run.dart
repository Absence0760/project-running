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

  Map<String, dynamic> toJson() => _$RunToJson(this);
}
