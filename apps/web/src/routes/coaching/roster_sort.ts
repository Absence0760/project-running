/// The coach roster's column sort, in a module the unit runner can hold —
/// `+page.svelte`'s `$derived` cannot be exercised without booting SvelteKit,
/// and the property worth pinning is one a render never shows twice.
import { injuryRiskBand } from '$lib/training/coach_load';
import type { CoachRosterRow } from '$lib/core/data';

export type RosterSortKey = 'risk' | 'lastRun' | 'load' | 'plan' | 'name';

const RISK_RANK: Record<string, number> = {
	high: 4,
	elevated: 3,
	optimal: 2,
	low: 1,
	insufficient: 0
};

export function rosterRisk(r: CoachRosterRow): string {
	return injuryRiskBand(r.load_acute, r.load_chronic);
}

function lastRunMs(r: CoachRosterRow): number {
	return r.last_run_at ? new Date(r.last_run_at).getTime() : 0;
}

/// Order the roster by one column.
///
/// Every key can tie — two athletes on the same risk band and the same
/// last-run day, two on 0 km acute load, two called `John Smith` (a collation
/// answers 0 for two DIFFERENT strings) — and `coach_roster_summary` carries
/// no unique `ORDER BY`, so the coach's roster reshuffled between renders.
/// The `athlete_id` tiebreak sits OUTSIDE the direction so reversing the
/// column does not also reverse a tie group.
export function sortRoster(
	rows: readonly CoachRosterRow[],
	sortKey: RosterSortKey,
	sortDir: 'asc' | 'desc'
): CoachRosterRow[] {
	const dir = sortDir === 'desc' ? -1 : 1;
	return [...rows].sort((a, b) => {
		let cmp = 0;
		switch (sortKey) {
			case 'risk':
				cmp = RISK_RANK[rosterRisk(a)] - RISK_RANK[rosterRisk(b)];
				if (cmp === 0) cmp = lastRunMs(a) - lastRunMs(b);
				break;
			case 'lastRun':
				cmp = lastRunMs(a) - lastRunMs(b);
				break;
			case 'load':
				cmp = a.load_acute - b.load_acute;
				break;
			case 'plan':
				cmp = a.plan_completion_pct - b.plan_completion_pct;
				break;
			case 'name':
				// A collation, deliberately: this roster is web-only, so the reason
				// § 1337 folded the routes list — a Dart twin whose runtime ships no
				// collator — does not apply, and folding would give every coach the
				// English order (decisions § 1400).
				cmp = (a.display_name ?? '').localeCompare(b.display_name ?? '');
				break;
		}
		return cmp !== 0 ? cmp * dir : a.athlete_id.localeCompare(b.athlete_id);
	});
}
