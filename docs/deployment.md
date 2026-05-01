# Deployment overview

Where every service runs in production, who owns it, what it costs, and how it gets there.

This is the **plan**, not a record of what's already deployed. Most services are still local-only at the time of writing — the per-service docs spell out what's shipped vs. what's a forward-looking proposal. Update each section the moment something flips from "plan" to "live".

For the orthogonal "how a tag triggers a build" mechanics, see [releasing.md](releasing.md). For the strategic phase-by-phase architecture story, see [backend_scaling.md](backend_scaling.md). This file is the ops-side counterpart: where the bytes physically run.

---

## What runs where

| Service | Path | Provider | Status |
|---|---|---|---|
| Web app (static + Coach SSR) | `apps/web/` | **Vercel** (canonical) — GitHub Pages mirror for the static slice | Plan |
| Backend (Postgres + Auth + Storage + Edge Functions) | `apps/backend/` | **Supabase Cloud** | Plan |
| Job worker (Go) | `apps/job_worker/` | **Fly.io** — single machine, distroless | Plan |
| OSRM (map-matching engine) | `apps/job_worker/osrm/` | **Fly.io** — single machine + Volume | Plan |
| Coach LLM | `apps/web/src/routes/api/coach/+server.ts` | Anthropic Claude (default) — `OPENAI_BASE_URL` for self-host | Plan (web) |
| Mobile Android | `apps/mobile_android/` | **Google Play** — Internal → Beta → Production tracks | Plan |
| Mobile iOS | `apps/mobile_ios/` | **App Store Connect** — TestFlight → App Store | Plan |
| Wear OS | `apps/watch_wear/` | **Google Play** — separate listing (`com.runapp.watchwear`) | Plan |
| Apple Watch | `apps/watch_ios/` | Bundled inside the iOS app — no separate listing | Plan |
| RevenueCat | (third party) | RevenueCat dashboard — webhook to `apps/backend/supabase/functions/revenuecat-webhook` | Plan |
| MapTiler | (third party) | MapTiler Cloud — `PUBLIC_MAPTILER_KEY` shared by web + Wear OS | Plan |
| Anthropic API | (third party) | api.anthropic.com — `ANTHROPIC_API_KEY` on Vercel | Plan |

Per-service deep dives:

- [`apps/backend/deployment.md`](../apps/backend/deployment.md)
- [`apps/web/deployment.md`](../apps/web/deployment.md)
- [`apps/job_worker/deployment.md`](../apps/job_worker/deployment.md) (covers the OSRM stack too)
- [`apps/mobile_android/deployment.md`](../apps/mobile_android/deployment.md)
- [`apps/mobile_ios/deployment.md`](../apps/mobile_ios/deployment.md) (covers Apple Watch bundling)
- [`apps/watch_wear/deployment.md`](../apps/watch_wear/deployment.md)

---

## Topology

```
                          users
                            │
              ┌─────────────┴─────────────┐
              │                           │
              ▼                           ▼
      runonward.app                  app stores
      ─────────────                  ──────────
      Vercel — web app +             Play Store (Android)
      /api/coach SSR                 Play Store (Wear OS)
            │                        App Store (iOS + watchOS)
            │
            ├────► api.anthropic.com (or self-hosted via OPENAI_BASE_URL)
            │
            └────► Supabase Cloud (api.runonward.app)
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

Buy `runonward.app` (or whatever the brand ends up as) at one registrar. Recommended: Cloudflare Registrar (no markup, free DNSSEC) or Porkbun.

Subdomain map:

| Subdomain | Points at | TTL |
|---|---|---|
| `runonward.app` | Vercel (apex) | 300 |
| `www.runonward.app` | CNAME → `runonward.app` | 300 |
| `api.runonward.app` | Supabase project URL (CNAME or A — depends on plan) | 300 |
| `worker.runonward.app` | Not exposed publicly — internal Fly.io 6PN address only | — |
| `osrm.runonward.app` | Same — never publicly resolvable | — |

The Coach endpoint and the Vercel SSR routes live under `runonward.app/api/...`; we don't carve a separate `coach.runonward.app` because that adds a CORS hop without a corresponding benefit. Server-Side Rendering happens on the same Vercel app as the static site.

**Email-from domain** (for transactional email — password resets, magic links): `noreply@runonward.app` via SendGrid or Resend. Configure SPF + DKIM + DMARC at the same DNS provider. Supabase's default `noreply@mail.app.supabase.io` works in dev but ends up in spam folders for half the population in prod.

---

## Cost ladder

Numbers are USD/month at the launch tier (1000 active users, ~5 runs/user/month). Update as we scale.

| Service | Tier | Monthly |
|---|---|---|
| Vercel | Hobby (free) for the static slice + Pro for SSR + bandwidth past 100 GB | $0 → $20 |
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

**Launch baseline: ~$80/month.** Scaling drivers (bandwidth, OSRM RAM as we add regions, Anthropic at higher coach usage) push that toward $200–300 in the 10k-user range. Detailed projections per service in each `deployment.md`.

---

## Observability

The bar for v1 is: **someone gets paged when the site is down, can read the relevant logs, and can roll back without thinking.** Anything beyond that is nice-to-have.

| Surface | Tool | What we get | Cost |
|---|---|---|---|
| Web (Vercel) | Vercel Analytics + native logs | request volume, error rate, p95, function runtime | included |
| Backend (Supabase) | Supabase Dashboard → Logs | Postgres slow queries, EF invocations, Auth events | included |
| Worker + OSRM (Fly.io) | `fly logs -a job_worker` / `fly logs -a osrm` + native metrics | per-machine CPU/RAM, restart history, log stream | included |
| Cross-service errors | **Sentry** — single org, separate projects per service | grouped exceptions, release tagging, breadcrumb trail on mobile | $0 (free tier) → $26 (team) |
| Uptime | **Better Stack** or **UptimeRobot** | external probe of `/`, `api.runonward.app/health`, `runonward.app/api/coach` (HEAD-only) | $0 (free tier) |
| RevenueCat / Stripe events | dashboards on each | subscription lifecycle, churn signals | included |

**Alerts that page someone** (Better Stack → email + push):

1. `runonward.app/` returns non-200 for >2 min
2. `api.runonward.app/rest/v1/runs?select=count` returns non-200 for >2 min (proxy for "PostgREST is up + DB reachable + RLS still permits reads")
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
| Postgres | Supabase Pro daily PITR backups, 7-day window | 30 min | 24 h (PITR closes the gap to ~5 min) |
| Storage (`runs`, `route-files`, `run-photos`) | Supabase Storage built-in (object versioning is opt-in per bucket — turn it on for `runs`, leave off for `run-photos` to save cost) | 2 h | 24 h |
| OSRM graph | Reproducible — `make download && make build` against a Geofabrik PBF; ~15 min on the build machine. We do **not** back up the extracted graph. | 15 min | N/A (regenerable) |
| Worker state | Stateless — every claim is a fresh DB read. Restart loses nothing. | seconds | 0 |
| Mobile / watch local stores | User's device + Supabase row mirror. The local store is a cache, not a source of truth. | N/A | N/A |
| Vercel deployment artifact | Tagged as a GitHub Release at every `web@*` tag; redeploy by re-running the workflow. | 5 min | per-deploy |

**RTO** = recovery time objective (how long to get back up). **RPO** = recovery point objective (max acceptable data loss).

Run a full restore drill **once per quarter**. The procedure (in [`apps/backend/deployment.md`](../apps/backend/deployment.md) § Disaster recovery): take a fresh Supabase project, restore the latest backup into it, point a staging build at it, verify a smoke run. Without a drill, the backup is a fiction.

---

## Secrets management

Never commit a production secret. Three storage layers, in order of preference:

1. **Provider-native secret store** — Supabase Vault (already set up for OAuth tokens via `get_integration_tokens` / `set_integration_tokens` per [decisions.md § 41](decisions.md#41-oauth-tokens-are-stored-in-supabase-vault-not-as-plaintext-columns)), Vercel encrypted env vars, Fly.io secrets, GitHub Actions secrets. Scoped to the service that needs them.
2. **`.env.local` files** — gitignored, present on developer laptops and CI runners that need them. Templates committed as `.env.example`.
3. **1Password (or similar) vault** — single source of truth for the keys themselves; CI runners read via the 1Password CLI rather than stuffing them into provider-native stores when possible. Keeps rotation a one-place change.

The matrix of "what lives where":

| Secret | Origin | Stored in |
|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase project settings | Fly.io secrets (worker) |
| `SUPABASE_ANON_KEY` (publishable) | Supabase | Vercel env, Mobile build configs |
| `STRAVA_CLIENT_SECRET` | Strava developer dashboard | Supabase Vault |
| `STRAVA_VERIFY_TOKEN`, `STRAVA_WEBHOOK_SECRET` | We invent | Supabase EF env |
| `REVENUECAT_WEBHOOK_SECRET` | RevenueCat dashboard | Supabase EF env |
| `ANTHROPIC_API_KEY` | Anthropic console | Vercel env |
| `PUBLIC_MAPTILER_KEY` | MapTiler dashboard | Vercel env (build-time `PUBLIC_*`); Mobile build configs |
| Android upload keystore | We generate once | GitHub Secrets (`ANDROID_KEYSTORE_BASE64`) |
| iOS distribution `.p12` + provisioning profile | Apple Developer | GitHub Secrets (`IOS_BUILD_CERTIFICATE_BASE64` etc.) |
| Wear OS upload keystore | We generate once | GitHub Secrets (`WATCH_WEAR_KEYSTORE_BASE64`) |
| Play `service-account.json` | Google Cloud | GitHub Secrets (`PLAY_SERVICE_ACCOUNT_JSON`) |
| App Store Connect `.p8` API key | Apple Developer | GitHub Secrets (`APP_STORE_CONNECT_API_KEY_BASE64`) |

**Rotation rule**: if a secret is suspected leaked, the rotation is in three steps: (1) issue a new key in the provider, (2) update everywhere it's stored, (3) revoke the old key. Step 3 is what "the old one is dead" really means — without it the leaked key still works.

---

## Release vs deploy

Two orthogonal axes. **Release** is "we cut a tagged version of the product"; **deploy** is "those bytes are now serving traffic". They overlap in different ways per service:

| Service | Tag triggers | Deploy means |
|---|---|---|
| Web | `web@*` | Vercel deployment goes live within ~30 s of CI build success |
| Backend (migrations + EF) | `backend@*` | Migrations applied + EFs uploaded to the linked Supabase project |
| Job worker | `worker@*` (proposed) | `flyctl deploy` against the worker app |
| OSRM | `osrm@*` (proposed) | `flyctl deploy` against the OSRM app — separate from the worker because it has different rebuild/restart cadences |
| Mobile Android | `mobile_android@*` | `.aab` uploaded to Play Internal track; manual promotion to Beta/Production from the Console |
| Mobile iOS | `mobile_ios@*` | `.ipa` uploaded to TestFlight; manual promotion to App Store from App Store Connect |
| Wear OS | `watch_wear@*` | `.aab` uploaded to Play Internal track for the separate Wear listing |

Tag → workflow → deploy is the canonical path for everything except the job worker and OSRM, which today still need a hand-rolled `flyctl deploy` from a maintainer's laptop. Adding `release-worker.yml` + `release-osrm.yml` workflows is a natural follow-up — see [`apps/job_worker/deployment.md`](../apps/job_worker/deployment.md) § CI wiring.

---

## Pre-flight checklist before going live

Before flipping any service from "Plan" to live in the table at the top:

1. The per-service `deployment.md` is up to date — provider, region, instance size, command to deploy.
2. Secrets are loaded (provider-native + GitHub Actions where the workflow needs them).
3. DNS records resolve from a few networks.
4. An uptime probe is configured.
5. A rollback path is verified — actually run it once against a staging deploy.
6. Update the row at the top of this file from "Plan" to "Live (region)".
7. Tick the corresponding box in [roadmap.md](roadmap.md).
8. If this enables a feature, flip the cell in [parity.md](parity.md).
