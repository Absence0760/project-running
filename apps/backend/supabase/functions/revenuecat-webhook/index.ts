/// RevenueCat server-to-server webhook receiver.
///
/// RevenueCat fires events for INITIAL_PURCHASE, RENEWAL,
/// CANCELLATION, EXPIRATION, and more. We care about the transition
/// between "has an active entitlement" and "doesn't", and map that to
/// `user_profiles.subscription_tier`.
///
/// Auth: the webhook request is verified via HMAC (the shared secret is
/// the REVENUECAT_WEBHOOK_SECRET env var). The function runs with the
/// Supabase service role so it can update any user's tier.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { hmac } from 'https://deno.land/x/hmac@v2.0.1/mod.ts';

serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const secret = Deno.env.get('REVENUECAT_WEBHOOK_SECRET');
  if (!secret) {
    return new Response('Webhook not configured', { status: 503 });
  }

  // Verify HMAC signature.
  const body = await req.text();
  const sig = req.headers.get('x-revenuecat-hmac');
  if (sig) {
    const expected = hmac('sha256', secret, body, 'utf8', 'hex');
    if (sig !== expected) {
      return new Response('Bad signature', { status: 401 });
    }
  }

  let event: RevenueCatEvent;
  try {
    event = JSON.parse(body).event;
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  // The `app_user_id` RevenueCat sends is the Supabase user id — we
  // set it on the client when configuring the RevenueCat SDK.
  const userId = event.app_user_id;
  if (!userId || userId.startsWith('$RCAnonymousID')) {
    // Anonymous users can't map to a Supabase profile. This happens
    // when someone subscribes before signing in; RevenueCat will fire
    // another event when they log in and the alias resolves.
    return Response.json({ ok: true, skipped: 'anonymous_user' });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Map event type to a tier change. RevenueCat's event taxonomy:
  // https://www.revenuecat.com/docs/integrations/webhooks/event-types
  const activating = [
    'INITIAL_PURCHASE',
    'RENEWAL',
    'UNCANCELLATION',
    'NON_RENEWING_PURCHASE',
    'PRODUCT_CHANGE',
  ];
  const deactivating = [
    'EXPIRATION',
    'CANCELLATION',  // at the end of the billing period
  ];

  let newTier: string | null = null;

  if (activating.includes(event.type)) {
    // A non-renewing purchase with a product-id containing "lifetime"
    // maps to the `lifetime` tier rather than `pro`. Everything else
    // is monthly/annual → `pro`.
    const productId = event.product_id ?? '';
    newTier = productId.includes('lifetime') ? 'lifetime' : 'pro';
  } else if (deactivating.includes(event.type)) {
    // Only downgrade to `free` if the user doesn't have `lifetime`.
    // A lifetime holder might also have had a monthly sub for another
    // entitlement; cancelling that shouldn't reset them.
    const { data } = await supabase
      .from('user_profiles')
      .select('subscription_tier')
      .eq('id', userId)
      .single();
    if (data?.subscription_tier !== 'lifetime') {
      newTier = 'free';
    }
  }

  if (newTier !== null) {
    const { error } = await supabase
      .from('user_profiles')
      .update({ subscription_tier: newTier })
      .eq('id', userId);
    if (error) {
      console.error('Tier update failed:', error);
      return Response.json({ ok: false, error: error.message }, { status: 500 });
    }
  }

  return Response.json({ ok: true, new_tier: newTier });
});

interface RevenueCatEvent {
  type: string;
  app_user_id: string;
  product_id?: string;
  [key: string]: unknown;
}
