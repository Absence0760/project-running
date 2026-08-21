/// Paging constants for the Art 20 export's PostgREST reads.
///
/// PostgREST clamps every response to `db-max-rows` (1000 on Supabase)
/// and signals the truncation nowhere in the body: an unbounded SELECT
/// returns the first 1000 rows, and an explicit `limit=5000` is clamped
/// to the same 1000. A runner with more than one page of runs, photos,
/// food-log rows or gym sets therefore received a silently short export
/// whose manifest asserted it was whole.
///
/// The walk itself lives in `stream_section.ts`, which serialises each
/// page into the archive and drops it. There is deliberately **no
/// per-section row ceiling** on this path any more: the ceiling existed
/// only because the whole archive was assembled in memory first, and a
/// bound that exists to keep an allocation alive is a subject not
/// receiving their data. The surviving bound is the function's wall
/// clock (`export_budget.ts`).

/// Page size. Matched to PostgREST's `db-max-rows` so a full page is
/// also the server's cap; asking for more per request buys nothing.
export const EXPORT_PAGE_SIZE = 1000;

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
