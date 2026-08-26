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

/** A usable ordinal: the RPC returns `1 + count(...)`, so anything else came
 *  from a wire coercion going wrong and is treated as no answer. */
function usableRank(rank: number | null | undefined): number | null {
	if (rank == null) return null;
	const n = Number(rank);
	return Number.isFinite(n) && n >= 1 ? n : null;
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
		const usable = usableRank(rank as number | null | undefined);
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
