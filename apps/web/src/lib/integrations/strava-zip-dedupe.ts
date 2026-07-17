/// Pure helper for the Strava ZIP importer — kept in its own file so
/// `npx tsx --test` can exercise it without dragging in the SvelteKit
/// `$env` chain that `strava-zip.ts` imports via supabase.ts.
///
/// Persona-hunt finding Intermediate #1: pre-fix the importer queried
/// only `source='strava'` + metadata.strava_id, so older rows from
/// before the strava_id tag was added — or rows that lost the
/// metadata key during a partial restore — slipped past the dedup
/// and re-imported as silent duplicates. The fix pulls IDs from BOTH
/// the canonical metadata.strava_id (set by every modern path) AND
/// the external_id column (`strava:<id>` set by every path including
/// the EF backfill + the mobile importer). Also drops the
/// `source='strava'` filter — a Strava activity re-saved by another
/// path still dedupes against its strava:<id> key.
import { RUN_IDENTITY_PAGE_SIZE, RUN_IDENTITY_SAFETY_MAX } from './garmin_dedupe';

export type StravaDedupeRow = { metadata?: unknown; external_id?: string | null };

export function buildStravaDedupeSet(rows: StravaDedupeRow[]): Set<string> {
	const seen = new Set<string>();
	for (const r of rows) {
		const sid = (r.metadata as Record<string, unknown> | null)?.strava_id;
		if (sid) seen.add(String(sid));
		const extId = r.external_id;
		if (extId && extId.startsWith('strava:')) {
			seen.add(extId.slice('strava:'.length));
		}
	}
	return seen;
}

/// Page the existing-runs read in `RUN_IDENTITY_PAGE_SIZE` chunks before
/// building the dedupe set. An unbounded PostgREST SELECT caps at 1000 rows,
/// so a 1000+-run migrant re-importing a refreshed ZIP would otherwise dedupe
/// against an arbitrary slice and silently re-import everything past the cap
/// as full duplicates. Mirrors `collectRunIdentities`; `fetchPage` returns the
/// rows for the inclusive `[from, to]` range, or `null` on error (stops, no
/// throw). Pure + injectable so `npx tsx --test` can exercise the paging.
export async function collectStravaDedupeSet(
	fetchPage: (from: number, to: number) => PromiseLike<StravaDedupeRow[] | null>,
	pageSize: number = RUN_IDENTITY_PAGE_SIZE,
	safetyMax: number = RUN_IDENTITY_SAFETY_MAX,
): Promise<Set<string>> {
	const seen = new Set<string>();
	for (let from = 0; from < safetyMax; from += pageSize) {
		const data = await fetchPage(from, from + pageSize - 1);
		if (!data) break;
		for (const k of buildStravaDedupeSet(data)) seen.add(k);
		if (data.length < pageSize) break;
	}
	return seen;
}
