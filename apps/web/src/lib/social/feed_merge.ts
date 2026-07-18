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
 * Merge per-chunk pages ordered by a recency timestamp into the global page.
 * Each chunk query already applied the same cursor + ordering + limit, so the
 * global top-`limit` rows (ordered by `tsOf` desc, then id desc) are guaranteed
 * to be a subset of the union of the per-chunk results. Dedupe by id (a row can
 * only come from one chunk, but guard anyway), sort, and trim to `limit`.
 */
export function mergeRecencyPages<T extends { id: string }>(
	pages: (T[] | null | undefined)[],
	limit: number,
	tsOf: (row: T) => string
): T[] {
	const byId = new Map<string, T>();
	for (const page of pages) {
		for (const row of page ?? []) byId.set(row.id, row);
	}
	const merged = Array.from(byId.values());
	merged.sort((a, b) => {
		const ta = tsOf(a);
		const tb = tsOf(b);
		if (ta !== tb) return ta < tb ? 1 : -1;
		return a.id < b.id ? 1 : -1;
	});
	return merged.slice(0, Math.max(0, limit));
}

/** The run / lift feed ordered by `started_at` — see `mergeRecencyPages`. */
export function mergeFeedPages<T extends { id: string; started_at: string }>(
	pages: (T[] | null | undefined)[],
	limit: number
): T[] {
	return mergeRecencyPages(pages, limit, (r) => r.started_at);
}

/**
 * Merge chunked `user_profiles` reads into one id→row map. The profile-join
 * leg (`.in('id', ids)`) is chunked for the same request-URL reason as the
 * feed: a club / event with more than ~100 members overflows the gateway's
 * request-line limit and the leg silently returns null, degrading every
 * name / avatar to a placeholder. A row can only come from one chunk (ids are
 * deduped upstream); later chunks win on a collision.
 */
export function mergeProfilePages<T extends { id: string }>(
	pages: (T[] | null | undefined)[]
): Map<string, T> {
	const byId = new Map<string, T>();
	for (const page of pages) {
		for (const row of page ?? []) byId.set(row.id, row);
	}
	return byId;
}
