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

import Stripe, {
  type AssertNoUnknownParamKeys,
  type UnknownParamKeys,
} from '../_shared/stripe.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database } from '../_shared/database.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import {
  type AccountCreateParams,
  type AccountLinkParams,
  buildAccountCreateParams,
  buildAccountLinkParams,
  validateReturnUrl,
} from './lib.ts';
import { publishableKey, secretKey } from '../_shared/api_keys.ts';
import { parseRedirectAllowlist } from '../_shared/redirect_allowlist.ts';

/// Every key of the hand-shaped params must be one Stripe declares.
/// Assignability at the call site does not check that: what is handed to
/// `create` is a function return, not a fresh object literal, so no
/// excess-property check runs and a misspelled optional field would
/// compile and come back from Stripe as `Received unknown parameter`.
/// Nothing references the alias — declaring it is the check.
type AccountParamsAreStripeParams = AssertNoUnknownParamKeys<
  UnknownParamKeys<AccountCreateParams, Stripe.AccountCreateParams>
>;
type AccountLinkParamsAreStripeParams = AssertNoUnknownParamKeys<
  UnknownParamKeys<AccountLinkParams, Stripe.AccountLinkCreateParams>
>;

Deno.serve(withSentry('events-connect-onboard', async (req: Request) => {
  if (req.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY');
  if (!stripeSecretKey) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }

  // Allowlist the return/refresh origins, the strava-import precedent.
  // Fail closed when unset — a missed `supabase secrets set` must not
  // silently allow an open-redirect target.
  const allowlist = parseRedirectAllowlist(Deno.env.get('STRIPE_EVENTS_ALLOWED_REDIRECTS'));
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
  const userClient = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    publishableKey(),
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }

  // OAuth-grade path: fail closed on rate-limit RPC error so a DB blip
  // can't let an attacker spray account-create churn.
  const service = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    secretKey(),
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

  const stripe = new Stripe(stripeSecretKey, {
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

  // The column is nullable, so the row can exist with no account attached yet
  // (a create that failed after the upsert). `null` and "no row" are the same
  // case here — both mean "create one" — but they are not the same as a cast
  // to `string | undefined`, which is what this used to be: it erased the null
  // the read can actually return, and every later use read as a string that
  // was not one.
  let accountId = existing?.stripe_connect_account_id ?? null;

  if (accountId === null) {
    let account: Stripe.Account;
    try {
      account = await stripe.accounts.create(
        buildAccountCreateParams(body.country ?? null, null),
        // Keyed on the host, because a host has exactly one payout account
        // (`instructor_payout_accounts.user_id`). Unkeyed, an attempt that
        // created the account and then failed to persist it — a lost response,
        // a failed upsert, a second click — created a SECOND Stripe account on
        // the retry and abandoned the first, live and unreachable, on the
        // platform. The rate limit put the ceiling at eight of those per host
        // per hour.
        { idempotencyKey: `events-connect-onboard:${user.id}` },
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

  // No idempotency key on the LINK, deliberately: an account link is
  // single-use and short-lived, so replaying the first one hands a host
  // returning to finish their onboarding a URL that Stripe has already spent.
  // A fresh link per call is the correct answer here and a duplicate costs
  // nothing.
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
