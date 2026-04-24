# Paywall

## Current model: Pro subscription + optional donations

**Every feature is available to every signed-in user** — `isLocked()` in
`features.ts` always returns `false`, so no screen is hidden behind a
paywall. What the Pro tier changes is behaviour *inside* two features:

- **AI Coach.** Free users get 10 messages / day (cost-control for the
  Claude API bill). Pro users get no cap.
- **Priority processing.** Pro requests are routed ahead of free at
  rate-limit / queue boundaries. Today this is a marketing claim with
  enforcement limited to the coach-cap bypass; concrete enforcement
  (Edge Function priority, client throttle hints) lands over time.

`/settings/upgrade` shows a two-card layout: a Pro plan card
($9.99 / month, feature bullets, "Get Pro" CTA) and a one-off Donate
button that links to an external payment provider. The transparent
cost breakdown, monthly progress bars, donor count, and tiered
donation buttons that existed under the previous donations-only model
are gone — see [decisions.md § 23](decisions.md#23-pro-tier-reintroduced-at-999mo-alongside-one-off-donations).

The `monthly_funding` table stays in the schema (orphaned but not
dropped); reviving transparent funding later is a one-page revert.

## Tiers

| Tier | How you get it | What it unlocks |
|---|---|---|
| `free` | Default for every new account | Every feature. AI coach capped at 10 messages / day. Standard request priority. |
| `pro` | RevenueCat subscription ($9.99 / month) | Everything free users get + unlimited AI coach + priority processing. |
| `lifetime` | RevenueCat one-time purchase (not currently sold) | Same as `pro`. |

`user_profiles.subscription_tier` is the authoritative column. A CHECK
constraint enforces the three valid values. The `is_pro()` SQL helper
(and its `p_user_id uuid` variant `is_user_pro(uid)`) returns `true`
for both `pro` and `lifetime`.

## Pro perks and where they're enforced

| Perk | Feature key | Enforcement point |
|---|---|---|
| Unlimited AI Coach messages | `ai_coach` | Server: `/api/coach/+server.ts` calls `is_user_pro(uid)` before `increment_coach_usage` — the cap and 429 response only fire for free users. |
| Priority processing | `priority_processing` | Marketing claim today. Planned enforcement: tier-aware rate limiting on Edge Functions + Go service once it lands. The registry entry is documentation; no client code currently branches on it. |

These perks are **behaviour changes**, not gated screens, so they do
not call through `isLocked()`. `isLocked()` remains the correct hook
for a future feature that should be hidden entirely behind Pro (e.g.
"live spectator link") — flip it to return `!isPro()` for the key.

## Client-side `isPro()` helper

`apps/web/src/lib/features.ts` exports `isPro()` — reads the auth
store's cached `user_profiles.subscription_tier` and returns true for
`pro` / `lifetime`. Use it for conditional UI flourishes (a "Pro"
badge, a "Pro — unlimited" label next to the coach input). Never use
it as the sole check for anything expensive: always mirror the check
server-side with the `is_user_pro(uid)` RPC.

## Adding a new gated feature

1. **Register the feature.** Add an entry to `GATED_FEATURES` in
   `apps/web/src/lib/features.ts`:
   ```ts
   training_plans: {
     label: 'Training Plans',
     description: 'VDOT-based plan generation with ...',
   },
   ```

2. **Server-side gate.** In the endpoint or RPC that does the expensive
   work, check the user's tier before proceeding:
   ```ts
   // SvelteKit server endpoint
   const { data: profile } = await supabase
     .from('user_profiles')
     .select('subscription_tier')
     .eq('id', userId)
     .single();
   if (profile?.subscription_tier === 'free' && env.BYPASS_PAYWALL !== 'true') {
     return new Response(JSON.stringify({
       error: 'pro_required',
       feature: 'training_plans',
       message: 'Training Plans is a Pro feature.',
     }), { status: 403 });
   }
   ```
   Or in an Edge Function:
   ```ts
   const { data } = await supabase.rpc('is_user_pro', { p_user_id: userId });
   if (!data) return new Response('Pro required', { status: 403 });
   ```

3. **Client-side gate.** Wrap the UI entry point:
   ```svelte
   {#if isLocked('training_plans')}
     <ProGate feature="training_plans" />
   {:else}
     <ActualFeatureComponent />
   {/if}
   ```
   Import `isLocked` from `$lib/features` and `ProGate` from
   `$lib/components/ProGate.svelte`.

4. **Android gate.** In the Flutter app, read the tier from the
   profile and show a locked-state card:
   ```dart
   final tier = api.userProfile?.subscriptionTier ?? 'free';
   if (tier == 'free' && !dotenv.env['BYPASS_PAYWALL'] == 'true') {
     // Show upgrade prompt
   }
   ```

5. **Update this doc.** Add the feature to the "Gated features" table
   above with the exact `feature` key, label, and where it's gated.

## BYPASS_PAYWALL

Every surface reads a `BYPASS_PAYWALL` env flag. When set to `'true'`:

- Server endpoints skip the tier check.
- Client-side `isLocked()` could also be overridden, but today it reads
  the user's actual tier from the profile, so the way to bypass on the
  client during dev is to set the seed user's `subscription_tier` to
  `'pro'` in `seed.sql`.

This flag exists in:
- `apps/web/.env.example` → read by `+server.ts` endpoints via `$env/dynamic/private`
- `apps/mobile_android/.env.example` → read at build time via `flutter_dotenv`

Never set this flag in production.

## RevenueCat integration

### Server → Supabase (webhook)

`apps/backend/supabase/functions/revenuecat-webhook/index.ts` receives
events from RevenueCat's server-to-server webhook. On relevant events
(`INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `EXPIRATION`, etc.) it
updates `user_profiles.subscription_tier` for the `app_user_id` (which
must be set to the Supabase user id on the client SDK).

Webhook URL (configure in RevenueCat → Integrations → Webhooks):
```
https://<project-ref>.supabase.co/functions/v1/revenuecat-webhook
```

Signing secret: the `REVENUECAT_WEBHOOK_SECRET` env var. Set this on
both the RevenueCat dashboard and the Supabase project's function
secrets (`supabase secrets set REVENUECAT_WEBHOOK_SECRET=whsec_...`).

### Client → RevenueCat SDK

**Web**: use the `@revenuecat/purchases-js` package (or a simple
fetch to RevenueCat's REST API). Configure with the RevenueCat project
API key and the Supabase user id as the `app_user_id`. Show a checkout
flow and let RevenueCat handle payment + receipt validation. After a
successful purchase, the webhook fires and the server updates the tier;
the client refetches the profile to see the change.

**Android (Flutter)**: use `purchases_flutter` package. Initialise in
`main.dart` after sign-in with the user id as `appUserId`. The
`PurchasesConfiguration` object takes the RevenueCat API key from
the `.env.local` file.

**Wear OS (Kotlin)**: Wear OS doesn't support in-app purchases. The
watch inherits the phone's subscription via the paired Supabase session
(same `user_id` → same `subscription_tier`).

**Apple Watch (Swift)**: same — inherits from the phone's session.

### Secrets

| Secret | Where | What |
|---|---|---|
| `REVENUECAT_WEBHOOK_SECRET` | Supabase function env | HMAC signing secret from RevenueCat |
| `REVENUECAT_API_KEY_IOS` | iOS app `.env` / CI secrets | RevenueCat project API key for iOS |
| `REVENUECAT_API_KEY_ANDROID` | Android app `.env` / CI secrets | RevenueCat project API key for Android |
| `REVENUECAT_API_KEY_WEB` | Web `.env` / CI secrets | RevenueCat project API key for web |

## Donation flow (user perspective)

1. User navigates to `/settings/upgrade` (linked from sidebar and
   settings layout).
2. Page shows a transparent cost breakdown (server costs, dev time)
   with progress bars showing donation coverage for the current month.
3. User picks a donation tier (e.g. "Buy me a gel" / "Cover a day of
   servers") and is directed to an external payment link.
4. Project owner updates `monthly_funding` when donations land.

## Payment flow (retained for future re-gating)

If features are re-gated behind a paywall:

1. User taps a locked feature → sees the `<ProGate>` card.
2. Taps "Upgrade" → navigates to `/settings/upgrade`.
3. RevenueCat SDK presents the native payment flow (Play Store / App
   Store / Stripe for web).
4. On success, RevenueCat fires the webhook → Edge Function updates
   `subscription_tier` → client refetches profile → feature unlocks.

Latency between payment and unlock is typically <5 seconds. If the
webhook is slow, the client can poll `user_profiles.subscription_tier`
every 3 seconds for up to 30 seconds as a fallback.
