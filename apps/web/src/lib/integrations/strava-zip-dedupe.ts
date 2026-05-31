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

export function buildStravaDedupeSet(
	rows: Array<{ metadata?: unknown; external_id?: string | null }>,
): Set<string> {
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
