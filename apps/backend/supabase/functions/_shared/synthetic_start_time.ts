/// Synthetic UTC start time for date-only imported results.
///
/// Several importers ingest a result that carries a calendar date but
/// no time-of-day or timezone — parkrun returns DD/MM/YYYY, and the
/// RunSignUp / ChronoTrack / UltraSignup race feeds carry a race date
/// with no start clock. `runs.started_at` is a `timestamptz`, so we
/// synthesise one by appending this suffix to the ISO (YYYY-MM-DD)
/// date. The choice of hour determines which timezones get the right
/// LOCAL calendar date when their dashboard / heatmap reads the run
/// back.
///
/// Persona-hunt finding Pro #5: T08:00:00Z was a UK-centric default.
/// At UTC-10 (Hawaii — parkrun has a Hawai'i event) and UTC-11
/// (American Samoa), 08:00 UTC wraps backward to the PREVIOUS local
/// calendar day. A Saturday result would land on Friday in the
/// runner's heatmap.
///
/// T10:00:00Z covers UTC-10 (Hawaii) through UTC+13 (New Zealand
/// NZDT) — the realistic worldwide audience. The remaining edge case
/// is Samoa (UTC+14 during DST), which crosses the dateline to land
/// one calendar day forward. That's a known acceptable trade — no
/// single UTC hour can satisfy every offset in the 26-hour worldwide
/// range simultaneously. Shared so parkrun-import and
/// race-results-import make the SAME choice for the SAME reason and
/// can't silently diverge; pinned by both importers' lib.test.ts.
export const SYNTHETIC_START_TIME_UTC = 'T10:00:00Z';
