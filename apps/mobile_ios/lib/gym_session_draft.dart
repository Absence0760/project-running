/// Does a `gym_workouts` row's metadata bag carry an in-flight guided session?
///
/// The marker's shape is a cross-platform contract, not a local convention:
/// the `gym_routine_history` RPC asks `jsonb_typeof(...) = 'object'` and web
/// asks `isJsonObject`, so anything that is not a JSON object under the key —
/// an array, a string, a JSON `null` — has to answer "not a draft" here too,
/// or a row the other rails count as performed reads as in-flight on this one
/// (decisions.md § 662). `metadata` is unconstrained jsonb and a row owner can
/// PATCH their own through PostgREST, so writer discipline is not the check.
///
/// Not a twin of web's `gym_session_draft.ts` — mobile writes and replays the
/// snapshot inside the session screen. Only this predicate is shared.
library;

import 'package:core_models/core_models.dart' show MetadataKeys;

bool hasGymSessionDraft(Object? metadata) {
  if (metadata is! Map) return false;
  return metadata[MetadataKeys.gymSessionDraft] is Map;
}
