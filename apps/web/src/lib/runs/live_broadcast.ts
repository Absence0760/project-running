/// Whether a public run row is a live broadcast that is still running.
///
/// The recorder pre-creates a stub `runs` row (`beginLiveBroadcast`) so live
/// spectator pings have a parent, then overwrites it with the real
/// `duration_s` on stop and stamps `concluded_at`. A stub therefore reads as a
/// 0 km / 0:00 run with no conclusion — which is exactly what every share
/// surface rendered before this, giving a spectator no way to tell "happening
/// right now" from "a finished run of nothing" and no way to reach
/// `/live/{id}`.
///
/// `concluded_at` is the positive terminal marker (migration 20270427_001), so
/// it is checked FIRST: a concluded run is never live, whatever its duration.
/// Mirrored in `apps/mobile_android/lib/live_broadcast.dart`.
export function isLiveBroadcast(
	run: { duration_s?: number | null; concluded_at?: string | null } | null | undefined,
): boolean {
	if (!run) return false;
	if (run.concluded_at != null && run.concluded_at !== '') return false;
	// Fail closed: "live" is a claim about right now, so it is only made when
	// the duration is actually present and zero — never inferred from a
	// missing column.
	if (typeof run.duration_s !== 'number') return false;
	return run.duration_s <= 0;
}
