/// Pure URL + body shape helpers for the cloud-export flip. Lives in
/// its own module so unit tests can pin the wire shape without the
/// SvelteKit `$env` / `supabase-js` imports. Mirrors the layering in
/// `live_hub_helpers.ts`.
///
/// The Go endpoint and the legacy `export-data` Edge Function both
/// accept `{format: 'csv' | 'gpx'}` and both return
/// `{url, expires_in, count, format}`. The only thing that differs is
/// the transport — `supabase.functions.invoke()` vs `fetch()` against
/// the Go base URL — and the auth header shape (the EF picks up the
/// bearer from supabase-js's session automatically; the Go endpoint
/// needs an explicit `Authorization: Bearer <jwt>` header). The
/// helper here just builds the absolute URL so the call site doesn't
/// have to reason about trailing-slash normalisation.

export type CloudExportFormat = 'csv' | 'gpx';

export interface CloudExportResponse {
	url: string;
	expires_in: number;
	count: number;
	format: CloudExportFormat;
}

/// Build the absolute URL of the Go service's `/v1/export` endpoint.
/// Strips a trailing slash on the base so a paste-in
/// `https://live.runonward.com/` still produces a single-slash join.
export function buildCloudExportUrl(base: string): string {
	return `${base.replace(/\/+$/, '')}/v1/export`;
}

/// Build the JSON body the endpoint expects. Constant in shape today
/// but factored so a future option (e.g. since-date filter) can live
/// in one place instead of bleeding through every call site.
export function buildCloudExportBody(format: CloudExportFormat): string {
	return JSON.stringify({ format });
}
