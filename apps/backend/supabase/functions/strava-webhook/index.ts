/// Strava webhook receiver.
///
/// Auth model:
///   - GET (subscription handshake): Strava sends the verify_token we
///     gave it during subscription creation. We compare against
///     STRAVA_VERIFY_TOKEN.
///   - POST (activity event): Strava does NOT sign payloads — their
///     security model is "the callback URL is secret." That is not
///     enough on its own (a leak of the function URL is permanent
///     and unrotatable), so we require a shared secret in the query
///     string of the URL configured in Strava:
///         https://<host>/strava-webhook?secret=<STRAVA_WEBHOOK_SECRET>
///     Strava preserves the configured URL's query string on both
///     GET and POST, so the same secret guards both methods.
///
/// Without STRAVA_WEBHOOK_SECRET set, the function refuses all POSTs
/// (and all GETs that don't supply the secret) — the only correct
/// behaviour for a misconfigured webhook is to fail closed.
///
/// Replay protection: the URL secret authenticates the channel but a
/// captured POST is otherwise replayable forever. Each actionable
/// event is bound to a 7-day freshness window on `event_time` AND
/// deduped via `webhook_events` (provider='strava', event_id =
/// '<owner>:<object>:<aspect>:<event_time>') — first writer wins,
/// any 23505 unique-violation maps to a 200 ok-skipped. Mirrors the
/// revenuecat-webhook pattern; see migration 20260623_001.
///
/// Activity ingestion is delegated to `../_shared/strava.ts` so the
/// webhook and the backfill EF (`strava-import`) write byte-identical
/// rows. A webhook firing while a backfill is mid-run is harmless —
/// the dedupe check on `metadata.strava_id` short-circuits.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import {
	fetchStravaActivity,
	ingestActivity,
	isAlreadyImported,
	refreshStravaToken,
} from '../_shared/strava.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import * as Sentry from 'https://deno.land/x/sentry@8.40.0/index.mjs';
import { timingSafeEqual, validateFreshness } from '../_shared/webhook_security.ts';

Deno.serve(withSentry('strava-webhook', async (req: Request) => {
	// Body cap is enforced in the POST branch below via readJsonWithLimit
	// — closes the chunked-transfer-encoding bypass that the bare header
	// check left open. GET has no body.

	const webhookSecret = Deno.env.get('STRAVA_WEBHOOK_SECRET');
	if (!webhookSecret) {
		return Response.json({ error: 'webhook_not_configured' }, { status: 503 });
	}
	// audit/strava May 2026 Low #2 — short secret refuses to operate.
	// Matches the Go variant's 32-char floor. Defends against a
	// misconfigured deploy (e.g. `STRAVA_WEBHOOK_SECRET=test`).
	if (webhookSecret.length < 32) {
		return Response.json({ error: 'webhook_not_configured' }, { status: 503 });
	}

	// IP-keyed rate limit BEFORE the secret check — closes the
	// brute-force surface from /audit/all edge-functions Medium. A
	// caller that has discovered the function URL (semi-public — it's
	// registered with Strava's API) could otherwise grind the secret
	// at network rate; `timingSafeEqual` closes the per-byte channel
	// but doesn't slow the offline guess rate. 60 hits/hour/IP is
	// generous for legitimate Strava traffic (a single subscription
	// emits maybe 1-10 events/hour for an active user) and brutal
	// for an attacker. Service-role client is required because
	// `ipBucketKey` returns a synthetic UUID that can't satisfy the
	// `auth.uid()` guard in `check_rate_limit`.
	const adminClient = createClient(
		Deno.env.get('SUPABASE_URL')!,
		Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
	);
	{
		const anonKey = await ipBucketKey(req);
		const denied = await checkRateLimit(
			adminClient,
			anonKey,
			'strava-webhook:anon',
			60,
			3600,
			{ failClosed: true },
		);
		if (denied) return denied;
	}

	const url = new URL(req.url);
	const suppliedSecret = url.searchParams.get('secret');
	if (!suppliedSecret || !timingSafeEqual(suppliedSecret, webhookSecret)) {
		return Response.json({ error: 'forbidden' }, { status: 403 });
	}

	// GET: Strava webhook subscription handshake.
	if (req.method === 'GET') {
		const challenge = url.searchParams.get('hub.challenge');
		const verifyToken = url.searchParams.get('hub.verify_token') ?? '';
		const expectedToken = Deno.env.get('STRAVA_VERIFY_TOKEN') ?? '';

		// Timing-safe comparison: a plain `!==` would let an attacker who
		// has the URL secret probe the verify token byte-by-byte via
		// response-latency differences. The two secrets are independent;
		// hardening this one closes the side-channel.
		if (!expectedToken || !timingSafeEqual(verifyToken, expectedToken)) {
			return Response.json({ error: 'forbidden' }, { status: 403 });
		}

		return Response.json({ 'hub.challenge': challenge });
	}

	if (req.method !== 'POST') {
		return Response.json({ error: 'method_not_allowed' }, { status: 405 });
	}

	// POST: Activity event from Strava. Payload shape:
	//   { object_type, object_id, aspect_type, owner_id, subscription_id,
	//     event_time, updates }
	// We only handle 'activity' / 'create' — updates and deletes are
	// ignored (the backfill picks up edits on the next manual sync).
	const guarded = await readJsonWithLimit<{
		object_type?: string;
		object_id?: number;
		aspect_type?: string;
		owner_id?: number;
		event_time?: number;
	}>(req, 4096);
	if ('tooLarge' in guarded) return guarded.tooLarge;
	const event = guarded.body ?? {};

	if (event.object_type !== 'activity' || event.aspect_type !== 'create') {
		// Strava expects a 200 within 2s for any POST; logging 'OK' for
		// non-actionable events keeps the subscription healthy without
		// implying we did work. Don't burn a webhook_events row for
		// noise we'll never act on.
		return new Response('OK');
	}

	const activityId = event.object_id;
	const ownerId = event.owner_id;
	const eventTime = event.event_time;
	if (!activityId || !ownerId) {
		return Response.json({ error: 'missing_object_id_or_owner_id' }, { status: 400 });
	}
	if (typeof eventTime !== 'number') {
		return Response.json({ error: 'missing_event_time' }, { status: 400 });
	}

	// Replay protection. Strava doesn't sign payloads — the URL secret
	// authenticates the *channel* but does nothing against a captured
	// POST being re-sent. Two gates, mirroring revenuecat-webhook:
	//   1. Freshness — reject events whose event_time is older than
	//      REPLAY_WINDOW_MS or further in the future than CLOCK_SKEW_MS.
	//      Catches captures sitting on a flash drive.
	//   2. Event-id dedupe — first writer to webhook_events wins.
	//      Strava doesn't send a server-side unique event id, so we
	//      synthesise one from owner+object+aspect+event_time. A
	//      replayed POST with the same body inserts the same key and
	//      raises 23505, which we map to 200 ok-skipped.
	//
	if (validateFreshness(eventTime * 1000, Date.now()) !== 'ok') {
		return Response.json({ error: 'event_outside_freshness_window' }, { status: 400 });
	}

	const supabase = createClient(
		Deno.env.get('SUPABASE_URL')!,
		Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
	);

	const eventId = `${ownerId}:${activityId}:${event.aspect_type}:${eventTime}`;
	const { error: dedupeErr } = await supabase
		.from('webhook_events')
		.insert({ provider: 'strava', event_id: eventId });
	if (dedupeErr) {
		if (dedupeErr.code === '23505') {
			return Response.json({ ok: true, skipped: 'duplicate_event' });
		}
		console.error('Webhook dedupe insert failed:', dedupeErr?.message ?? String(dedupeErr));
		return Response.json({ ok: false, error: 'dedupe_failed' }, { status: 500 });
	}

	// Look up user by Strava athlete ID.
	const { data: integration } = await supabase
		.from('integrations')
		.select('user_id')
		.eq('provider', 'strava')
		.eq('external_id', String(ownerId))
		.single();

	if (!integration) {
		// User isn't connected (or disconnected since the webhook fired).
		// Returning 200 prevents Strava from retrying a payload we can
		// never act on; 404 would have them retry.
		return new Response('OK');
	}

	const userId = integration.user_id as string;

	// Dedupe early. A backfill running concurrently may have already
	// written this activity; no point fetching the detail again.
	if (await isAlreadyImported(supabase, userId, activityId)) {
		return new Response('OK');
	}

	// Pull a fresh access token from Vault. Refresh ad-hoc if it's
	// within 5 minutes of expiry — webhooks fire whenever Strava feels
	// like it, including hours after the user last opened the app.
	const { data: tokenRows, error: tokenErr } = await supabase.rpc(
		'get_integration_tokens',
		{ p_user_id: userId, p_provider: 'strava' },
	);
	const tokenRow = tokenRows?.[0];
	if (tokenErr || !tokenRow?.access_token) {
		// User disconnected Strava but the integration row outlived the
		// disconnect (or Vault returned nothing for another reason). We
		// can't act on this event; ack 200 so Strava stops retrying.
		return new Response('OK');
	}

	let accessToken = tokenRow.access_token as string;
	if (tokenRow.token_expiry) {
		const expiryMs = new Date(tokenRow.token_expiry as string).getTime();
		if (Date.now() + 300_000 > expiryMs) {
			const refreshed = await refreshStravaToken(
				supabase,
				userId,
				tokenRow.refresh_token as string,
			);
			if (refreshed) accessToken = refreshed;
		}
	}

	const fetchResult = await fetchStravaActivity(accessToken, activityId);
	if (fetchResult.status === 'rate_limited') {
		// Strava returned 429 / 503 on the detail fetch. We need to
		// signal Strava to retry (Strava retries up to 3 attempts on
		// non-200), but the `webhook_events` dedupe row was inserted
		// at line 137-146 — a retry with the same payload would hit
		// the 23505 path and silently 200 ok-skipped, dropping the
		// activity. So delete the dedupe row before returning 500 so
		// the retry path actually re-fetches.
		const { error: undoErr } = await supabase
			.from('webhook_events')
			.delete()
			.eq('provider', 'strava')
			.eq('event_id', eventId);
		if (undoErr) {
			console.error('strava-webhook: failed to roll back dedupe row before retry', undoErr?.message ?? String(undoErr));
		}
		return Response.json({ error: 'upstream_rate_limited' }, { status: 500 });
	}
	if (fetchResult.status === 'not_found') {
		// Activity vanished between webhook + fetch (deleted within
		// seconds, very unusual but possible). 200 prevents retries.
		return new Response('OK');
	}
	const activity = fetchResult.activity;

	// Drop activities Strava records but we don't surface — rides etc.
	// `ingestActivity` itself doesn't filter, so the gate lives here.
	const sportLower = (activity.sport_type ?? activity.type ?? '').toLowerCase();
	if (
		!sportLower.includes('run') &&
		!sportLower.includes('walk') &&
		!sportLower.includes('hike')
	) {
		return new Response('OK');
	}

	try {
		await ingestActivity(supabase, userId, accessToken, activity);
	} catch (err) {
		// Log but ack 200 so Strava doesn't retry — a retried import
		// would create a duplicate before the dedupe can catch it.
		// Log the message only — Postgrest `err.details` / `err.hint`
		// can leak schema-adjacent data into the log aggregator.
		// /audit/all edge-functions Low.
		console.error('strava-webhook ingest failed', {
			alert: 'strava_ingest_failure',
			activityId,
			userId,
			error: err instanceof Error ? err.message : String(err),
		});
		// audit/strava May 2026 Low #4 — surface to Sentry with an
		// explicit tag so dashboards light up. The `withSentry`
		// wrapper catches throws from the handler body; this
		// `try/catch` swallows BEFORE the wrapper sees, so we need
		// to capture explicitly.
		Sentry.captureException(err instanceof Error ? err : new Error(String(err)), {
			tags: { alert: 'strava_ingest_failure' },
			extra: { activityId, userId },
		});
	}

	return new Response('OK');
}));

