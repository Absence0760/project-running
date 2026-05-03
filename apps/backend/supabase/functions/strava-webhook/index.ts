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

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
	fetchStravaActivity,
	ingestActivity,
	isAlreadyImported,
	refreshStravaToken,
} from '../_shared/strava.ts';
import { enforceBodyLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';

serve(withSentry('strava-webhook', async (req: Request) => {
	// Strava activity event payloads are tiny — a few hundred bytes
	// of identifiers + state — but cap at 4 KB so a malicious caller
	// who guessed the URL secret can't force a multi-MB allocation.
	if (req.method === 'POST') {
		const tooBig = enforceBodyLimit(req, 4096);
		if (tooBig) return tooBig;
	}

	const webhookSecret = Deno.env.get('STRAVA_WEBHOOK_SECRET');
	if (!webhookSecret) {
		return new Response('Webhook not configured', { status: 503 });
	}

	const url = new URL(req.url);
	const suppliedSecret = url.searchParams.get('secret');
	if (!suppliedSecret || !timingSafeEqual(suppliedSecret, webhookSecret)) {
		return new Response('Forbidden', { status: 403 });
	}

	// GET: Strava webhook subscription handshake.
	if (req.method === 'GET') {
		const challenge = url.searchParams.get('hub.challenge');
		const verifyToken = url.searchParams.get('hub.verify_token');

		if (verifyToken !== Deno.env.get('STRAVA_VERIFY_TOKEN')) {
			return new Response('Forbidden', { status: 403 });
		}

		return Response.json({ 'hub.challenge': challenge });
	}

	if (req.method !== 'POST') {
		return new Response('Method not allowed', { status: 405 });
	}

	// POST: Activity event from Strava. Payload shape:
	//   { object_type, object_id, aspect_type, owner_id, subscription_id,
	//     event_time, updates }
	// We only handle 'activity' / 'create' — updates and deletes are
	// ignored (the backfill picks up edits on the next manual sync).
	let event: {
		object_type?: string;
		object_id?: number;
		aspect_type?: string;
		owner_id?: number;
		event_time?: number;
	};
	try {
		event = await req.json();
	} catch (_) {
		return new Response('Invalid JSON', { status: 400 });
	}

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
		return new Response('Missing object_id or owner_id', { status: 400 });
	}
	if (typeof eventTime !== 'number') {
		return new Response('Missing event_time', { status: 400 });
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
	// REPLAY_WINDOW_MS must be wider than Strava's retry envelope
	// (hours) and narrower than the dedupe-row TTL (30 days). 7 days
	// matches revenuecat-webhook for one-knob consistency.
	const REPLAY_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
	const CLOCK_SKEW_MS = 60 * 1000;
	const ageMs = Date.now() - eventTime * 1000;
	if (ageMs > REPLAY_WINDOW_MS || ageMs < -CLOCK_SKEW_MS) {
		return new Response('Event outside freshness window', { status: 400 });
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
		console.error('Webhook dedupe insert failed:', dedupeErr);
		return Response.json({ ok: false, error: 'dedupe failed' }, { status: 500 });
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

	const activity = await fetchStravaActivity(accessToken, activityId);
	if (!activity) {
		// Activity vanished between webhook + fetch (deleted within
		// seconds, very unusual but possible). 200 prevents retries.
		return new Response('OK');
	}

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
		console.error('strava-webhook ingest failed', { activityId, userId, err });
	}

	return new Response('OK');
}));

/// Constant-time string compare so an attacker can't tease out the
/// secret one character at a time via response-timing differences.
/// Returns false on length mismatch without short-circuiting on
/// content (the length check itself is observable, but that's the
/// length of the secret which is fixed and known to anyone who reads
/// this source, not new information).
function timingSafeEqual(a: string, b: string): boolean {
	if (a.length !== b.length) return false;
	let mismatch = 0;
	for (let i = 0; i < a.length; i++) {
		mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
	}
	return mismatch === 0;
}
