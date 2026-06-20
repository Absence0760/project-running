# E2E test coverage + dev accounts needed

Quick reference for "what's covered by Playwright today" and "what needs a real dev account before we can e2e it". Pair with [local_testing_stubs.md](local_testing_stubs.md) which covers *manual* testing of these flows.

## Covered today — no dev account needed

All of the following run in CI against the local Supabase stack. The seed user (`runner@test.com` / `testtest`) is the canonical actor.

### Web — auth + legal

| Surface | Spec file | What's pinned |
|---|---|---|
| Landing | `landing/page.spec.ts` | Page renders, footer present |
| Sign in (email + password) | `auth/login.spec.ts` | Rejects bad creds, happy-path resets password |
| Sign up | `auth/login.spec.ts` + `auth/signup-age-gate.spec.ts` | 16+ + ToS gating, happy-path signup ends on /dashboard |
| Password reset via Mailpit | `auth/reset.spec.ts` | Recovery email → reset → new password → re-sign-in |
| /privacy, /terms, /cookie-notice | `legal/pages.spec.ts` | Pages render with draft banner |
| Cookie consent banner | `cross-cutting/cookie-consent.spec.ts` | Show / hide / persist / Sentry gate |
| Pro pricing currency | `settings/pricing-localization.spec.ts` | $ / £ / € per locale |

### Web — core product

| Surface | Spec file | Notes |
|---|---|---|
| Dashboard | `dashboard/page.spec.ts`, `dashboard/period.spec.ts`, `cross-cutting/dashboard-journey.spec.ts` | Weekly mileage, PBs, goal cards |
| Runs (list / detail / new / photos / social / save-as-route) | `runs/*.spec.ts` | Full coverage of the run lifecycle |
| Routes (list / detail / import) | `routes/*.spec.ts` | Including GPX import |
| Plans (list / create / detail / workout-detail) | `plans/*.spec.ts` | Wizard + week grid |
| Clubs (list / detail / posts / events / members / approval / invite / join) | `clubs/*.spec.ts` | Full social-layer suite |
| Feed | `social/feed.spec.ts`, `cross-cutting/feed-journey.spec.ts` | Activity feed with author filter |
| Settings (account / devices / export / integrations / licenses / preferences / privacy-zones / upgrade / restore-backup) | `settings/*.spec.ts` | Almost every tab |
| Share (run / route public pages) | `share/*.spec.ts` | Anon read-through |
| Profile | `u/profile.spec.ts`, `u/notifications.spec.ts` | Follow toggle + notifications inbox |
| Explore (public routes) | `explore/page.spec.ts` | Search + filters |
| Live spectator (UI only) | `live/spectator.spec.ts`, `live/event.spec.ts` | Simulated pings |
| Coach (with mocked SSE) | `coach/page.spec.ts` | Chat surface mounts; 429 path + happy-path mocked |
| Compare | `compare/page.spec.ts` | Strava-comparison table |
| Guided runs | `guided/page.spec.ts` | Library + detail |
| Recap | `recap/page.spec.ts` | Year-in-running surface |
| Sitemap | `sitemap/page.spec.ts` | XML + robots.txt |

### Cross-cutting

- `cross-cutting/auth-walls.spec.ts` — every protected route redirects to /login when anon.
- `cross-cutting/paywall-wire.spec.ts` — Pro-only API endpoints reject when subscription_tier=free.
- `cross-cutting/realtime.spec.ts` — Supabase Realtime subscriptions deliver.
- `cross-cutting/sign-in-out.spec.ts` — full sign-in → /dashboard → sign-out → /login.
- `cross-cutting/db-constraints.spec.ts` — CHECK constraints fire on bad inserts.
- `cross-cutting/privacy-zones.spec.ts` — non-owner viewers see clipped tracks.
- `cross-user/{kudos, comments, follows, notifications, sagas}.spec.ts` — multi-user behaviours.

### Backend (not Playwright, but covered)

- `apps/backend/supabase/functions/**/*.test.ts` — ~210 Deno tests across ~15 files on shared helpers + webhook/checkout/export handlers.
- `apps/backend/supabase/tests/*.sql` — pgtap suite for RLS / SECURITY DEFINER / triggers.
- `apps/job_worker/internal/**/*_test.go` — Go tests for the worker, live-hub, dataexport, premium endpoints.

## Blocked — need a dev account to fully e2e-test

If you want to wire any of the below up, here's exactly what to create. Until then we either use a mock (per-spec `page.route()` stub like `coach.spec.ts` does), exercise the local-Supabase happy path only, or document the gap.

### 1. Google Sign-In — Google Cloud OAuth credentials

**What's needed:**
- Google Cloud project → Credentials → OAuth client → **Web application**.
- Authorized JavaScript origin: `https://your-domain.com` (+ `http://localhost:7777` for local).
- Authorized redirect URI: `https://<project-ref>.supabase.co/auth/v1/callback` (prod), `http://localhost:54321/auth/v1/callback` (local).
- Paste the Web client id into Supabase Dashboard → Authentication → Providers → Google → Authorized Client IDs.

**What you can test once configured:**
- E2E: button click → real Google account picker → return to /dashboard.
- Stub mode (today): we can test the button renders + click handler is wired, but not the post-Google return.

**Already covered by the mock-OIDC lane (`e2e-web-sso`, 2026-06-10):** the entire OAuth path *downstream of the provider redirect* — `signInWithOAuth` → GoTrue authorize → callback `?code` → `exchangeCodeForSession` → real Supabase session → the `/auth/confirm-age` age/terms gate → the app — is exercised end-to-end against a local `oauth2-mock-server`. GoTrue special-cases `google`/`apple` (validates them against the real providers), so the mock stands in as the generic `keycloak` provider; the **only** un-exercised piece is the provider *identity* (a literal Google account picker). See `apps/web/tests-e2e/sso/README.md`. A real Google dev account is therefore needed **only** for that final identity check, not for the callback/session/age-gate code.

**Test strategy when wired (real provider-identity check):**
A dedicated `e2e-test@gmail.com` test account. The actual id-token validation happens server-side at Supabase, so a fully-mocked *Google* flow doesn't work — you need the real account OR a sandbox token from Google's auth-emulator (limited support). This is a manual / non-CI check, since the post-redirect behaviour is already covered by the mock lane above.

### 2. Apple Sign-In — Apple Developer account

**What's needed:**
- Apple Developer Program ($99/year).
- Identifier → App ID with Sign In with Apple capability.
- Services ID for the web (`com.yourdomain.web`).
- Key with Sign In with Apple enabled; download the .p8.
- Supabase Dashboard → Authentication → Providers → Apple → Services ID + Team ID + Key ID + .p8 contents.

**Status today:** Apple Sign-In button on the login page shows a "Soon" pill and the click handler surfaces a "coming soon" error message. Spec coverage of the soon-pill exists implicitly; the real flow is blocked here.

### 3. Strava — Strava API application + test account

**What's needed:**
- <https://developers.strava.com> → Create an App.
- Client ID + Client Secret.
- Authorization Callback Domain: `localhost` for local, your domain for prod.
- `STRAVA_CLIENT_ID` + `STRAVA_CLIENT_SECRET` in `apps/backend/.env.local`.
- `STRAVA_ALLOWED_REDIRECTS` (your exact callback URLs).

**What you can test once configured:**
- E2E: web settings → Connect Strava → real OAuth dance → activities sync.
- Today: ZIP-import path runs against fixture files in `fixtures/strava/` (test-only). The OAuth + webhook paths exist but aren't e2e-tested.

**Test strategy when wired:**
Two Strava accounts (one as the "user", one as a "buddy" to exercise the privacy filter); spec drives the OAuth handshake with the user's real session.

### 4. Garmin Connect — developer-program approval (BLOCKED)

**Status:** Per `docs/product/roadmap.md`, Garmin Connect Developer API requires application + manual approval that's currently outstanding. Until that lands no Garmin e2e is possible.

**Workaround today:** the Garmin ZIP-import path (single .fit OR Account-Data .zip) IS wired and could be e2e'd with a fixture file. Track in roadmap.

### 5. Stripe + RevenueCat — sandbox accounts (free)

**What's needed:**
- Stripe dashboard → switch to **Test mode**. Grab `pk_test_…` and `sk_test_…`.
- RevenueCat → new sandbox project; paste Stripe `sk_test_…` into Integrations → Stripe. Create the `pro_monthly` product mapped to a Stripe test-mode price.
- `PUBLIC_REVENUECAT_WEB_CHECKOUT_URL` (RC sandbox Web Paywall Link `https://pay.rev.cat/<token>`) in `apps/web/.env.local`; optional `PUBLIC_REVENUECAT_WEB_PORTAL_URL` for the manage-subscription link.
- `REVENUECAT_WEBHOOK_SECRET` (RC webhook signing secret) in `apps/backend/.env.local`.
- Optional but recommended: install `stripe` CLI for `stripe listen --forward-to http://127.0.0.1:54321/functions/v1/revenuecat-webhook`.

**What you can test once configured:**
- E2E: /settings/upgrade → "Get Pro" → Stripe test card 4242 4242 4242 4242 → returns to app → webhook flips tier → `auth.isPro` becomes true.
- Today: the upgrade page renders, button click would fail with "Pro checkout is not configured on this build" (the `isRevenueCatConfigured()` fallback). Pricing display is e2e-tested at the unit level.

**Test strategy when wired:**
`pricing-localization.spec.ts` already covers locale. Add a `purchase-flow.spec.ts` that uses Stripe's published test cards + listens to RC webhook delivery via the CLI shim. Pinning the tier-flip via a `webhook_events` row insert is the canonical assertion.

### 6. Apple In-App Purchase / Google Play Billing — device-only

**Status:** Cannot be e2e-tested on a laptop. Both flows require a real iOS / Android device with a sandbox-tester account signed into the App Store / Play Store. See [local_testing_stubs.md § Apple IAP / Google Play Billing](local_testing_stubs.md#apple-iap--google-play-billing) for manual setup.

**What you can test today:** the in-app purchase button on mobile renders; the rest is integration test on device.

### 7. Anthropic API — for the AI Coach

**What's needed:**
- <https://console.anthropic.com> → API keys → create a key (`sk-ant-…`).
- `ANTHROPIC_API_KEY` in `apps/web/.env.local` for local dev, or the Lambda env in prod.

**Status today:** `coach.spec.ts` mocks the SSE response via `page.route('**/api/coach', ...)`. Real Anthropic calls cost ~$0.01/chat at typical context — fine for occasional manual testing, but the mocked path is the canonical e2e signal.

**Alternative — free local stub:** `COACH_PROVIDER=openai` + `OPENAI_BASE_URL=http://localhost:11434/v1` + `OPENAI_MODEL=llama3` points the Coach handler at a local Ollama instance. Zero cost, slower responses.

### 8. Sentry — for the error monitoring + replay

**What's needed:**
- <https://sentry.io> → create a project.
- `PUBLIC_SENTRY_DSN` in `apps/web/.env.local`.

**Status today:** Sentry is gated on `dev=false && dsn && hasAcceptedConsent()`, so it doesn't fire in local dev. Nothing to e2e until prod traffic.

### 9. MapTiler — for map tiles

**What's needed:** Free at <https://maptiler.com/cloud>.
- `PUBLIC_MAPTILER_KEY` in `apps/web/.env.local`.

**Status today:** Maps render in dev. The free tier covers all local testing. E2E tests that exercise the map (`runs/detail.spec.ts`, `routes/detail.spec.ts`) work as long as the key is set.

### 10. FCM (Android) + APNs (iOS) push notifications

**What's needed:**
- Firebase project for Android.
- Apple Developer Program + APNs auth key for iOS.
- Supabase Auth → Notifications config.

**Status today:** `device_tokens` table rows write correctly (covered by spec); actual delivery is gated on real upstream credentials. Today there's no automated push-delivery test.

### 11. parkrun — no sandbox available

**Status today:** parkrun is a public scraper, no API/sandbox. The `parkrun-import` Edge Function takes an athlete number; testing requires a real athlete number that's run real events. Use your own number for manual testing.

**Test strategy:** mock the upstream fetch in the Edge Function via dependency injection (the function is already structured for this; `apps/backend/CLAUDE.md` § Testing without real credentials documents the pattern).

## Summary — what to create first

If your goal is "get the e2e suite to cover everything", the **best ROI** is:

1. **Stripe + RevenueCat sandbox** — frees up the entire paywall flow (about a day of e2e wiring).
2. **Google Cloud OAuth credentials** — Google Sign-In, ~15 min to configure.
3. **Anthropic API key** — Coach real-mode if you ever want to verify the model response shape against fresh Anthropic releases.

If your goal is "ship to international" without further e2e investment, the **existing coverage is already strong** — the gaps are:
- Real OAuth flows (mocked or skipped, both are defensible).
- Real payment flows (sandbox-tested manually before each release; sufficient for a $9.99/month consumer SaaS).
- Mobile e2e (separate doc — [docs/testing/mobile_e2e.md](mobile_e2e.md)).
