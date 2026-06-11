/// Stripe Connect onboarding for an event host (club_events.md slice P1).
///
/// A host who wants to charge for an event onboards ONCE here:
///   1. We create (or reuse) a Stripe Express connected account for the
///      host and persist its id in instructor_payout_accounts.
///   2. We create a hosted Account Link (account_onboarding) and return
///      its URL; the host completes KYC / bank / tax on Stripe's pages.
/// Their charges_enabled flag flips later via the account.updated webhook
/// (stripe-events-webhook) — never written here.
///
/// Auth: JWT-gated (config.toml default verify_jwt = true), so the
/// platform gateway 401s an anonymous caller before this body runs. We
/// re-derive the user via auth.getUser() and operate ONLY on their own
/// instructor_payout_accounts row, via the service role (the row has no
/// client write policy — the EF + webhook are its sole writers).
///
/// PCI: onboarding is fully Stripe-hosted (Account Links). No card data,
/// no banking data touches us — SAQ A. Hard constraint.
///
/// TEST MODE ONLY in P1: STRIPE_SECRET_KEY must be an sk_test_ key. The
/// function fails closed (503) when Stripe is unconfigured.

import Stripe from 'https://esm.sh/stripe@17.5.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import {
  buildAccountCreateParams,
  buildAccountLinkParams,
  validateReturnUrl,
} from './lib.ts';

Deno.serve(withSentry('events-connect-onboard', async (req: Request) => {
  if (req.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  const secretKey = Deno.env.get('STRIPE_SECRET_KEY');
  if (!secretKey) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }

  // Allowlist the return/refresh origins, the strava-import precedent.
  // Fail closed when unset — a missed `supabase secrets set` must not
  // silently allow an open-redirect target.
  const allowlist = (Deno.env.get('STRIPE_EVENTS_ALLOWED_REDIRECTS') ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  if (allowlist.length === 0) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }

  // The body is small (optional return_url/refresh_url override); 4 KB is
  // a generous ceiling.
  const guarded = await readJsonWithLimit<{
    return_url?: string;
    refresh_url?: string;
    country?: string;
  }>(req, 4 * 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;
  const body = guarded.body ?? {};

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }
  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }

  // OAuth-grade path: fail closed on rate-limit RPC error so a DB blip
  // can't let an attacker spray account-create churn.
  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  const denied = await checkRateLimit(
    service,
    user.id,
    'events-connect-onboard',
    8,
    3600,
    { failClosed: true },
  );
  if (denied) return denied;

  // Resolve the return/refresh URLs. A client may suggest them, but they
  // must clear the allowlist; otherwise fall back to the first allowed
  // origin's /settings/payouts.
  const defaultOrigin = new URL(allowlist[0]).origin;
  const returnUrl = body.return_url && validateReturnUrl(body.return_url, allowlist)
    ? body.return_url
    : `${defaultOrigin}/settings/payouts?onboard=return`;
  const refreshUrl = body.refresh_url && validateReturnUrl(body.refresh_url, allowlist)
    ? body.refresh_url
    : `${defaultOrigin}/settings/payouts?onboard=refresh`;

  const stripe = new Stripe(secretKey, {
    httpClient: Stripe.createFetchHttpClient(),
  });

  // Read-or-create the host's payout account row (own row, service role).
  const { data: existing, error: readErr } = await service
    .from('instructor_payout_accounts')
    .select('user_id, stripe_connect_account_id')
    .eq('user_id', user.id)
    .maybeSingle();
  if (readErr) {
    console.error('payout account read failed (code):', readErr?.code ?? 'unknown');
    return Response.json({ error: 'onboard_failed' }, { status: 500 });
  }

  let accountId = existing?.stripe_connect_account_id as string | undefined;

  if (!accountId) {
    let account;
    try {
      account = await stripe.accounts.create(
        buildAccountCreateParams(body.country ?? null, null),
      );
    } catch (e) {
      console.error('stripe account create failed:', e instanceof Error ? e.message : 'unknown');
      return Response.json({ error: 'stripe_account_create_failed' }, { status: 502 });
    }
    accountId = account.id;
    const { error: upsertErr } = await service
      .from('instructor_payout_accounts')
      .upsert({
        user_id: user.id,
        stripe_connect_account_id: accountId,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id' });
    if (upsertErr) {
      console.error('payout account upsert failed (code):', upsertErr?.code ?? 'unknown');
      return Response.json({ error: 'onboard_failed' }, { status: 500 });
    }
  }

  let link;
  try {
    link = await stripe.accountLinks.create(
      buildAccountLinkParams(accountId, returnUrl, refreshUrl),
    );
  } catch (e) {
    console.error('stripe account link failed:', e instanceof Error ? e.message : 'unknown');
    return Response.json({ error: 'stripe_account_link_failed' }, { status: 502 });
  }

  return Response.json({ url: link.url });
}));
