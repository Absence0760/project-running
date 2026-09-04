/// The Art 20 export's two text renderers, plus the two Storage-path
/// assertions that gate the service-role downloader.
///
/// They lived inside `index.ts`, which cannot be imported by a test —
/// importing it runs `Deno.serve` — so every claim about them was a source
/// grep proving a call site's TEXT survived. `decode_track.ts` was split out
/// for exactly this reason and says so; this is the same split for the
/// renderers. Keep the file pure: no `Deno.env`, no `createClient`, no
/// `fetch`.
///
/// Twin: `csvColumns` / `csvRow` / `buildGpxDoc` / `xmlEscape` in the Go
/// worker's `apps/job_worker/internal/dataexport/server.go`. The Go side
/// decodes a track into typed fields, so a non-numeric coordinate never
/// reaches its renderer; here the track is `JSON.parse` of a blob the subject
/// uploaded, and nothing between the two has a schema.
///
/// Both transports are live and a runner reaches whichever one their build's
/// `PUBLIC_EXPORT_HUB_URL` selects, so the two column lists must agree. The Go
/// half of the `hr_coverage` column of § 1134 is filed, not written — that
/// tree belonged to no lane in the round that added it.

export type RenderRunRow = {
	id: string;
	user_id: string;
	started_at: string;
	duration_s: number;
	distance_m: number;
	source: string;
	activity_type: string;
	is_dnf: boolean;
	external_id: string | null;
	metadata: Record<string, unknown> | null;
	track_url: string | null;
	hr_series_url: string | null;
	is_public: boolean | null;
	event_id: string | null;
	route_id: string | null;
	created_at: string;
	updated_at: string;
};

export type RenderTrackPoint = {
	lat: number;
	lng: number;
	ele?: number;
	ts?: string;
	bpm?: number;
};

/// What a per-run GPX needs, and nothing else.
export type GpxRef = { id: string; startedAt: string; title: string; key: string };

/// Field set kept stable across the GDPR export so a user-owned
/// pipeline can rely on the column shape. New metadata keys go in
/// the `metadata` column as JSON rather than expanding the header —
/// the one thing that earns a column of its own is a key without
/// which a column ALREADY here cannot be read, because then the
/// header's stability is buying a consumer a number it will
/// misinterpret. `hr_coverage` is that case for `avg_bpm`
/// (decisions § 1134), and it sits beside the column it qualifies
/// rather than at the end, where a reader would have to know to
/// look for it.
export const CSV_COLS = [
	'id',
	'started_at',
	'distance_m',
	'duration_s',
	'source',
	'activity_type',
	'is_dnf',
	'title',
	'avg_bpm',
	'hr_coverage',
	'steps',
	'elevation_m',
	'route_id',
	'event_id',
	'external_id',
	'is_public',
	// `track_url` deliberately omitted: the GPX export already
	// includes the actual track bytes per run; the CSV consumer
	// needs the run shape, not the Storage path. Removing it
	// closes a leak path where the CSV (which the user might
	// share or store off-device) carries the raw owner-folder
	// Storage path that bypasses the clip-public-track EF for any
	// active session JWT. /audit/all storage Low.
	'metadata',
	'created_at',
	'updated_at',
];

export function csvEscape(v: string): string {
	// RFC 4180 minimal: wrap in quotes if the value contains comma,
	// quote, newline, or carriage return; escape interior quotes by
	// doubling.
	if (v === '') return '';
	if (/[",\n\r]/.test(v)) {
		return '"' + v.replace(/"/g, '""') + '"';
	}
	return v;
}

export function stringy(v: unknown): string {
	if (v == null) return '';
	if (typeof v === 'string') return v;
	if (typeof v === 'number' || typeof v === 'boolean') return String(v);
	return JSON.stringify(v);
}

/// `metadata.hr_coverage` as the export may state it, or `''` when the
/// stored value is not one this build can vouch for.
///
/// The column exists because the `avg_bpm` beside it is a QUALIFIED number.
/// The Wear recorder measures the share of ACTIVE elapsed time its sensor
/// delivered and SUPPRESSES the average below 0.5, because a mean over less
/// of the run than not is not the run's average (decisions § 1083). So a bare
/// `avg_bpm` cell states a mean over an unstated share of the run, and an
/// EMPTY one is either a suppressed average or a run recorded with no strap
/// at all. Run detail resolves those three states (§ 1088); an export that
/// contradicts the page is its own defect.
///
/// Graded rather than passed straight through, for the reason § 1088 gives
/// for the page: the writer's contract is a FRACTION, and a writer storing a
/// percentage would put `85` in a column whose consumer reads it as 8500 %.
/// The stored value survives verbatim in the `metadata` column either way, so
/// grading withholds nothing from the subject — it keeps this column to what
/// its header promises.
export function hrCoverageCell(v: unknown): string {
	if (typeof v !== 'number' || !Number.isFinite(v)) return '';
	if (v < 0 || v > 1) return '';
	// `0` is a measurement, not an absence: the sensor was enabled and
	// delivered nothing. It must not render as the empty cell an unmeasured
	// run gets.
	return String(v);
}

export function csvRow(r: RenderRunRow): string {
	const md = r.metadata ?? {};
	return [
		csvEscape(r.id),
		csvEscape(r.started_at),
		String(r.distance_m),
		String(r.duration_s),
		csvEscape(r.source),
		// activity_type + is_dnf are real columns now (F3).
		csvEscape(r.activity_type ?? ''),
		csvEscape(String(r.is_dnf ?? false)),
		csvEscape((md.title as string | undefined) ?? ''),
		csvEscape(stringy(md.avg_bpm)),
		csvEscape(hrCoverageCell(md.hr_coverage)),
		csvEscape(stringy(md.steps)),
		csvEscape(stringy(md.elevation_m)),
		csvEscape(r.route_id ?? ''),
		csvEscape(r.event_id ?? ''),
		csvEscape(r.external_id ?? ''),
		csvEscape(String(r.is_public ?? false)),
		csvEscape(JSON.stringify(md)),
		csvEscape(r.created_at),
		csvEscape(r.updated_at),
	].join(',');
}

export function xmlEscape(v: string): string {
	return v
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}

/// A coordinate / elevation as GPX may carry it, or null when the stored
/// value is not a number at all.
///
/// `lat` and `lng` land inside a QUOTED ATTRIBUTE, so a string value closes
/// the attribute and everything after it is markup — and the track is
/// `JSON.parse` of a blob, so its fields carry whatever type the writer put
/// there. The Go twin gets this for free: its decode types the field as
/// `float64` and a non-numeric point never reaches the renderer.
function gpxNumber(v: unknown): string | null {
	return typeof v === 'number' && Number.isFinite(v) ? String(v) : null;
}

export function buildGpx(run: GpxRef, track: readonly RenderTrackPoint[]): string {
	// Minimal GPX 1.1 — track points only, no waypoints / routes. Loaders
	// (Strava, Garmin Connect, GPX viewers) handle this shape uniformly.
	const escapedTitle = xmlEscape(run.title);
	const lines: string[] = [];
	lines.push('<?xml version="1.0" encoding="UTF-8"?>');
	lines.push(
		'<gpx version="1.1" creator="Runonward" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">',
	);
	lines.push(
		`  <metadata><name>${escapedTitle}</name><time>${xmlEscape(run.startedAt)}</time></metadata>`,
	);
	lines.push('  <trk>');
	lines.push(`    <name>${escapedTitle}</name>`);
	lines.push('    <trkseg>');
	for (const p of track) {
		const lat = gpxNumber(p.lat);
		const lng = gpxNumber(p.lng);
		// A point we cannot place is dropped rather than written: an
		// unplaceable trkpt is worth less than the rest of the file, and
		// emitting it would put an unescaped value inside an attribute.
		if (lat === null || lng === null) continue;
		const ele = gpxNumber(p.ele);
		const eleTag = ele !== null ? `<ele>${ele}</ele>` : '';
		const timeTag = p.ts ? `<time>${xmlEscape(String(p.ts))}</time>` : '';
		const bpm = gpxNumber(p.bpm);
		const hrExt = bpm !== null && Number(bpm) !== 0
			? `<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>${
				Math.trunc(Number(bpm))
			}</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>`
			: '';
		lines.push(
			`      <trkpt lat="${lat}" lon="${lng}">${eleTag}${timeTag}${hrExt}</trkpt>`,
		);
	}
	lines.push('    </trkseg>');
	lines.push('  </trk>');
	lines.push('</gpx>');
	return lines.join('\n') + '\n';
}

// Path-shape assertion mirroring the one in clip-public-track. RLS
// guarantees the user owns these rows, but a corrupt or legacy row with
// a malformed track_url would otherwise feed an unconstrained string
// into the service-role downloader. The CHECK constraint in
// 20260621_001 means new writes always match this shape; these are the
// runtime backstop.
export function canonicalTrackUrl(r: RenderRunRow): string | null {
	if (!r.track_url) return null;
	return r.track_url === `${r.user_id}/${r.id}.json.gz` ? r.track_url : null;
}

export function canonicalHrUrl(r: RenderRunRow): string | null {
	if (!r.hr_series_url) return null;
	return r.hr_series_url === `${r.user_id}/${r.id}.hr.json.gz` ? r.hr_series_url : null;
}
