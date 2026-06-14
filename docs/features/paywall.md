# Paywall

**Contents:** [Current model: Pro subscription + optional donations](#current-model-pro-subscription--optional-donations) · [Tiers](#tiers) · [Pro gates and perks](#pro-gates-and-perks) · [Client-side `isPro()` helper](#client-side-ispro-helper) · [Adding a new gated feature](#adding-a-new-gated-feature) · [BYPASS_PAYWALL](#bypass_paywall) · [RevenueCat integration](#revenuecat-integration) · [One-off donation flow (user perspective)](#one-off-donation-flow-user-perspective) · [Payment flow (retained for future re-gating)](#payment-flow-retained-for-future-re-gating)

## Current model: Pro subscription + optional donations

Every screen in the app is reachable by free users. The Pro tier
changes **behaviour inside the surfaces**, not access to them — there
is no Pro-only screen. `PRO_ONLY_FEATURES` in
`apps/web/src/lib/settings/features.ts` is empty today, so `isLocked()` returns
`false` for every key. The infrastructure (`<ProGate>` component,
`isLocked()` helper, `GATED_FEATURES` registry) is kept so a future
Pro-only screen is a one-line addition. See [decisions.md § 23]
(decisions.md#23-pro-tier-reintroduced-at-999mo-alongside-one-off-donations)
for why the AI Coach uses per-tier daily caps rather than a screen
gate.

What the Pro tier changes:

- **Higher AI Coach daily cap (10/day vs 2/day for free).** Both tiers
  go through the same `increment_coach_usage` RPC and the same
  `usedToday > dailyLimit` gate in `apps/web/src/lib/coach/handler.ts`;
  only the resolved cap differs. Free users get
  `TIER_LIMITS.free.dailyLimit = 2` messages per UTC day, then the
  composer is replaced by a `<div class="limit-bar">` "you've used all
  2 messages for today — Upgrade to Pro…" banner until midnight. Pro
  users get `TIER_LIMITS.pro.dailyLimit = 10` and the same limit-bar
  shape at the higher ceiling. The production AWS Lambda hardcodes
  `bypassPaywallEnabled: false`, so a caller that POSTs directly to
  `/api/coach` from devtools still gets a 429 once they exceed their
  tier's cap with `{ error: 'daily_limit', tier, limit }`.
- **Priority processing.** Pro users get a wider processing budget on
  every coach request: a 2048 max-token response (vs 768 for free) for
  longer / more thorough answers, and up to 75 runs of context per
  turn (vs 30 for free). Coupled with the higher daily cap above,
  these are concrete tier-aware budgets enforced server-side on
  `/api/coach/+server.ts` and surfaced in `X-Coach-Tier` /
  `X-RateLimit-*` response headers. Backend Edge Functions don't
  currently branch on tier beyond the shared tier-aware rate-limit
  helper; that's the next planned widening when individual functions
  get hot.

- **AI route descriptions.** On a route's detail page, every user can
  tap "Describe this route" to get an instant, offline templated
  description built from the route's stats (`localisedTemplate` in
  `$lib/routes/route_description.ts`). Pro users' tap additionally calls
  `/api/coach/route-describe`, which asks Claude (`claude-opus-4-8`,
  adaptive thinking) to turn those facts into a richer paragraph. The
  gate is server-side (`is_pro()`, fail-closed) and the enhancement is
  L4-additive: a free caller, a missing key, a model error/refusal, or a
  timeout all degrade to the templated text, so the affordance never
  breaks. A free user's response carries `upgrade:true`, which surfaces a
  one-line "Enhance with AI (Pro)" upsell linking to `/settings/upgrade`.

`/settings/upgrade` shows a two-card layout: a Pro plan card
($9.99 / month, feature bullets, "Get Pro" CTA) and a one-off Donate
button that links to an external payment provider. The transparent
cost breakdown, monthly progress bars, donor count, and tiered
donation buttons that existed under the previous donations-only model
are gone — see [decisions.md § 23](../architecture/decisions.md#23-pro-tier-reintroduced-at-999mo-alongside-one-off-donations).

The `monthly_funding` table stays in the schema (orphaned but not
dropped); reviving transparent funding later is a one-page revert.

## Tiers

| Tier | How you get it | What it unlocks |
|---|---|---|
| `free` | Default for every new account | Every screen in the app. AI Coach capped at 2 messages/day. Standard request priority. |
| `pro` | RevenueCat subscription ($9.99 / month) | Everything free users get + AI Coach capped at 10 messages/day (5× the free cap) + priority processing (wider context budget, longer responses). |
| `lifetime` | RevenueCat one-time purchase (not currently sold) | Same as `pro`. |

`user_profiles.subscription_tier` is the authoritative column. A CHECK
constraint enforces the three valid values. The `is_pro()` SQL helper
takes no arguments and gates internally on `auth.uid()`; it returns
`true` for both `pro` and `lifetime`. (An earlier `is_user_pro(uuid)`
variant was dropped in `20260516_001_drop_is_user_pro.sql` — it took a
user-id parameter and let any authenticated caller probe another user's
tier.)

The column is **write-protected against user-JWT writers**. Migration
`20260624_001_lock_subscription_tier_to_service_role.sql` splits the
catch-all profile policy into per-command policies and adds a `BEFORE
UPDATE` trigger (`lock_subscription_columns`) that rejects any
`subscription_tier` or `subscription_at` change unless the JWT role is
`service_role` (the only legitimate writer is the `revenuecat-webhook`
Edge Function) or empty (direct SQL — migrations + seed). A user
attempting to self-promote via `PATCH /rest/v1/user_profiles` gets a
403 `insufficient_privilege`. Bumping the tier outside the webhook
flow requires an admin SQL session; from a client there is no way.

## Pro gates and perks

| Perk | Feature key | Enforcement point |
|---|---|---|
| Higher AI Coach daily cap (10/day vs 2/day) | `ai_coach` | Server: `apps/web/src/lib/coach/handler.ts` checks `is_pro()` via the auth context, resolves `TIER_LIMITS[tier].dailyLimit`, and runs the same `increment_coach_usage` + `usedToday > dailyLimit` gate for both tiers. A free user's 3rd attempt of a UTC day returns 429 with `{ error: 'daily_limit', tier: 'free', limit: 2 }`; a Pro user's 11th attempt returns 429 with `{ error: 'daily_limit', tier: 'pro', limit: 10 }`. Client: `CoachChat.svelte` reads back the tier and limit from the SSE `meta` event and shows the "Free badge · N of 2 remaining" or "Pro badge · N of 10 remaining · priority context window" footer. The composer is replaced with a `.limit-bar` block when `usedToday >= dailyLimit`. |
| Priority processing — coach context | `priority_processing` | Server: `/api/coach/+server.ts` derives `tier` from `is_pro()` then resolves a `TIER_LIMITS` budget (`maxTokens`, `maxRunsLimit`, `dailyLimit`). Pro gets 2048 max-tokens + 75-runs context cap; free gets 768 + 30. Budget is echoed in `X-Coach-Tier` / `X-RateLimit-*` headers and the response body's `tier` + `limits`, so clients can render the right footer state without parsing headers. |
| AI route description | _(no key — perk, not gate)_ | Server: `apps/web/src/lib/routes/route_describe/handler.ts` verifies the JWT, gates on `is_pro()` (fail-closed: an RPC error or a free caller serves the templated text, never the model), then calls `claude-opus-4-8` (adaptive thinking, 400-token cap, 12 s timeout). Reached via `/api/coach/route-describe` (dev `+server.ts`; prod routed inside the coach Lambda by `rawPath.includes('/route-describe')`). Every failure mode — not-Pro, missing `ANTHROPIC_API_KEY`, model error, `stop_reason:'refusal'`, empty completion, timeout — returns 200 with `{ description: <templated>, source: 'template' }`; a free caller also gets `upgrade:true`. Client: `/routes/[id]` renders `localisedTemplate` instantly, then swaps in the AI text on a `source:'ai'` 200 with an `auto_awesome` attribution. |
| Priority map-matching | `priority_processing` | DB: every enqueue site for `kind='map_match'` jobs (the auto-trigger `runs_enqueue_match_job` and the manual-rematch RPC `enqueue_run_rematch`) calls `job_scheduled_at_for_user(uuid)` from migration `20260730_001`. Pro / lifetime → `now()` (front of queue); free → `now() + 30 s` (defers behind Pro). The worker's `claim_next_job` orders by `(scheduled_at, id)` so Pro jobs are always claimable strictly before free jobs enqueued at the same instant. **Future job kinds follow the same pattern** — call the helper at enqueue time; don't inline `case ... subscription_tier ...`. See [decisions.md § 57](../architecture/decisions.md#57-map-matching-is-free-queue-priority-is-the-pro-perk). |

`PRO_ONLY_FEATURES` in `features.ts` is empty today — every screen is
reachable by free users, and the Pro tier is delivered through
behaviour changes inside the surfaces. The `priority_processing` and
`ai_coach` perks above are behaviour changes, not gated screens, so
they don't call through `isLocked()`. Add a key to
`PRO_ONLY_FEATURES` to gate a new screen behind Pro.

**No feature or analytic is locked behind Pro.** Net effect of the
above: a free user reaches every screen and gets the full feature set —
training plans, VDOT / VO₂ max, training-load curves, recovery advice,
race predictor, segments, social, backup, etc. — all computed
client-side for free. The Pro tier only buys a *higher* AI-coach daily
cap, a wider coach context/response budget, and front-of-queue
map-matching. (The `apps/job_worker/internal/premium/*` Go endpoints
return `402 pro_required` for non-Pro, but **no client calls them** —
the same analytics run client-side for free, so that gate is dormant
server scaffolding, not a live paywall. If a client is ever wired to
those endpoints, this is the one place a real analytics paywall would
appear; revisit the "everything is free" claim then.)

## Client-side `isPro()` helper

`apps/web/src/lib/settings/features.ts` exports `isPro()` — reads the auth
store's cached `user_profiles.subscription_tier` and returns true for
`pro` / `lifetime`. Use it for conditional UI flourishes (a "Pro"
badge, a higher-cap label next to the coach input). Never use it as
the sole check for anything expensive: always mirror the check
server-side with the `is_pro()` RPC.

## Adding a new gated feature

1. **Register the feature.** Add an entry to `GATED_FEATURES` in
   `apps/web/src/lib/settings/features.ts`:
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
   const { data } = await supabase.rpc('is_pro');
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
   Import `isLocked` from `$lib/settings/features` and `ProGate` from
   `$lib/components/ProGate.svelte`.

4. **Android gate.** In the Flutter app, read the tier from the
   profile and gate the feature on it. **Do not branch on
   `BYPASS_PAYWALL` in mobile code** — see the BYPASS_PAYWALL section
   below for why mobile has no env-flag bypass.
   ```dart
   final tier = api.userProfile?.subscriptionTier ?? 'free';
   if (tier == 'free') {
     // Show upgrade prompt
   }
   ```

5. **Update this doc.** Add the feature to the "Gated features" table
   above with the exact `feature` key, label, and where it's gated.

## BYPASS_PAYWALL

Two independent dev-only escape hatches: `BYPASS_PAYWALL` for the
server-side `/api/coach` daily-cap, and `PUBLIC_BYPASS_PAYWALL` for the
client-side `isLocked()` UI gate. Both stay off by default and must be
opted into per dev machine via `apps/web/.env.local`.

### Server — `BYPASS_PAYWALL` for `/api/coach`

The flag is honoured *only when all three conditions are
simultaneously true*:

1. `NODE_ENV !== 'production'` — i.e. running under `npm run dev`,
   never in a build artifact.
2. `PUBLIC_SUPABASE_URL` contains `127.0.0.1` or `localhost` — i.e.
   the dev wrapper is talking to a local Supabase stack, not a real
   project.
3. `BYPASS_PAYWALL === 'true'` (the literal string).

Logic lives in `apps/web/src/routes/api/coach/+server.ts`. The
production AWS Lambda (`apps/web/lambda/coach/src/index.ts`)
hardcodes `bypassPaywallEnabled: false` regardless of process env, so
even if the flag leaked into the Lambda's runtime environment it
would not flip the gate. The shared handler logs a `console.warn` on
every bypass-enabled request so any prod accident shows up
immediately in CloudWatch.

The flag is intentionally **not exported** in `apps/web/.env.example`
— it should never be set in a checked-in template. Add it ad-hoc to
your own `.env.local` if you need it.

### Client — `PUBLIC_BYPASS_PAYWALL` for `isLocked()`

`apps/web/src/lib/settings/features.ts::isLocked()` already returns `false` for
every key today because `PRO_ONLY_FEATURES` is empty, so this client
bypass is dormant infrastructure. It stays in place so that the
moment a new key lands in `PRO_ONLY_FEATURES`, local devs can flip
`PUBLIC_BYPASS_PAYWALL=true` in `apps/web/.env.local` to iterate as a
free user without leaving the gate armed. Same three-condition AND as
the server flag (`import.meta.env.DEV`, local Supabase URL, literal
`'true'`), with one extra opt-out: a
`localStorage.paywall_force_locked = '1'` entry re-arms the gate for
the current page so e2e tests can exercise the lock-card path on a
machine that otherwise has the bypass on. The override is gated on
`import.meta.env.DEV` so it's inert in production.

The two flags are separate by design — leaking one (e.g. into a prod
bundle) doesn't leak the other. `PUBLIC_BYPASS_PAYWALL` is fine to
commit to `apps/web/.env.example` because the public-prefix surface is
already client-readable; `BYPASS_PAYWALL` (no prefix) stays out of any
template.

### Mobile / watch / other web endpoints

No bypass. The mobile app reads `subscription_tier` from the user's
profile and gates accordingly; for dev work flip the seed user's
tier in `apps/backend/supabase/seed.sql` to `'pro'` instead of
inventing a client-side override. The watch has no paywalled
surfaces at all.

Never re-introduce a BYPASS_PAYWALL read in mobile / watch code —
without the prod-env trio above, a stray `.env` containing
`BYPASS_PAYWALL=true` would silently disable the check in a release
build. The audit pass-2 report flagged this as a documentation gap;
this section is the corrected guidance.

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

**Web (shipped)**: `@revenuecat/purchases-js` is wired via
`apps/web/src/lib/billing/revenuecat.ts`. `/settings/upgrade` "Get Pro" button
calls `Purchases.purchase(...)` with the Supabase user id as the
`appUserId`. The `managementURL` on `CustomerInfo` backs the
"Manage subscription" button. Env-gated by `PUBLIC_REVENUECAT_WEB_API_KEY`;
builds without the key fall back to the original "coming soon" toast so
local dev and previews still compile. After a successful purchase the
`revenuecat-webhook` Edge Function flips `subscription_tier` server-side
and the web re-fetches the user profile via `auth.fetchUser()`.

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
| `PUBLIC_REVENUECAT_WEB_API_KEY` | `apps/web/.env.local` / CI public env | RevenueCat project API key for web (read by `$lib/billing/revenuecat.ts`); unset → Pro CTA falls back to placeholder |

### Regional availability & international payments

**RevenueCat is not the payment processor.** On mobile it sits on top of **Apple StoreKit** (App Store) and **Google Play Billing**; the charge runs through the buyer's Apple ID / Google account. That makes cross-border purchases work *for free* — but only once the store-side configuration exists. The split is:

- **Handled by Apple / Google (no work for us):** local currency + payment methods (e.g. UPI / net-banking / cards / carrier billing in India), currency conversion, and — critically — **tax as merchant of record** (Apple/Google collect + remit GST/VAT/sales tax per territory; we never file foreign tax for IAP). They also own refunds and the auto-renewal mechanics. We're paid out in our configured currency after their 15–30% cut.
- **The buyer always sees their store-localized price**, not a hard-coded USD figure. The mobile Subscribe tile reads it via `proMonthlyPriceString` → `storeProduct.priceString` (`apps/mobile_android/lib/screens/settings_pro_screen.dart` + iOS twin), falling back to the `$9.99` USD list price + a "billed in USD" note only when RevenueCat is unconfigured or the offering hasn't loaded. Apple Guideline 3.1.1 / the Play subscription policy require the displayed amount to come from the store (it varies by territory), which is why the price is never hard-coded.

**Operator prerequisites — a purchase from (say) India only succeeds when all of these are set up (none are code):**

1. **Storefront availability.** The app *and* the subscription product must be enabled for the buyer's country (App Store Connect → Availability; Play Console → Countries/regions). Excluding a country silently makes Pro unbuyable there — this is the most common gap, so any "is Pro reachable in country X?" check starts here. (`/audit/regional-availability` exercises this.)
2. **Per-region price.** Apple via a price tier (auto-generates the local amount per storefront) or a custom per-region price; Play via per-country pricing. RevenueCat just reports whatever the store says.
3. **RC project provisioned** — the `pro_monthly` package + `REVENUECAT_API_KEY_*` (followups.md §#9). Until then the tile falls through to the web URL.

**Caveats:**

- **The web Stripe path is a separate story.** When RevenueCat is unconfigured the app routes to `/settings/upgrade` (Stripe), which has its own international constraints — notably India's RBI e-mandate rules for recurring charges and Stripe-India entity requirements. That is *not* solved by the IAP path above.
- **iOS effectively requires IAP for the Pro subscription** (Guideline 3.1.1 forbids routing users to an external processor for digital goods), so on iOS the RevenueCat → StoreKit path is mandatory, not optional. Play has similar rules with narrower external-link exceptions.
- **Auto-renewal in India** broke ecosystem-wide under the 2021–22 RBI mandate rules; Apple and Google now implement compliant recurring billing *inside* IAP — another reason to go through them rather than a self-hosted recurring charge in those markets.

## One-off donation flow (user perspective)

1. User navigates to `/settings/upgrade` (linked from sidebar and
   settings layout).
2. Page shows the two-card layout: Pro plan card ($9.99 / month) plus
   a one-off **Donate** button.
3. Tapping Donate opens an external payment link in a new tab.

The tiered donation picker, transparent cost breakdown, progress bars,
and donor count that existed under the previous donations-only model
were removed when the Pro tier was reintroduced — see
[decisions.md § 23](../architecture/decisions.md#23-pro-tier-reintroduced-at-999mo-alongside-one-off-donations).
The `monthly_funding` table is retained but no longer read by the UI.

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
