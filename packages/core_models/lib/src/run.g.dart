// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Run _$RunFromJson(Map<String, dynamic> json) => Run(
  id: json['id'] as String,
  startedAt: DateTime.parse(json['startedAt'] as String),
  duration: Duration(microseconds: (json['duration'] as num).toInt()),
  distanceMetres: (json['distanceMetres'] as num).toDouble(),
  track:
      (json['track'] as List<dynamic>?)
          ?.map((e) => Waypoint.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  routeId: json['routeId'] as String?,
  source: $enumDecode(_$RunSourceEnumMap, json['source']),
  externalId: json['externalId'] as String?,
  metadata: json['metadata'] as Map<String, dynamic>?,
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$RunToJson(Run instance) => <String, dynamic>{
  'id': instance.id,
  'startedAt': instance.startedAt.toIso8601String(),
  'duration': instance.duration.inMicroseconds,
  'distanceMetres': instance.distanceMetres,
  'track': instance.track,
  'routeId': instance.routeId,
  'source': _$RunSourceEnumMap[instance.source]!,
  'externalId': instance.externalId,
  'metadata': instance.metadata,
  'createdAt': instance.createdAt?.toIso8601String(),
};

const _$RunSourceEnumMap = {
  RunSource.app: 'app',
  RunSource.watch: 'watch',
  RunSource.healthkit: 'healthkit',
  RunSource.healthconnect: 'healthconnect',
  RunSource.strava: 'strava',
  RunSource.garmin: 'garmin',
  RunSource.parkrun: 'parkrun',
  RunSource.race: 'race',
};
