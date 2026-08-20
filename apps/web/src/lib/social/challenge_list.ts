/// Pure shaping for the challenge surfaces: the "My challenges" list on
/// /challenges and the leaderboard's team column.
///
/// The list's per-caller value is NOT carried by the `challenges` table read —
/// it only exists in the `challenge_leaderboard` aggregate, surfaced in bulk by
/// `my_active_challenges`. These helpers fold that aggregate onto the list and
/// decide what the row is allowed to claim, so a missing value renders as
/// missing rather than as a confident zero next to the goal.
///
/// Twinned by `apps/mobile_android/lib/challenge_list.dart`; keep the two in
/// lockstep (algorithm, edge cases, outputs, test counts). Distinct from the
/// `challenge_progress` pair, which shapes a value already in hand.

/** The caller-relative fields `my_active_challenges` can fill in. */
export interface MyProgressRow {
	id: string;
	my_value: number | null;
	my_rank: number | null;
	completed_at: string | null;
}

/** Fold the authoritative per-caller values from `my_active_challenges` onto a
 * joined-challenge list, matched by id. Rows the aggregate doesn't cover (it
 * only spans challenges live now or ended within 7 days) keep whatever they
 * already carried — never a fabricated zero. Input order is preserved so the
 * caller's `ends_at` ordering survives. */
export function mergeMyProgress<T extends MyProgressRow>(
	rows: T[],
	authoritative: MyProgressRow[],
): T[] {
	const byId = new Map(authoritative.map((a) => [a.id, a]));
	return rows.map((r) => {
		const a = byId.get(r.id);
		if (a === undefined) return r;
		return {
			...r,
			my_value: a.my_value ?? r.my_value,
			my_rank: a.my_rank ?? r.my_rank,
			completed_at: r.completed_at ?? a.completed_at,
		};
	});
}

/** What a list row may claim about the caller's progress. `not_started` is a
 * *known* zero (the aggregate's window is `started_at >= starts_at`, so nothing
 * can have counted yet); `unknown` means the number simply isn't on this page. */
export type MyProgressState = 'known' | 'not_started' | 'unknown';

export interface MyProgressView {
	state: MyProgressState;
	/** The value to render. 0 for `not_started` (true) and for `unknown` (unused
	 * — the caller must not render a bar in that state). */
	value: number;
}

/** Decide what a "My challenges" row may show. A value from the server always
 * wins over the clock comparison, so a client clock running behind the server's
 * can't downgrade a real number to a presumed zero. A non-finite value or an
 * unparseable `starts_at` falls through to `unknown` — fail closed to claiming
 * nothing rather than claiming zero. */
export function myProgressView(
	c: { my_value: number | null; starts_at: string },
	nowMs: number,
): MyProgressView {
	if (c.my_value !== null && Number.isFinite(c.my_value)) {
		return { state: 'known', value: c.my_value };
	}
	const startMs = Date.parse(c.starts_at);
	if (Number.isFinite(startMs) && Number.isFinite(nowMs) && nowMs < startMs) {
		return { state: 'not_started', value: 0 };
	}
	return { state: 'unknown', value: 0 };
}

/** What a club-vs-club leaderboard row's team column may say. `no_club` is a
 * real bucket — `challenge_participants.team_club_id` is nullable and its FK is
 * `on delete set null`, so a deleted club leaves its people as an unaffiliated
 * group the SQL aggregate still sums. `unresolved` is a club RLS did not let the
 * viewer read. */
export type TeamLabel = { kind: 'named'; name: string } | { kind: 'no_club' } | { kind: 'unresolved' };

/** Resolve a team row's club id against the names the caller could read. A miss
 * is `unresolved`, never the raw id: a uuid is meaningless to a reader and puts
 * an internal identifier on screen. The CALLER localises the two id-less
 * kinds. */
export function teamLabel(
	teamClubId: string | null | undefined,
	clubNames: Record<string, string>,
): TeamLabel {
	if (!teamClubId) return { kind: 'no_club' };
	const name = clubNames[teamClubId];
	if (typeof name === 'string' && name.trim().length > 0) return { kind: 'named', name };
	return { kind: 'unresolved' };
}
