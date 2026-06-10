/// Pure dedupe-key helper for the Garmin bulk importer, split out of
/// `garmin-zip.ts` so it can be unit-tested without pulling in that
/// module's Svelte / Supabase dependency graph.

/// Canonical dedupe key for the `started_at + distance` fallback path.
/// The three sources that feed the importer's `seenComposite` set format
/// these fields differently — the DB serialises `started_at` as a
/// timestamptz (`2026-01-01T09:00:00+00:00`) while parsed imports carry a
/// `Z`-suffixed ISO string, and distances arrive as floats from the DB
/// but rounded ints from the GPX/TCX path. Left un-normalised the same
/// logical run never matched itself across a re-import, so every GPX/TCX
/// re-import duplicated. Normalise both (parse → toISOString, round
/// metres) so all three paths produce the same key.
export function compositeKey(startedAt: string, distanceM: number | null | undefined): string {
	const parsed = Date.parse(startedAt);
	const ts = Number.isFinite(parsed) ? new Date(parsed).toISOString() : startedAt;
	return `${ts}|${Math.round(distanceM ?? 0)}`;
}
