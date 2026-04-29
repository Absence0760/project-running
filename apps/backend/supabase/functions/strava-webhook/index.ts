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

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req: Request) => {
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

  // POST: Activity event from Strava.
  const { object_type, object_id: _object_id, aspect_type, owner_id } = await req.json();

  if (object_type !== 'activity' || aspect_type !== 'create') {
    return new Response('OK');
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Look up user by Strava athlete ID.
  const { data: integration } = await supabase
    .from('integrations')
    .select('user_id, access_token')
    .eq('provider', 'strava')
    .eq('external_id', String(owner_id))
    .single();

  if (!integration) {
    return new Response('User not found', { status: 404 });
  }

  // TODO: Fetch activity detail + GPS stream from Strava API
  // TODO: Map to Run and upsert into runs table

  return new Response('OK');
});

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
