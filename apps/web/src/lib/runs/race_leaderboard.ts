/// Deterministic ordering for the event live-leaderboard.
///
/// Sorting by distance alone leaves runners who share a distance in an
/// arbitrary, fetch-order-dependent position, so two consecutive
/// refreshes can swap their ranks and the board visibly jitters. The
/// tie-break makes the order a total order: furthest first, then —
/// among runners at the same distance — the one with the lower elapsed
/// time (they covered it faster), then the user_id as a final stable
/// discriminator so the result is identical on every client and every
/// refresh.
///
/// `distance_m` / `elapsed_s` are nullable on a ping (a watch may push
/// raw GPS with no odometer); a missing distance sorts to the back
/// (treated as 0) and a missing elapsed sorts after a present one
/// (treated as +Infinity) so a partial ping never jumps the board.

export interface LeaderboardSortable {
	user_id: string;
	distance_m: number | null;
	elapsed_s: number | null;
}

export function compareLeaderboard(a: LeaderboardSortable, b: LeaderboardSortable): number {
	const byDistance = (b.distance_m ?? 0) - (a.distance_m ?? 0);
	if (byDistance !== 0) return byDistance;
	const byElapsed = (a.elapsed_s ?? Infinity) - (b.elapsed_s ?? Infinity);
	if (byElapsed !== 0) return byElapsed;
	return a.user_id < b.user_id ? -1 : a.user_id > b.user_id ? 1 : 0;
}
