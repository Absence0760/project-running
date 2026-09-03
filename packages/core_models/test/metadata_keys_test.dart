import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  _runsBucketLimitTests();

  group('MetadataKeys', () {
    test('constants carry the snake_case wire value', () {
      expect(MetadataKeys.activityType, 'activity_type');
      expect(MetadataKeys.avgBpm, 'avg_bpm');
      expect(MetadataKeys.createdByUserId, 'created_by_user_id');
      expect(MetadataKeys.lastModifiedAt, 'last_modified_at');
      expect(MetadataKeys.trackUrl, 'track_url');
      expect(MetadataKeys.isDnf, 'is_dnf');
      expect(MetadataKeys.recoveredFromCrash, 'recovered_from_crash');
      expect(MetadataKeys.workoutStepResults, 'workout_step_results');
      expect(MetadataKeys.routineId, 'routine_id');
      expect(MetadataKeys.gymStepResults, 'gym_step_results');
      expect(MetadataKeys.gymAdherence, 'gym_adherence');
      expect(MetadataKeys.sessionPlanId, 'session_plan_id');
      expect(MetadataKeys.sessionStepResults, 'session_step_results');
      expect(MetadataKeys.sessionAdherence, 'session_adherence');
    });

    test('every value is unique snake_case', () {
      const values = [
        MetadataKeys.activityType,
        MetadataKeys.ageGrade,
        MetadataKeys.avgBpm,
        MetadataKeys.bib,
        MetadataKeys.cadenceSpm,
        MetadataKeys.chipTime,
        MetadataKeys.createdByUserId,
        MetadataKeys.distanceSource,
        MetadataKeys.elevationM,
        MetadataKeys.event,
        MetadataKeys.fastest10kS,
        MetadataKeys.fastest5kS,
        MetadataKeys.fastestHalfMarathonS,
        MetadataKeys.fastestMarathonS,
        MetadataKeys.garminId,
        MetadataKeys.gymAdherence,
        MetadataKeys.gymStepResults,
        MetadataKeys.healthConnectType,
        MetadataKeys.hrSeriesUrl,
        MetadataKeys.importedAt,
        MetadataKeys.importedFrom,
        MetadataKeys.indoor,
        MetadataKeys.indoorEstimated,
        MetadataKeys.inProgress,
        MetadataKeys.inProgressSavedAt,
        MetadataKeys.isDnf,
        MetadataKeys.laps,
        MetadataKeys.lastModifiedAt,
        MetadataKeys.manualEntry,
        MetadataKeys.maxBpm,
        MetadataKeys.notes,
        MetadataKeys.overallPlace,
        MetadataKeys.perceivedEffort,
        MetadataKeys.planWorkoutId,
        MetadataKeys.position,
        MetadataKeys.raceName,
        MetadataKeys.recoveredFromCrash,
        MetadataKeys.routineId,
        MetadataKeys.runningDynamics,
        MetadataKeys.runNumber,
        MetadataKeys.sessionAdherence,
        MetadataKeys.sessionPlanId,
        MetadataKeys.sessionStepResults,
        MetadataKeys.sourceFile,
        MetadataKeys.steps,
        MetadataKeys.stravaActivityType,
        MetadataKeys.stravaId,
        MetadataKeys.subSport,
        MetadataKeys.title,
        MetadataKeys.trackUrl,
        MetadataKeys.workoutAdherence,
        MetadataKeys.workoutStepResults,
      ];
      expect(values.toSet().length, values.length, reason: 'duplicate key');
      final snake = RegExp(r'^[a-z][a-z0-9_]*$');
      for (final v in values) {
        expect(snake.hasMatch(v), isTrue, reason: 'not snake_case: $v');
      }
    });
  });

  group('StorageBuckets', () {
    test('bucket names match the Supabase buckets', () {
      expect(StorageBuckets.runs, 'runs');
      expect(StorageBuckets.runPhotos, 'run-photos');
      expect(StorageBuckets.routePhotos, 'route-photos');
    });
  });
}

void _runsBucketLimitTests() {
  group('StorageBuckets.runsBucketMaxBytes', () {
    test('matches the runs bucket file_size_limit the migration sets', () {
      // A client rail on a server bound. Storage refuses a larger object with a
      // 413 whose only stable identity is an English message, so the uploader
      // carries the number — and it has to be THE number, or it either refuses
      // a blob Storage would take or sends one it will not.
      final sql = File(
        '../../apps/backend/supabase/migrations/'
        '20260620_001_storage_bucket_limits.sql',
      ).readAsStringSync();
      final m = RegExp(
        r"set file_size_limit = (\d+)[^;]*?where id = 'runs'",
        dotAll: true,
      ).firstMatch(sql);
      expect(m, isNotNull,
          reason: 'the runs bucket no longer sets file_size_limit in '
              '20260620_001 — find the migration that does and re-anchor this');
      expect(
        StorageBuckets.runsBucketMaxBytes,
        int.parse(m!.group(1)!),
      );
    });
  });
}
