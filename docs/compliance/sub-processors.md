# Sub-processors

Every external service that touches user data. This is both:

- The **Privacy Policy** sub-processor disclosure (Art 13(1)(e) + 14(1)(e) GDPR).
- The **GDPR Art 30 Record of Processing Activities** input.

**Status**: scaffold based on the codebase. Verify against actual prod config + each provider's current DPA before publishing.

## Required by the project today

| Provider | What we send | Region | Lawful basis (claimed) | DPA / SCC | User opt-out |
|---|---|---|---|---|---|
| **Supabase** | All Postgres + Auth + Storage data | `eu-west-2` (London) — per `apps/backend/deployment.md` | Contract (Art 6(1)(b)) | <https://supabase.com/legal/dpa> | Account deletion |
| **AWS** (S3, CloudFront, Lambda, KMS, Route 53, Fly→peering) | Web bundle, run-export Storage objects, CloudFront access logs, KMS-encrypted sops secrets | us-east-1 (primary), edge worldwide | Contract | <https://aws.amazon.com/compliance/data-protection/> | Account deletion |
| **Fly.io** (job_worker + OSRM) | Map-match jobs (run tracks transit through), strava-webhook payloads, data-export job state | `lhr` (London) — per `apps/job_worker/fly.toml` + `osrm/fly.toml` `primary_region` | Contract | <https://fly.io/legal/dpa/> | None practical (server-side only) |
| **MapTiler** | Viewport bbox + request IP per tile fetch | EU + global edge | Consent — ePrivacy Art 5(3) / GDPR Art 6(1)(a). The map never instantiates maplibregl (nor fetches a static-map tile) before the cookie banner is accepted, on **every** surface including authenticated ones: `RunMap` + `PersonalHeatmap` gate init on `hasAcceptedConsent()`, anon share/live pages additionally require a per-view "Load map" tap, and `RouteTrackPreview` / `RunTrackPreview` gate the static-map URL on `consent.accepted`. | <https://www.maptiler.com/privacy-policy/> | Don't accept the banner (or Reject / GPC) — maps render as a "Load map" placeholder and no tile request fires |
| **Anthropic** (AI Coach primary) | Coach prompt incl. last-N runs, plan, HR pills, weekly goal | us-east-1 | Consent (user opens the Coach) | <https://www.anthropic.com/legal/data-processing-addendum> | Don't use the Coach |
| **OpenAI** (Coach fallback, only when `COACH_PROVIDER=openai`) | Same as Anthropic | Operator-configured via `OPENAI_BASE_URL` — US for `api.openai.com`, or wherever a self-hosted/Ollama endpoint runs. **Not used in the default prod config** (Anthropic is the default provider). | Consent | <https://openai.com/policies/data-processing-addendum> | Don't use the Coach |
| **Strava** (when user connects) | OAuth code → access token; pull activities; push webhooks | US | Consent (user explicitly connects) | <https://www.strava.com/legal/api> | Disconnect in Settings |
| **parkrun** (when user enters athlete number) | Athlete number → scrape `https://www.parkrun.com/parkrunner/...` | UK | Consent (user explicitly enters their athlete number). **Controller relationship:** parkrun is an independent controller of the source data; our use is consent-based portability into the user's account, not a processor arrangement — there is no parkrun DPA to execute. | parkrun TOS | Disconnect in Settings |
| **Upstash Redis** (live-hub cache — ONLY when `REDIS_URL` points to external Upstash; the default in-process Hub uses no third party) | Live-ping lat/lng (24h TTL), keyed by run_id | Operator-configured Upstash region | Legitimate interest (live spectator fan-out) | <https://upstash.com/trust/dpa.pdf> | None practical (ephemeral 24h cache). **Execute the Upstash DPA before enabling external Redis in prod.** |
| **Garmin Connect** (scaffolded, blocked on developer approval) | OAuth tokens; sync workouts | US | Consent | TBD on approval | Disconnect in Settings |
| **RevenueCat** | RevenueCat customer id (user uuid) + subscription tier + receipt | US | Contract (paid tier purchase) | <https://www.revenuecat.com/dpa> | Cancel subscription |
| **Stripe** (via RevenueCat) | Stripe customer id, card token (Stripe-side, never reaches us) | US | Contract | <https://stripe.com/legal/dpa> | Cancel subscription |
| **Apple IAP** (via RevenueCat, iOS only) | Transaction id, subscription state | Apple-managed | Contract | Apple DPA via App Store Connect | Cancel subscription |
| **Google Play Billing** (via RevenueCat, Android only) | Same | Google-managed | Contract | Google DPA via Play Console | Cancel subscription |
| **Sentry** | User uuid (pseudonymous), URL paths, error stack traces, breadcrumbs (redacted). Edge Functions run server-side so cannot consult the browser consent state — capture there relies on the legitimate-interest basis with data minimisation: PostgREST errors are sanitized to message + SQLSTATE (row-bearing `details`/`hint` dropped) and the request envelope is stripped (`apps/backend/supabase/functions/_shared/sentry_scrub.ts`). | US (default) — verify project region | Legitimate interest (operational error monitoring) | <https://sentry.io/legal/dpa/> | Settings → Privacy & telemetry toggle on web (`apps/web/src/routes/settings/preferences/+page.svelte`); same toggle on mobile twin (`Settings → Privacy → Send error reports`) |
| **Open-Meteo** | Lat/lng of route waypoints for elevation API | EU | Legitimate interest (elevation rendering during route build) | <https://open-meteo.com/en/terms> | None practical |
| **Google** (Sign-In) | ID token validation; user-supplied email + name | Global | Consent (user picks Google) | <https://policies.google.com/privacy> | Don't use Google sign-in |
| **Apple** (Sign-In, scaffolded) | ID token validation; relay email if user chose private relay | Global | Consent | <https://www.apple.com/legal/privacy/> | Don't use Apple sign-in |
| **FCM** (Firebase Cloud Messaging, when push wired) | Push token + push payload | Global | Consent (user enables notifications) | <https://firebase.google.com/support/privacy> | Disable notifications |
| **APNs** (Apple Push Notification service, when push wired) | Same | Global | Consent | Apple DPA | Disable notifications |
| **Supabase Auth transactional email** | User email + auth event content (confirm-signup, password-reset) | Same as Supabase (`eu-west-2`) — see verify note | Contract | Covered by the Supabase DPA above | None (mandatory transactional emails) |

**Transactional-email verify note (audit/third-party-data-flows + audit/gdpr 2026-05-30 Critical):** `supabase/config.toml` declares no custom `[auth.email.smtp]` block, so confirm-signup / password-reset mail is sent by Supabase's own managed email service — a Supabase sub-processor, covered by the Supabase DPA already linked above, not a separate Resend / Postmark / in-house provider. **Before publishing, the operator must confirm the production project's dashboard (Auth → Emails → SMTP Settings) has no custom SMTP host configured.** If a custom SMTP provider *is* set there, add it as its own row with that provider's region + DPA — the dashboard setting is invisible to this repo.

## Sub-sub-processors

Each row above is itself a top-level provider. Their sub-processors (e.g. AWS for Sentry's hosting, GCP for Anthropic's hosting) propagate down. The Privacy Policy should point readers to each provider's own sub-processor list rather than enumerate the entire chain.

## Notification of changes

GDPR Art 28(2): we must notify users of "any intended changes concerning the addition or replacement of sub-processors". Mechanism we commit to in the Privacy Policy:

- Committed mechanism (matches the Privacy Policy §4): an **in-app notice** shown to registered users **at least 30 days before** a new sub-processor goes live. Users who object may withdraw consent and delete their account. (Earlier drafts floated a public changelog; that was dropped because there is no public web surface to host it, and an in-app notice reaches every active user directly.)

## Cross-border transfer mechanisms

For EU-data-subject flows landing in non-adequacy countries (most of the above are US):

- **Standard Contractual Clauses (SCCs)** under the European Commission's 2021 module 2 (controller → processor). Every provider above publishes these in their DPA.
- **TODO**: confirm we've executed each provider's DPA from our account console (Supabase, AWS, Sentry, RevenueCat, Anthropic, OpenAI). Self-service is the norm.
- **Transfer impact assessment**: for the US-hosted ones, document our reliance on EU-US Data Privacy Framework (EUDPF, replacing Privacy Shield post-Schrems II). Each provider's DPA states their certification status.

## Verification

The `/audit/third-party-data-flows` command walks the codebase and produces a current sub-processor table from `fetch(` + SDK imports. Re-run after every new integration; diff against this doc; close any drift.
