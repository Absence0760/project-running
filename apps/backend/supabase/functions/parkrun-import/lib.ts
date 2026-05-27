// Pure helpers for the parkrun scraper.
//
// Includes both the audit/edge-functions input-cap helpers (below)
// and the date / time parsers extracted from index.ts so unit tests
// can exercise them without importing the EF module (whose top-level
// `serve(...)` binds a port at module-load time).

/// Parkrun returns its result date as DD/MM/YYYY with no time-of-day
/// or timezone. We need a UTC timestamp for the runs row, so we
/// synthesise one. The choice of hour determines which timezones get
/// the right local date when their dashboard / heatmap reads back.
///
/// Persona-hunt finding Pro #5: T08:00:00Z was a UK-centric default.
/// At UTC-10 (Hawaii — parkrun has a Hawai'i event) and UTC-11
/// (American Samoa), 08:00 UTC wraps backward to the PREVIOUS local
/// calendar day. A Saturday parkrun would land on Friday in the
/// runner's heatmap.
///
/// T10:00:00Z covers UTC-10 (Hawaii) through UTC+13 (New Zealand
/// NZDT) — the realistic worldwide parkrun audience. The remaining
/// edge case is Samoa (UTC+14 during DST), which crosses the
/// dateline to land on Sunday locally. That's a known acceptable
/// trade — no single UTC hour can satisfy every offset in the
/// 26-hour worldwide range simultaneously. Pinned by lib.test.ts.
export function parseParkrunDate(d: string): string {
	const [dd, mm, yyyy] = d.split('/');
	return `${yyyy}-${mm}-${dd}T10:00:00Z`;
}

export function parseParkrunTime(time: string): number {
	const parts = time.split(':').map(Number);
	if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
	if (parts.length === 2) return parts[0] * 60 + parts[1];
	return 0;
}

// ──────────────────────────────────────────────────────────────────
// Input-cap helpers for the parkrun scraper.
//
// audit/edge-functions (May 2026) flagged the importer's unbounded
// inputs: a hostile or mis-served parkrun page can return arbitrary
// HTML, and the scraper writes every scraped string into the runs
// table (most notably `external_id` and `metadata.event`). Without
// caps a single import call can write multi-MB rows + exhaust EF
// memory parsing the HTML.
//
// The caps below are generous against real parkrun pages (~50 KB of
// HTML, 8-char event names, low-thousand-event history for the most
// prolific parkrunners) while bounding the worst case to numbers
// that survive Edge Function memory limits.

export const MAX_PARKRUN_HTML_BYTES = 2 * 1024 * 1024; // 2 MB
export const MAX_PARKRUN_FIELD_LEN = 200;
export const MAX_PARKRUN_ROWS = 5000;

/**
 * Trim + truncate a scraped text field. Empty strings stay empty;
 * non-string inputs become empty (the scraper relies on jQuery-style
 * `.text()` which returns string, but defence in depth).
 */
export function capParkrunField(
	raw: unknown,
	max: number = MAX_PARKRUN_FIELD_LEN,
): string {
	if (typeof raw !== 'string') return '';
	const trimmed = raw.trim();
	if (trimmed.length <= max) return trimmed;
	return trimmed.slice(0, max);
}

/**
 * Read a `Response` body as text, but bail with `null` if the byte
 * count exceeds `max`. Streams the body so we don't allocate beyond
 * the cap. Used to bound the parkrun HTML page before Cheerio sees
 * it.
 */
export async function readBodyTextWithCap(
	res: Response,
	max: number = MAX_PARKRUN_HTML_BYTES,
): Promise<{ ok: true; text: string } | { ok: false; reason: 'too_large' }> {
	const cl = res.headers.get('content-length');
	if (cl && Number(cl) > max) {
		// Consume to release the connection back to the pool.
		try {
			await res.body?.cancel();
		} catch {
			/* swallow */
		}
		return { ok: false, reason: 'too_large' };
	}
	const reader = res.body?.getReader();
	if (!reader) {
		return { ok: true, text: await res.text() };
	}
	const chunks: Uint8Array[] = [];
	let total = 0;
	while (true) {
		const { done, value } = await reader.read();
		if (done) break;
		total += value.byteLength;
		if (total > max) {
			try {
				await reader.cancel();
			} catch {
				/* swallow */
			}
			return { ok: false, reason: 'too_large' };
		}
		chunks.push(value);
	}
	const buf = new Uint8Array(total);
	let off = 0;
	for (const c of chunks) {
		buf.set(c, off);
		off += c.byteLength;
	}
	return { ok: true, text: new TextDecoder('utf-8').decode(buf) };
}
