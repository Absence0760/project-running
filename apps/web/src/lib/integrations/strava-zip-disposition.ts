/// What to do with a csv row, decided before any I/O.
///  - `import`      — a run/walk/hike we haven't seen before
///  - `duplicate`   — already present on the user's runs (safe to skip)
///  - `unsupported` — a Ride/Swim/Yoga/etc. the app can't hold; DROPPED,
///                    never imported (must not be conflated with a
///                    duplicate in the summary shown to the user)
/// Unsupported is checked before duplicate to match the importer loop's
/// ordering: a row we can't import is unsupported even if its id recurs.

export type RowDisposition = 'import' | 'duplicate' | 'unsupported';

export function classifyStravaRow(
	actType: string,
	stravaId: string,
	seen: Set<string>,
): RowDisposition {
	const t = (actType ?? '').toLowerCase();
	if (t && !t.includes('run') && !t.includes('walk') && !t.includes('hike')) return 'unsupported';
	if (stravaId && seen.has(stravaId)) return 'duplicate';
	return 'import';
}
