// Reputation-weighted ranking comparators for the People search /
// suggested-list flows. Pulled into its own module so node:test can
// exercise them without booting SvelteKit or Supabase.
//
// Anti-spam phase 1: a bot mass-creating empty accounts has zero
// public runs and zero shared clubs. By ranking on those signals
// first, real users surface above bots even when the bot's display
// name is a closer ILIKE prefix match.
//
// 0-runs accounts aren't *hidden* — a friend the viewer searches for
// by exact name may legitimately have posted no runs yet. They just
// rank last within the result set.

export interface RankablePerson {
	display_name: string | null;
	public_runs_count: number;
	shared_clubs: number;
}

export function comparePeopleRank(a: RankablePerson, b: RankablePerson): number {
	if (b.public_runs_count !== a.public_runs_count) {
		return b.public_runs_count - a.public_runs_count;
	}
	if (b.shared_clubs !== a.shared_clubs) {
		return b.shared_clubs - a.shared_clubs;
	}
	return (a.display_name ?? '').localeCompare(b.display_name ?? '');
}
