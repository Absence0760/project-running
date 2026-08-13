/**
 * Gear backfill — given a piece of gear the runner has just registered, which
 * of their past runs could plausibly have been done in it.
 *
 * A runner rarely registers a pair of shoes the day they buy them; they log
 * them three weeks in, by which point the mileage the app is about to track
 * is already wrong. Backfill closes that: pick the runs since the purchase
 * date whose activity matches the gear kind, and attach the gear to them in
 * one go, so the retirement target means something from the first render.
 *
 * Pure functions, no Supabase / auth. TS↔Dart parity pair with
 * `apps/mobile_android/lib/gear_backfill.dart` — keep in lockstep (activity
 * mapping, boundary, ordering, edge cases).
 */

/// The subset of a run row the candidate filter reads. Deliberately
/// structural: callers pass whatever run shape they already hold (a narrow
/// `fetchRuns` projection on web) and get the same rows back.
export interface GearBackfillRun {
	id: string;
	started_at: string;
	activity_type?: string | null;
}

/// The instant a gear item's backfill window opens, from its `purchased_at`
/// (a date, no time). Resolved at LOCAL midnight because that is how the
/// runner means it — "I bought them on the 3rd" includes the 3rd's morning
/// run wherever they live. Reading it as UTC midnight would drop that run
/// for every runner east of Greenwich. Mirrors what the mobile date picker
/// hands the Dart twin (a local-midnight `DateTime`).
///
/// Returns null when there is no usable purchase date — the caller then has
/// no window to offer and skips the prompt.
export function gearPurchaseSince(purchasedAt: string | null | undefined): number | null {
	if (!purchasedAt) return null;
	const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(purchasedAt);
	if (!match) return null;
	const [, y, mo, d] = match;
	const local = new Date(Number(y), Number(mo) - 1, Number(d));
	const ms = local.getTime();
	return Number.isFinite(ms) ? ms : null;
}

/// Can this activity plausibly have been done in this gear kind?
///
/// DERIVED as "the bike takes cycling, everything else takes shoes", which is
/// the `auto_tag_default_gear` trigger's mapping verbatim (`case activity_type
/// when 'cycle' then 'bike' else 'shoe' end`, re-emitted over the promoted
/// column by migration `20261207_001`). Deliberately NOT an enumerated shoe
/// allowlist: `{run, walk, hike}` silently dropped `stroller` — a real value in
/// `runs_activity_type_check` — so the trigger auto-tagged a stroller run with
/// the current pair while backfill never offered it. An enumeration has to be
/// revisited every time the CHECK grows; this cannot fall behind it.
///
/// An unrecognised gear kind falls through to shoe semantics rather than
/// returning nothing, so a future gear kind can't silently make the prompt
/// disappear either.
function matchesGearKind(gearKind: string, activity: string): boolean {
	return gearKind === 'bike' ? activity === 'cycle' : activity !== 'cycle';
}

/// Past runs that are plausible backfill candidates for a piece of gear:
/// activity matches the gear kind, started on or after `sinceMs`. Returned
/// newest-first so the prompt's default selection lands on the most recent
/// runs. A run with no `activity_type` counts as a run, matching the rest of
/// the app (and the `auto_tag_default_gear` trigger, whose kind mapping this
/// mirrors — see `matchesGearKind`).
export function gearBackfillCandidates<T extends GearBackfillRun>(opts: {
	gearKind: string;
	sinceMs: number;
	runs: readonly T[];
}): T[] {
	return opts.runs
		.filter((r) => {
			const activity = (r.activity_type ?? 'run').toLowerCase();
			if (!matchesGearKind(opts.gearKind, activity)) return false;
			// A NaN parse (a malformed started_at) fails this comparison and
			// drops the row — a run we can't date can't be placed in the
			// window, and offering it would be a guess.
			return Date.parse(r.started_at) >= opts.sinceMs;
		})
		.sort((a, b) => Date.parse(b.started_at) - Date.parse(a.started_at));
}
