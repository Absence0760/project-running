/// Canonical key names for the `runs.metadata` jsonb bag and the names of
/// the Supabase Storage buckets.
///
/// `runs.metadata` has no schema codegen — it's a free-form jsonb column —
/// so a typo or a cross-client casing drift (`activity_type` vs
/// `activityType`) is invisible to the type system and only surfaces as a
/// silently-missing field at runtime. Routing every Dart read/write through
/// these constants makes the compiler the first line of defence, and keeps
/// the keys here in lockstep with the registry in
/// `docs/backend/metadata.md` (the `metadata_registry_test` resolves
/// `MetadataKeys.*` references back to these literal values and fails if one
/// isn't documented).
///
/// The identifier is the camelCase form of the snake_case wire key.
class MetadataKeys {
  MetadataKeys._();

  static const String activityType = 'activity_type';
  static const String ageGrade = 'age_grade';
  static const String avgBpm = 'avg_bpm';
  static const String bib = 'bib';
  static const String cadenceSpm = 'cadence_spm';
  static const String chipTime = 'chip_time';
  static const String createdByUserId = 'created_by_user_id';
  static const String distanceSource = 'distance_source';
  static const String elevationM = 'elevation_m';
  static const String event = 'event';
  static const String fastest10kS = 'fastest_10k_s';
  static const String fastest5kS = 'fastest_5k_s';
  static const String fastestHalfMarathonS = 'fastest_half_marathon_s';
  static const String fastestMarathonS = 'fastest_marathon_s';
  static const String garminId = 'garmin_id';
  static const String gymAdherence = 'gym_adherence';
  static const String gymStepResults = 'gym_step_results';
  static const String healthConnectType = 'health_connect_type';
  static const String hrSeriesUrl = 'hr_series_url';
  static const String importedAt = 'imported_at';
  static const String importedFrom = 'imported_from';
  static const String indoor = 'indoor';
  static const String indoorEstimated = 'indoor_estimated';
  static const String inProgress = 'in_progress';
  static const String inProgressSavedAt = 'in_progress_saved_at';
  static const String isDnf = 'is_dnf';
  static const String laps = 'laps';
  static const String lastModifiedAt = 'last_modified_at';
  static const String manualEntry = 'manual_entry';
  static const String maxBpm = 'max_bpm';
  static const String notes = 'notes';
  static const String overallPlace = 'overall_place';
  static const String perceivedEffort = 'perceived_effort';
  static const String planWorkoutId = 'plan_workout_id';
  static const String position = 'position';
  static const String raceName = 'race_name';
  static const String recoveredFromCrash = 'recovered_from_crash';
  static const String routineId = 'routine_id';
  static const String runningDynamics = 'running_dynamics';
  static const String runNumber = 'run_number';
  static const String sessionAdherence = 'session_adherence';
  static const String sessionPlanId = 'session_plan_id';
  static const String sessionStepResults = 'session_step_results';
  static const String sourceFile = 'source_file';
  static const String steps = 'steps';
  static const String stravaActivityType = 'strava_activity_type';
  static const String stravaId = 'strava_id';
  static const String subSport = 'sub_sport';
  static const String title = 'title';
  static const String trackUrl = 'track_url';
  static const String workoutAdherence = 'workout_adherence';
  static const String workoutStepResults = 'workout_step_results';
}

/// Names of the Supabase Storage buckets the client touches directly.
///
/// The gzipped GPS track for a run lives in the [runs] bucket at
/// `{user_id}/{run_id}.json.gz` (see `decisions.md` on why the track isn't
/// a column); run photos live in [runPhotos] at `{owner_id}/{photo_id}.ext`.
class StorageBuckets {
  StorageBuckets._();

  static const String runs = 'runs';
  static const String runPhotos = 'run-photos';
  static const String routePhotos = 'route-photos';
  static const String avatars = 'avatars';
}
