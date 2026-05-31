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
import { supabase } from '../core/supabase';

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

/// sessionStorage key used to stash the OAuth `state` token between
/// the redirect-out and the redirect-back. Keyed-by-user would be
/// stricter, but the client doesn't have the user id at the moment
/// of click and the same-tab sessionStorage scope is sufficient for
/// the CSRF check. /audit/strava May 2026 Critical #1.
const STRAVA_OAUTH_STATE_KEY = 'strava_oauth_state';

/// Generate a fresh CSRF state token using crypto.randomUUID. The
/// returned value is what the caller passes to [stravaAuthUrl] and
/// what [verifyStravaOAuthState] checks against on callback.
export function mintStravaOAuthState(): string {
	return crypto.randomUUID();
}

/// Build the Strava authorization URL. `approval_prompt=auto` so users
/// who already authorised the app get bounced through without a second
/// consent screen. `activity:read_all` is the scope we need to see
/// non-public runs too.
///
/// [state] is the OAuth 2.0 CSRF guard (RFC 6749 §10.12). REQUIRED —
/// without it, an attacker can forge a callback URL that links the
/// victim's session to the attacker's Strava account. The caller
/// stores it in sessionStorage via [storeStravaOAuthState] and
/// verifies on return via [verifyStravaOAuthState].
export function stravaAuthUrl(origin: string, state: string): string {
	const params = new URLSearchParams({
		client_id: PUBLIC_STRAVA_CLIENT_ID,
		response_type: 'code',
		redirect_uri: `${origin}/settings/integrations`,
		approval_prompt: 'auto',
		scope: 'activity:read_all,read',
		state,
	});
	return `https://www.strava.com/oauth/authorize?${params.toString()}`;
}

/// Stash the OAuth state in sessionStorage. Safari private-mode
/// swallows the write — the verify step treats a missing stash as
/// "tab reload mid-flow" and reprompts.
export function storeStravaOAuthState(state: string): void {
	try {
		sessionStorage.setItem(STRAVA_OAUTH_STATE_KEY, state);
	} catch (_) {
		/* private mode — verify step will reject */
	}
}

/// Read + clear the stashed state. Returns null when missing
/// (Safari private mode, expired session, attacker-supplied callback
/// not preceded by our authorize). One-shot read clears the stash
/// regardless of match — replay is also a CSRF condition.
export function consumeStravaOAuthState(): string | null {
	try {
		const v = sessionStorage.getItem(STRAVA_OAUTH_STATE_KEY);
		sessionStorage.removeItem(STRAVA_OAUTH_STATE_KEY);
		return v;
	} catch (_) {
		return null;
	}
}

/// Complete the OAuth flow after Strava redirects back to the app.
/// Extracts `code` + `scope` from the URL, POSTs them to the Edge
/// Function, and strips the params from `history` so a refresh doesn't
/// re-run the exchange (Strava codes are single-use).
export async function completeStravaOAuth(
	searchParams: URLSearchParams,
	origin: string,
): Promise<StravaSyncResult> {
	const code = searchParams.get('code');
	const scope = searchParams.get('scope') ?? '';
	const state = searchParams.get('state') ?? '';
	const error = searchParams.get('error');
	if (error) throw new Error(`Strava denied access: ${error}`);
	if (!code) throw new Error('Missing authorization code from Strava');

	// OAuth 2.0 §10.12 CSRF check. The state the caller minted before
	// the redirect-out MUST match what Strava echoes back. A mismatch
	// (or missing stash — sessionStorage cleared / Safari private
	// mode / attacker-supplied callback URL not preceded by our
	// authorize) is treated as forged and refuses to exchange the
	// code. /audit/strava May 2026 Critical #1.
	const expected = consumeStravaOAuthState();
	if (!expected || expected !== state) {
		throw new Error(
			'Strava OAuth state mismatch — please retry from Settings. ' +
				'(If this keeps happening, your browser may be blocking ' +
				'session storage in this tab.)',
		);
	}

	const { data: sessionData } = await supabase.auth.getSession();
	const token = sessionData.session?.access_token;
	if (!token) throw new Error('Not signed in');

	// Forward the redirect_uri so the EF can validate it against the
	// configured allow-list. Same shape we used to build the authorize
	// URL — see `stravaAuthUrl`.
	const redirect_uri = `${origin}/settings/integrations`;

	const { data, error: fnError } = await supabase.functions.invoke('strava-import', {
		body: { action: 'connect', code, scope, redirect_uri },
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
