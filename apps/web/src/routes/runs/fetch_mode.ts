/// Which read the `/runs` list performs: one server page at a time
/// (`paginated`) or the whole matching history in one go (`full`).
///
/// The page narrows AND orders the run list in the browser. Both of those are
/// only sound over the complete set: `fetchRuns` pages by `started_at`
/// descending, so anything the client re-filters or re-sorts is computed over
/// the newest N rows that happen to be in memory, not over the runner's
/// history. Filtering already forced `full`; ordering did not, which is how
/// "All time · Longest" came to rank the newest 50 runs and hide a marathon
/// from two years ago.
///
/// `newest` is the one sort key that agrees with the server's own order, so it
/// is the only one that may paginate.
export type RunsFetchMode = 'paginated' | 'full';

export interface RunsFetchModeInput {
	/// The date range actually in force (a `custom` selection with no bounds
	/// committed yet resolves back to the previous range before it gets here).
	effectiveDateRange: string;
	sourceFilter: string;
	activityFilter: string;
	sortKey: string;
}

export const PAGINATED_SORT_KEY = 'newest';

export function runsFetchMode(input: RunsFetchModeInput): RunsFetchMode {
	const narrowed =
		input.effectiveDateRange !== 'all' ||
		input.sourceFilter !== 'all' ||
		input.activityFilter !== 'all';
	const reordered = input.sortKey !== PAGINATED_SORT_KEY;
	return narrowed || reordered ? 'full' : 'paginated';
}
