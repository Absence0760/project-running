// Pure helpers for the following-feed query. The feed filters runs by the
// viewer's followee set via `.in('user_id', ids)`. PostgREST serialises
// `.in()` into the URL query string, so a viewer following many hundreds of
// people overflows the gateway's ~8 KB request-line limit and the query
// returns `{ data: null }` — a silently empty feed. We chunk the id set,
// query each chunk, and merge. These helpers are extracted so the chunking +
// merge math is unit-testable without a live Supabase.

// Conservative chunk size: a UUID serialises to ~38 chars inside `.in(...)`,
// so 100 ids keep the in-clause well under the gateway header budget even
// alongside the other query params.
export const FEED_FOLLOWEE_CHUNK = 100;

export function chunk<T>(items: T[], size: number): T[][] {
	if (size <= 0) throw new Error('chunk size must be positive');
	const out: T[][] = [];
	for (let i = 0; i < items.length; i += size) {
		out.push(items.slice(i, i + size));
	}
	return out;
}

/**
 * Merge per-chunk feed pages into the global page. Each chunk query already
 * applied the same cursor + ordering + limit, so the global top-`limit` rows
 * (ordered by started_at desc, then id desc) are guaranteed to be a subset of
 * the union of the per-chunk results. Dedupe by id (a row can only come from
 * one chunk, but guard anyway), sort, and trim to `limit`.
 */
export function mergeFeedPages<T extends { id: string; started_at: string }>(
	pages: (T[] | null | undefined)[],
	limit: number
): T[] {
	const byId = new Map<string, T>();
	for (const page of pages) {
		for (const row of page ?? []) byId.set(row.id, row);
	}
	const merged = Array.from(byId.values());
	merged.sort((a, b) => {
		if (a.started_at !== b.started_at) return a.started_at < b.started_at ? 1 : -1;
		return a.id < b.id ? 1 : -1;
	});
	return merged.slice(0, Math.max(0, limit));
}
