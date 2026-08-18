/// Paging for the Art 20 export's PostgREST reads.
///
/// PostgREST clamps every response to `db-max-rows` (1000 on Supabase)
/// and signals the truncation nowhere in the body: an unbounded SELECT
/// returns the first 1000 rows, and an explicit `limit=5000` is clamped
/// to the same 1000. A runner with more than one page of runs, photos,
/// food-log rows or gym sets therefore received a silently short export
/// whose manifest asserted it was whole.
///
/// Mirrors `collectRunIdentities` in `_shared/strava.ts` — offset paging,
/// a page fetcher that returns null to stop, terminate on a short page —
/// plus the bookkeeping an Art 20 manifest needs: a section that could
/// not be read in full is never counted as whole.

/// Page size. Matched to PostgREST's `db-max-rows` so a full page is
/// also the server's cap; asking for more per request buys nothing.
export const EXPORT_PAGE_SIZE = 1000;

/// Hard ceiling per section. Both export paths assemble the whole
/// archive in memory before uploading it, so an unbounded walk of a
/// high-cardinality table (`live_run_pings` runs into the millions on a
/// deep history) is an OOM, not a slow export. Reaching it marks the
/// section incomplete rather than silently truncating it, so the
/// shortfall is stated in `manifest.json` instead of hidden. Keep in
/// lockstep with `exportRowCeiling` in the Go worker's supabase.go.
export const EXPORT_ROW_CEILING = 50_000;

export interface ExportPage<T> {
	rows: T[];
	/// Authoritative row count the server reported for the whole
	/// filtered set (PostgREST's `Content-Range` total), or null when
	/// the page didn't ask for one.
	total: number | null;
}

export interface PagedRows<T> {
	rows: T[];
	/// The count that goes in `manifest.json`: the server's own total
	/// when it reported one, else the number of rows read (which is the
	/// true count exactly when `complete` is true).
	total: number;
	/// False whenever the rows may be short of `total` — a failed page,
	/// the ceiling, or a server total above what was read.
	complete: boolean;
}

/// Walk `fetchPage` in `pageSize` chunks until it returns a short page.
/// A null page means the fetch failed: the walk stops with what it has
/// and `complete` stays false, so the caller still ships the rows it
/// read without being able to claim they are all of them.
export async function fetchAllPages<T>(
	fetchPage: (offset: number, limit: number) => Promise<ExportPage<T> | null>,
	pageSize: number = EXPORT_PAGE_SIZE,
	ceiling: number = EXPORT_ROW_CEILING,
): Promise<PagedRows<T>> {
	const rows: T[] = [];
	let total: number | null = null;
	let complete = false;
	for (let offset = 0; offset < ceiling; offset += pageSize) {
		const want = Math.min(pageSize, ceiling - offset);
		const page = await fetchPage(offset, want);
		if (!page) break;
		if (page.total != null) total = page.total;
		for (const row of page.rows) rows.push(row);
		if (page.rows.length < want) {
			complete = true;
			break;
		}
	}
	if (total != null) return { rows, total, complete: rows.length >= total };
	return { rows, total: rows.length, complete };
}

/// Read the total out of a PostgREST `Content-Range` header
/// (`0-999/1212`). Returns null for the countless forms (`0-999/*`) and
/// for anything unparseable — an unknown total must never be mistaken
/// for a small one.
export function parseContentRangeTotal(header: string | null): number | null {
	if (!header) return null;
	const slash = header.lastIndexOf('/');
	if (slash < 0) return null;
	const tail = header.slice(slash + 1).trim();
	if (!/^\d+$/.test(tail)) return null;
	return Number(tail);
}
