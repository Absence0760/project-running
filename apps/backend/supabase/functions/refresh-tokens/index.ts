import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database } from '../_shared/database.ts';
import { discardBody } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { timingSafeEqual } from '../_shared/webhook_security.ts';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
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
///
/// Three defences now, matching `strava-webhook` on two of them and
/// deliberately differing on the third: the 32-character floor on the
/// secret (§ 937), the timing-safe compare, and an IP-keyed bucket
/// spent ONLY on a failed compare rather than in front of it (§ 973).
/// `gate_invariants.test.ts` pins all three, including the divergence.

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
  // Same 32-char floor strava-webhook carries, and for the same reason: a
  // timing-safe compare closes the per-byte channel but does nothing about a
  // secret short enough to guess offline, and the case that actually happens
  // is a misconfigured deploy (`CRON_SECRET=test`). This function is
  // `verify_jwt = false`, so the bearer is the only gate in front of a loop
  // over the whole `integrations` table against Strava's OAuth endpoint.
  // A short secret is a misconfiguration, not an attack, so it answers the
  // same `cron_not_configured` 503 as an absent one rather than 403 — a
  // deployer reading the log learns the config is wrong, and a caller learns
  // nothing about the secret's length either way.
  if (cronSecret.length < 32) {
    return Response.json({ error: 'cron_not_configured' }, { status: 503 });
  }
  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token || !timingSafeEqual(token, cronSecret)) {
    // An IP-keyed bucket spent ONLY on a supplied bearer that did not match —
    // the one place this function deliberately diverges from `strava-webhook`,
    // which limits BEFORE its secret check. Copying that here would have been
    // the wrong shape twice over.
    //
    // In front of the compare: `ipBucketKey` collapses every caller the trusted
    // header does not identify into one shared `unknown` bucket, nothing
    // establishes that pg_cron's invocation carries `cf-connecting-ip`, and a
    // limiter there would therefore let an attacker starve the hourly token
    // refresh out of a bucket they share with it. Behind it, the authorised
    // path acquires no database dependency at all.
    //
    // And on a request carrying no bearer: that is not a guess at the secret,
    // it is a probe, so counting it would spend a `rate_limits` write on the
    // cheapest request an attacker can generate while crowding out the guesses
    // the ceiling exists to bound. The empty POST keeps its zero-cost 403.
    //
    // Fail-closed costs nothing here, which is why it is not a judgement call:
    // this branch refuses either way, so the "false denial during a DB blip"
    // the fail-open default exists to avoid cannot happen — the caller gets a
    // 503 instead of a 403 and is refused in both (decisions § 973).
    if (token) {
      const admin = createClient<Database>(
        Deno.env.get('SUPABASE_URL')!,
        secretKey(),
      );
      const denied = await checkRateLimit(
        admin,
        await ipBucketKey(req),
        'refresh-tokens:anon',
        60,
        3600,
        { failClosed: true },
      );
      if (denied) return denied;
    }
    return Response.json({ error: 'forbidden' }, { status: 403 });
  }

  const supabase = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    secretKey(),
  );

  const { refreshed } = await refreshExpiringStravaTokens(supabase);
  return Response.json({ refreshed });
}));
