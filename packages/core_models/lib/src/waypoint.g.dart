// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'waypoint.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Waypoint _$WaypointFromJson(Map<String, dynamic> json) => Waypoint(
  lat: (json['lat'] as num).toDouble(),
  lng: (json['lng'] as num).toDouble(),
  elevationMetres: (json['elevationMetres'] as num?)?.toDouble(),
  timestamp: json['timestamp'] == null
      ? null
      : DateTime.parse(json['timestamp'] as String),
  bpm: (json['bpm'] as num?)?.toInt(),
);

Map<String, dynamic> _$WaypointToJson(Waypoint instance) => <String, dynamic>{
  'lat': instance.lat,
  'lng': instance.lng,
  'elevationMetres': instance.elevationMetres,
  'timestamp': instance.timestamp?.toIso8601String(),
  'bpm': instance.bpm,
};
