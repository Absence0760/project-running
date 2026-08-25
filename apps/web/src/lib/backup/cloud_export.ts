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
///   * Set    → the Go service's QUEUED rail (decisions §53, §717):
///              `POST {url}/v1/export/jobs` enqueues and answers with a
///              job id, `GET {url}/v1/export/jobs/latest` reports the
///              outcome and mints the signed URL at read time. Nothing
///              holds the connection open for the build, so a closed
///              tab or a client timeout can no longer end an export.
///   * Unset  → `supabase.functions.invoke('export-data', ...)` on
///              the legacy Edge Function, which still builds inline.
///              Same rate-limit RPC, same Storage path. Kept as the
///              fallback so unconfigured / preview builds work.
///
/// Both paths require an authenticated session (the Edge Function's
/// `verify_jwt = true` and the Go endpoint's `JWTAuthorizer` both
/// reject anon). Caller is expected to gate on `auth.user` before
/// invoking.

import { env } from '$env/dynamic/public';
import { supabase } from '../core/supabase';
import {
	type CloudExportFormat,
	type CloudExportJob,
	type CloudExportResponse,
	buildCloudExportBody,
	buildCloudExportJobStatusUrl,
	buildCloudExportJobsUrl,
	buildCloudExportUrl,
	cloudExportJobFromResponse,
} from './cloud_export_helpers';

export type { CloudExportFormat, CloudExportJob, CloudExportResponse };

/// What asking for an export got us. The queued rail answers with a job
/// to watch; the legacy Edge Function still answers with the finished
/// archive, because it builds inline. The caller branches on `kind`
/// rather than on which transport is configured.
export type CloudExportStart =
	| { kind: 'ready'; response: CloudExportResponse }
	| { kind: 'queued'; job: CloudExportJob };

async function hubSession(): Promise<string> {
	const { data } = await supabase.auth.getSession();
	const token = data.session?.access_token;
	if (!token) throw new Error('Not signed in');
	return token;
}

function throwForStatus(res: Response, body: string): never {
	if (res.status === 429) {
		const retryAfter = res.headers.get('retry-after');
		throw new Error(`Rate-limited — try again in ${retryAfter ?? '60'}s.`);
	}
	throw new Error(`Export failed (${res.status}): ${body || 'no detail'}`);
}

/// Ask for an export.
///
/// On the Go service this ENQUEUES and returns immediately: the archive
/// is built off a `data_export` job with no connection attached, so the
/// caller's timeout, a closed tab, or a backgrounded app can no longer
/// end an export that would otherwise have completed (decisions.md
/// § 717). Watch it with [fetchCloudExportJob].
///
/// On the legacy Edge Function fallback the build is still synchronous
/// and the finished archive comes back on this call. That rail is
/// deprecated; the split is by TRANSPORT, not by export size — a
/// size-based split would need a size the server cannot know before
/// building, and would make one endpoint's response shape depend on the
/// subject's data.
export async function startCloudExport(
	format: CloudExportFormat,
): Promise<CloudExportStart> {
	const hubUrl = (env.PUBLIC_EXPORT_HUB_URL ?? '').trim();
	if (!hubUrl) {
		return { kind: 'ready', response: await cloudExport(format) };
	}
	const token = await hubSession();
	const res = await fetch(buildCloudExportJobsUrl(hubUrl), {
		method: 'POST',
		headers: {
			'content-type': 'application/json',
			authorization: `Bearer ${token}`,
		},
		body: buildCloudExportBody(format),
	});
	if (!res.ok) throwForStatus(res, await res.text().catch(() => ''));
	const body = await res.json().catch(() => null);
	// The enqueue answers `{job_id, status, format, reused}` — the same
	// vocabulary the status endpoint uses, so one normaliser covers both.
	return { kind: 'queued', job: cloudExportJobFromResponse(body) };
}

/// Read the state of the subject's most recent export, minting a fresh
/// signed URL if one is ready. Returns `{status: 'none'}` when the hub
/// is unconfigured (the Edge Function rail has no job to watch) so a
/// caller can run this on mount without branching on the transport.
export async function fetchCloudExportJob(): Promise<CloudExportJob> {
	const hubUrl = (env.PUBLIC_EXPORT_HUB_URL ?? '').trim();
	if (!hubUrl) return { status: 'none' };
	const token = await hubSession();
	const res = await fetch(buildCloudExportJobStatusUrl(hubUrl), {
		headers: { authorization: `Bearer ${token}` },
	});
	if (!res.ok) throwForStatus(res, await res.text().catch(() => ''));
	return cloudExportJobFromResponse(await res.json().catch(() => null));
}

/// Kicks off a server-side export and returns the signed-URL
/// response. Throws on auth / rate-limit / 5xx errors so the caller
/// can surface a toast.
///
/// DEPRECATED on the Go rail: it POSTs the synchronous `/v1/export`,
/// which holds the connection open for the whole build. Reach for
/// [startCloudExport] instead. It survives because the mobile client
/// has not moved to the queued rail yet and the Edge Function fallback
/// has no queued rail at all.
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
