import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import { checkRateLimit, checkRateLimitTiered } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import {
	type StravaActivity,
	type StravaTokens,
	ingestActivity,
	isStravaRunFamily,
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

Deno.serve(withSentry('strava-import', async (req: Request) => {
	if (req.method !== 'POST') {
		return Response.json({ error: 'method_not_allowed' }, { status: 405 });
	}

	// 4 KB is plenty for both action shapes — `connect` carries a code
	// (~40 chars), scope (~40 chars) and a redirect_uri (~80 chars);
	// `sync` carries action + lookbackDays.
	const guarded = await readJsonWithLimit<Record<string, unknown>>(req, 4096);
	if ('tooLarge' in guarded) return guarded.tooLarge;

	const authHeader = req.headers.get('Authorization');
	if (!authHeader) return Response.json({ error: 'unauthorized' }, { status: 401 });

	const supabase = createClient(
		Deno.env.get('SUPABASE_URL')!,
		Deno.env.get('SUPABASE_ANON_KEY')!,
		{ global: { headers: { Authorization: authHeader } } },
	);

	const { data: userData } = await supabase.auth.getUser();
	const user = userData.user;
	if (!user) return Response.json({ error: 'unauthorized' }, { status: 401 });

	const body = (guarded.body ?? {}) as Record<string, unknown>;
	// audit/edge-functions Low: require an explicit action. Both the
	// web OAuth callback (`apps/web/src/lib/strava.ts:73`) and the
	// mobile sync caller (`packages/api_client/.../api_client.dart:2511`)
	// now send `action` explicitly, so the prior `body.code ? 'connect'`
	// implicit-routing fallback was retired in /audit/all 2026-05-07.
	const action = body.action as string | undefined;
	if (action !== 'connect' && action !== 'sync' && action !== 'disconnect') {
		return Response.json(
			{ error: 'invalid_action', expected: ['connect', 'sync', 'disconnect'] },
			{ status: 400 },
		);
	}

	// Validate body shape per action before any side effects. The
	// later helpers cast straight from `body.<field>` and we don't
	// want a number-typed `lookbackDays` to drive negative-epoch
	// arithmetic, or a non-string scope to throw inside .split().
	if (action === 'connect') {
		if (typeof body.code !== 'string' || body.code.length === 0) {
			return Response.json({ error: 'invalid_code' }, { status: 400 });
		}
		if (typeof body.scope !== 'string') {
			return Response.json({ error: 'invalid_scope' }, { status: 400 });
		}
		if (typeof body.redirect_uri !== 'string') {
			return Response.json({ error: 'invalid_redirect_uri' }, { status: 400 });
		}
	} else if (action === 'sync') {
		if (body.lookbackDays !== undefined) {
			if (
				!Number.isInteger(body.lookbackDays) ||
				body.lookbackDays <= 0 ||
				body.lookbackDays > 365
			) {
				return Response.json({ error: 'invalid_lookback_days' }, { status: 400 });
			}
		}
	}

	// Connect is one-shot per user (re-running just rotates tokens),
	// so 10/h is plenty and tier doesn't matter. Sync is the heavy
	// path: free 4/h, pro 16/h. Strava's own per-user budget is
	// 100 requests / 15 min and our backfill walks ~20 pages per call;
	// the pro 16/h still stays well inside that envelope while
	// removing the "refresh again in an hour" UX friction for paying
	// users.
	// `connect` is fail-closed: it exchanges an OAuth code (one-shot,
	// time-bounded by Strava) and writes credentials to Vault. Letting
	// the limiter fall open on RPC error means a stolen JWT during a
	// DB blip can spam-exchange codes against Strava's per-app budget.
	// `sync` stays fail-open — it's idempotent and read-mostly.
	const denied = action === 'connect'
		? await checkRateLimit(supabase, user.id, 'strava-import:connect', 10, 3600, {
			failClosed: true,
		})
		: action === 'disconnect'
			? await checkRateLimit(supabase, user.id, 'strava-import:disconnect', 10, 3600, {
				failClosed: true,
			})
			: await checkRateLimitTiered(supabase, user.id, 'strava-import:sync', 4, 16, 3600);
	if (denied) return denied;

	if (action === 'connect') {
		return handleConnect(supabase, user.id, body.code, body.scope, body.redirect_uri);
	}
	if (action === 'sync') {
		return handleSync(supabase, user.id, body.lookbackDays ?? 90);
	}
	if (action === 'disconnect') {
		return handleDisconnect(supabase, user.id);
	}
	return Response.json({ error: 'unknown_action' }, { status: 400 });
}));

// audit/strava May 2026 High #1 — user-initiated Disconnect must
// (a) revoke at Strava's end so the token can't be replayed,
// (b) wipe the vault rows so the operator can't read decoded
// secrets at rest, (c) stamp `disconnected_at` so the UI shows
// Reconnect Strava. Pre-fix the disconnect path was a bare DELETE
// FROM integrations — left vault secrets orphaned + Strava-side
// connection live indefinitely.
async function handleDisconnect(
	_userScopedSupabase: ReturnType<typeof createClient>,
	userId: string,
): Promise<Response> {
	// `delete_user_provider_secrets` is GRANTed to service_role only
	// (migration 20261005_001) — the user-scoped client would 42501
	// on the RPC. The user-scoped client gated the caller's identity
	// at the EF entrypoint; from here on we run as service-role on
	// `userId`. The other writes here (vault read via DEFINER RPC,
	// integrations UPDATE on the user's own row) are reachable from
	// either, so consolidating on one client keeps the path uniform.
	const supabase = createClient(
		Deno.env.get('SUPABASE_URL')!,
		Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
	);

	const { data: tokenRows } = await supabase.rpc('get_integration_tokens', {
		p_user_id: userId,
		p_provider: 'strava',
	});
	const tokenRow = tokenRows?.[0];

	// audit/strava L6 — best-effort pre-deauth refresh. If the
	// stored access token is expired, deauth would 401 and we'd
	// record `'failed'` while the upstream connection persists.
	// Refresh first; swallow failures so the deauth attempt still
	// runs with whatever token we have.
	let accessToken = (tokenRow?.access_token ?? '') as string;
	if (tokenRow?.refresh_token && tokenRow.token_expiry) {
		const expiryMs = new Date(tokenRow.token_expiry as string).getTime();
		if (Date.now() + 60_000 > expiryMs) {
			try {
				const fresh = await refreshStravaToken(
					supabase,
					userId,
					tokenRow.refresh_token as string,
				);
				if (fresh) accessToken = fresh;
			} catch (_) {
				/* fall through with stale token — best-effort */
			}
		}
	}

	// POST /oauth/deauthorize — Strava revokes the access token at
	// their end. Best-effort: a 401 here is fine (the token aged out
	// before we got around to disconnecting); a 5xx outage just
	// means Strava's side stays live a bit longer.
	let stravaDeauthOutcome: 'ok' | 'skipped' | 'failed' = 'skipped';
	if (accessToken) {
		try {
			const r = await fetch('https://www.strava.com/oauth/deauthorize', {
				method: 'POST',
				headers: { Authorization: `Bearer ${accessToken}` },
			});
			stravaDeauthOutcome = r.ok ? 'ok' : 'failed';
		} catch (_) {
			stravaDeauthOutcome = 'failed';
		}
	}

	// Drop vault rows + clear FK + clear token_expiry. Idempotent
	// — re-running yields 0 deletes + clean state.
	const { error: rpcErr } = await supabase.rpc('delete_user_provider_secrets', {
		p_user_id: userId,
		p_provider: 'strava',
	});
	if (rpcErr) {
		console.error('strava-import: delete_user_provider_secrets failed', rpcErr.message);
		return Response.json({ error: 'vault_cleanup_failed' }, { status: 500 });
	}

	// Stamp `disconnected_at` so subsequent token-refresh sweeps
	// skip the row + the UI shows Reconnect Strava.
	const { error: stampErr } = await supabase
		.from('integrations')
		.update({
			disconnected_at: new Date().toISOString(),
			disconnected_reason: 'user_initiated',
		})
		.eq('user_id', userId)
		.eq('provider', 'strava');
	if (stampErr) {
		console.error('strava-import: stamp disconnected_at failed', stampErr.message);
		return Response.json({ error: 'stamp_failed' }, { status: 500 });
	}

	return Response.json({ ok: true, strava_deauth: stravaDeauthOutcome });
}

async function handleConnect(
	supabase: ReturnType<typeof createClient>,
	userId: string,
	code: string,
	_clientClaimedScope: string,
	redirectUri: string | undefined,
): Promise<Response> {
	if (!code) return Response.json({ error: 'missing_code' }, { status: 400 });

	// We don't trust the client-supplied `scope` field — it's just a
	// hint Strava's redirect echoed back, and a man-in-the-middle on
	// that redirect could rewrite it. The authoritative scope comes
	// from Strava's /oauth/token response and is checked after the
	// exchange below.

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
	//
	// Fail closed when unset — matches the secret-gated webhooks
	// (CRON_SECRET, REVENUECAT_WEBHOOK_SECRET, STRAVA_WEBHOOK_SECRET)
	// which 503 on missing config. A silent fall-through to "allow
	// any redirect" would defeat the remediation in a single missed
	// `supabase secrets set`.
	const allowed = (Deno.env.get('STRAVA_ALLOWED_REDIRECTS') ?? '')
		.split(',')
		.map((s) => s.trim())
		.filter(Boolean);
	if (allowed.length === 0) {
		return Response.json({ error: 'strava_not_configured' }, { status: 503 });
	}
	if (!redirectUri || !allowed.includes(redirectUri)) {
		// audit/strava May 2026 Low #1 — debug log only on the host
		// part of the URL (NOT the path or query — those can carry the
		// OAuth code in some malformed callers). Lets an operator
		// diagnose a `STRAVA_ALLOWED_REDIRECTS` typo during cutover
		// without dumping anything sensitive into logs.
		let receivedHost = '<unparseable>';
		try {
			receivedHost = redirectUri ? new URL(redirectUri).host : '<missing>';
		} catch (_) {
			/* keep <unparseable> */
		}
		console.warn('strava-import: redirect_uri mismatch', {
			received_host: receivedHost,
			allowed_count: allowed.length,
		});
		return Response.json({ error: 'invalid_redirect_uri' }, { status: 400 });
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
		// Don't log Strava's response body — it can echo our client_id
		// and partial code state, both of which are credential-adjacent
		// and shouldn't sit in function logs. The status alone is
		// enough to debug a real exchange failure.
		console.error('strava-import: token exchange failed', { status: tokenResponse.status });
		return Response.json({ error: 'strava_token_exchange_failed' }, { status: 502 });
	}

	const tokens = (await tokenResponse.json()) as StravaTokens;

	// Authoritative scope check, against Strava's response — not the
	// client-claimed `scope` field (which a MITM on the redirect can
	// forge). Strava returns the actually-granted scopes here; if
	// `activity:read_all` is missing, the backfill below would
	// silently 401 every page and the user would see "connected,
	// 0 imports" instead of a useful "missing permission, please
	// reconnect" prompt.
	const grantedScopes = (tokens.scope ?? '').split(',').map((s) => s.trim()).filter(Boolean);
	if (!grantedScopes.includes('activity:read_all')) {
		return new Response(
			'Strava connection is missing the activity:read_all scope. Please reconnect and accept all permissions.',
			{ status: 400 },
		);
	}

	// Upsert non-secret fields (external_id, scope) directly; the
	// access / refresh tokens go to Vault via set_integration_tokens.
	// Persist the *granted* scope, not the client-claimed value.
	const { error: upsertErr } = await supabase.from('integrations').upsert(
		{
			user_id: userId,
			provider: 'strava',
			external_id: String(tokens.athlete.id),
			scope: tokens.scope ?? '',
		},
		{ onConflict: 'user_id,provider' },
	);
	if (upsertErr) {
		console.error('strava-import: integrations upsert failed:', upsertErr?.message ?? String(upsertErr));
		return Response.json({ error: 'store_integration_failed' }, { status: 500 });
	}

	const { error: tokErr } = await supabase.rpc('set_integration_tokens', {
		p_user_id: userId,
		p_provider: 'strava',
		p_access_token: tokens.access_token,
		p_refresh_token: tokens.refresh_token,
		p_token_expiry: new Date(tokens.expires_at * 1000).toISOString(),
	});
	if (tokErr) {
		// audit/strava May 2026 Medium #5 — the vault.update_secret
		// upstream message can embed the secret's label
		// (`integration_access_<uuid>_<provider>`), leaking the user
		// UUID into the log aggregator. Strip the label pattern.
		const msg = (tokErr?.message ?? String(tokErr))
			.replace(/integration_(access|refresh)_[0-9a-f-]{8,}_[a-z_]+/gi, 'integration_<provider>_<redacted>');
		console.error('strava-import: set_integration_tokens RPC failed', {
			rpc: 'set_integration_tokens',
			error_class: 'vault_write',
			error: msg,
		});
		return Response.json({ error: 'store_tokens_failed' }, { status: 500 });
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
		return Response.json({ error: 'strava_not_connected' }, { status: 400 });
	}

	let accessToken = tokenRow.access_token as string;

	// Refresh on-demand if the stored token is within 5 minutes of expiry.
	// This path runs independently of the scheduled refresh job so an
	// ad-hoc sync after a long gap still works.
	//
	// /audit/strava May 2026 Medium #4: a null `refreshed` means the
	// Strava refresh endpoint returned 4xx (revoked grant) or 5xx
	// (transient). The handler used to silently proceed with the stale
	// access token; the next page fetch 401'd and we'd return "imported
	// 0, skipped 0" with no signal to the user that they need to
	// reconnect. Surface the failure as a structured 401 so the UI can
	// prompt Reconnect Strava — matches the shape of `strava_not_connected`
	// 400 above. The token-refresh cron (Go worker handler_token_refresh)
	// stamps `disconnected_at` on a 4xx refresh; the next sync attempt
	// won't even reach this branch.
	if (tokenRow.token_expiry) {
		const expiryMs = new Date(tokenRow.token_expiry as string).getTime();
		if (Date.now() + 300_000 > expiryMs) {
			const refreshed = await refreshStravaToken(supabase, userId, tokenRow.refresh_token as string);
			if (!refreshed) {
				return Response.json(
					{ error: 'refresh_failed', reconnect_required: true },
					{ status: 401 },
				);
			}
			accessToken = refreshed;
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

	// Resolve privacy_default ONCE for the whole backfill (persona #27) so
	// imported runs match the user's chosen visibility. Only an explicit
	// 'public' default publishes; followers/private/unset and any read error
	// fall closed to private.
	let importIsPublic = false;
	try {
		const { data: settings } = await supabase
			.from('user_settings')
			.select('prefs')
			.eq('user_id', userId)
			.maybeSingle();
		const prefs = (settings?.prefs ?? null) as Record<string, unknown> | null;
		importIsPublic = prefs?.privacy_default === 'public';
	} catch (_) {
		importIsPublic = false;
	}

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

	let rateLimited = false;
	while (true) {
		const url = `https://www.strava.com/api/v3/athlete/activities?after=${afterEpoch}&per_page=${pageSize}&page=${page}`;
		const resp = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
		if (resp.status === 429 || resp.status === 503) {
			// Strava rate-limit / maintenance — surface to the caller so
			// the client can show "Strava is rate-limiting us, try again
			// in 15 minutes" rather than treating partial as success.
			console.warn('strava backfill rate-limited', { page, status: resp.status });
			rateLimited = true;
			break;
		}
		if (!resp.ok) {
			// Bail silently on the first non-rate-limit failure rather
			// than looping forever — partial imports are still useful.
			break;
		}
		const activities = (await resp.json()) as StravaActivity[];
		if (!Array.isArray(activities) || activities.length === 0) break;

		for (const act of activities) {
			// Restrict to run-family activities (Run / TrailRun / VirtualRun
			// / Walk / Hike). Strava's `sport_type` is the modern field;
			// `type` is the legacy fallback. Routed through the shared
			// helper so the allowlist stays in one place — ingestActivity
			// now also rejects defensively (persona-hunt Pro #3).
			if (!isStravaRunFamily(act.sport_type ?? act.type)) continue;
			if (seen.has(String(act.id))) {
				skipped++;
				continue;
			}
			try {
				await ingestActivity(supabase, userId, accessToken, act, importIsPublic);
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

	return { imported, skipped, failed, rate_limited: rateLimited };
}
