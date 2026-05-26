import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import { discardBody } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { timingSafeEqual } from '../_shared/webhook_security.ts';

/// pg_cron schedules this function on the hour; the cron job invokes
/// it with `Authorization: Bearer ${CRON_SECRET}`. Without the gate
/// the function URL is publicly invokable — any attacker hitting it
/// would loop the entire `integrations` table through Strava's OAuth
/// refresh endpoint, burning Strava API quota and forcing token
/// churn. The secret is shared between the cron job config and the
/// EF env. Timing-safe compare so a missed-character probe can't
/// tease the secret out byte-by-byte — shared with the webhook
/// path via _shared/webhook_security.ts to avoid divergence on a
/// future hardening pass (audit/auth 2026-05-25).

Deno.serve(withSentry('refresh-tokens', async (req: Request) => {
  // No body input — drop the stream before the auth check so a caller
  // that POST-streams a chunked body can't hold the connection open
  // until the runtime timeout. The Go service equivalent already
  // does this; the EF was the lone outlier (audit/edge-functions
  // 2026-05-25 Medium).
  discardBody(req);

  const cronSecret = Deno.env.get('CRON_SECRET');
  if (!cronSecret) {
    // Fail-closed when misconfigured. Same posture as strava-webhook.
    return Response.json({ error: 'cron_not_configured' }, { status: 503 });
  }
  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token || !timingSafeEqual(token, cronSecret)) {
    return Response.json({ error: 'forbidden' }, { status: 403 });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Find Strava integrations with tokens expiring within 1 hour. The
  // `id, user_id` projection used to also pull `refresh_token`; tokens
  // now live in Vault, accessed via `get_integration_tokens`.
  // Explicit `.order().limit()` so a future PostgREST default-row
  // bump doesn't blow this up — at 500 rows × ~1s/Strava-refresh we
  // stay well under the 150s function timeout, and the next cron
  // tick handles the remainder.
  const { data: expiring } = await supabase
    .from('integrations')
    .select('id, user_id')
    .eq('provider', 'strava')
    .lt('token_expiry', new Date(Date.now() + 3600_000).toISOString())
    .order('token_expiry', { ascending: true })
    .limit(500);

  let refreshed = 0;

  for (const integration of expiring ?? []) {
    // Decrypt the existing refresh token through the SECURITY DEFINER
    // helper. Service role bypasses the owner check.
    const { data: tokenRows, error: tokenErr } = await supabase
      .rpc('get_integration_tokens', {
        p_user_id: integration.user_id,
        p_provider: 'strava',
      });
    if (tokenErr || !tokenRows || tokenRows.length === 0) continue;
    const refreshToken = tokenRows[0]?.refresh_token;
    if (!refreshToken) continue;

    const response = await fetch('https://www.strava.com/oauth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        client_id: Deno.env.get('STRAVA_CLIENT_ID'),
        client_secret: Deno.env.get('STRAVA_CLIENT_SECRET'),
        refresh_token: refreshToken,
        grant_type: 'refresh_token',
      }),
    });

    if (!response.ok) continue;

    const tokens = await response.json();

    // Round-trip the refreshed pair through the setter so the vault
    // entries get updated in place (secret_id stays stable). The
    // setter also writes token_expiry + updated_at on the row.
    const { error: setErr } = await supabase.rpc('set_integration_tokens', {
      p_user_id: integration.user_id,
      p_provider: 'strava',
      p_access_token: tokens.access_token,
      p_refresh_token: tokens.refresh_token,
      p_token_expiry: new Date(tokens.expires_at * 1000).toISOString(),
    });
    if (setErr) continue;

    refreshed++;
  }

  return Response.json({ refreshed });
}));
