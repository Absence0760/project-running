/// `POST /export-data` — GDPR data portability.
///
/// Three formats:
///   - `csv`: single CSV with one summary row per run.
///   - `gpx`: zip with one per-run GPX file plus a top-level
///     `runs.json` summary mirroring the CSV column set.
///   - `backup`: structured JSON zip that mirrors the Go worker's
///     `FetchExportPersonalDataTables` table set so the deprecated
///     EF rollback path is functionally equivalent to the primary.
///     Added per audit/data-export-completeness May 2026 High.
///
/// Output is uploaded to the `runs` Storage bucket under the caller's
/// user-id-prefixed path (`{user_id}/exports/<ts>.<ext>`) so the
/// existing path-based RLS still gates direct reads. The returned
/// URL is a signed URL with a 10-minute expiry — the user can
/// download once without re-authenticating.
///
/// Caps:
///   - 5000 runs per export. A serious power-user would still see
///     every run; a runaway loop on a corrupt account doesn't run
///     forever.
///   - 150s function timeout (Supabase platform default). For GPX,
///     the per-run track fetch is the dominant cost. With 5000 runs
///     and ~10 KB tracks the EF needs ~30 s — well inside the budget.
///
/// Rate limit: free 2/h, pro 8/h via `check_rate_limit_tiered`. Heavy
/// op (zip-and-ship of every run + track) so even Pro doesn't get
/// unlimited; the higher Pro ceiling accommodates "I'm migrating off
/// the platform / making backups for several reasons today" without
/// the half-hour wait.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import {
	BlobWriter,
	TextReader,
	ZipWriter,
} from 'https://deno.land/x/zipjs@v2.7.45/index.js';
import { checkRateLimitTiered } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';

const MAX_RUNS = 5000;
const SIGNED_URL_TTL_S = 600; // 10 minutes

type RunRow = {
	id: string;
	user_id: string;
	started_at: string;
	duration_s: number;
	distance_m: number;
	source: string;
	external_id: string | null;
	metadata: Record<string, unknown> | null;
	track_url: string | null;
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

Deno.serve(withSentry('export-data', async (req: Request) => {
	if (req.method !== 'POST') {
		return new Response('Method not allowed', { status: 405 });
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
		Deno.env.get('SUPABASE_ANON_KEY')!,
		{ global: { headers: { Authorization: authHeader } } },
	);
	const adminSupabase = createClient(
		Deno.env.get('SUPABASE_URL')!,
		Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
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
		return new Response('format must be "csv", "gpx", or "backup"', {
			status: 400,
		});
	}

	// Pull every run for the user. The authedSupabase client respects
	// RLS so `eq('user_id', user.id)` is belt-and-braces — but it also
	// keeps the query plan honest about which user owns the rows.
	const { data: runs, error: runsErr } = await authedSupabase
		.from('runs')
		.select(
			'id, user_id, started_at, duration_s, distance_m, source, external_id, metadata, track_url, is_public, event_id, route_id, created_at, updated_at',
		)
		.eq('user_id', user.id)
		.order('started_at', { ascending: false })
		.limit(MAX_RUNS);

	if (runsErr) {
		console.error('export-data: runs select failed:', runsErr?.message ?? String(runsErr));
		return new Response('Run fetch failed', { status: 500 });
	}

	const ts = new Date().toISOString().replace(/[:.]/g, '-');
	const ext = format === 'csv' ? 'csv' : 'zip';
	const path = `${user.id}/exports/${ts}.${ext}`;

	let body_: Uint8Array;
	let contentType: string;
	if (format === 'csv') {
		body_ = new TextEncoder().encode(buildCsv(runs ?? []));
		contentType = 'text/csv';
	} else if (format === 'gpx') {
		body_ = await buildGpxZip(adminSupabase, runs ?? []);
		contentType = 'application/zip';
	} else {
		body_ = await buildBackupZip(adminSupabase, user.id, runs ?? []);
		contentType = 'application/zip';
	}

	const { error: upErr } = await adminSupabase.storage
		.from('runs')
		.upload(path, new Blob([new Uint8Array(body_)], { type: contentType }), {
			contentType,
			upsert: false,
		});
	if (upErr) {
		console.error('export-data: storage upload failed:', upErr?.message ?? String(upErr));
		return new Response('Upload failed', { status: 500 });
	}

	const { data: signed, error: signErr } = await adminSupabase.storage
		.from('runs')
		.createSignedUrl(path, SIGNED_URL_TTL_S);
	if (signErr || !signed) {
		// Log message only — the full error object can carry storage
		// path / internal codes into the shared log aggregator.
		console.error('export-data: createSignedUrl failed:', signErr?.message);
		return new Response('Signed URL failed', { status: 500 });
	}

	// Don't echo the Storage `path` — clients only need the signed URL
	// + TTL to download. Returning the path leaked the
	// `{user_id}/exports/<ts>.{csv,zip}` shape into the JSON response,
	// where it could land in browser history / dev-tools / logs and
	// later be re-used (within owner-folder Storage SELECT) without
	// the time-bounded signed URL. /audit/all storage Low.
	return Response.json({
		url: signed.signedUrl,
		expires_in: SIGNED_URL_TTL_S,
		count: runs?.length ?? 0,
		format,
	});
}));

function buildCsv(runs: RunRow[]): string {
	// Field set kept stable across the GDPR export so a user-owned
	// pipeline can rely on the column shape. New metadata keys go in
	// the `metadata` column as JSON rather than expanding the header.
	const cols = [
		'id',
		'started_at',
		'distance_m',
		'duration_s',
		'source',
		'activity_type',
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

	const lines = [cols.join(',')];
	for (const r of runs) {
		const md = r.metadata ?? {};
		lines.push(
			[
				csvEscape(r.id),
				csvEscape(r.started_at),
				String(r.distance_m),
				String(r.duration_s),
				csvEscape(r.source),
				csvEscape((md.activity_type as string | undefined) ?? ''),
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
			].join(','),
		);
	}
	return lines.join('\n') + '\n';
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

async function buildGpxZip(
	supabase: ReturnType<typeof createClient>,
	runs: RunRow[],
): Promise<Uint8Array> {
	const blobWriter = new BlobWriter('application/zip');
	const zip = new ZipWriter(blobWriter);

	// Manifest first so a partial / corrupt zip still has it.
	await zip.add(
		'runs.json',
		new TextReader(
			JSON.stringify(
				runs.map((r) => ({
					id: r.id,
					started_at: r.started_at,
					distance_m: r.distance_m,
					duration_s: r.duration_s,
					source: r.source,
					external_id: r.external_id,
					metadata: r.metadata,
					is_public: r.is_public,
					event_id: r.event_id,
					route_id: r.route_id,
				})),
				null,
				2,
			),
		),
	);

	for (const r of runs) {
		// Skip tracks for runs that don't have one; they still appear in
		// the manifest, just without a per-run GPX. Saves the round-trip.
		if (!r.track_url) continue;

		// Path-shape assertion mirrors the one in clip-public-track. RLS
		// guarantees the user owns these rows, but a corrupt or legacy
		// row with a malformed track_url would otherwise feed an
		// unconstrained string into the service-role downloader. The
		// CHECK constraint in 20260621_001 means new writes always match
		// this shape; the assertion is the runtime backstop.
		const expectedTrackUrl = `${r.user_id}/${r.id}.json.gz`;
		if (r.track_url !== expectedTrackUrl) continue;

		let track: TrackPoint[] | null = null;
		try {
			const { data: blob } = await supabase.storage.from('runs').download(r.track_url);
			if (!blob) continue;
			track = await decodeTrack(blob);
		} catch (_) {
			continue;
		}
		if (!track || track.length < 2) continue;

		const gpx = buildGpx(r, track);
		await zip.add(`runs/${r.id}.gpx`, new TextReader(gpx));
	}

	await zip.close();
	const blob = await blobWriter.getData();
	const buf = await blob.arrayBuffer();
	return new Uint8Array(buf);
}

// decodeTrack now lives in ./decode_track.ts so it can be unit-tested
// in isolation (importing index.ts pulls in the entire handler +
// Deno.serve, which we can't easily type-check standalone).
import { decodeTrack as _decodeTrack } from './decode_track.ts';
async function decodeTrack(blob: Blob): Promise<TrackPoint[]> {
	return (await _decodeTrack(blob)) as TrackPoint[];
}

function buildGpx(run: RunRow, track: TrackPoint[]): string {
	// Minimal GPX 1.1 — track points only, no waypoints / routes. Loaders
	// (Strava, Garmin Connect, GPX viewers) handle this shape uniformly.
	const md = run.metadata ?? {};
	const title = (md.title as string | undefined) ?? `Run ${run.id}`;
	const escapedTitle = xmlEscape(title);
	const lines: string[] = [];
	lines.push('<?xml version="1.0" encoding="UTF-8"?>');
	lines.push(
		'<gpx version="1.1" creator="Runonward" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">',
	);
	lines.push(`  <metadata><name>${escapedTitle}</name><time>${run.started_at}</time></metadata>`);
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

// Backup format — mirrors the Go worker's FetchExportPersonalDataTables
// in `apps/job_worker/internal/supabase.go`. Same table set, same
// filter shapes, same column projections + redactions. When the
// audit's rollback-path equivalence question is asked, the answer is
// "yes — same shape, just slower because Deno isolates spin per
// request". See audit/data-export-completeness May 2026 High.
//
// Per-table failures are tolerated (logged + skipped) so a single
// missing migration doesn't strand the export. The runs.json + per-
// run track entries match the gpx export's manifest shape.
import { type BackupTableSpec, buildBackupSpecs, summariseJobsByKind } from './backup_spec.ts';

async function buildBackupZip(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	runs: RunRow[],
): Promise<Uint8Array> {
	const blobWriter = new BlobWriter('application/zip');
	const zip = new ZipWriter(blobWriter);

	const specs = buildBackupSpecs(userId);

	for (const spec of specs) {
		try {
			const rows = await fetchBackupTable(supabase, spec);
			if (!rows || rows.length === 0) continue;
			const projected = spec.redact ? rows.map(spec.redact) : rows;
			await zip.add(
				spec.entry,
				new TextReader(JSON.stringify(projected, null, 2)),
			);
		} catch (e) {
			console.error(
				`export-data backup: ${spec.entry} fetch failed:`,
				e instanceof Error ? e.message : String(e),
			);
			// Per-table tolerance — the rest of the export still ships.
		}
	}

	// jobs summary — count by kind. Audit's preferred shape over the
	// raw payload (which would leak internal retry state). Aggregation
	// helper lives in backup_spec.ts so it can be unit-tested.
	try {
		const { data: jobsRows } = await supabase
			.from('jobs')
			.select('kind')
			.filter('payload->>user_id', 'eq', userId);
		if (jobsRows && jobsRows.length > 0) {
			const summary = summariseJobsByKind(jobsRows as Array<{ kind: string }>);
			await zip.add('jobs_summary.json', new TextReader(JSON.stringify(summary, null, 2)));
		}
	} catch (e) {
		console.error(
			'export-data backup: jobs summary failed:',
			e instanceof Error ? e.message : String(e),
		);
	}

	// runs.json — same shape as the gpx-zip manifest.
	await zip.add(
		'runs.json',
		new TextReader(
			JSON.stringify(
				runs.map((r) => ({
					id: r.id,
					started_at: r.started_at,
					distance_m: r.distance_m,
					duration_s: r.duration_s,
					source: r.source,
					external_id: r.external_id,
					metadata: r.metadata,
					is_public: r.is_public,
					event_id: r.event_id,
					route_id: r.route_id,
				})),
				null,
				2,
			),
		),
	);

	// Per-run track bytes — same path-shape assertion + RLS guarantee
	// as buildGpxZip. Tracks ship as raw GPX (not gzipped JSON) so
	// the consumer can re-import without a custom decoder.
	for (const r of runs) {
		if (!r.track_url) continue;
		const expectedTrackUrl = `${r.user_id}/${r.id}.json.gz`;
		if (r.track_url !== expectedTrackUrl) continue;
		try {
			const { data: blob } = await supabase.storage.from('runs').download(r.track_url);
			if (!blob) continue;
			const track = (await _decodeTrack(blob)) as TrackPoint[];
			if (!track || track.length < 2) continue;
			await zip.add(`runs/${r.id}.gpx`, new TextReader(buildGpx(r, track)));
		} catch (_) {
			/* skip the run; manifest still lists it */
		}
	}

	await zip.close();
	const blob = await blobWriter.getData();
	const buf = await blob.arrayBuffer();
	return new Uint8Array(buf);
}

async function fetchBackupTable(
	supabase: ReturnType<typeof createClient>,
	spec: BackupTableSpec,
): Promise<Record<string, unknown>[]> {
	// Run a raw PostgREST query so the `target_kind=eq.user&target_id=eq.X`
	// filter (two params) works the same way the Go worker passes it.
	// Using `from(...).select(...)` doesn't natively combine arbitrary
	// `&`-joined filter strings, so go through the auth-bound client's
	// REST URL directly.
	const url =
		`${Deno.env.get('SUPABASE_URL')!}/rest/v1/${spec.table}?select=${encodeURIComponent(spec.select)}&${spec.filter}`;
	const r = await fetch(url, {
		headers: {
			apikey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
			Authorization: `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!}`,
			Accept: 'application/json',
		},
	});
	if (!r.ok) {
		throw new Error(`${spec.table} REST ${r.status}`);
	}
	return (await r.json()) as Record<string, unknown>[];
}

