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

export interface NamedPerson {
	id: string;
	display_name: string | null;
}

export interface RankablePerson extends NamedPerson {
	public_runs_count: number;
	shared_clubs: number;
}

/// The last two terms of a people sort: the reader's own collation, then the
/// id that makes the order total.
///
/// A collation, deliberately, and NOT the folded compare § 1337 put on the
/// routes list: that pair has a Dart twin whose runtime ships no collator,
/// and this surface has none. Folding would hand every reader the English
/// order — `Åsa` before `Zoe` for the Swede who expects the reverse
/// (decisions § 1400).
///
/// The id is what the collation cannot supply. It answers 0 for two DIFFERENT
/// strings — two people genuinely called `John Smith`, or one display name
/// stored precomposed against another stored decomposed — and
/// `Array.prototype.sort` then falls through to whatever the query returned,
/// which no `ORDER BY` on these paths makes unique. Same reason
/// `dmRecipientCandidates` breaks its own ties on the id.
export function comparePersonName(a: NamedPerson, b: NamedPerson): number {
	const byName = (a.display_name ?? '').localeCompare(b.display_name ?? '');
	return byName !== 0 ? byName : a.id.localeCompare(b.id);
}

export function comparePeopleRank(a: RankablePerson, b: RankablePerson): number {
	if (b.public_runs_count !== a.public_runs_count) {
		return b.public_runs_count - a.public_runs_count;
	}
	if (b.shared_clubs !== a.shared_clubs) {
		return b.shared_clubs - a.shared_clubs;
	}
	return comparePersonName(a, b);
}
