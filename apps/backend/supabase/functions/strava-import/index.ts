import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { checkRateLimit, checkRateLimitTiered } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import {
	type StravaActivity,
	type StravaTokens,
	ingestActivity,
	refreshStravaToken,
} from '../_shared/strava.ts';

// `strava-import` handles two modes, selected by the `action` field:
//
// - `connect` — first-time OAuth handshake. Exchanges the auth code
//   Strava handed the browser for access / refresh tokens and stores
//   them in `integrations`. Triggers an immediate `sync` so the user
//   sees data on first connect.
//
// - `sync` — pulls activities for an already-connected user. Fetches
//   `/api/v3/athlete/activities` paginated back `lookbackDays` days
//   (default 90), and for each running activity upserts a row into
//   `runs` with `source = 'strava'`, keyed by the Strava activity ID
//   (stored in `metadata.strava_id`). Skips activities already ingested
//   so repeat syncs are cheap.
//
// Per-activity ingestion (insert + GPS-stream fetch + Storage upload)
// lives in `../_shared/strava.ts` so the `strava-webhook` EF reuses
// the same path without drift.

serve(withSentry('strava-import', async (req: Request) => {
	if (req.method !== 'POST') {
		return new Response('Method not allowed', { status: 405 });
	}

	const authHeader = req.headers.get('Authorization');
	if (!authHeader) return new Response('Unauthorized', { status: 401 });

	const supabase = createClient(
		Deno.env.get('SUPABASE_URL')!,
		Deno.env.get('SUPABASE_ANON_KEY')!,
		{ global: { headers: { Authorization: authHeader } } },
	);

	const { data: userData } = await supabase.auth.getUser();
	const user = userData.user;
	if (!user) return new Response('Unauthorized', { status: 401 });

	const body = await req.json().catch(() => ({}));
	const action = body.action ?? (body.code ? 'connect' : 'sync');

	// Connect is one-shot per user (re-running just rotates tokens),
	// so 10/h is plenty and tier doesn't matter. Sync is the heavy
	// path: free 4/h, pro 16/h. Strava's own per-user budget is
	// 100 requests / 15 min and our backfill walks ~20 pages per call;
	// the pro 16/h still stays well inside that envelope while
	// removing the "refresh again in an hour" UX friction for paying
	// users.
	const denied = action === 'connect'
		? await checkRateLimit(supabase, user.id, 'strava-import:connect', 10, 3600)
		: await checkRateLimitTiered(supabase, user.id, 'strava-import:sync', 4, 16, 3600);
	if (denied) return denied;

	if (action === 'connect') {
		return handleConnect(supabase, user.id, body.code, body.scope, body.redirect_uri);
	}
	if (action === 'sync') {
		return handleSync(supabase, user.id, body.lookbackDays ?? 90);
	}
	return new Response('Unknown action', { status: 400 });
}));

async function handleConnect(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	code: string,
	scope: string,
	redirectUri: string | undefined,
): Promise<Response> {
	if (!code) return new Response('Missing code', { status: 400 });

	// Pin the redirect_uri the client claims it used. Strava's
	// /oauth/authorize already enforces that callbacks land on the
	// registered domain (`Authorization Callback Domain`), but that
	// validation is path-prefix loose — any path under our domain
	// counts. A code captured from an unrelated path under our domain
	// (e.g. an old or experimental route that got a code in its query
	// string) would still token-exchange. The allow-list pins the
	// exchange to an explicit set of redirect URIs declared via env,
	// closing that window. We never call Strava with this value
	// (Strava's token endpoint ignores redirect_uri); it's purely a
	// client-claim assertion against our own allow-list.
	const allowed = (Deno.env.get('STRAVA_ALLOWED_REDIRECTS') ?? '')
		.split(',')
		.map((s) => s.trim())
		.filter(Boolean);
	if (allowed.length > 0) {
		if (!redirectUri || !allowed.includes(redirectUri)) {
			return new Response('Invalid redirect_uri', { status: 400 });
		}
	}

	const tokenResponse = await fetch('https://www.strava.com/oauth/token', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({
			client_id: Deno.env.get('STRAVA_CLIENT_ID'),
			client_secret: Deno.env.get('STRAVA_CLIENT_SECRET'),
			code,
			grant_type: 'authorization_code',
		}),
	});

	if (!tokenResponse.ok) {
		const text = await tokenResponse.text();
		return new Response(`Strava token exchange failed: ${text}`, { status: 502 });
	}

	const tokens = (await tokenResponse.json()) as StravaTokens;

	// Upsert non-secret fields (external_id, scope) directly; the
	// access / refresh tokens go to Vault via set_integration_tokens.
	const { error: upsertErr } = await supabase.from('integrations').upsert(
		{
			user_id: userId,
			provider: 'strava',
			external_id: String(tokens.athlete.id),
			scope,
		},
		{ onConflict: 'user_id,provider' },
	);
	if (upsertErr) {
		return new Response(`Store integration failed: ${upsertErr.message}`, { status: 500 });
	}

	const { error: tokErr } = await supabase.rpc('set_integration_tokens', {
		p_user_id: userId,
		p_provider: 'strava',
		p_access_token: tokens.access_token,
		p_refresh_token: tokens.refresh_token,
		p_token_expiry: new Date(tokens.expires_at * 1000).toISOString(),
	});
	if (tokErr) {
		return new Response(`Store tokens failed: ${tokErr.message}`, { status: 500 });
	}

	// First-time connects always trigger a backfill so the user sees data
	// immediately. 90 days is a sensible default — Strava's athlete list
	// goes much further back but that's rarely what someone wants on day
	// one.
	const result = await backfill(supabase, userId, tokens.access_token, 90);
	return Response.json({ ...result, athlete_id: String(tokens.athlete.id) });
}

async function handleSync(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	lookbackDays: number,
): Promise<Response> {
	const { data: tokenRows, error: tokenErr } = await supabase.rpc(
		'get_integration_tokens',
		{ p_user_id: userId, p_provider: 'strava' },
	);
	const tokenRow = tokenRows?.[0];
	if (tokenErr || !tokenRow?.access_token) {
		return new Response('Strava not connected', { status: 400 });
	}

	let accessToken = tokenRow.access_token as string;

	// Refresh on-demand if the stored token is within 5 minutes of expiry.
	// This path runs independently of the scheduled refresh job so an
	// ad-hoc sync after a long gap still works.
	if (tokenRow.token_expiry) {
		const expiryMs = new Date(tokenRow.token_expiry as string).getTime();
		if (Date.now() + 300_000 > expiryMs) {
			const refreshed = await refreshStravaToken(supabase, userId, tokenRow.refresh_token as string);
			if (refreshed) accessToken = refreshed;
		}
	}

	const result = await backfill(supabase, userId, accessToken, lookbackDays);
	return Response.json(result);
}

async function backfill(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	accessToken: string,
	lookbackDays: number,
): Promise<{ imported: number; skipped: number; failed: number }> {
	const afterEpoch = Math.floor((Date.now() - lookbackDays * 86400_000) / 1000);
	let page = 1;
	const pageSize = 50;
	let imported = 0;
	let skipped = 0;
	let failed = 0;

	// Pull existing Strava-sourced runs in one shot so we can dedupe
	// without hitting the DB per activity. Keyed by Strava activity ID
	// stored in metadata.
	const { data: existing } = await supabase
		.from('runs')
		.select('metadata')
		.eq('user_id', userId)
		.eq('source', 'strava');
	const seen = new Set<string>();
	for (const r of existing ?? []) {
		const sid = (r.metadata as Record<string, unknown> | null)?.strava_id;
		if (sid) seen.add(String(sid));
	}

	while (true) {
		const url = `https://www.strava.com/api/v3/athlete/activities?after=${afterEpoch}&per_page=${pageSize}&page=${page}`;
		const resp = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
		if (!resp.ok) {
			// Bail silently on the first failure rather than looping forever —
			// partial imports are still useful.
			break;
		}
		const activities = (await resp.json()) as StravaActivity[];
		if (!Array.isArray(activities) || activities.length === 0) break;

		for (const act of activities) {
			// Restrict to run-type activities. Strava's `sport_type` is the
			// preferred modern field; `type` is the legacy fallback.
			const kind = (act.sport_type ?? act.type ?? '').toLowerCase();
			if (!kind.includes('run') && !kind.includes('walk') && !kind.includes('hike')) continue;
			if (seen.has(String(act.id))) {
				skipped++;
				continue;
			}
			try {
				await ingestActivity(supabase, userId, accessToken, act);
				imported++;
			} catch (_) {
				failed++;
			}
		}

		if (activities.length < pageSize) break;
		page++;
		if (page > 20) break; // safety cap — 1000 activities per sync
	}

	await supabase
		.from('integrations')
		.update({ last_sync_at: new Date().toISOString() })
		.eq('user_id', userId)
		.eq('provider', 'strava');

	return { imported, skipped, failed };
}
