/// Donation checkout for a charity fundraiser (fundraising.md).
///
/// Validates, then opens a Stripe-hosted Checkout Session as a DESTINATION
/// charge against the fundraiser OWNER's connected account, and inserts a
/// `pending` donations row (service role). The shared stripe-events webhook
/// confirms the donation (CAS pending->paid) on checkout.session.completed.
///
/// Validation gates (each fails closed):
///   - the fundraiser exists, is visible to the caller, and is `status='open'`,
///   - the owner has a charges-enabled payout account (else 409),
///   - the amount is within sane bounds (100..1_000_000 cents).
///
/// Unlike events-checkout, the donor MAY be anonymous — a donation has no seat,
/// so no JWT is required. If a JWT is present it's attributed (donor_user_id);
/// a logged-out stranger donates fine.
///
/// PCI: Checkout is fully Stripe-hosted — SAQ A. No card form here.
/// Idempotency: the caller mints one `idempotency_key` per donation attempt and
/// re-sends it on a retry. It is persisted as `donations.client_request_id`
/// (unique), so a retry resolves to the pending donation the first attempt
/// opened and rebuilds byte-identical Stripe params against it — Stripe then
/// replays the session already open rather than charging the donor twice. The
/// key HAS to come from the client: a donor may be anonymous, so the server has
/// no identity to reconstruct one from, and repeat giving is legitimate so the
/// amount is not a natural key either. decisions § 776.
///
/// GATING: live charges require operator sk_live_ keys (default unset → 503
/// stripe_not_configured) AND owner+CISO+counsel sign-off. TEST MODE ONLY in
/// P1: STRIPE_SECRET_KEY must be an sk_test_ key. See decisions.md §166.

import Stripe, {
  type AssertNoUnknownParamKeys,
  type UnknownParamKeys,
} from '../_shared/stripe.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database } from '../_shared/database.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { isValidUuid } from '../_shared/input_validation.ts';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { validateReturnUrl } from '../events-connect-onboard/lib.ts';
import {
  buildDonationSessionParams,
  clampText,
  computeApplicationFeeCents,
  type DonationIntentRow,
  donationIdempotencyKey,
  MAX_DISPLAY_NAME_LEN,
  MAX_MESSAGE_LEN,
  resolveDonationIntent,
  validateDonationAmount,
} from './lib.ts';
import { publishableKey, secretKey } from '../_shared/api_keys.ts';
import { parseRedirectAllowlist } from '../_shared/redirect_allowlist.ts';

/// Every key of the hand-shaped params must be one Stripe declares.
/// Assignability at the call site does not check that: what is handed to
/// `create` is a function return, not a fresh object literal, so no
/// excess-property check runs and a misspelled optional field would
/// compile and come back from Stripe as `Received unknown parameter`.
/// Nothing references the alias — declaring it is the check.
type DonationParamsAreStripeParams = AssertNoUnknownParamKeys<
  UnknownParamKeys<
    ReturnType<typeof buildDonationSessionParams>,
    Stripe.Checkout.SessionCreateParams
  >
>;

interface DonationBody {
  fundraiser_id?: string;
  idempotency_key?: string;
  amount_cents?: number;
  display_name?: string;
  message?: string;
  is_anonymous?: boolean;
  success_url?: string;
  cancel_url?: string;
}

Deno.serve(withSentry('donations-checkout', async (req: Request) => {
  if (req.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY');
  if (!stripeSecretKey) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }
  const allowlist = parseRedirectAllowlist(Deno.env.get('STRIPE_EVENTS_ALLOWED_REDIRECTS'));
  if (allowlist.length === 0) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }

  const guarded = await readJsonWithLimit<DonationBody>(req, 4 * 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;
  const body = guarded.body ?? {};

  const fundraiserId = typeof body.fundraiser_id === 'string' ? body.fundraiser_id : null;
  if (!fundraiserId) {
    return Response.json({ error: 'missing_fundraiser' }, { status: 400 });
  }
  // Checked before the rate limit below so a malformed id can neither
  // 500 on the `.eq('id', …)` cast nor burn an anon bucket slot.
  if (!isValidUuid(fundraiserId)) {
    return Response.json({ error: 'invalid_fundraiser' }, { status: 400 });
  }
  // Checked here for the same reason as the fundraiser id above: a malformed
  // key must not burn an anon bucket slot. Required rather than optional — the
  // whole donation surface is gated off in prod (PUBLIC_FUNDRAISING_ENABLED
  // unset + no Stripe keys), so there is no deployed caller to keep working,
  // and an optional dedupe key is one an omission silently disables.
  const idempotencyKey = typeof body.idempotency_key === 'string' ? body.idempotency_key : null;
  if (!idempotencyKey || !isValidUuid(idempotencyKey)) {
    return Response.json({ error: 'invalid_idempotency_key' }, { status: 400 });
  }
  const amountOutcome = validateDonationAmount(body.amount_cents);
  if (amountOutcome !== 'ok') {
    return Response.json({ error: `amount_${amountOutcome}` }, { status: 400 });
  }
  const amountCents = body.amount_cents as number;

  // The donor MAY be anonymous. If a JWT is present, attribute the donation;
  // otherwise donor_user_id stays null. Either way the visibility read is done
  // as the caller (anon or user) so a private-anchor fundraiser is unreachable.
  const authHeader = req.headers.get('Authorization');
  const anonKey = publishableKey();
  const callerClient = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    anonKey,
    authHeader ? { global: { headers: { Authorization: authHeader } } } : undefined,
  );
  let donorUserId: string | null = null;
  if (authHeader) {
    const { data: { user } } = await callerClient.auth.getUser();
    donorUserId = user?.id ?? null;
  }

  const service = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    secretKey(),
  );

  // Rate-limit before any DB read or the Stripe session create. The donor path
  // is intentionally anonymous, so a logged-out attacker could otherwise spam
  // pending Checkout-session creation against the platform Stripe account (each
  // call is a Stripe API round-trip + a `donations` insert). Authenticated
  // donors get a per-user bucket; anon donors share a per-IP bucket via the
  // service-role client (the user-context guard rejects synthetic IP-derived
  // keys). Fail-closed — this abuse surface must not open up on a rate-limit
  // RPC blip. Mirrors clip-public-track's anon path. /audit/cost-controls Medium.
  if (donorUserId) {
    const denied = await checkRateLimit(
      callerClient, donorUserId, 'donations-checkout', 30, 3600, { failClosed: true },
    );
    if (denied) return denied;
  } else {
    const anonKey = await ipBucketKey(req);
    const denied = await checkRateLimit(
      service, anonKey, 'donations-checkout:anon', 10, 3600, { failClosed: true },
    );
    if (denied) return denied;
  }

  // Visibility gate AS THE CALLER (RLS): a fundraiser on a non-visible anchor
  // reads as not-found. The fundraisers SELECT policy returns the row only when
  // the anchor is publicly visible (or the caller owns it).
  const { data: visible, error: visibleErr } = await callerClient
    .from('fundraisers')
    .select('id, status')
    .eq('id', fundraiserId)
    .maybeSingle();
  if (visibleErr) {
    console.error('fundraiser visibility read failed (code):', visibleErr?.code ?? 'unknown');
    return Response.json({ error: 'checkout_failed' }, { status: 500 });
  }
  if (!visible) {
    return Response.json({ error: 'fundraiser_not_found' }, { status: 404 });
  }
  if (visible.status !== 'open') {
    return Response.json({ error: 'fundraiser_closed' }, { status: 409 });
  }

  // The gating columns (owner_user_id is revoked from client roles) are read
  // via the service role, scoped to the already-visibility-checked fundraiser.
  const { data: fundraiser, error: frErr } = await service
    .from('fundraisers')
    .select('owner_user_id, charity_name, title, currency, platform_fee_bps')
    .eq('id', fundraiserId)
    .maybeSingle();
  if (frErr || !fundraiser) {
    console.error('fundraiser detail read failed (code):', frErr?.code ?? 'missing');
    return Response.json({ error: 'checkout_failed' }, { status: 500 });
  }
  const ownerUserId = fundraiser.owner_user_id as string;

  // Owner capability — block a charge the owner can't receive.
  const { data: canTake, error: canTakeErr } = await service.rpc(
    'host_can_take_payment',
    { p_user_id: ownerUserId },
  );
  if (canTakeErr) {
    console.error('host_can_take_payment failed (code):', canTakeErr?.code ?? 'unknown');
    return Response.json({ error: 'checkout_failed' }, { status: 500 });
  }
  if (canTake !== true) {
    return Response.json({ error: 'owner_cannot_take_payment' }, { status: 409 });
  }
  const { data: ownerAccount, error: ownerAccountErr } = await service
    .from('instructor_payout_accounts')
    .select('stripe_connect_account_id')
    .eq('user_id', ownerUserId)
    .maybeSingle();
  if (ownerAccountErr || !ownerAccount?.stripe_connect_account_id) {
    console.error('owner account read failed (code):', ownerAccountErr?.code ?? 'missing');
    return Response.json({ error: 'owner_cannot_take_payment' }, { status: 409 });
  }
  const ownerAccountId = ownerAccount.stripe_connect_account_id as string;

  const currency = (fundraiser.currency as string) ?? 'usd';
  const platformFeeBps = (fundraiser.platform_fee_bps as number) ?? 0;
  const applicationFee = computeApplicationFeeCents(amountCents, platformFeeBps);
  const isAnonymous = body.is_anonymous === true;
  const displayName = isAnonymous ? null : clampText(body.display_name, MAX_DISPLAY_NAME_LEN);
  const message = clampText(body.message, MAX_MESSAGE_LEN);

  // Resolve the caller's key to the donation it already opened, if any. Read
  // before the Stripe call so a retry rebuilds the same params against the same
  // row and Stripe replays rather than opening a second session.
  const { data: existing, error: existingErr } = await service
    .from('donations')
    .select('id, status, fundraiser_id, amount_cents, donor_user_id')
    .eq('client_request_id', idempotencyKey)
    .maybeSingle();
  if (existingErr) {
    console.error('donation idempotency read failed (code):', existingErr?.code ?? 'unknown');
    return Response.json({ error: 'checkout_failed' }, { status: 500 });
  }
  const intent = resolveDonationIntent((existing ?? null) as DonationIntentRow | null, {
    fundraiserId,
    amountCents,
    donorUserId,
  });
  if (intent.action === 'conflict') {
    return Response.json({ error: `idempotency_${intent.reason}` }, { status: 409 });
  }

  // Persist BEFORE the Stripe call, so a crash between the two is repairable:
  // the retry finds this row by its key, rebuilds the same params, and Stripe
  // replays the session. Writing the row afterwards left the only record of the
  // attempt at Stripe, where the next call could not find it. Mirrors
  // events-checkout, which persists its pending order the same way and repairs
  // the session id on the next attempt.
  let donationId: string;
  if (intent.action === 'resume') {
    donationId = intent.donationId;
  } else {
    donationId = crypto.randomUUID();
    const { error: insErr } = await service
      .from('donations')
      .insert({
        id: donationId,
        client_request_id: idempotencyKey,
        fundraiser_id: fundraiserId,
        donor_user_id: donorUserId,
        owner_user_id: ownerUserId,
        display_name: displayName,
        message,
        amount_cents: amountCents,
        currency,
        platform_fee_cents: applicationFee,
        status: 'pending',
        is_anonymous: isAnonymous,
      });
    if (insErr) {
      // 23505 on the unique key: a concurrent attempt with the same key won the
      // race. It opened the donation this call would have, so answer 409 and
      // let the client retry onto the row that now exists rather than opening a
      // second one against a fresh id.
      if (insErr.code === '23505') {
        return Response.json({ error: 'idempotency_in_progress' }, { status: 409 });
      }
      console.error('donation insert failed (code):', insErr?.code ?? 'unknown');
      return Response.json({ error: 'checkout_failed' }, { status: 500 });
    }
  }

  const successUrl = body.success_url && validateReturnUrl(body.success_url, allowlist)
    ? body.success_url
    : `${new URL(allowlist[0]).origin}/fundraisers/${fundraiserId}?donated=1`;
  const cancelUrl = body.cancel_url && validateReturnUrl(body.cancel_url, allowlist)
    ? body.cancel_url
    : `${new URL(allowlist[0]).origin}/fundraisers/${fundraiserId}?donated=0`;

  const stripe = new Stripe(stripeSecretKey, {
    httpClient: Stripe.createFetchHttpClient(),
  });

  let session;
  try {
    session = await stripe.checkout.sessions.create(
      buildDonationSessionParams({
        amountCents,
        currency,
        productName: `Donation: ${(fundraiser.charity_name as string) ?? 'Charity'}`,
        applicationFeeCents: applicationFee,
        ownerAccountId,
        successUrl,
        cancelUrl,
        metadata: {
          kind: 'donation',
          donation_id: donationId,
          fundraiser_id: fundraiserId,
        },
      }),
      { idempotencyKey: donationIdempotencyKey(donationId) },
    );
  } catch (e) {
    console.error('stripe donation checkout create failed:', e instanceof Error ? e.message : 'unknown');
    return Response.json({ error: 'stripe_checkout_failed' }, { status: 502 });
  }

  // Attach the session to the row. Also the repair path: a first attempt that
  // died between the Stripe create and this write left the row session-less,
  // and the retry lands here with the replayed session. The three presentation
  // fields ride along so a resumed attempt keeps the donor's LATEST name and
  // message rather than the abandoned attempt's — they are not part of what
  // `resolveDonationIntent` compares precisely because they do not change the
  // charge. Still CAS'd on `pending` so a confirmed donation can never have its
  // session or its feed entry rewritten.
  const { error: sessionErr } = await service
    .from('donations')
    .update({
      stripe_checkout_session_id: session.id,
      display_name: displayName,
      message,
      is_anonymous: isAnonymous,
    })
    .eq('id', donationId)
    .eq('status', 'pending');
  if (sessionErr) {
    console.error('donation session attach failed (code):', sessionErr?.code ?? 'unknown');
    return Response.json({ error: 'checkout_failed' }, { status: 500 });
  }

  return Response.json({ checkout_url: session.url, donation_id: donationId });
}));
