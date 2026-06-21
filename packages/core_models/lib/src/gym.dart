import 'generated/db_rows.dart';

/// A single logged set inside a [GymWorkout]. The typed view of one entry in
/// the inline `sets` list a [GymWorkout] carries (the offline store keeps a
/// workout's sets inline, one file per workout).
class GymSet {
  const GymSet({
    required this.exerciseName,
    this.reps,
    this.weightKg,
    this.rpe,
    this.setType = 'working',
    this.durationS,
    this.setIndex,
  });

  final String exerciseName;
  final int? reps;
  final double? weightKg;
  final double? rpe;

  /// Role this set played (warmup/working/dropset/amrap/failure/backoff);
  /// defaults to 'working'. Raw string mirroring the DB CHECK union — the
  /// gym_routine_sets.set_type vocabulary (migration 20270224_001).
  final String setType;

  /// Optional hold/interval time in seconds for timed work (planks, holds);
  /// null for rep/load-only sets (migration 20261231_001).
  final int? durationS;

  /// Positional index within the workout. Often null for client-minted sets
  /// (assigned server-side on INSERT).
  final int? setIndex;

  factory GymSet.fromRow(Map<String, dynamic> row) => GymSet(
        exerciseName: (row[GymSetRow.colExerciseName] as String?) ?? '',
        reps: (row[GymSetRow.colReps] as num?)?.toInt(),
        weightKg: (row[GymSetRow.colWeightKg] as num?)?.toDouble(),
        rpe: (row[GymSetRow.colRpe] as num?)?.toDouble(),
        setType: (row[GymSetRow.colSetType] as String?) ?? 'working',
        durationS: (row[GymSetRow.colDurationS] as num?)?.toInt(),
        setIndex: (row[GymSetRow.colSetIndex] as num?)?.toInt(),
      );
}

/// Typed domain view of a gym workout — the `gym_workouts` row scalars plus
/// the workout's [sets]. Built from the raw row map (and inline set maps)
/// the offline `LocalGymStore` holds so screens read typed fields instead of
/// reaching into a `Map<String, dynamic>` by string key.
class GymWorkout {
  const GymWorkout({
    required this.id,
    this.title,
    this.startedAt,
    this.durationS,
    this.notes,
    this.isPublic = false,
    this.externalId,
    this.lastModifiedAt,
    this.createdAt,
    this.sets = const [],
  });

  final String id;
  final String? title;
  final DateTime? startedAt;
  final int? durationS;
  final String? notes;
  final bool isPublic;
  final String? externalId;
  final DateTime? lastModifiedAt;
  final DateTime? createdAt;
  final List<GymSet> sets;

  factory GymWorkout.fromRow(
    Map<String, dynamic> row, {
    List<Map<String, dynamic>> sets = const [],
  }) =>
      GymWorkout(
        id: row[GymWorkoutRow.colId] as String,
        title: row[GymWorkoutRow.colTitle] as String?,
        startedAt: _parseTs(row[GymWorkoutRow.colStartedAt]),
        durationS: (row[GymWorkoutRow.colDurationS] as num?)?.toInt(),
        notes: row[GymWorkoutRow.colNotes] as String?,
        isPublic: (row[GymWorkoutRow.colIsPublic] as bool?) ?? false,
        externalId: row[GymWorkoutRow.colExternalId] as String?,
        lastModifiedAt: _parseTs(row[GymWorkoutRow.colLastModifiedAt]),
        createdAt: _parseTs(row[GymWorkoutRow.colCreatedAt]),
        sets: [for (final s in sets) GymSet.fromRow(s)],
      );
}

DateTime? _parseTs(dynamic v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
