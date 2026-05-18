# Local testing — third-party stubs

How to exercise every feature locally without touching a real upstream account. The default is "use the real API in test/sandbox mode"; for providers without a sandbox we either mock the HTTP call or document a manual happy-path.

The starting point for any local session is the local Supabase stack:

```bash
pnpm dev:db:up                  # apps/backend supabase start
pnpm dev:run:web                # SvelteKit on :7777
pnpm dev:run:android            # optional — Flutter Android
```

Seed user: `runner@test.com` / `testtest`. See [apps/backend/local_testing.md](../apps/backend/local_testing.md).

## Coverage by feature

| Feature | Local mode | What you can verify |
|---|---|---|
| **Auth (email / password)** | Real, against local Supabase | Sign in, sign up, password reset (delivery into Mailpit at <http://127.0.0.1:54324>), 16+ age gate, ToS acceptance |
| **Auth (Google)** | Manual setup (see [apps/mobile_android/local_testing.md](../apps/mobile_android/local_testing.md#google-sign-in-optional)) | OAuth-only — needs real Google Cloud client |
| **Auth (Apple)** | Not testable locally | Apple Sign-In needs a real Apple Developer account + paired domain |
| **GPS recording** | Real, on real device | Phone in foreground, screen off, lap markers, hold-to-stop |
| **GPS recording on emulator** | Real, with Android Studio's Location → Routes player | See [apps/mobile_android/local_testing.md § Simulating GPS](../apps/mobile_android/local_testing.md#simulating-gps) |
| **Run sync** | Real, against local Supabase | Background, foreground, on-connectivity, after-conflict |
| **Strava import (ZIP)** | Real | Strava lets you export your own data as a ZIP from Settings → My Account → Download — drop the ZIP into the importer |
| **Strava OAuth + webhook** | Stubbed (see below) | The Edge Function `strava-import` accepts a `connect` action; mock `STRAVA_OAUTH_URL` + a fixture access token |
| **parkrun import** | Real | The scraper hits public profile pages; use your own athlete number or `A123` for the seed |
| **Health Connect / HealthKit** | Real, on device | Emulator + real device both work for read; write isn't wired |
| **AI Coach (Anthropic)** | Real with throwaway `sk-ant-` key, or stubbed (see below) | Real run on a sandbox API key burns ~$0.01 / chat at small context. Or set `COACH_PROVIDER=openai` + `OPENAI_BASE_URL=http://localhost:11434/v1` to point at local Ollama |
| **AI Coach (OpenAI fallback)** | Stubbed via local Ollama | `COACH_PROVIDER=openai` + `OPENAI_BASE_URL=http://localhost:11434/v1` + `OPENAI_MODEL=llama3` — zero $ cost |
| **Payment (Stripe — web Pro purchase)** | **Stripe test mode** (see below) | Full happy path: subscribe, renew, cancel, refund, payment-method update, webhook delivery |
| **Payment (Apple IAP / Play Billing)** | **Store sandbox accounts** (see below) | App-store flows only — no laptop-only path exists |
| **RevenueCat webhook** | Stripe-CLI replay or scripted curl | Verifies the HMAC + dedupe + tier flip end-to-end |
| **Account deletion** | Real, against local Supabase | Seed user, populate every table, run the delete-account function, assert empty |
| **Data export** | Real, against local Supabase + Go worker | `pnpm dev:run:worker` then trigger an export from Settings |
| **Live spectator** | Real, against local Go worker | Run `pnpm dev:run:worker` (the live-hub is mounted on the same binary at `POST /v1/live/...`); web `/live/[id]` connects via WebSocket |
| **Push notifications** | Stubbed | `device_tokens` rows write OK; FCM / APNs send is a no-op unless you wire real credentials |
| **Maps (MapTiler tiles)** | Real, free tier | Free tier covers local dev |
| **OSRM map matching** | Optional, via local docker-compose | One-time: `pnpm dev:setup:osrm` (downloads + builds the routing graph, ~5-15 min). Then `pnpm dev:run:osrm` brings up the matching service. The worker falls back to passthrough when `OSRM_URL` is unset. |
| **Sentry** | Disabled by default | Only initialises when `dev=false` AND `PUBLIC_SENTRY_DSN` is set AND user has accepted consent |

## Stripe (web Pro purchase)

Stripe's **test mode** is the canonical local-testing path. RevenueCat acts as a billing aggregator on top of Stripe; both have native test environments.

### 1. Stripe test keys

1. Sign in to <https://dashboard.stripe.com>.
2. Top-right toggle: switch to **Test mode**.
3. Developers → API keys → grab the **publishable** key (`pk_test_...`) and **secret** key (`sk_test_...`).

### 2. RevenueCat sandbox project

1. <https://app.revenuecat.com> → create a project for local testing (separate from prod).
2. Project settings → Integrations → Stripe → paste `sk_test_...`.
3. Add a product: `pro_monthly` with the Stripe test-mode price you create.
4. Project settings → API keys → copy the **public web** key.

### 3. Wire into the app

```bash
# apps/web/.env.local
PUBLIC_REVENUECAT_WEB_API_KEY=rcb_xxx     # public sandbox web key

# apps/backend/.env.local
REVENUECAT_WEBHOOK_SECRET=whsec_xxx        # sandbox webhook signing secret
```

Restart `pnpm dev:run:web` so the SvelteKit Vite dev server picks them up.

### 4. Test cards

Stripe publishes a long list at <https://stripe.com/docs/testing>. The most useful:

| Card | What it does |
|---|---|
| `4242 4242 4242 4242` | Succeeds always |
| `4000 0000 0000 9995` | Charge declined |
| `4000 0027 6000 3184` | Requires 3D Secure (SCA) flow |
| `4000 0000 0000 0341` | Succeeds, but next renewal fails |
| `4000 0035 6000 0008` | Brazilian card (test BRL flow) |

Any future expiry; any 3-digit CVC; any 5-digit ZIP.

### 5. Deliver the RevenueCat webhook to your local backend

Two options:

**(a) Stripe CLI listen (preferred).** The Stripe CLI forwards real test-mode events to your local URL. RevenueCat re-emits Stripe events on its own webhook channel, so you'll trigger one Stripe event and watch RevenueCat fire its own POST a moment later.

```bash
stripe listen --forward-to http://127.0.0.1:54321/functions/v1/revenuecat-webhook
# In a second terminal:
stripe trigger checkout.session.completed
```

RevenueCat receives the Stripe event, classifies it, and POSTs an `INITIAL_PURCHASE` to your local webhook handler. The handler validates the HMAC against `REVENUECAT_WEBHOOK_SECRET`, dedupes via `webhook_events`, flips `user_profiles.subscription_tier` to `pro`. The dashboard refreshes within a tick because `auth.fetchUser()` is called in the success path.

**(b) Curl replay.** Capture a payload from the RevenueCat dashboard "Test webhook" feature, sign it with the secret, replay.

### 6. Verify

```bash
psql 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' -c \
  "SELECT id, subscription_tier FROM user_profiles WHERE id='<runner-uuid>';"
```

You should see `subscription_tier = 'pro'`. The `/settings/upgrade` page now shows the "Active" badge.

## Bypass paywall entirely (dev only)

For testing Pro-gated features without going through the full Stripe path:

```bash
# apps/web/.env.local
BYPASS_PAYWALL=true
```

The `/api/coach` handler honours this only when:
- `NODE_ENV !== 'production'`, AND
- `PUBLIC_SUPABASE_URL` points at `127.0.0.1` / `localhost`, AND
- The literal string `'true'`.

Production Lambda hardcodes the bypass off. Don't commit a `BYPASS_PAYWALL=true` to `.env.example` — there's a comment in there explaining why.

## Apple IAP / Google Play Billing

These can't be exercised on a laptop without the matching device + a sandbox tester account.

**iOS:**

1. App Store Connect → Users + Access → Sandbox → add a test user (e.g. `pro+sandbox-1@example.com`). Use this email/password to sign in to Settings → iTunes Store on a real device or simulator with sandbox sign-in enabled.
2. App Store Connect → In-App Purchases → create the `pro_monthly` product. Status: "Ready to Submit" is sufficient for sandbox.
3. Build the app with the RevenueCat iOS SDK keyed to the sandbox project.
4. Sandbox subscriptions have an accelerated renewal cycle (1 month = 5 minutes). Burn a few sandbox cycles to verify the renewal webhook.

**Android:**

1. Play Console → Setup → License testing → add tester emails.
2. Play Console → Internal testing → upload a release build.
3. Subscriptions are free in license-test mode; sign in to the test device with the tester email.
4. RevenueCat Android SDK config matches the sandbox project.

## Mocking outbound HTTP for Edge Functions

For Strava / parkrun / Garmin / Anthropic happy-path tests where we don't want to hit the real provider, the Edge Function pattern is to inject the fetcher. Deno makes this easy because `fetch` is a globally-replaceable name. Example pattern in [apps/backend/CLAUDE.md § Testing without real credentials](../apps/backend/CLAUDE.md#testing-without-real-credentials).

For per-test fixture servers, drop a tiny `python -m http.server` in `apps/backend/fixtures/` and override the relevant base URL via env.

## Local payment-stubbing summary

| Surface | What you get | What you don't |
|---|---|---|
| Stripe test mode + RevenueCat sandbox | Full lifecycle end-to-end (purchase → renew → cancel → refund → webhook) | Real production rates / region settlement |
| `BYPASS_PAYWALL=true` | Pro features unlocked without auth/billing | The actual purchase + webhook flow |
| Apple / Google sandbox | Real IAP UI on a real device | Anything web-only |

The Critical-tier compliance fix here is that **all of the above are reproducible without touching the production Stripe account.** Verify that before any new feature that touches subscription state lands.
