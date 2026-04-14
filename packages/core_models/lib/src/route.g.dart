// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'route.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Route _$RouteFromJson(Map<String, dynamic> json) => Route(
      id: json['id'] as String,
      name: json['name'] as String,
      waypoints: (json['waypoints'] as List<dynamic>)
          .map((e) => Waypoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      distanceMetres: (json['distanceMetres'] as num).toDouble(),
      elevationGainMetres:
          (json['elevationGainMetres'] as num?)?.toDouble() ?? 0,
      isPublic: json['isPublic'] as bool? ?? false,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      surface: json['surface'] as String?,
    );

Map<String, dynamic> _$RouteToJson(Route instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'waypoints': instance.waypoints.map((e) => e.toJson()).toList(),
      'distanceMetres': instance.distanceMetres,
      'elevationGainMetres': instance.elevationGainMetres,
      'isPublic': instance.isPublic,
      'createdAt': instance.createdAt?.toIso8601String(),
      'surface': instance.surface,
    };
