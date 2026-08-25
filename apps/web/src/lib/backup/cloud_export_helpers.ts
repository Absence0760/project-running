/// Pure URL + body shape helpers for the cloud-export flip. Lives in
/// its own module so unit tests can pin the wire shape without the
/// SvelteKit `$env` / `supabase-js` imports. Mirrors the layering in
/// `live_hub_helpers.ts`.
///
/// The legacy `export-data` Edge Function accepts
/// `{format: 'csv' | 'gpx' | 'backup'}` and returns
/// `{url, expires_in, count, total, complete, format}`. `count` is what
/// the archive carries, `total` what the database holds, and `complete`
/// whether the two agree — a runner past the per-export run ceiling gets
/// a short archive and has to be told so. `backup` is the comprehensive
/// GDPR Art. 20 archive (the `run-app-backup` zip bundling every
/// personal-data table that the mobile `backup_server_client.dart`
/// already requests); `csv` / `gpx` are the runs-only summaries. The
/// The Go service answers in the same vocabulary but never on one
/// request: it enqueues, and the status endpoint below reports. Its own
/// synchronous rail was deleted with decisions.md § 724, so this
/// response shape belongs to the Edge Function alone. The auth header
/// shape differs too — the EF picks up the bearer from supabase-js's
/// session automatically; the Go endpoints need an explicit
/// `Authorization: Bearer <jwt>` header. The helpers here just build
/// the absolute URLs so the call site doesn't have to reason about
/// trailing-slash normalisation.

export type CloudExportFormat = 'csv' | 'gpx' | 'backup';

export interface CloudExportResponse {
	url: string;
	expires_in: number;
	count: number;
	total?: number;
	complete?: boolean;
	format: CloudExportFormat;
}

export interface CloudExportShortfall {
	count: number;
	total: number;
}

/// What the UI must disclose about a finished export, or null when the
/// archive is whole. `complete` is the single flag to gate on — a
/// shortfall has two causes (the per-export run ceiling and a page that
/// failed to read) and the response distinguishes neither, so the copy
/// states the counts rather than a cause it can't know.
///
/// Only an explicit `complete: false` claims a shortfall: a response
/// without the field (an older deployment of either transport) is not
/// evidence of truncation, and warning on every export would be its own
/// dishonesty. `total` is floored at `count` so a malformed pair can
/// never render "12 of 3".
export function cloudExportShortfall(
	res:
		| CloudExportResponse
		| CloudExportJob
		| { count?: number; total?: number; complete?: boolean },
): CloudExportShortfall | null {
	if (res.complete !== false) return null;
	const num = (v: unknown): number | null =>
		typeof v === 'number' && Number.isFinite(v) ? v : null;
	const count = num(res.count) ?? 0;
	const total = num(res.total) ?? count;
	return { count, total: Math.max(total, count) };
}

/// ─────────────────── the queued rail (decisions.md § 717) ───────────────────
///
/// The Go service no longer builds the archive on the caller's own
/// connection: `POST /v1/export/jobs` enqueues and answers with a job id,
/// and `GET /v1/export/jobs/latest` reports the outcome and mints the
/// signed URL at that moment — so the 10-minute window starts when the
/// subject asks for it rather than when the worker happened to finish.
///
/// The legacy `export-data` Edge Function (the transport this module
/// falls back to when `PUBLIC_EXPORT_HUB_URL` is unset) is still
/// synchronous, so the two shapes below coexist by transport, not by
/// export size.

/// What the status endpoint can say. `none` is a subject who has never
/// asked; `stalled` is a row nothing has touched for longer than the
/// worker's whole retry budget, which is the server's way of saying the
/// worker building it is gone.
export type CloudExportJobStatus =
	| 'none'
	| 'queued'
	| 'running'
	| 'ready'
	| 'failed'
	| 'expired'
	| 'stalled';

export interface CloudExportJob {
	status: CloudExportJobStatus;
	job_id?: string;
	format?: CloudExportFormat;
	requested_at?: string;
	url?: string;
	expires_in?: number;
	count?: number;
	total?: number;
	complete?: boolean;
	error_code?: string;
}

const KNOWN_JOB_STATUSES: readonly string[] = [
	'none',
	'queued',
	'running',
	'ready',
	'failed',
	'expired',
	'stalled',
];

/// Normalise a status-endpoint body into a `CloudExportJob`.
///
/// Fail-closed in two directions, and both matter. A status this build
/// does not recognise becomes `failed` carrying the raw token: a client
/// that keeps polling a status it cannot interpret spins for ever, and
/// one that guesses `ready` offers a download it has no URL for. And a
/// `ready` job that arrived without a URL is not offerable either, so it
/// is reported as a failure rather than rendered as a dead button.
export function cloudExportJobFromResponse(raw: unknown): CloudExportJob {
	if (!raw || typeof raw !== 'object') {
		return { status: 'failed', error_code: 'unreadable_response' };
	}
	const body = raw as Record<string, unknown>;
	const status = typeof body.status === 'string' ? body.status : '';
	const num = (v: unknown): number | undefined =>
		typeof v === 'number' && Number.isFinite(v) ? v : undefined;
	const str = (v: unknown): string | undefined =>
		typeof v === 'string' && v !== '' ? v : undefined;

	if (!KNOWN_JOB_STATUSES.includes(status)) {
		return { status: 'failed', error_code: status || 'unknown_status' };
	}
	const job: CloudExportJob = {
		status: status as CloudExportJobStatus,
		job_id: str(body.job_id),
		format: str(body.format) as CloudExportFormat | undefined,
		requested_at: str(body.requested_at),
		url: str(body.url),
		expires_in: num(body.expires_in),
		count: num(body.count),
		total: num(body.total),
		complete: typeof body.complete === 'boolean' ? body.complete : undefined,
		error_code: str(body.error_code),
	};
	if (job.status === 'ready' && !job.url) {
		return { status: 'failed', error_code: 'no_url' };
	}
	return job;
}

/// True while the build is still in progress and the client should keep
/// asking. Every other status is terminal — including `none`, which is
/// what a subject who has never exported sees.
export function isCloudExportJobActive(status: CloudExportJobStatus): boolean {
	return status === 'queued' || status === 'running';
}

export const CLOUD_EXPORT_POLL_MIN_MS = 2_000;
export const CLOUD_EXPORT_POLL_MAX_MS = 15_000;

/// How long to wait before the next status read. Doubles every two
/// attempts up to a cap: a deep-history archive can take minutes, and a
/// fixed 2-second poll would spend hundreds of requests waiting for it,
/// while a fixed 15 would make the common small export feel slow.
export function cloudExportPollDelayMs(attempt: number): number {
	if (!Number.isFinite(attempt) || attempt < 0) return CLOUD_EXPORT_POLL_MIN_MS;
	const ms = CLOUD_EXPORT_POLL_MIN_MS * 2 ** Math.floor(attempt / 2);
	return Math.min(ms, CLOUD_EXPORT_POLL_MAX_MS);
}

/// Build the absolute URL of the queued rail's enqueue endpoint. Strips
/// trailing slashes on the base so a paste-in
/// `https://live.threkir.com/` still produces a single-slash join.
export function buildCloudExportJobsUrl(base: string): string {
	return `${base.replace(/\/+$/, '')}/v1/export/jobs`;
}

/// Build the absolute URL of the queued rail's status endpoint. It
/// answers for the subject's LATEST export rather than by id, so a page
/// that reloads mid-build needs no local state to find its way back.
export function buildCloudExportJobStatusUrl(base: string): string {
	return `${base.replace(/\/+$/, '')}/v1/export/jobs/latest`;
}

/// Build the JSON body the endpoint expects. Constant in shape today
/// but factored so a future option (e.g. since-date filter) can live
/// in one place instead of bleeding through every call site.
export function buildCloudExportBody(format: CloudExportFormat): string {
	return JSON.stringify({ format });
}
