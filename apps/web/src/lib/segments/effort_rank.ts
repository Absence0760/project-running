/**
 * A segment effort's standing: how it is read off the wire, and how it renders.
 *
 * Rank is not a property of the effort row. It arrives separately, from
 * `segment_effort_ranks` / `global_segment_effort_ranks`, so an effort the RPC
 * did not answer for has a genuinely UNKNOWN standing. Both clients used to
 * spend that absence as `?? 1` — a CROWN, the single most flattering claim
 * these surfaces can make, produced by having no answer at all. Absent is
 * modelled as null end to end and rendered as a neutral placeholder, the same
 * fail-closed default `live_freshness`, `live_motion` and `leaderboard_standing`
 * hold. See decisions §746.
 */

/** Shown in place of "#3" when the standing is unknown. */
export const UNKNOWN_RANK_TEXT = '—';

/**
 * A usable ordinal: the RPC returns `1 + count(...)`, a positive INTEGER, so
 * anything else came from a wire coercion going wrong and is treated as no
 * answer.
 *
 * The type gate is the point. `Number()` alone is what let the absence back
 * in through the door §746 closed: `Number(true)` and `Number([1])` are both
 * `1`, so a boolean or a single-element array anywhere in the `rank` position
 * rendered a GOLD CROWN — the most flattering claim these surfaces make,
 * produced by a wire shape carrying no rank at all. A numeric STRING is still
 * accepted, because PostgREST serves a `bigint` count as one.
 */
function usableRank(rank: unknown): number | null {
	if (typeof rank !== 'number' && typeof rank !== 'string') return null;
	const n = Number(rank);
	return Number.isInteger(n) && n >= 1 ? n : null;
}

/**
 * Index the rank RPC's rows by effort id, dropping anything unusable.
 *
 * `null` is what `supabase.rpc` yields for a call that FAILED — it resolves
 * with `{ data: null, error }` rather than throwing — so an empty map is the
 * normal shape of an outage, not an impossible one.
 */
export function readRankRows(rows: unknown): Map<string, number> {
	const out = new Map<string, number>();
	if (!Array.isArray(rows)) return out;
	for (const row of rows) {
		if (row == null || typeof row !== 'object') continue;
		const { effort_id: id, rank } = row as { effort_id?: unknown; rank?: unknown };
		if (typeof id !== 'string' || id === '') continue;
		const usable = usableRank(rank);
		if (usable != null) out.set(id, usable);
	}
	return out;
}

/** Medal tier for a rank pill. An unknown standing is never a medal. */
export function rankPillClass(rank: number | null): string {
	const r = usableRank(rank);
	if (r == null) return '';
	if (r === 1) return 'gold';
	if (r <= 3) return 'silver';
	if (r <= 10) return 'bronze';
	return '';
}

/** Pill text: the ordinal, or the placeholder when the standing is unknown. */
export function rankPillText(rank: number | null): string {
	const r = usableRank(rank);
	return r == null ? UNKNOWN_RANK_TEXT : `#${r}`;
}
