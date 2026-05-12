/// Cloud-export call site. Asks the server to build a CSV or
/// GPX-zip of the user's full run history, upload it to Storage, and
/// return a 10-minute signed URL. The body is built server-side
/// (Go service or the legacy `export-data` Edge Function) so the
/// client doesn't have to hold the full dataset in memory — useful
/// for runners with thousands of runs where a browser-side ZIP would
/// blow the heap, and the only path that emits GPX-with-HR
/// extensions (the in-page CSV / JSON / Full-backup paths don't).
///
/// Transport flips on `PUBLIC_EXPORT_HUB_URL`:
///   * Set    → POST `{url}/v1/export` on the Go service (decisions
///              §53 — the production cutover target).
///   * Unset  → `supabase.functions.invoke('export-data', ...)` on
///              the legacy Edge Function. Same response shape, same
///              rate-limit RPC, same Storage path. Kept as the
///              fallback so unconfigured / preview builds work.
///
/// Both paths require an authenticated session (the Edge Function's
/// `verify_jwt = true` and the Go endpoint's `JWTAuthorizer` both
/// reject anon). Caller is expected to gate on `auth.user` before
/// invoking.

import { env } from '$env/dynamic/public';
import { supabase } from './supabase';
import {
	type CloudExportFormat,
	type CloudExportResponse,
	buildCloudExportBody,
	buildCloudExportUrl,
} from './cloud_export_helpers';

export type { CloudExportFormat, CloudExportResponse };

export function isCloudExportHubConfigured(): boolean {
	return (env.PUBLIC_EXPORT_HUB_URL ?? '') !== '';
}

/// Kicks off a server-side export and returns the signed-URL
/// response. Throws on auth / rate-limit / 5xx errors so the caller
/// can surface a toast.
export async function cloudExport(
	format: CloudExportFormat,
): Promise<CloudExportResponse> {
	const hubUrl = (env.PUBLIC_EXPORT_HUB_URL ?? '').trim();
	if (hubUrl) {
		// Go service path. Caller must be signed in — JWTAuthorizer
		// returns 401 on missing / invalid bearer.
		const { data: sessionData } = await supabase.auth.getSession();
		const token = sessionData.session?.access_token;
		if (!token) throw new Error('Not signed in');
		const res = await fetch(buildCloudExportUrl(hubUrl), {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				authorization: `Bearer ${token}`,
			},
			body: buildCloudExportBody(format),
		});
		if (res.status === 429) {
			const retryAfter = res.headers.get('retry-after');
			throw new Error(
				`Rate-limited — try again in ${retryAfter ?? '60'}s.`,
			);
		}
		if (!res.ok) {
			const body = await res.text().catch(() => '');
			throw new Error(`Export failed (${res.status}): ${body || 'no detail'}`);
		}
		return (await res.json()) as CloudExportResponse;
	}
	// Fallback: the legacy `export-data` Edge Function. Same body
	// shape, same response shape — supabase-js attaches the user's
	// bearer automatically.
	const { data, error } = await supabase.functions.invoke('export-data', {
		body: { format },
	});
	if (error) throw error;
	if (!data || typeof data !== 'object') {
		throw new Error('Export response was empty');
	}
	return data as CloudExportResponse;
}
