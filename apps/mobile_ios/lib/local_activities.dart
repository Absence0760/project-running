import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'local_gym_store.dart';

/// Assemble the unified History timeline from the three offline-first local
/// stores, newest-first. This replaces the old server-backed
/// `ApiClient.fetchActivities` so History always reflects every modality the
/// device has — with no network, no "run-only when offline" fallback, and live
/// updates as the local stores change (a logged lift / meal appears at once).
/// See [decisions §63](../../docs/architecture/decisions.md). Pure + unit
/// tested; the screen hands it the raw store lists.
///
/// `foods` are the raw `food_log` rows (`LocalFoodStore.rows`); each carries
/// `id` / `started_at` / `item_name` / `calories`. The `summary` maps mirror
/// the keys `widgets/activity_timeline_list.dart` reads, which in turn mirror
/// the server `activities` view they replace.
///
/// **Precondition: each source list is sorted newest-first by `started_at`** —
/// which is exactly what `LocalRunStore.runs` / `LocalGymStore.workouts` /
/// `LocalFoodStore.rows` all guarantee. That lets us cap each source at `limit`
/// *before* building rows: the global newest `limit` can draw at most `limit`
/// from any one source, so anything past a source's first `limit` entries is
/// provably out of the result. Without the cap a user with thousands of runs /
/// lifts / meals would allocate an `ActivityRow` for every row and sort the
/// whole merged list on every store-change rebuild, only to throw all but 200
/// away. Capped, a rebuild is O(limit log limit) regardless of total history.
List<ActivityRow> buildLocalActivities({
  required List<Run> runs,
  required List<StoredGymWorkout> workouts,
  required List<Map<String, dynamic>> foods,
  int limit = 200,
}) {
  final out = <ActivityRow>[];

  List<T> capped<T>(List<T> xs) =>
      xs.length > limit ? xs.sublist(0, limit) : xs;
  runs = capped(runs);
  workouts = capped(workouts);
  foods = capped(foods);

  for (final r in runs) {
    out.add(ActivityRow(
      id: r.id,
      kind: 'run',
      startedAt: r.startedAt,
      summary: {
        'distance_m': r.distanceMetres,
        'duration_s': r.duration.inSeconds,
      },
    ));
  }

  for (final w in workouts) {
    final startedAt = w.startedAt;
    if (startedAt == null) continue;
    // set_count = total sets (matching the server view's gym_sets row count);
    // volume = Σ reps × weight over the completed sets.
    var setCount = 0;
    var volume = 0.0;
    for (final s in w.sets) {
      setCount++;
      final reps = (s['reps'] as num?)?.toDouble();
      final weight = (s['weight_kg'] as num?)?.toDouble();
      if (reps != null && weight != null) volume += reps * weight;
    }
    out.add(ActivityRow(
      id: w.id,
      kind: 'lift',
      startedAt: startedAt,
      summary: {
        'title': w.row['title'],
        'set_count': setCount,
        'volume_kg': volume,
      },
    ));
  }

  for (final f in foods) {
    final id = f['id'] as String?;
    final startedAtRaw = f['started_at'] as String?;
    if (id == null || id.isEmpty || startedAtRaw == null) continue;
    final startedAt = DateTime.tryParse(startedAtRaw);
    if (startedAt == null) continue;
    out.add(ActivityRow(
      id: id,
      kind: 'meal',
      startedAt: startedAt,
      summary: {
        'item_name': f['item_name'],
        'calories': f['calories'],
      },
    ));
  }

  out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return out.length > limit ? out.sublist(0, limit) : out;
}
