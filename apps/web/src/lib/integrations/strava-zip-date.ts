// Pure date parsing for the Strava bulk-export `activities.csv` "Activity
// Date" column. Extracted from strava-zip.ts so it can be unit-tested without
// the JSZip / supabase import chain (same reason strava-zip-header.ts and
// strava-zip-classify.ts are standalone).
//
// The bug this fixes: Strava emits "Activity Date" as a UTC wall-clock string
// WITHOUT a zone designator, e.g. "Apr 15, 2026, 1:00:00 PM". Feeding that to
// `new Date(...)` reads it in the importer's LOCAL zone, shifting every
// imported run by the local offset — a midnight run lands on the wrong day,
// week, and heatmap cell. We parse the documented no-zone shape explicitly as
// UTC. An already-zoned / ISO value is left to the native parser untouched so
// we never corrupt a value that already carries an offset.
//
// NOTE: written against Strava's DOCUMENTED export format without a real
// export fixture on hand. A real Strava bulk export should validate the format
// string(s) below pre-prod (decisions_or_risks).

const MONTHS: Record<string, number> = {
	jan: 0,
	feb: 1,
	mar: 2,
	apr: 3,
	may: 4,
	jun: 5,
	jul: 6,
	aug: 7,
	sep: 8,
	oct: 9,
	nov: 10,
	dec: 11,
};

// "Apr 15, 2026, 1:00:00 PM" — month name, day, year, h:m:s, optional AM/PM.
// Commas after the day and year are optional; the month may be the long form
// (we slice the first 3 chars for the lookup).
const NO_ZONE_RE =
	/^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4}),?\s+(\d{1,2}):(\d{2}):(\d{2})\s*([AP]M)?$/i;

/// Parse a Strava CSV "Activity Date" cell into an ISO-8601 UTC instant.
///
/// - If the cell carries an explicit zone / is ISO-8601, defer to the native
///   `Date` parser (don't corrupt an already-zoned value).
/// - If it matches the documented no-zone shape, interpret the wall-clock
///   fields as UTC (Strava's documented semantics) via `Date.UTC`.
/// - Returns null when the input is empty or matches neither shape; the caller
///   decides how to handle an unparseable date.
export function parseStravaCsvDateToIso(raw: string | undefined | null): string | null {
	if (!raw) return null;
	const trimmed = raw.trim();
	if (!trimmed) return null;

	const m = NO_ZONE_RE.exec(trimmed);
	if (m) {
		const month = MONTHS[m[1].slice(0, 3).toLowerCase()];
		if (month === undefined) return fallbackParse(trimmed);
		const day = Number(m[2]);
		const year = Number(m[3]);
		let hour = Number(m[4]);
		const minute = Number(m[5]);
		const second = Number(m[6]);
		const ampm = m[7]?.toUpperCase();
		if (ampm === 'PM' && hour < 12) hour += 12;
		if (ampm === 'AM' && hour === 12) hour = 0;
		return new Date(Date.UTC(year, month, day, hour, minute, second)).toISOString();
	}

	return fallbackParse(trimmed);
}

function fallbackParse(s: string): string | null {
	const d = new Date(s);
	return Number.isNaN(d.getTime()) ? null : d.toISOString();
}
