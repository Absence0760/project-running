/// Pure URL + body shape helpers for the cloud-export flip. Lives in
/// its own module so unit tests can pin the wire shape without the
/// SvelteKit `$env` / `supabase-js` imports. Mirrors the layering in
/// `live_hub_helpers.ts`.
///
/// The Go endpoint and the legacy `export-data` Edge Function both
/// accept `{format: 'csv' | 'gpx' | 'backup'}` and both return
/// `{url, expires_in, count, total, complete, format}`. `count` is what
/// the archive carries, `total` what the database holds, and `complete`
/// whether the two agree — a runner past the per-export run ceiling gets
/// a short archive and has to be told so. `backup` is the comprehensive
/// GDPR Art. 20 archive (the `run-app-backup` zip bundling every
/// personal-data table that the mobile `backup_server_client.dart`
/// already requests); `csv` / `gpx` are the runs-only summaries. The
/// only thing that differs is
/// the transport — `supabase.functions.invoke()` vs `fetch()` against
/// the Go base URL — and the auth header shape (the EF picks up the
/// bearer from supabase-js's session automatically; the Go endpoint
/// needs an explicit `Authorization: Bearer <jwt>` header). The
/// helper here just builds the absolute URL so the call site doesn't
/// have to reason about trailing-slash normalisation.

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
	res: CloudExportResponse,
): CloudExportShortfall | null {
	if (res.complete !== false) return null;
	const count = Number.isFinite(res.count) ? res.count : 0;
	const total = Number.isFinite(res.total) ? (res.total as number) : count;
	return { count, total: Math.max(total, count) };
}

/// Build the absolute URL of the Go service's `/v1/export` endpoint.
/// Strips a trailing slash on the base so a paste-in
/// `https://live.threkir.com/` still produces a single-slash join.
export function buildCloudExportUrl(base: string): string {
	return `${base.replace(/\/+$/, '')}/v1/export`;
}

/// Build the JSON body the endpoint expects. Constant in shape today
/// but factored so a future option (e.g. since-date filter) can live
/// in one place instead of bleeding through every call site.
export function buildCloudExportBody(format: CloudExportFormat): string {
	return JSON.stringify({ format });
}
