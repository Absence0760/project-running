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
/// Idempotency: the Stripe create call carries a stable key derived from the
/// server-generated donation row id.
///
/// GATING: live charges require operator sk_live_ keys (default unset → 503
/// stripe_not_configured) AND owner+CISO+counsel sign-off. TEST MODE ONLY in
/// P1: STRIPE_SECRET_KEY must be an sk_test_ key. See decisions.md §166.

import Stripe from 'https://esm.sh/stripe@17.5.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { validateReturnUrl } from '../events-connect-onboard/lib.ts';
import {
  buildDonationSessionParams,
  clampText,
  computeApplicationFeeCents,
  donationIdempotencyKey,
  MAX_DISPLAY_NAME_LEN,
  MAX_MESSAGE_LEN,
  validateDonationAmount,
} from './lib.ts';

interface DonationBody {
  fundraiser_id?: string;
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

  const secretKey = Deno.env.get('STRIPE_SECRET_KEY');
  if (!secretKey) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }
  const allowlist = (Deno.env.get('STRIPE_EVENTS_ALLOWED_REDIRECTS') ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
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
  const amountOutcome = validateDonationAmount(body.amount_cents);
  if (amountOutcome !== 'ok') {
    return Response.json({ error: `amount_${amountOutcome}` }, { status: 400 });
  }
  const amountCents = body.amount_cents as number;

  // The donor MAY be anonymous. If a JWT is present, attribute the donation;
  // otherwise donor_user_id stays null. Either way the visibility read is done
  // as the caller (anon or user) so a private-anchor fundraiser is unreachable.
  const authHeader = req.headers.get('Authorization');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const callerClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    anonKey,
    authHeader ? { global: { headers: { Authorization: authHeader } } } : undefined,
  );
  let donorUserId: string | null = null;
  if (authHeader) {
    const { data: { user } } = await callerClient.auth.getUser();
    donorUserId = user?.id ?? null;
  }

  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

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

  // Generate the row id server-side before the Stripe call so the idempotency
  // key + the session metadata both reference it.
  const donationId = crypto.randomUUID();

  const successUrl = body.success_url && validateReturnUrl(body.success_url, allowlist)
    ? body.success_url
    : `${new URL(allowlist[0]).origin}/fundraisers/${fundraiserId}?donated=1`;
  const cancelUrl = body.cancel_url && validateReturnUrl(body.cancel_url, allowlist)
    ? body.cancel_url
    : `${new URL(allowlist[0]).origin}/fundraisers/${fundraiserId}?donated=0`;

  const stripe = new Stripe(secretKey, {
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

  const { error: insErr } = await service
    .from('donations')
    .insert({
      id: donationId,
      fundraiser_id: fundraiserId,
      donor_user_id: donorUserId,
      owner_user_id: ownerUserId,
      display_name: displayName,
      message,
      stripe_checkout_session_id: session.id,
      amount_cents: amountCents,
      currency,
      platform_fee_cents: applicationFee,
      status: 'pending',
      is_anonymous: isAnonymous,
    });
  if (insErr) {
    console.error('donation insert failed (code):', insErr?.code ?? 'unknown');
    return Response.json({ error: 'checkout_failed' }, { status: 500 });
  }

  return Response.json({ checkout_url: session.url, donation_id: donationId });
}));
