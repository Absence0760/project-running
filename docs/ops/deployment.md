# Deployment overview

Where every service runs in production, who owns it, what it costs, and how it gets there.

This is the **plan**, not a record of what's already deployed. Most services are still local-only at the time of writing — the per-service docs spell out what's shipped vs. what's a forward-looking proposal. Update each section the moment something flips from "plan" to "live".

For the orthogonal "how a tag triggers a build" mechanics, see [releasing.md](releasing.md). For the strategic phase-by-phase architecture story, see [backend_scaling.md](../backend/backend_scaling.md). This file is the ops-side counterpart: where the bytes physically run.

---

## What runs where

| Service | Path | Provider | Status |
|---|---|---|---|
| Web app (static + Coach SSR) | `apps/web/` | **AWS** — S3 + CloudFront + Lambda Function URL + Route 53 (Terraform-provisioned, sops + AWS KMS for runtime secrets, OIDC-deployed) — see [decisions.md § 53](../architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) | Plan |
| Backend (Postgres + Auth + Storage + Edge Functions) | `apps/backend/` | **Supabase Cloud** | Plan |
| Job worker (Go) | `apps/job_worker/` | **Fly.io** (`job_worker`, region `lhr`) — single machine, distroless | Plan |
| OSRM (map-matching engine) | `apps/job_worker/osrm/` | **Fly.io** (`osrm`, region `lhr`) — single machine + Volume | Plan |
| GraphHopper (`round_trip` route generator, `foot` profile) | `apps/job_worker/graphhopper/` | **Fly.io** (`graphhopper`, region `lhr`) — serves the "Generate a route by distance" loop endpoint; reached by the generate-route Lambda over public https with an `X-Engine-Key` Caddy guard | Plan |
| graph_cycle (v3 loop generator map sidecar) | `apps/graph_cycle/` | **Fly.io** (`graph-cycle`, region `lhr`) — distroless Go service, parses an OSM PBF into an in-memory foot graph; in-process `X-Engine-Key` guard | Plan |
| Coach LLM | `apps/web/src/routes/api/coach/+server.ts` (deployed as a Node 24 Lambda) | Anthropic Claude (default) — `OPENAI_BASE_URL` for self-host | Plan (web) |
| Mobile Android | `apps/mobile_android/` | **Google Play** — Internal → Beta → Production tracks | Plan |
| Mobile iOS | `apps/mobile_ios/` | **App Store Connect** — TestFlight → App Store | Plan |
| Wear OS | `apps/watch_wear/` | **Google Play** — separate listing (`com.threkir.watchwear`) | Plan |
| Apple Watch | `apps/watch_ios/` | Bundled inside the iOS app — no separate listing | Plan |
| RevenueCat | (third party) | RevenueCat dashboard — webhook to `apps/backend/supabase/functions/revenuecat-webhook` | Plan |
| MapTiler | (third party) | MapTiler Cloud — `PUBLIC_MAPTILER_KEY` shared by web + Wear OS | Plan |
| Anthropic API | (third party) | api.anthropic.com — `ANTHROPIC_API_KEY` injected into the coach Lambda via env var (Terraform reads it from a sops-encrypted file under `infra/envs/<env>/secrets.enc.yaml`, encrypted with the env's AWS KMS key) | Plan |

Per-service deep dives:

- [`apps/backend/deployment.md`](../../apps/backend/deployment.md)
- [`apps/web/deployment.md`](../../apps/web/deployment.md)
- [`apps/job_worker/deployment.md`](../../apps/job_worker/deployment.md) (covers the OSRM stack too)
- [`apps/mobile_android/deployment.md`](../../apps/mobile_android/deployment.md)
- [`apps/mobile_ios/deployment.md`](../../apps/mobile_ios/deployment.md) (covers Apple Watch bundling)
- [`apps/watch_wear/deployment.md`](../../apps/watch_wear/deployment.md)

---

## Topology

```
                          users
                            │
              ┌─────────────┴─────────────┐
              │                           │
              ▼                           ▼
      threkir.com                  app stores
      ─────────────                  ──────────
      Route 53 → CloudFront          Play Store (Android)
        ├── default → S3 (static)    Play Store (Wear OS)
        └── /api/coach/* → Lambda    App Store (iOS + watchOS)
            │
            ├────► api.anthropic.com (or self-hosted via OPENAI_BASE_URL)
            │
            └────► Supabase Cloud (<ref>.supabase.co)
                   ├── Postgres + PostGIS
                   ├── Auth (email + Google + Apple)
                   ├── Storage (runs/, route-files/, run-photos/)
                   ├── Realtime
                   ├── Edge Functions (parkrun-import, refresh-tokens,
                   │                   strava-import, strava-webhook,
                   │                   revenuecat-webhook, delete-account,
                   │                   export-data)
                   └── pg_cron (mv refresh, rate-limit GC, ping cleanup)
                          ▲
                          │ service-role REST + Storage
                          │
                          ▼
                   Fly.io private network (6PN)
                   ├── job_worker  (1+ machines, shared-cpu-1x)
                   │     └─ drains kind='map_match' jobs
                   │     └─ drains future kinds (strava-webhook,
                   │        token-refresh, data-export per
                   │        backend_scaling.md)
                   └── osrm  (single machine, performance-2x, 8 GB)
                         └─ /match/v1/foot — talks only on 6PN,
                            no public route

                   third-party webhooks
                   ├── RevenueCat → revenuecat-webhook EF (HMAC)
                   └── Strava → strava-webhook EF (shared ?secret=)
```

---

## Domain and DNS

Buy `threkir.com` (or whatever the brand ends up as) at one registrar. Recommended: Cloudflare Registrar (no markup, free DNSSEC) or Porkbun.

Subdomain map:

| Subdomain | Points at | TTL |
|---|---|---|
| `threkir.com` | Route 53 ALIAS → CloudFront distribution | 300 |
| `www.threkir.com` | Route 53 ALIAS → CloudFront distribution | 300 |
| `api.threkir.com` | Reserved for the Supabase custom domain (Pro + add-on) — **not provisioned on the current Free tier**; clients use the raw `<ref>.supabase.co` | 300 |
| `worker.threkir.com` | Not exposed publicly — internal Fly.io 6PN address only | — |
| `osrm.threkir.com` | Same — never publicly resolvable | — |

The Coach endpoint lives under `threkir.com/api/coach`; CloudFront routes that path to a Lambda Function URL while everything else hits the S3 origin. Same domain, same CORS posture as the static site — see [decisions.md § 53](../architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages).

**Email-from domain** (for transactional email — password resets, magic links): `noreply@threkir.com` via SendGrid or Resend. Configure SPF + DKIM + DMARC at the same DNS provider. Supabase's default `noreply@mail.app.supabase.io` works in dev but ends up in spam folders for half the population in prod.

---

## Cost ladder

Numbers are USD/month at the launch tier (1000 active users, ~5 runs/user/month). Update as we scale.

| Service | Tier | Monthly |
|---|---|---|
| AWS — S3 + CloudFront + Lambda + Route 53 | Free tier covers Lambda + most CF egress for year one; Route 53 hosted zone $0.50; S3 storage <$0.50; CF egress past free tier ~$0.085/GB | $1.50 → ~$5 |
| Supabase | Pro ($25) — required for daily backups, custom domain, larger compute | $25 |
| Fly.io — job_worker | shared-cpu-1x, 256 MB | $5 |
| Fly.io — OSRM | performance-2x, 8 GB RAM, 20 GB Volume | $30 |
| Fly.io — bandwidth | mostly internal 6PN (free); Storage egress goes through Supabase | <$5 |
| MapTiler Cloud | Free tier (100k tile reqs/mo) → paid ~$25 above | $0 → $25 |
| Anthropic API | Coach usage at ~$0.003 per chat turn × ~5k turns/mo | $15 |
| Domain | Cloudflare Registrar (.app cost) | ~$1.5 |
| Email (Resend) | Free tier 3k emails/mo → $20 above | $0 → $20 |
| Apple Developer Program | $99/year ÷ 12 | $8.25 |
| Google Play Console | $25 once (not recurring) | $0 |
| RevenueCat | Free up to $2.5k/mo MTR → 1% above | $0 → variable |

**Launch baseline: ~$70/month.** Scaling drivers (CloudFront egress past 1 TB once the free year ends, OSRM RAM as we add regions, Anthropic at higher coach usage) push that toward $200–300 in the 10k-user range. Detailed projections per service in each `deployment.md`.

**Cost-minimized launch:** to ship for a few dollars a month, [`deployment_lean.md`](deployment_lean.md) records which services to defer (the two Fly routing engines, the worker, mobile stores, coach) and why each degrades gracefully — a **Lean** tier (~$34–49/mo, Supabase Pro + worker, backups intact) and a **Rock-bottom** tier (~$3–4/mo, Supabase Free + web-only). Every deferral re-attaches later by setting one env var or standing up one Fly app.

**Cost-control ceilings (what stops a runaway):**

Each spend vector carries at least two independent caps — one in IaC, one (where possible) in the provider console:

- **AWS account total** — `aws_budgets_budget` in [`infra/envs/prod/budgets.tf`](../../infra/envs/prod/budgets.tf) fires at 50 % / 100 % ACTUAL and 100 % FORECASTED of `monthly_budget_limit_usd` (default $200). The FORECASTED notification is the one that catches a runaway *during* the month — ACTUAL lags by up to 24 h.
- **Lambda concurrency** — `lambda_reserved_concurrency` in [`infra/envs/{prod,preview}/main.tf`](../../infra/envs/prod/main.tf) caps per-env concurrency (prod 20, preview 5). Throttle alarm fires on the first throttled invocation. Subscribed via `alert_emails` (validated non-empty + placeholder-rejected on both envs).
- **CloudFront edge cost** — `price_class = PriceClass_100` in [`infra/modules/web-stack/main.tf`](../../infra/modules/web-stack/main.tf) bills only NA + EU edge locations (skips SA + AU which 10× the per-GB cost). WAF `aws_wafv2_web_acl` rate-limits `/api/coach*` at 100 req / 5 min / IP via the scope-down filter — keeps static-asset traffic outside the rate-limit envelope.
- **CloudWatch log retention** — every log group sets `retention_in_days` ≤ 90 (default "Never expire" is $0.50/GB/month forever).
- **S3 lifecycle** — non-current versions expire at 30 d, incomplete multipart uploads abort at 7 d (prevents version-history cost ramp).
- **Coach per-user cap** — `TIER_LIMITS.free.dailyLimit` in [`apps/web/src/lib/coach/types.ts`](../../apps/web/src/lib/coach/types.ts) caps free at 2 messages/UTC-day, server-enforced before any Anthropic call. Pro is daily-uncapped but each turn is capped at `maxTokens = 2048`.
- **Anthropic console spend limit** — **MUST be set manually** at https://console.anthropic.com/settings/limits — code cannot enforce a provider-side ceiling on a key that's leaked from a sops file. The recommended floor is ~2× the projected monthly Anthropic spend (~$30/mo at launch baseline, so $60–$100 cap).
- **Supabase egress alert** — **MUST be set manually** in Supabase project settings. Code cannot enforce a daily-egress ceiling at the provider level.

The full audit + arch-guard tests covering each ceiling live in [`apps/web/src/lib/security_guards.test.ts`](../../apps/web/src/lib/security_guards.test.ts) under the "audit:cost-controls" section.

---

## Observability

The bar for v1 is: **someone gets paged when the site is down, can read the relevant logs, and can roll back without thinking.** Anything beyond that is nice-to-have.

| Surface | Tool | What we get | Cost |
|---|---|---|---|
| Web (AWS) | CloudFront access logs (S3) + CloudWatch Logs (Lambda) + CloudWatch Metrics | request volume, 4xx/5xx rate, cache hit ratio, Lambda p95 + cold-start rate | <$1/mo |
| Backend (Supabase) | Supabase Dashboard → Logs | Postgres slow queries, EF invocations, Auth events | included |
| Worker + OSRM (Fly.io) | `fly logs -a job_worker` / `fly logs -a osrm` + native metrics | per-machine CPU/RAM, restart history, log stream | included |
| Cross-service errors | **Sentry** — single org, separate projects per service | grouped exceptions, release tagging, breadcrumb trail on mobile | $0 (free tier) → $26 (team) |
| Uptime | **Better Stack** or **UptimeRobot** | external probe of `/`, `<ref>.supabase.co/rest/v1/…`, `threkir.com/api/coach` (HEAD-only) | $0 (free tier) |
| RevenueCat / Stripe events | dashboards on each | subscription lifecycle, churn signals | included |

**Alerts that page someone** (Better Stack → email + push):

1. `threkir.com/` returns non-200 for >2 min
2. `<ref>.supabase.co/rest/v1/runs?select=count` returns non-200 for >2 min (proxy for "PostgREST is up + DB reachable + RLS still permits reads")
3. Worker hasn't claimed a job in >10 min while `jobs.status='queued'` count > 0 (worker stuck)
4. OSRM `/health` non-200 for >5 min
5. Sentry: any new error class with >10 events in 5 min

Not paging on:
- Single failed Edge Function call (transient, EF logs catch the trend)
- Single client-side JS error (Sentry rolls up; investigate on a schedule)
- Worker `defer_job` calls (those are the *correct* response to a transient)

---

## Backups and disaster recovery

| What | How | RTO | RPO |
|---|---|---|---|
| Postgres | **Free tier today: no automated backups** — periodic manual `pg_dump` until the Pro upgrade (Pro: daily backups, 7-day window; PITR closes the gap to ~5 min) | 30 min | last manual dump (Pro: 24 h → ~5 min with PITR) |
| Storage (`runs`, `route-files`, `run-photos`) | Supabase Storage built-in (object versioning is opt-in per bucket — turn it on for `runs`, leave off for `run-photos` to save cost) | 2 h | 24 h |
| OSRM graph | Reproducible — `make download && make build` against a Geofabrik PBF; ~15 min on the build machine. We do **not** back up the extracted graph. | 15 min | N/A (regenerable) |
| Worker state | Stateless — every claim is a fresh DB read. Restart loses nothing. | seconds | 0 |
| Mobile / watch local stores | User's device + Supabase row mirror. The local store is a cache, not a source of truth. | N/A | N/A |
| Web deployment artifact | Static build zip attached to each `web@*` GitHub Release; coach Lambda versions retained by AWS for rollback via the `live` alias. Redeploy by re-running the workflow against an older tag. | 5 min | per-deploy |

**RTO** = recovery time objective (how long to get back up). **RPO** = recovery point objective (max acceptable data loss).

Run a full restore drill **once per quarter**. The procedure (in [`apps/backend/deployment.md`](../../apps/backend/deployment.md) § Disaster recovery): take a fresh Supabase project, restore the latest backup into it, point a staging build at it, verify a smoke run. Without a drill, the backup is a fiction.

---

## Secrets management

Never commit a production secret. Three storage layers, in order of preference:

1. **Provider-native secret store** — Supabase Vault (already set up for OAuth tokens via `get_integration_tokens` / `set_integration_tokens` per [decisions.md § 41](../architecture/decisions.md#41-oauth-tokens-are-stored-in-supabase-vault-not-as-plaintext-columns)), AWS Secrets Manager (the coach Lambda's `ANTHROPIC_API_KEY` and server-side `SENTRY_DSN`), Fly.io secrets, GitHub Actions secrets. Scoped to the service that needs them.
2. **`.env.local` files** — gitignored, present on developer laptops and CI runners that need them. Templates committed as `.env.example`.
3. **1Password (or similar) vault** — single source of truth for the keys themselves; CI runners read via the 1Password CLI rather than stuffing them into provider-native stores when possible. Keeps rotation a one-place change.

The matrix of "what lives where":

| Secret | Origin | Stored in |
|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase project settings | Fly.io secrets (worker) |
| `SUPABASE_ANON_KEY` (publishable) | Supabase | GitHub Secrets (injected into web build at CI build-time as `PUBLIC_SUPABASE_ANON_KEY`); Mobile build configs |
| `STRAVA_CLIENT_SECRET` | Strava developer dashboard | Supabase Vault |
| `STRAVA_VERIFY_TOKEN`, `STRAVA_WEBHOOK_SECRET` | We invent | Supabase EF env |
| `REVENUECAT_WEBHOOK_SECRET` | RevenueCat dashboard | Supabase EF env |
| `ANTHROPIC_API_KEY` | Anthropic console | sops-encrypted in `infra/envs/<env>/secrets.enc.yaml` (AWS KMS key per env) — Terraform decrypts at apply time and writes to the coach Lambda's `environment` block |
| `PUBLIC_MAPTILER_KEY` | MapTiler dashboard | GitHub Secrets (injected at CI build-time as `PUBLIC_*`); Mobile build configs |
| Android upload keystore | We generate once | GitHub Secrets (`ANDROID_KEYSTORE_BASE64`) |
| iOS distribution `.p12` + provisioning profile | Apple Developer | GitHub Secrets (`IOS_BUILD_CERTIFICATE_BASE64` etc.) |
| Wear OS upload keystore | We generate once | GitHub Secrets (`WATCH_WEAR_KEYSTORE_BASE64`) |
| Play `service-account.json` | Google Cloud | GitHub Secrets (`PLAY_SERVICE_ACCOUNT_JSON`) |
| App Store Connect `.p8` API key | Apple Developer | GitHub Secrets (`APP_STORE_CONNECT_API_KEY_BASE64`) |

**Rotation rule**: if a secret is suspected leaked, the rotation is in three steps: (1) issue a new key in the provider, (2) update everywhere it's stored, (3) revoke the old key. Step 3 is what "the old one is dead" really means — without it the leaked key still works.

**Operator scripts.** The AWS-side rotation flows are wrapped in [`bin/`](../../bin/README.md): `secret-set.sh <env> <KEY>` (rewrite a single sops-encrypted Lambda secret without opening an editor), `key-rotate.sh <env>` (re-encrypt under a new KMS key when the key itself is replaced), and `onboard-operator.sh <arn>` (grant a second human/role decrypt access on the env's KMS key). All take input via stdin / file / prompt — nothing routes secrets through argv or shell history.

---

## Release vs deploy

Two orthogonal axes. **Release** is "we cut a tagged version of the product"; **deploy** is "those bytes are now serving traffic". They overlap in different ways per service. Every `release-*.yml` deploy is **triggered by publishing a GitHub Release** for the tag below (a bare tag push no longer deploys — the published Release is the gate; see [releasing.md](releasing.md)):

| Service | Release tag | Deploy means |
|---|---|---|
| Web | `web@*` | CI builds → `aws s3 sync` to the prod bucket → `aws cloudfront create-invalidation` → `aws lambda update-function-code` for the coach handler. Live within ~60 s of CI success. |
| Backend (migrations + EF) | `backend@*` | Migrations applied + EFs uploaded to the linked Supabase project |
| Job worker | `worker@*` | `release-worker.yml` → `flyctl deploy --remote-only` against the `job_worker` Fly app |
| OSRM | `osrm@*` | `release-osrm.yml` → `flyctl deploy` against the `osrm` Fly app (image only — the graph rides along on the Volume); separate from the worker because it has different rebuild/restart cadences |
| graph_cycle | `graph-cycle@*` | `release-graph-cycle.yml` → `flyctl deploy` against the `graph-cycle` Fly app (the OSM PBF persists on the `graph_cycle_data` Volume; redeploy reparses it on boot) |
| GraphHopper | none | No release workflow yet — still a hand-rolled `flyctl deploy` against the `graphhopper` Fly app from a maintainer's laptop |
| Mobile Android | `mobile_android@*` | `.aab` uploaded to Play Internal track; manual promotion to Beta/Production from the Console |
| Mobile iOS | `mobile_ios@*` | `.ipa` uploaded to TestFlight; manual promotion to App Store from App Store Connect |
| Wear OS | `watch_wear@*` | `.aab` uploaded to Play Internal track for the separate Wear listing |

Tag → workflow → deploy is the canonical path for every Fly service except GraphHopper, which today still needs a hand-rolled `flyctl deploy` from a maintainer's laptop (no `release-graphhopper.yml` yet). See [`apps/job_worker/deployment.md`](../../apps/job_worker/deployment.md) § CI wiring.

---

## Pre-flight checklist before going live

Before flipping any service from "Plan" to live in the table at the top:

1. The per-service `deployment.md` is up to date — provider, region, instance size, command to deploy.
2. Secrets are loaded (provider-native + GitHub Actions where the workflow needs them).
3. DNS records resolve from a few networks.
4. An uptime probe is configured.
5. A rollback path is verified — actually run it once against a staging deploy.
6. Update the row at the top of this file from "Plan" to "Live (region)".
7. Tick the corresponding box in [roadmap.md](../product/roadmap.md).
8. If this enables a feature, flip the cell in [parity.md](../product/parity.md).

### Legal pages — before public launch

The legal pages (`/privacy`, `/terms`, `/cookie-notice`, `/health-data-notice`) are complete text
(decisions §242); what remains is operator work, not code:

1. Counsel review of the four pages (plus the docs under `docs/compliance/`).
2. Fill the operator facts in `apps/web/src/lib/legal/operator.ts` — registered postal address and
   governing-law state; the pages' "pending" lines disappear on their own.
3. Appoint the Art 27 EU + UK representatives (vendors + process in
   [docs/compliance/eu-representative.md](../compliance/eu-representative.md)) and fill them in the
   same file.
4. Create the `dmca@threkir.com` mailbox/alias and register the DMCA agent with the US Copyright
   Office (the Terms already name the address).
5. Confirm each sub-processor DPA is executed (list in
   [docs/compliance/sub-processors.md](../compliance/sub-processors.md)).
