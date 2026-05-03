/// `POST /export-data` — GDPR data portability.
///
/// Two formats:
///   - `csv`: single CSV with one summary row per run.
///   - `gpx`: zip with one per-run GPX file plus a top-level
///     `runs.json` summary mirroring the CSV column set.
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

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.105.1';
import {
	BlobWriter,
	TextReader,
	ZipWriter,
} from 'https://deno.land/x/zipjs@v2.7.45/index.js';
import { checkRateLimitTiered } from '../_shared/rate_limit.ts';
import { enforceBodyLimit } from '../_shared/body_limit.ts';
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

serve(withSentry('export-data', async (req: Request) => {
	if (req.method !== 'POST') {
		return new Response('Method not allowed', { status: 405 });
	}

	// Body is `{ format: 'csv' | 'gpx' }` — 1 KB is plenty.
	const tooBig = enforceBodyLimit(req, 1024);
	if (tooBig) return tooBig;

	const authHeader = req.headers.get('Authorization');
	if (!authHeader) return new Response('Unauthorized', { status: 401 });

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
	if (!user) return new Response('Unauthorized', { status: 401 });

	// Fail-closed: an export builds a multi-MB GPX zip per call.
	// Letting the throttle silently fall open on RPC error is a free
	// DoS vector against the function and the caller's Storage prefix.
	const denied = await checkRateLimitTiered(authedSupabase, user.id, 'export-data', 2, 8, 3600, {
		failClosed: true,
	});
	if (denied) return denied;

	const body = await req.json().catch(() => ({}));
	const format = (body.format ?? 'csv') as string;
	if (format !== 'csv' && format !== 'gpx') {
		return new Response('format must be "csv" or "gpx"', { status: 400 });
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
		console.error('export-data: runs select failed:', runsErr);
		return new Response('Run fetch failed', { status: 500 });
	}

	const ts = new Date().toISOString().replace(/[:.]/g, '-');
	const ext = format === 'gpx' ? 'zip' : 'csv';
	const path = `${user.id}/exports/${ts}.${ext}`;

	let body_: Uint8Array;
	let contentType: string;
	if (format === 'csv') {
		body_ = new TextEncoder().encode(buildCsv(runs ?? []));
		contentType = 'text/csv';
	} else {
		body_ = await buildGpxZip(adminSupabase, runs ?? []);
		contentType = 'application/zip';
	}

	const { error: upErr } = await adminSupabase.storage
		.from('runs')
		.upload(path, new Blob([body_], { type: contentType }), {
			contentType,
			upsert: false,
		});
	if (upErr) {
		console.error('export-data: storage upload failed:', upErr);
		return new Response('Upload failed', { status: 500 });
	}

	const { data: signed, error: signErr } = await adminSupabase.storage
		.from('runs')
		.createSignedUrl(path, SIGNED_URL_TTL_S);
	if (signErr || !signed) {
		console.error('export-data: createSignedUrl failed:', signErr);
		return new Response('Signed URL failed', { status: 500 });
	}

	return Response.json({
		url: signed.signedUrl,
		path,
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
		'track_url',
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
				csvEscape(r.track_url ?? ''),
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

async function decodeTrack(blob: Blob): Promise<TrackPoint[]> {
	// Tracks are gzipped JSON arrays. Storage's download() returns the
	// raw bytes; we gunzip in-process.
	const gz = new Uint8Array(await blob.arrayBuffer());
	const ds = new (globalThis as any).DecompressionStream('gzip');
	const stream = new Response(gz).body!.pipeThrough(ds);
	const txt = await new Response(stream).text();
	return JSON.parse(txt) as TrackPoint[];
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

