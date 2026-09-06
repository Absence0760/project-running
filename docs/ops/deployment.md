# Deployment overview

Where every service runs in production, who owns it, what it costs, and how it gets there.

This is the **plan**, not a record of what's already deployed. Most services are still local-only at the time of writing — the per-service docs spell out what's shipped vs. what's a forward-looking proposal. Update each section the moment something flips from "plan" to "live".

For the orthogonal "how a tag triggers a build" mechanics, see [releasing.md](releasing.md). For the strategic phase-by-phase architecture story, see [backend_scaling.md](../backend/backend_scaling.md). This file is the ops-side counterpart: where the bytes physically run.

---

## What runs where

| Service | Path | Provider | Status |
|---|---|---|---|
| Web app (static + Coach SSR) | `apps/web/` | **AWS** — S3 + CloudFront + Lambda Function URL + Route 53 (Terraform-provisioned, sops + AWS KMS for runtime secrets, OIDC-deployed) — see [decisions.md § 53](../architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) | **Live** — threkir.com serves from CloudFront (verified 2026-07-20) |
| Backend (Postgres + Auth + Storage + Edge Functions) | `apps/backend/` | **Supabase Cloud** | **Live** — project `mcbgrgvegqcmdmtraikl`, East US (Ohio) |
| Job worker (Go) | `apps/job_worker/` | **Fly.io** (`threkir-worker`, region `ord`) — single machine, distroless; sited next to the Ohio Supabase project, not next to the team | **Live** — deployed 2026-07-21, queue draining + live hub serving (auth JWKS-verified, smoke matrix passed); client cutover pending (`PUBLIC_LIVE_HUB_URL` / `LIVE_HUB_URL` unset, so recorders/spectators still ride Supabase Realtime) |
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
| `live.threkir.com` | CNAME → `threkir-worker.fly.dev` — the Go live spectator hub (TLS at Fly's edge via `flyctl certs add`) | 300 |
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
- **Lambda concurrency** — `lambda_reserved_concurrency` in [`infra/envs/{prod,preview}/main.tf`](../../infra/envs/prod/main.tf) caps per-env concurrency (prod 20, preview 5). Throttle alarms cover coach, generate-route and osrm-proxy; prod fires on the first throttled invocation (`lambda_throttle_alarm_threshold = 1`), preview at 5. Subscribed via `alert_emails` (validated non-empty + placeholder-rejected on both envs).
- **CloudFront edge cost** — `price_class = PriceClass_100` in [`infra/modules/web-stack/main.tf`](../../infra/modules/web-stack/main.tf) bills only NA + EU edge locations (skips SA + AU which 10× the per-GB cost). WAF `aws_wafv2_web_acl` rate-limits `/api/coach*` at 100 req / 5 min / IP via the scope-down filter — keeps static-asset traffic outside the rate-limit envelope.
- **CloudWatch log retention** — every log group sets `retention_in_days` ≤ 90 (default "Never expire" is $0.50/GB/month forever).
- **S3 lifecycle** — non-current versions expire at 30 d, incomplete multipart uploads abort at 7 d (prevents version-history cost ramp).
- **Coach per-user cap** — `TIER_LIMITS.free.dailyLimit` in [`apps/web/src/lib/coach/types.ts`](../../apps/web/src/lib/coach/types.ts) caps free at 2 messages/UTC-day, server-enforced before any Anthropic call. Pro is daily-uncapped but each turn is capped at `maxTokens = 2048`.
- **Anthropic console spend limit** — **MUST be set manually** at https://console.anthropic.com/settings/limits — code cannot enforce a provider-side ceiling on a key that's leaked from a sops file. The recommended floor is ~2× the projected monthly Anthropic spend (~$30/mo at launch baseline, so $60–$100 cap).
- **Supabase egress alert** — **MUST be set manually** in Supabase project settings. Code cannot enforce a daily-egress ceiling at the provider level.

The full audit + arch-guard tests covering each ceiling live in [`apps/web/src/lib/infra_guards.test.ts`](../../apps/web/src/lib/infra_guards.test.ts) under the "audit:cost-controls" section.

---

## Observability

The bar for v1 is: **someone gets paged when the site is down, can read the relevant logs, and can roll back without thinking.** Anything beyond that is nice-to-have.

| Surface | Tool | What we get | Cost |
|---|---|---|---|
| Web (AWS) | CloudWatch Logs (Lambda) + CloudWatch Metrics + CloudWatch alarms | request volume, 4xx/5xx rate, cache hit ratio, Lambda p95 + cold-start rate | <$1/mo |
| Backend (Supabase) | Supabase Dashboard → Logs | Postgres slow queries, EF invocations, Auth events | included |
| Worker + OSRM (Fly.io) | `fly logs -a threkir-worker` / `fly logs -a osrm` + native metrics | per-machine CPU/RAM, restart history, log stream | included |
| Cross-service errors | **Sentry** — single org, separate projects per service | grouped exceptions, release tagging, breadcrumb trail on mobile | $0 (free tier) → $26 (team) |
| Uptime | **Better Stack** or **UptimeRobot** | external probe of `/`, `<ref>.supabase.co/rest/v1/…`, `threkir.com/api/coach` (HEAD-only — expect **405 + `Allow: POST`**, not a 2xx: the coach Lambda is POST-only since [decisions § 896](../architecture/decisions.md), and before that a HEAD answered 401. Either status is proof the function is alive; configure the monitor on the status, not on 2xx) | $0 (free tier) |
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
3. **The private estate secrets repo** (`Absence0760/infra-secrets`, sops + per-project AWS KMS — see the repo-root CLAUDE.md § Production secrets) — durable source of truth for long-lived key material that must survive a lost workstation (e.g. the Android upload keystore at `running/android-upload-keystore.sops.yaml`). Access is IAM (`kms:Decrypt`); Bitwarden holds the owner's interactive credentials. There is no 1Password anywhere in this estate.

The matrix of "what lives where":

| Secret | Origin | Stored in |
|---|---|---|
| `SUPABASE_SECRET_KEY` (`sb_secret_…`; legacy `service_role` JWT also accepted) | Supabase project settings | Fly.io secrets (worker) |
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

### Owed: move `STRAVA_WEBHOOK_SECRET` off the query string, then rotate it

**Status: open. Do this before the Strava webhook path is considered production-hardened.**

The Strava callback is registered as `https://<host>/…?secret=<STRAVA_WEBHOOK_SECRET>`, because Strava's subscription API accepts a callback **URL** and nothing else — there is no place to configure a header. A query-string secret is written verbatim into the receiver's request log on **every** delivery (Supabase function logs for the Edge Function, the worker's HTTP log for the Go endpoint), so anyone with log read access recovers it and can forge activity ingests into any user's `runs` by enumerable Strava athlete id.

Both receivers now also accept the secret from an `X-Webhook-Secret` header, preferred over the query param and compared in constant time on both paths (`apps/backend/supabase/functions/strava-webhook/index.ts`, `apps/job_worker/internal/stravahook/server.go`). That is the half that is code. The rest is operator work and must run **in this order**:

1. Confirm both receivers are deployed with header support (the Go worker is the production path; the Edge Function is the rollback path — **both**, or a rollback re-opens the hole).
2. Mint a new `STRAVA_WEBHOOK_SECRET` (≥ 32 chars — both receivers refuse below that floor).
3. Set the new value on the worker (Fly.io secret) and the Edge Function env, and **re-register the Strava subscription** with a callback URL that still carries `?secret=` set to the new value. Strava cannot send the header, so the query path stays live for Strava itself; the point of the rotation is that the value in the logs is no longer the one anything else trusts.
4. Revoke the old value — it is in every historical log line and must be treated as public from here on.
5. Any non-Strava caller of these endpoints (replay tooling, smoke tests, the manual recipes in [manual_testing.md](../testing/manual_testing.md)) switches to the header.

Until step 4 lands, treat the secret as compromised-if-logs-are: the channel is authenticated but not confidential. Recorded in [decisions.md § 567](../architecture/decisions.md).

**Operator scripts.** The AWS-side rotation flows are wrapped in [`bin/`](../../bin/README.md): `secret-set.sh <env> <KEY>` (rewrite a single sops-encrypted Lambda secret without opening an editor), `key-rotate.sh <env>` (re-encrypt under a new KMS key when the key itself is replaced), and `onboard-operator.sh <arn>` (grant a second human/role decrypt access on the env's KMS key). All take input via stdin / file / prompt — nothing routes secrets through argv or shell history.

**Lambda env rotations need an alias repoint.** An env-only `terraform apply` publishes a new Lambda version but the eight web Lambdas' `live` aliases are CI-owned and stay behind, still serving the previous version's frozen env — the rotated secret isn't live until the alias moves (issue #590 defect 2). Finish every web-Lambda env rotation with `bin/lambda-alias-sync.sh <env>` (or cut a `web@*` release, whose deploy repoints the aliases anyway).

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

Tag → workflow → deploy is the canonical path for every Fly service, GraphHopper included — `release-graphhopper.yml` fires on a published `graphhopper@*` release, so no service is left on a hand-rolled `flyctl deploy` from a maintainer's laptop. See [`apps/job_worker/deployment.md`](../../apps/job_worker/deployment.md) § CI wiring.

### One-off: the SPA-shell cutover from `index.html` to `200.html`

adapter-static's `fallback` moves from `build/index.html` to `build/200.html`
so the prerendered landing page can occupy `build/index.html`. CloudFront's
403 -> shell `custom_error_response` is what serves every deep link (each
dynamic client route is a missing S3 key, so S3 answers 403 and the
distribution substitutes the shell at 200), so the mapping has to follow the
shell to its new name or every deep link serves the landing page instead of
the app.

**Neither single-step order is safe.** Apply the Terraform first and
`/200.html` is a key the bucket does not hold, so a deep link 403s into a
second 403. Deploy the tag first and `/index.html` is the landing page, so a
deep link serves marketing at 200. Both windows last until the other half
lands.

**Three steps, in this order, close both windows** (derived from the workflow
and the Terraform, never executed against AWS -- no lane holds credentials):

1. `aws s3 cp s3://<bucket>/index.html s3://<bucket>/200.html` -- pre-seed the
   CURRENT shell under its new name. The default `--copy-props default` copies
   `content-type` and `cache-control` from the source object, so the copy is
   byte- and header-identical to what a deploy would have written.
2. `terraform apply` the `custom_error_response` change in
   [`infra/envs/<env>`](../../infra/README.md). `/200.html` now resolves to the
   shell deep links were already being served, so nothing about them changes.
3. Publish the `web@*` release. `index.html` becomes the landing page and
   `200.html` the new shell, both in the same `aws s3 sync` pass, and the
   workflow's closing `create-invalidation --paths "/*"` clears any cached
   error-response body rather than waiting out a TTL.

Between 1 and 3 the pre-seeded object cannot be swept: the deploy's first
`aws s3 sync` runs `--delete` but excludes `*.html`, and the CLI's own
reference states that "files excluded by filters are excluded from deletion".
The same two filter rules are why the sync needs no edit for the new file --
pass 2's `--exclude "*" --include "*.html"` matches `200.html` on
last-match-wins, so it uploads with the 60 s HTML cache like any other page.

**The code half is landed; the three steps are all that is left.** When this
section was written the repo was mid-move and the paragraph here warned that
the five share Lambdas still embedded `build/index.html` at bundle time, so
step 3 would bake the landing page into every share handler whatever the
ordering. That is no longer the state. Verified in the tree: `svelte.config.js`
emits `fallback: "200.html"`, all five `apps/web/lambda/share-*/build.mjs`
resolve `build/200.html`, `spa_shell_head_signals.test.ts` reads that artifact,
and the `custom_error_response` in `infra/modules/web-stack/main.tf` names
`/200.html`. `apps/web/src/lib/seo/spa_shell_filename.test.ts` derives the
expected name from the adapter config and fails the PR if any of those rails
drifts back, so the code cannot regress under the operator ([decisions
§ 1272](../architecture/decisions.md)).

**Which environment is this?** The steps are per-distribution and `prod` and
`preview` are cut over independently. To find out whether an environment has
already been through them, read the live mapping rather than assuming:

```
aws cloudfront get-distribution-config --id <DIST_ID> --query 'DistributionConfig.CustomErrorResponses.Items[?ErrorCode==`403`].ResponsePagePath' --output text
```

`/index.html` means the cutover has not happened on that distribution and the
next `web@*` release will break every deep link on it; `/200.html` means steps
1 and 2 are done. `aws s3 ls s3://<bucket>/200.html` answers step 1 on its own.

**The one derived claim, and how to falsify it.** Everything above is read out
of the workflow, the Terraform and the AWS CLI reference -- no lane holds
credentials, so none of it has been executed against AWS. The step that carries
the most weight is that the pre-seeded `200.html` survives the release's
`aws s3 sync --delete`, which rests on excluded keys not being deletion
candidates. Confirm it the cheap way the first time through: run step 1, run a
release, and check `200.html` is still listed. If it is gone, the window
between the release's two sync passes is real and the pre-seed has to be
repeated after the deploy instead of before it.

Rollback is the mirror image: revert the Terraform first (the bucket still
holds an `index.html`, though after a post-cutover deploy it is the landing
page, so re-seed it from `200.html` before reverting), then redeploy the
previous tag.

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

The legal pages (`/privacy`, `/terms`, `/cookie-notice`, `/health-data-notice`, plus the
store-facing `/delete-account` instructions page — decisions §247) are complete text
(decisions §243); what remains is operator work, not code:

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
6. Enter `https://threkir.com/delete-account` as the **Delete account URL** in the Play Console
   Data safety form (and as the account-deletion link in App Store Connect). The page is live and
   pinned by `tests-e2e/legal/pages.spec.ts`; this item is just the console data entry.
