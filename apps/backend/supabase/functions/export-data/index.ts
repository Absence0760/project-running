/// `POST /export-data` — GDPR data portability.
///
/// Three formats:
///   - `csv`: single CSV with one summary row per run.
///   - `gpx`: zip with one per-run GPX file plus a top-level
///     `runs.json` summary mirroring the CSV column set.
///   - `backup`: run-app-backup v1 zip mirroring the Go worker's
///     `BuildBackupZip` archive layout (manifest.json + runs.json +
///     routes.json + profile.json + raw tracks/ + hr/ + photos/ +
///     the `FetchExportPersonalDataTables` table set) so the
///     deprecated EF rollback path is functionally equivalent to the
///     primary. Added per audit/data-export-completeness May 2026
///     High; brought to full layout parity per the 2026-07-02 High.
///
/// Output is streamed to the `exports` Storage bucket under the
/// caller's user-id-prefixed path (`{user_id}/exports/<ts>.<ext>`) so
/// the same path-based RLS gates direct reads. The returned URL is a
/// signed URL with a 10-minute expiry — the user can download once
/// without re-authenticating. Its own bucket because `file_size_limit`
/// is per bucket and `runs` caps an object at 25 MB, which was a far
/// tighter ceiling on a full-history archive than either cap below.
///
/// Nothing is assembled in memory. The archive goes out through the
/// chunked tus sink in `resumable_upload.ts` and each section is
/// serialised page by page (`stream_section.ts`), so peak memory is one
/// 6 MiB chunk plus the `EXPORT_FETCH_CONCURRENCY` blob window — flat in
/// the size of the subject's history. That is what removed the two caps
/// this function used to apologise for in `manifest.json`: a 5000-run
/// ceiling and 50,000 rows per section, both of which existed only to
/// keep one enormous Blob alive.
///
/// The bound that survives is real: the platform kills the request at
/// `EXPORT_FUNCTION_TIMEOUT_MS`, and for GPX and backup the per-run
/// Storage fetch dominates. So the builders run against an explicit
/// `ExportBudget`, stop opening new work when it is spent, and name what
/// they skipped in `manifest.json` (`complete` / `incomplete`) and in
/// the response's `complete`. The download sweeps still run
/// `EXPORT_FETCH_CONCURRENCY`-wide through `pooledPipeline` so the round
/// trips overlap. A deep history that cannot finish inside one request
/// belongs on the Go worker's queued rail (`POST /v1/export/jobs`),
/// which holds no connection at all.
///
/// Fail-closed: tus materialises the object only once the declared
/// length arrives, so any build failure aborts the upload and answers
/// 500 with no artifact at all. A truncated archive can never be
/// presented as a complete one.
///
/// Rate limit: free 2/h, pro 8/h via `check_rate_limit_tiered`. Heavy
/// op (zip-and-ship of every run + track) so even Pro doesn't get
/// unlimited; the higher Pro ceiling accommodates "I'm migrating off
/// the platform / making backups for several reasons today" without
/// the half-hour wait.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import {
	TextReader,
	Uint8ArrayReader,
	ZipWriter,
} from 'https://deno.land/x/zipjs@v2.7.45/index.js';
import { checkRateLimitTiered } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { publishableKey, secretKey, secretKeyHeaders } from '../_shared/api_keys.ts';
import { EXPORT_FETCH_CONCURRENCY, pooledPipeline } from './pooled.ts';
import { parseContentRangeTotal } from './paging.ts';
import { createExportBudget, type ExportBudget } from './export_budget.ts';
import {
	openJsonSection,
	type SectionPage,
	type SectionSummary,
	walkPages,
} from './stream_section.ts';
import {
	createResumableUpload,
	type ResumableUpload,
	resumableWritable,
} from './resumable_upload.ts';

const SIGNED_URL_TTL_S = 600; // 10 minutes

/// Export artifacts live in their own bucket because `file_size_limit`
/// is per bucket: `runs` caps an object at 25 MB (20260620_001), which
/// is right for one gzipped track and is a tighter ceiling on a
/// full-history archive than either cap this function used to carry.
/// Migration `20270602_001`, decisions §703.
const EXPORT_BUCKET = 'exports';

const RUNS_SELECT =
	'id, user_id, started_at, duration_s, distance_m, source, activity_type, is_dnf, external_id, metadata, track_url, hr_series_url, is_public, event_id, route_id, created_at, updated_at';

type RunRow = {
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

type TrackPoint = {
	lat: number;
	lng: number;
	ele?: number;
	ts?: string;
	bpm?: number;
};

/// A Storage object the archive still owes, kept instead of the whole
/// row so the object sweeps don't reintroduce a per-run memory cost.
type BlobRef = { id: string; key: string };

/// What a per-run GPX needs, and nothing else.
type GpxRef = { id: string; startedAt: string; title: string; key: string };

type PageFetcher<T> = (offset: number, limit: number) => Promise<SectionPage<T> | null>;

/// The runs read failed outright — no page came back at all. Distinct
/// from a short read: there is nothing to ship, so the caller answers
/// 500 rather than uploading an archive with no runs in it.
class RunFetchError extends Error {}

interface BuildResult {
	runs: SectionSummary;
	/// Sections that are systematically short (a failed page, or the
	/// wall clock). A single failed object download is tolerated by
	/// contract and does not land here.
	incomplete: string[];
}

Deno.serve(withSentry('export-data', async (req: Request) => {
	if (req.method !== 'POST') {
		return Response.json({ error: 'method_not_allowed' }, { status: 405 });
	}

	// Body is `{ format: 'csv' | 'gpx' }` — 1 KB is plenty.
	const guarded = await readJsonWithLimit<{ format?: unknown }>(req, 1024);
	if ('tooLarge' in guarded) return guarded.tooLarge;

	const authHeader = req.headers.get('Authorization');
	if (!authHeader) return Response.json({ error: 'unauthorized' }, { status: 401 });

	// Two clients: a JWT-bound one to identify the caller, and a
	// service-role one to bypass RLS for the export upload (which
	// writes to a path the user can't normally write to since they
	// don't own the export rows yet).
	const authedSupabase = createClient(
		Deno.env.get('SUPABASE_URL')!,
		publishableKey(),
		{ global: { headers: { Authorization: authHeader } } },
	);
	const adminSupabase = createClient(
		Deno.env.get('SUPABASE_URL')!,
		secretKey(),
	);

	const { data: userData } = await authedSupabase.auth.getUser();
	const user = userData.user;
	if (!user) return Response.json({ error: 'unauthorized' }, { status: 401 });

	// Fail-closed: an export builds a multi-MB GPX zip per call.
	// Letting the throttle silently fall open on RPC error is a free
	// DoS vector against the function and the caller's Storage prefix.
	const denied = await checkRateLimitTiered(authedSupabase, user.id, 'export-data', 2, 8, 3600, {
		failClosed: true,
	});
	if (denied) return denied;

	const body = (guarded.body ?? {}) as { format?: unknown };
	const format = (body.format ?? 'csv') as string;
	if (format !== 'csv' && format !== 'gpx' && format !== 'backup') {
		return Response.json(
			{ error: 'format must be "csv", "gpx", or "backup"' },
			{ status: 400 },
		);
	}

	// The authedSupabase client respects RLS so `eq('user_id', user.id)`
	// is belt-and-braces — but it also keeps the query plan honest about
	// which user owns the rows.
	//
	// Paged: a bare `.limit(n)` is clamped by PostgREST to `db-max-rows`
	// (1000), so every runner past their thousandth run silently received
	// a fraction of their history. `id` is the tiebreaker because two runs
	// can share a `started_at`, and offset paging under a non-total order
	// repeats one row and drops another.
	const runsPage: PageFetcher<RunRow> = async (offset, limit) => {
		const { data, error, count } = await authedSupabase
			.from('runs')
			.select(RUNS_SELECT, offset === 0 ? { count: 'exact' } : {})
			.eq('user_id', user.id)
			.order('started_at', { ascending: false })
			.order('id', { ascending: true })
			.range(offset, offset + limit - 1);
		if (error) {
			console.error('export-data: runs select failed:', error.message ?? String(error));
			return null;
		}
		return { rows: (data ?? []) as unknown as RunRow[], total: count ?? null };
	};

	const ts = new Date().toISOString().replace(/[:.]/g, '-');
	const ext = format === 'csv' ? 'csv' : 'zip';
	const path = `${user.id}/exports/${ts}.${ext}`;
	const contentType = format === 'csv' ? 'text/csv' : 'application/zip';

	const budget = createExportBudget();
	const upload = createResumableUpload({
		supabaseUrl: Deno.env.get('SUPABASE_URL')!,
		bucket: EXPORT_BUCKET,
		objectPath: path,
		contentType,
		headers: secretKeyHeaders(),
	});

	let built: BuildResult;
	try {
		if (format === 'csv') {
			built = await writeCsv(upload, runsPage, budget);
		} else if (format === 'gpx') {
			built = await writeGpxZip(upload, adminSupabase, runsPage, budget);
		} else {
			built = await writeBackupZip(upload, adminSupabase, user.id, runsPage, budget);
		}
	} catch (e) {
		// Abort the tus session so no object is left behind: an archive
		// that stopped half-way must not exist, let alone be signed.
		await upload.abort();
		if (e instanceof RunFetchError) {
			return Response.json({ error: 'run fetch failed' }, { status: 500 });
		}
		console.error(
			'export-data: archive build failed:',
			e instanceof Error ? e.message : String(e),
		);
		return Response.json({ error: 'export failed' }, { status: 500 });
	}

	const { data: signed, error: signErr } = await adminSupabase.storage
		.from(EXPORT_BUCKET)
		.createSignedUrl(path, SIGNED_URL_TTL_S);
	if (signErr || !signed) {
		// Log message only — the full error object can carry storage
		// path / internal codes into the shared log aggregator.
		console.error('export-data: createSignedUrl failed:', signErr?.message);
		return Response.json({ error: 'signed URL failed' }, { status: 500 });
	}

	// Don't echo the Storage `path` — clients only need the signed URL
	// + TTL to download. Returning the path leaked the
	// `{user_id}/exports/<ts>.{csv,zip}` shape into the JSON response,
	// where it could land in browser history / dev-tools / logs and
	// later be re-used (within owner-folder Storage SELECT) without
	// the time-bounded signed URL. /audit/all storage Low.
	// `count` is what the archive carries; `total` is what the database
	// holds and `complete` whether the two agree AND no section was cut
	// short. The backup format says the same thing in manifest.json, in
	// more detail.
	return Response.json({
		url: signed.signedUrl,
		expires_in: SIGNED_URL_TTL_S,
		count: built.runs.written,
		total: built.runs.total,
		complete: built.runs.complete && built.incomplete.length === 0,
		format,
	});
}));

// Field set kept stable across the GDPR export so a user-owned
// pipeline can rely on the column shape. New metadata keys go in
// the `metadata` column as JSON rather than expanding the header.
const CSV_COLS = [
	'id',
	'started_at',
	'distance_m',
	'duration_s',
	'source',
	'activity_type',
	'is_dnf',
	'title',
	'avg_bpm',
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

function csvRow(r: RunRow): string {
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

async function writeCsv(
	upload: ResumableUpload,
	runsPage: PageFetcher<RunRow>,
	budget: ExportBudget,
): Promise<BuildResult> {
	const enc = new TextEncoder();
	await upload.write(enc.encode(CSV_COLS.join(',') + '\n'));
	const runs = await walkPages<RunRow>(
		runsPage,
		async (r) => {
			await upload.write(enc.encode(csvRow(r) + '\n'));
		},
		{ budget, label: 'runs' },
	);
	if (runs.written === 0 && !runs.complete) throw new RunFetchError('runs read failed');
	await upload.finish();
	return { runs, incomplete: budget.deadlineSkipped() };
}

function csvEscape(v: string): string {
	// RFC 4180 minimal: wrap in quotes if the value contains comma,
	// quote, newline, or carriage return; escape interior quotes by
	// doubling.
	if (v === '') return '';
	if (/[",\n\r]/.test(v)) {
		return '"' + v.replace(/"/g, '""') + '"';
	}
	return v;
}

function stringy(v: unknown): string {
	if (v == null) return '';
	if (typeof v === 'string') return v;
	if (typeof v === 'number' || typeof v === 'boolean') return String(v);
	return JSON.stringify(v);
}

// Path-shape assertion mirroring the one in clip-public-track. RLS
// guarantees the user owns these rows, but a corrupt or legacy row with
// a malformed track_url would otherwise feed an unconstrained string
// into the service-role downloader. The CHECK constraint in
// 20260621_001 means new writes always match this shape; these are the
// runtime backstop.
function canonicalTrackUrl(r: RunRow): string | null {
	if (!r.track_url) return null;
	return r.track_url === `${r.user_id}/${r.id}.json.gz` ? r.track_url : null;
}

function canonicalHrUrl(r: RunRow): string | null {
	if (!r.hr_series_url) return null;
	return r.hr_series_url === `${r.user_id}/${r.id}.hr.json.gz` ? r.hr_series_url : null;
}

/// Wrap a pooled `load` so it stops fetching once the wall clock is
/// spent, and records that it did. Returning null is what the pipeline
/// already treats as "nothing to add".
function budgeted<T, R>(
	budget: ExportBudget,
	label: string,
	load: (item: T) => Promise<R | null>,
): (item: T) => Promise<R | null> {
	return (item) => {
		if (budget.expired()) {
			budget.noteSkipped(label);
			return Promise.resolve(null);
		}
		return load(item);
	};
}

async function writeGpxZip(
	upload: ResumableUpload,
	supabase: ReturnType<typeof createClient>,
	runsPage: PageFetcher<RunRow>,
	budget: ExportBudget,
): Promise<BuildResult> {
	const gpxRefs: GpxRef[] = [];
	const section = await openJsonSection<RunRow>(runsPage, {
		budget,
		label: 'runs',
		keep: (r) => {
			const key = canonicalTrackUrl(r);
			if (!key) return;
			gpxRefs.push({
				id: r.id,
				startedAt: r.started_at,
				title: ((r.metadata ?? {}).title as string | undefined) ?? `Run ${r.id}`,
				key,
			});
		},
		shape: (r) => ({
			id: r.id,
			started_at: r.started_at,
			distance_m: r.distance_m,
			duration_s: r.duration_s,
			source: r.source,
			activity_type: r.activity_type,
			is_dnf: r.is_dnf,
			external_id: r.external_id,
			metadata: r.metadata,
			is_public: r.is_public,
			event_id: r.event_id,
			route_id: r.route_id,
		}),
	});
	if (!section.opened && !section.summary.complete) {
		throw new RunFetchError('runs read failed');
	}

	const zip = new ZipWriter(resumableWritable(upload));
	// Manifest first so a partial / corrupt zip still has it.
	await zip.add('runs.json', section.opened ? section.body : new TextReader('[]\n'));

	// Runs without a track never entered `gpxRefs`, so no round trip is
	// spent on them; they still appear in runs.json.
	await pooledPipeline(
		gpxRefs,
		EXPORT_FETCH_CONCURRENCY,
		// The gzipped blob is what travels through the pool, not the
		// decoded points: a 5 MB track inflates to tens of MB of point
		// objects, and only one of those is alive at a time if the
		// decode happens on the single-threaded consume side.
		budgeted(budget, 'tracks', (r: GpxRef) => downloadBlob(supabase, 'runs', r.key)),
		async (r, blob) => {
			let track: TrackPoint[];
			try {
				track = await decodeTrack(blob);
			} catch (_) {
				return;
			}
			if (!track || track.length < 2) return;
			await zip.add(`runs/${r.id}.gpx`, new TextReader(buildGpx(r, track)));
		},
	);

	await zip.close();
	return { runs: section.summary, incomplete: budget.deadlineSkipped() };
}

async function downloadBlob(
	supabase: ReturnType<typeof createClient>,
	bucket: string,
	key: string,
): Promise<Blob | null> {
	try {
		const { data: blob } = await supabase.storage.from(bucket).download(key);
		return blob ?? null;
	} catch (_) {
		return null;
	}
}

async function downloadBytes(
	supabase: ReturnType<typeof createClient>,
	bucket: string,
	key: string,
): Promise<Uint8Array | null> {
	const blob = await downloadBlob(supabase, bucket, key);
	if (!blob) return null;
	try {
		const bytes = new Uint8Array(await blob.arrayBuffer());
		return bytes.length === 0 ? null : bytes;
	} catch (_) {
		return null;
	}
}

// decodeTrack now lives in ./decode_track.ts so it can be unit-tested
// in isolation (importing index.ts pulls in the entire handler +
// Deno.serve, which we can't easily type-check standalone).
import { decodeTrack as _decodeTrack } from './decode_track.ts';
async function decodeTrack(blob: Blob): Promise<TrackPoint[]> {
	return (await _decodeTrack(blob)) as TrackPoint[];
}

function buildGpx(run: GpxRef, track: TrackPoint[]): string {
	// Minimal GPX 1.1 — track points only, no waypoints / routes. Loaders
	// (Strava, Garmin Connect, GPX viewers) handle this shape uniformly.
	const escapedTitle = xmlEscape(run.title);
	const lines: string[] = [];
	lines.push('<?xml version="1.0" encoding="UTF-8"?>');
	lines.push(
		'<gpx version="1.1" creator="Runonward" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">',
	);
	lines.push(`  <metadata><name>${escapedTitle}</name><time>${run.startedAt}</time></metadata>`);
	lines.push('  <trk>');
	lines.push(`    <name>${escapedTitle}</name>`);
	lines.push('    <trkseg>');
	for (const p of track) {
		const eleTag = p.ele != null ? `<ele>${p.ele}</ele>` : '';
		const timeTag = p.ts ? `<time>${p.ts}</time>` : '';
		const hrExt = p.bpm
			? `<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>${p.bpm}</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>`
			: '';
		lines.push(
			`      <trkpt lat="${p.lat}" lon="${p.lng}">${eleTag}${timeTag}${hrExt}</trkpt>`,
		);
	}
	lines.push('    </trkseg>');
	lines.push('  </trk>');
	lines.push('</gpx>');
	return lines.join('\n') + '\n';
}

function xmlEscape(v: string): string {
	return v
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}

// Backup format — mirrors the Go worker's BuildBackupZip archive
// layout in `apps/job_worker/internal/dataexport/server.go`:
// `manifest.json` + `runs.json` + `routes.json` + `profile.json` +
// raw `tracks/<id>.json.gz` + `hr/<id>.hr.json.gz` + `photos/<name>`
// + one `.json` entry per personal-data table (same table set, same
// filter shapes, same projections + redactions, via backup_spec.ts).
// Byte-layout-compatible with the mobile / web restore paths, so the
// rollback EF produces the same archive a consumer of the Go path
// sees. audit/data-export-completeness 2026-07-02 High.
//
// Per-table failures are tolerated (logged + skipped) so a single
// missing migration doesn't strand the export.
import {
	avatarCandidatePaths,
	type BackupTableSpec,
	buildBackupManifest,
	buildBackupSpecs,
	isSafeStoragePath,
	orderForTable,
	orphanStorageEntries,
	PROFILE_SELECT,
	shapeExportRoute,
	stripProfileId,
	summariseJobsByKind,
} from './backup_spec.ts';

async function writeBackupZip(
	upload: ResumableUpload,
	supabase: ReturnType<typeof createClient>,
	userId: string,
	runsPage: PageFetcher<RunRow>,
	budget: ExportBudget,
): Promise<BuildResult> {
	const trackRefs: BlobRef[] = [];
	const hrRefs: BlobRef[] = [];
	const photoPaths: string[] = [];
	const gearIds: string[] = [];

	// Opened before the zip so a runs read that failed outright answers
	// 500 with nothing uploaded, rather than shipping an archive whose
	// runs.json is empty for a reason nobody can see.
	const runsSection = await openJsonSection<RunRow>(runsPage, {
		budget,
		label: 'runs',
		keep: (r) => {
			const track = canonicalTrackUrl(r);
			if (track) trackRefs.push({ id: r.id, key: track });
			const hr = canonicalHrUrl(r);
			if (hr) hrRefs.push({ id: r.id, key: hr });
		},
		// Same projection as the Go worker's backup (track_url +
		// hr_series_url + created_at/updated_at included; user_id
		// stripped for re-homeability).
		shape: (r) => ({
			id: r.id,
			started_at: r.started_at,
			duration_s: r.duration_s,
			distance_m: r.distance_m,
			source: r.source,
			activity_type: r.activity_type,
			is_dnf: r.is_dnf,
			external_id: r.external_id,
			metadata: r.metadata,
			track_url: r.track_url,
			hr_series_url: r.hr_series_url,
			is_public: r.is_public,
			event_id: r.event_id,
			route_id: r.route_id,
			created_at: r.created_at,
			updated_at: r.updated_at,
		}),
	});
	if (!runsSection.opened && !runsSection.summary.complete) {
		throw new RunFetchError('runs read failed');
	}

	const zip = new ZipWriter(resumableWritable(upload));
	const specs = buildBackupSpecs(userId);
	const counts: Record<string, number> = {};
	const incomplete: string[] = [];

	// The count published for a section is the database's own total, so a
	// short file reads as a shortfall instead of as the whole set. An
	// empty table stays absent from `counts` (the convention both export
	// paths share), but a section that FAILED short is recorded even at
	// zero rows — an absent key must not be readable as "the subject has
	// none of these".
	const note = (key: string, s: SectionSummary) => {
		const short = !s.complete || s.written < s.total;
		if (s.written > 0 || short) counts[key] = Math.max(s.total, s.written);
		if (short) incomplete.push(key);
	};

	// `load` opens each table (its first page, and the `count=exact`
	// query that goes with it) `EXPORT_FETCH_CONCURRENCY`-wide, because
	// that round trip is the dominant cost across 61 mostly-small
	// tables. `consume` drains the rest of a multi-page table on the
	// single zip stream, in input order.
	await pooledPipeline(
		specs,
		EXPORT_FETCH_CONCURRENCY,
		(spec) =>
			openJsonSection<Record<string, unknown>>(backupTablePage(spec), {
				budget,
				label: spec.entry.replace(/\.json$/, ''),
				shape: spec.redact,
				keep: keepFromSpec(spec, gearIds, photoPaths),
			}),
		async (spec, section) => {
			if (section.opened) await zip.add(spec.entry, section.body);
			note(spec.entry.replace(/\.json$/, ''), section.summary);
		},
	);

	// run_gear — two-step fetch mirroring the Go worker: PostgREST's
	// `in.()` takes a literal value list, not a subselect, so pull the
	// already-fetched gear ids and filter run_gear by that list.
	if (gearIds.length > 0) {
		const section = await openJsonSection<Record<string, unknown>>(
			backupTablePage({
				entry: 'run_gear.json',
				table: 'run_gear',
				filter: `gear_id=in.(${gearIds.join(',')})`,
				select: '*',
			}),
			{ budget, label: 'run_gear' },
		);
		if (section.opened) await zip.add('run_gear.json', section.body);
		note('run_gear', section.summary);
	}

	// jobs summary — count by kind. Audit's preferred shape over the
	// raw payload (which would leak internal retry state). Aggregation
	// helper lives in backup_spec.ts so it can be unit-tested.
	const jobKinds: Array<{ kind: string }> = [];
	const jobsSummary = await walkPages<{ kind: string }>(
		async (offset, limit) => {
			try {
				const { data, error, count } = await supabase
					.from('jobs')
					.select('kind', offset === 0 ? { count: 'exact' } : {})
					.filter('payload->>user_id', 'eq', userId)
					.order('id', { ascending: true })
					.range(offset, offset + limit - 1);
				if (error) {
					console.error('export-data backup: jobs summary failed:', error.message);
					return null;
				}
				return {
					rows: (data ?? []) as unknown as Array<{ kind: string }>,
					total: count ?? null,
				};
			} catch (e) {
				console.error(
					'export-data backup: jobs summary failed:',
					e instanceof Error ? e.message : String(e),
				);
				return null;
			}
		},
		(row) => {
			jobKinds.push(row);
		},
		{ budget, label: 'jobs_summary' },
	);
	if (jobKinds.length > 0) {
		const summary = summariseJobsByKind(jobKinds);
		await zip.add('jobs_summary.json', new TextReader(JSON.stringify(summary, null, 2)));
		// One row per kind, not one per job — but the aggregate is only
		// trustworthy if every job row was scanned.
		counts['jobs_summary'] = summary.length;
	}
	if (!jobsSummary.complete) incomplete.push('jobs_summary');

	// routes.json — the user's own created routes (geometry included),
	// shaped like the Go worker's ExportRoute projection.
	const routesSection = await openJsonSection<Record<string, unknown>>(
		async (offset, limit) => {
			const { data, error, count } = await supabase
				.from('routes')
				.select('*', offset === 0 ? { count: 'exact' } : {})
				.eq('user_id', userId)
				.order('id', { ascending: true })
				.range(offset, offset + limit - 1);
			if (error) {
				console.error('export-data backup: routes fetch failed:', error.message);
				return null;
			}
			return { rows: (data ?? []) as Record<string, unknown>[], total: count ?? null };
		},
		{ budget, label: 'routes', shape: shapeExportRoute },
	);
	if (!routesSection.opened && !routesSection.summary.complete) {
		throw new Error('routes fetch failed');
	}
	await zip.add(
		'routes.json',
		routesSection.opened ? routesSection.body : new TextReader('[]\n'),
	);

	// profile.json — user_profiles projection (incl. the subscription
	// columns) + user_settings.prefs, `id` stripped for re-homeability.
	// Fetch failures ship null/empty rather than stranding the export,
	// matching the Go handler's tolerance.
	let profile: Record<string, unknown> | null = null;
	try {
		const { data: profileRows, error: profileErr } = await supabase
			.from('user_profiles')
			.select(PROFILE_SELECT)
			.eq('id', userId)
			.limit(1);
		if (profileErr) throw new Error(profileErr.message);
		profile = ((profileRows ?? []) as Record<string, unknown>[])[0] ?? null;
	} catch (e) {
		console.error(
			'export-data backup: profile fetch failed; including null:',
			e instanceof Error ? e.message : String(e),
		);
	}
	let prefs: Record<string, unknown> = {};
	try {
		const { data: prefsRows, error: prefsErr } = await supabase
			.from('user_settings')
			.select('prefs')
			.eq('user_id', userId)
			.limit(1);
		if (prefsErr) throw new Error(prefsErr.message);
		const prefsRow = ((prefsRows ?? []) as Array<{ prefs: unknown }>)[0];
		if (prefsRow && prefsRow.prefs && typeof prefsRow.prefs === 'object') {
			prefs = prefsRow.prefs as Record<string, unknown>;
		}
	} catch (e) {
		console.error(
			'export-data backup: prefs fetch failed; including empty:',
			e instanceof Error ? e.message : String(e),
		);
	}
	await zip.add(
		'profile.json',
		new TextReader(
			JSON.stringify({ profile: stripProfileId(profile), settings_prefs: prefs }, null, 2),
		),
	);

	await zip.add(
		'runs.json',
		runsSection.opened ? runsSection.body : new TextReader('[]\n'),
	);

	// Per-run track bytes — raw gzipped `.json.gz`, archived verbatim
	// under `tracks/` (level 0: the source is already deflated) so the
	// restore paths can re-upload byte-for-byte. Same path-shape
	// assertion + RLS guarantee as writeGpxZip. The GPX rendering lives
	// in the `gpx` format; the backup format matches the Go layout.
	const archivedRunObjects = new Set<string>();
	const archivedPhotoObjects = new Set<string>();
	let tracksAdded = 0;
	await pooledPipeline(
		trackRefs,
		EXPORT_FETCH_CONCURRENCY,
		budgeted(budget, 'tracks', (r: BlobRef) => downloadBytes(supabase, 'runs', r.key)),
		async (r, bytes) => {
			await zip.add(`tracks/${r.id}.json.gz`, new Uint8ArrayReader(bytes), { level: 0 });
			archivedRunObjects.add(r.key);
			tracksAdded++;
		},
	);

	// HR sidecars (indoor/treadmill runs, decisions §116) — same
	// verbatim-bytes + path-shape-assertion shape as the tracks loop.
	let hrAdded = 0;
	await pooledPipeline(
		hrRefs,
		EXPORT_FETCH_CONCURRENCY,
		budgeted(budget, 'hr_series', (r: BlobRef) => downloadBytes(supabase, 'runs', r.key)),
		async (r, bytes) => {
			await zip.add(`hr/${r.id}.hr.json.gz`, new Uint8ArrayReader(bytes), { level: 0 });
			archivedRunObjects.add(r.key);
			hrAdded++;
		},
	);

	// Photos — the image bytes themselves under `photos/`, so the
	// Art 20 export carries the subject's run photos and not just the
	// run_photos.json metadata. Keyed off each fetched row's
	// storage_path; per-photo failures are tolerated.
	let photosAdded = 0;
	await pooledPipeline(
		photoPaths,
		EXPORT_FETCH_CONCURRENCY,
		budgeted(budget, 'photos', (sp: string) => downloadBytes(supabase, 'run-photos', sp)),
		async (sp, bytes) => {
			await zip.add(`photos/${sp.split('/').pop()!}`, new Uint8ArrayReader(bytes), { level: 0 });
			archivedPhotoObjects.add(sp);
			photosAdded++;
		},
	);

	// Avatar — the profile-picture bytes from the public `avatars`
	// bucket, so the Art 20 export carries the image itself and not
	// just the avatar_url on the profile row. Probes the enumerable
	// candidate paths; a miss on every path just means no avatar.
	let avatarsAdded = 0;
	await pooledPipeline(
		avatarCandidatePaths(userId),
		EXPORT_FETCH_CONCURRENCY,
		budgeted(budget, 'avatars', (p: string) => downloadBytes(supabase, 'avatars', p)),
		async (p, bytes) => {
			await zip.add(`avatar.${p.split('.').pop()}`, new Uint8ArrayReader(bytes), { level: 0 });
			avatarsAdded++;
		},
	);

	// Prefix-walk the user's folders in the runs + run-photos buckets so
	// every object under {userId}/ lands in the zip even without a DB
	// row — the row-driven loops above miss CAS-orphaned matched tracks,
	// legacy tracks whose run row is gone, and worker-generated photo
	// thumbnails. Deduped against the row-driven entries via
	// orphanStorageEntries; a per-bucket list failure is tolerated so the
	// row-driven export still ships. Mirrors the Go builder's walk.
	let orphansAdded = 0;
	for (const { bucket, archived } of [
		{ bucket: 'runs', archived: archivedRunObjects },
		{ bucket: 'run-photos', archived: archivedPhotoObjects },
	]) {
		try {
			const keys = await listAllObjects(supabase, bucket, userId);
			await pooledPipeline(
				orphanStorageEntries({ bucket, keys, userId, archived }),
				EXPORT_FETCH_CONCURRENCY,
				budgeted(budget, 'storage_orphans', ({ key }: { key: string }) =>
					downloadBytes(supabase, bucket, key)),
				async ({ entry }, bytes) => {
					await zip.add(entry, new Uint8ArrayReader(bytes), { level: 0 });
					orphansAdded++;
				},
			);
		} catch (e) {
			console.error(
				`export-data backup: ${bucket} orphan sweep failed:`,
				e instanceof Error ? e.message : String(e),
			);
		}
	}

	// manifest.json last so the counts reflect what actually made it in.
	// `runs` / `routes` carry the database's own total; the storage
	// sections carry what was archived, a per-object download failure
	// being tolerated by contract — but a section the wall clock cut off
	// is a systematic shortfall and is named in `incomplete`.
	note('runs', runsSection.summary);
	note('routes', routesSection.summary);
	counts['tracks'] = tracksAdded;
	counts['hr_series'] = hrAdded;
	counts['photos'] = photosAdded;
	counts['avatars'] = avatarsAdded;
	counts['storage_orphans'] = orphansAdded;
	const shortfall = [...new Set([...incomplete, ...budget.deadlineSkipped()])];
	await zip.add(
		'manifest.json',
		new TextReader(
			JSON.stringify(buildBackupManifest({ userId, counts, incomplete: shortfall }), null, 2),
		),
	);

	await zip.close();
	return { runs: runsSection.summary, incomplete: shortfall };
}

/// The two sections whose VALUES a later step needs: `gear` ids feed the
/// `run_gear` filter, `run_photos` storage paths feed the photo sweep.
/// Everything else is copied straight through and retained nowhere.
function keepFromSpec(
	spec: BackupTableSpec,
	gearIds: string[],
	photoPaths: string[],
): ((row: Record<string, unknown>) => void) | undefined {
	if (spec.entry === 'gear.json') {
		return (row) => {
			const id = row.id;
			if (typeof id === 'string' && id !== '') gearIds.push(id);
		};
	}
	if (spec.entry === 'run_photos.json') {
		return (row) => {
			const sp = row.storage_path;
			if (typeof sp === 'string' && isSafeStoragePath(sp)) photoPaths.push(sp);
		};
	}
	return undefined;
}

// listAllObjects walks a Storage bucket folder recursively, returning
// full object keys. The list API pages at `limit` and marks folders
// with a null id, so each folder is paged and null-id entries are
// descended into.
//
// The offset advances by the number of rows actually returned and the
// walk ends on an empty page, never on a short one: a server-side row
// cap below `pageSize` would otherwise make a stride-by-pageSize loop
// skip whole blocks of objects straight out of the export.
async function listAllObjects(
	supabase: ReturnType<typeof createClient>,
	bucket: string,
	folder: string,
): Promise<string[]> {
	const pageSize = 1000;
	const out: string[] = [];
	for (let offset = 0;;) {
		const { data, error } = await supabase.storage.from(bucket).list(folder, {
			limit: pageSize,
			offset,
			sortBy: { column: 'name', order: 'asc' },
		});
		if (error) throw new Error(error.message);
		const entries = (data ?? []) as Array<{ name: string; id: string | null }>;
		if (entries.length === 0) return out;
		for (const e of entries) {
			if (!e.name) continue;
			const full = `${folder}/${e.name}`;
			if (e.id == null) {
				out.push(...(await listAllObjects(supabase, bucket, full)));
			} else {
				out.push(full);
			}
		}
		offset += entries.length;
	}
}

function backupTablePage(spec: BackupTableSpec): PageFetcher<Record<string, unknown>> {
	// Run a raw PostgREST query so the `target_kind=eq.user&target_id=eq.X`
	// filter (two params) works the same way the Go worker passes it.
	// Using `from(...).select(...)` doesn't natively combine arbitrary
	// `&`-joined filter strings, so go through the auth-bound client's
	// REST URL directly.
	//
	// `order` is the table's primary key (see orderForTable) — offset
	// paging needs a total order or two pages can repeat one row and drop
	// another. Only the first page asks for `count=exact`, so the
	// authoritative total costs one COUNT per table rather than one per
	// page.
	const order = orderForTable(spec.table);
	return async (offset: number, limit: number) => {
		const url = `${Deno.env.get('SUPABASE_URL')!}/rest/v1/${spec.table}` +
			`?select=${encodeURIComponent(spec.select)}&order=${order}` +
			`&limit=${limit}&offset=${offset}&${spec.filter}`;
		try {
			const r = await fetch(url, {
				headers: {
					...secretKeyHeaders(),
					Accept: 'application/json',
					...(offset === 0 ? { Prefer: 'count=exact' } : {}),
				},
			});
			if (!r.ok) {
				console.error(`export-data backup: ${spec.entry} REST ${r.status}`);
				return null;
			}
			return {
				rows: (await r.json()) as Record<string, unknown>[],
				total: parseContentRangeTotal(r.headers.get('content-range')),
			};
		} catch (e) {
			console.error(
				`export-data backup: ${spec.entry} fetch failed:`,
				e instanceof Error ? e.message : String(e),
			);
			return null;
		}
	};
}
