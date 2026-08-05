import 'package:core_models/core_models.dart';

/// Whether a public run row is a live broadcast that is still running.
///
/// The recorder pre-creates a stub `runs` row (`beginLiveBroadcast`) so live
/// spectator pings have a parent, then overwrites it with the real
/// `duration_s` on stop and stamps `concluded_at`. A stub therefore reads as a
/// 0 km / 0:00 run with no conclusion — which is exactly what every spectator
/// surface rendered before this, giving a viewer no way to tell "happening
/// right now" from "a finished run of nothing" and no way to reach the live
/// tracker.
///
/// `concluded_at` is the positive terminal marker (migration 20270427_001), so
/// it is checked FIRST: a concluded run is never live, whatever its duration.
/// Mirror of `apps/web/src/lib/runs/live_broadcast.ts`.
bool isLiveBroadcast(RunRow? run) {
  if (run == null) return false;
  if (run.concludedAt != null) return false;
  return run.durationS <= 0;
}
