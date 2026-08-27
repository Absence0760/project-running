import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database } from '../_shared/database.ts';
import { discardBody } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { timingSafeEqual } from '../_shared/webhook_security.ts';
import { refreshExpiringStravaTokens } from './lib.ts';
import { secretKey } from '../_shared/api_keys.ts';

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

  const supabase = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    secretKey(),
  );

  const { refreshed } = await refreshExpiringStravaTokens(supabase);
  return Response.json({ refreshed });
}));
