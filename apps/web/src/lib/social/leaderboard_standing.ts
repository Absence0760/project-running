/// Where one entrant sits on a challenge leaderboard, relative to the entrants
/// immediately either side of them. The board itself only answers "who is
/// where"; the competitive signal a participant actually acts on is "how far
/// off is the place above me, and how much cushion do I have below" — and on a
/// board of any size their own row may be well off screen.
///
/// A pure re-shape of rows the caller already holds: no new query, no new data.
/// Every number stays in raw metric units and every neighbour is returned as
/// the ENTRY, not a label, so unit formatting and name/team resolution stay one
/// concern at the UI edge.
///
/// Web-only by design, like `challenge_list.ts`: the mobile challenge detail
/// renders the raw board with no standing summary, so a Dart twin would be a
/// helper with no caller. NOT part of the `challenge_progress` parity pair.

/** The shape any board row must carry. `ChallengeLeaderboardRow` satisfies it
 * structurally; `rank` is deliberately NOT required — see `standingFor`. */
export interface StandingEntry {
	user_id?: string | null;
	team_club_id?: string | null;
	value: number;
}

export interface Neighbour<T> {
	entry: T;
	/** Metric units separating this entry from the viewer. Always > 0. */
	delta: number;
}

export interface Standing<T> {
	entry: T;
	rank: number;
	/** Entrants on the board, including the viewer. */
	total: number;
	/** How many OTHER entries share the viewer's exact value, and so their rank. */
	tiedWith: number;
	/** Nearest entry ranked strictly above (a better value), and the units
	 * needed to draw level. Null when nobody is ahead. */
	chasing: Neighbour<T> | null;
	/** Nearest entry ranked strictly below, and the viewer's margin over it.
	 * Null when nobody is behind. */
	chasedBy: Neighbour<T> | null;
}

/** A team board keys on the club, an individual board on the runner. A row
 * carrying neither is the real unaffiliated bucket (`team_club_id` is nullable
 * and its FK is `on delete set null`), which no viewer can be matched to. */
export function entryKey(entry: StandingEntry): string | null {
	return entry.user_id ?? entry.team_club_id ?? null;
}

/** The viewer's standing on `rows`, or null when they aren't on the board (or
 * can't be identified, or their value isn't a number — fail closed to claiming
 * nothing rather than to a fabricated rank).
 *
 * Rank is DERIVED as one plus the number of strictly better values rather than
 * read off the row, which is `rank() over (order by value desc)` by definition
 * — so it cannot disagree with the rank the SQL sent and the list renders, and
 * the helper stays usable on any board that hasn't been ranked server-side. A
 * non-finite value on another row fails every comparison, so it lands in
 * neither neighbour slot and never inflates the rank.
 *
 * Neighbours tie-break on `entryKey` ascending, mirroring the SQL board's
 * `order by rank, <key> nulls last`, so the card names the same entrant across
 * two refreshes. */
export function standingFor<T extends StandingEntry>(
	rows: readonly T[],
	viewerKey: string | null | undefined,
): Standing<T> | null {
	if (!viewerKey) return null;
	const entry = rows.find((r) => entryKey(r) === viewerKey);
	if (entry === undefined || !Number.isFinite(entry.value)) return null;

	const mine = entry.value;
	let rank = 1;
	let tiedWith = 0;
	let chasing: Neighbour<T> | null = null;
	let chasedBy: Neighbour<T> | null = null;

	for (const row of rows) {
		if (row === entry) continue;
		if (row.value > mine) {
			rank += 1;
			if (chasing === null || row.value < chasing.entry.value || isPreferredTie(row, chasing.entry)) {
				chasing = { entry: row, delta: row.value - mine };
			}
		} else if (row.value < mine) {
			if (
				chasedBy === null ||
				row.value > chasedBy.entry.value ||
				isPreferredTie(row, chasedBy.entry)
			) {
				chasedBy = { entry: row, delta: mine - row.value };
			}
		} else if (row.value === mine) {
			tiedWith += 1;
		}
	}

	return { entry, rank, total: rows.length, tiedWith, chasing, chasedBy };
}

function isPreferredTie(candidate: StandingEntry, incumbent: StandingEntry): boolean {
	if (candidate.value !== incumbent.value) return false;
	const a = entryKey(candidate);
	const b = entryKey(incumbent);
	if (a === null) return false;
	if (b === null) return true;
	return a < b;
}
