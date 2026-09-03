/// Shared data types for the Run app.
///
/// A name added here can COLLIDE in a consumer, not here: `geolocator_apple`
/// exports an `ActivityType` of its own, so `run_recorder` — which imports both
/// — carries `hide ActivityType` (decisions § 1013 / § 1014). The collision is
/// an `ambiguous_import` ERROR at the use site, so `dart analyze` in the
/// COLLIDING package reports it and exits 3, and CI's `melos exec -- dart
/// analyze` covers every package. Analysing THIS package, or the app, reports
/// nothing — the analyzer only diagnoses the files it is pointed at, which is
/// what made the hazard read as invisible. After adding a name, analyse the
/// consumers (`melos exec -- dart analyze`), not just core_models.
///
/// `barrel_test.dart` pins the two things nothing else fails on: every library
/// under `src/` is exported from here, and this package still has no Flutter
/// dependency. It deliberately does NOT re-check collisions — decisions § 1043
/// records why.
library core_models;

export 'src/activity_type.dart';
export 'src/atomic_io.dart';
export 'src/distance_unit.dart';
export 'src/store_write_chain.dart';
export 'src/food.dart';
export 'src/gear.dart';
export 'src/generated/db_rows.dart';
export 'src/gym.dart';
export 'src/import_completeness.dart';
export 'src/local_store_schema.dart';
export 'src/metadata_keys.dart';
export 'src/profile_query.dart';
export 'src/route.dart';
export 'src/route_match_candidate.dart';
export 'src/run.dart';
export 'src/run_match_info.dart';
export 'src/run_row_shape.dart';
export 'src/run_source.dart';
export 'src/run_summary.dart';
export 'src/social.dart';
export 'src/strava_sync_result.dart';
export 'src/waypoint.dart';
