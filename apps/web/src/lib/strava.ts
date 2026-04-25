/// Strava OAuth + sync helpers.
///
/// OAuth happens entirely in the browser: we kick the user to
/// Strava's /oauth/authorize page, Strava redirects back to
/// `/settings/integrations?code=...&scope=...`, and we POST the code
/// to the `strava-import` Edge Function. The function exchanges it
/// for tokens (secret stays server-side) and backfills the last 90
/// days of activities in the same call. A subsequent "Sync now" click
/// posts `{ action: 'sync' }` to the same function.

import { env } from '$env/dynamic/public';
import { supabase } from './supabase';

// Read via `$env/dynamic/public` rather than `static/public` so a build
// without `PUBLIC_STRAVA_CLIENT_ID` set falls back gracefully to "not
// configured" instead of crashing the page with a 500. The static
// import would have failed the entire SvelteKit build.
const PUBLIC_STRAVA_CLIENT_ID = env.PUBLIC_STRAVA_CLIENT_ID ?? '';

export interface StravaSyncResult {
	imported: number;
	skipped: number;
	failed: number;
	athlete_id?: string;
}

/// Returns `true` when the Vite build has a public Strava client ID
/// baked in. The UI uses this to decide whether to show a real Connect
/// button or a "Strava is not configured" placeholder.
export function isStravaConfigured(): boolean {
	return Boolean(PUBLIC_STRAVA_CLIENT_ID && PUBLIC_STRAVA_CLIENT_ID !== '12345');
}

/// Build the Strava authorization URL. `approval_prompt=auto` so users
/// who already authorised the app get bounced through without a second
/// consent screen. `activity:read_all` is the scope we need to see
/// non-public runs too.
export function stravaAuthUrl(origin: string): string {
	const params = new URLSearchParams({
		client_id: PUBLIC_STRAVA_CLIENT_ID,
		response_type: 'code',
		redirect_uri: `${origin}/settings/integrations`,
		approval_prompt: 'auto',
		scope: 'activity:read_all,read',
	});
	return `https://www.strava.com/oauth/authorize?${params.toString()}`;
}

/// Complete the OAuth flow after Strava redirects back to the app.
/// Extracts `code` + `scope` from the URL, POSTs them to the Edge
/// Function, and strips the params from `history` so a refresh doesn't
/// re-run the exchange (Strava codes are single-use).
export async function completeStravaOAuth(
	searchParams: URLSearchParams,
): Promise<StravaSyncResult> {
	const code = searchParams.get('code');
	const scope = searchParams.get('scope') ?? '';
	const error = searchParams.get('error');
	if (error) throw new Error(`Strava denied access: ${error}`);
	if (!code) throw new Error('Missing authorization code from Strava');

	const { data: sessionData } = await supabase.auth.getSession();
	const token = sessionData.session?.access_token;
	if (!token) throw new Error('Not signed in');

	const { data, error: fnError } = await supabase.functions.invoke('strava-import', {
		body: { action: 'connect', code, scope },
	});
	if (fnError) throw fnError;
	return data as StravaSyncResult;
}

/// Trigger a manual sync for an already-connected user. Safe to call
/// repeatedly; the Edge Function dedupes against already-imported
/// activity IDs.
export async function syncStrava(lookbackDays = 90): Promise<StravaSyncResult> {
	const { data, error } = await supabase.functions.invoke('strava-import', {
		body: { action: 'sync', lookbackDays },
	});
	if (error) throw error;
	return data as StravaSyncResult;
}
