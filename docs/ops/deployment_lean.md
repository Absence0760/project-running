# Lean / minimum-cost deployment

A cost-minimized variant of [`deployment.md`](deployment.md). Same providers, same
mechanics, same IaC — it just **defers the expensive, additive services** and leans on
each one's graceful-degradation path so a fully usable web app ships for a few dollars a
month instead of ~$70.

This is a launch strategy, not a different architecture. Every deferred service re-attaches
later by setting one env var or standing up one Fly app — nothing here paints you into a
corner. Read [`deployment.md`](deployment.md) first for the full topology; this file only
records **what to leave out at launch and why it's safe**.

Web-first is already the house position ([decisions.md § 24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)) — the web app is the
canonical feature surface, so a web-only launch loses no capability the product depends on.

---

## Where the money is

Almost all of the full-plan cost is three deferrable line items: the two Fly.io routing
engines and the mobile-store fees.

| Service | Full-plan / mo | Load-bearing? | Lean verdict |
|---|---|---|---|
| Supabase Pro | $25 | Backups + no auto-pause | Keep on Lean; **Free ($0)** on Rock-bottom (see risk below) |
| Fly OSRM (8 GB) + 20 GB vol | ~$33 | No — map-matching is cosmetic | **Defer** |
| Fly GraphHopper (4 GB) + vol | ~$16.50 | No — route generation is additive | **Defer** |
| Fly graph_cycle (Go sidecar) | ~$5+ (not separately costed in the docs) | No — v3 loop generator, tried first for route generation | **Defer** |
| Fly worker (256 MB) | ~$5 | Email / push / live / photo thumbnails | Keep on Lean; **defer** on Rock-bottom |
| AWS S3 + CloudFront + Lambda + R53 (prod only) | ~$2–3 | Yes — the web app | Keep |
| Anthropic (Coach) | ~$15 usage | Optional feature | Hard-cap on Lean; **off** on Rock-bottom |
| Domain (.com) | ~$1 | Yes | Keep |
| MapTiler / Resend / RevenueCat | $0 free tier | — | Keep (free) |
| Apple Developer $99/yr + Play $25 once | ~$8.25 | Only for mobile launch | **Defer** (web-first) |

---

## Two tiers

### Lean — ~$34–49/mo

Fully functional web launch with backups intact.

- Supabase **Pro** ($25) — daily PITR backups + no auto-pause. Do not cut this once real
  users exist; the backup gap is not worth $25.
- AWS prod web-stack (~$3), `preview` env deferred.
- Fly **worker only** (~$5) — email, web push, live spectator, photo thumbnails, premium
  compute endpoints. No OSRM, no GraphHopper.
- Coach **on**, with a manual Anthropic console spend cap (~$30).
- No mobile stores.

### Rock-bottom — ~$3–4/mo (coach off) — SELECTED 2026-07-02

Absolute floor. Appropriate **pre-launch / no real users** or for a demo. Accepts real
tradeoffs (below).

- Supabase **Free** ($0) — **auto-pauses after 7 days idle and has no daily backups.**
- AWS prod web-stack (~$2–3), `preview` env deferred, coach Lambda left at 503.
- Domain (~$1/mo).
- **No Fly services at all** (no worker, no OSRM, no GraphHopper, no graph_cycle).
- Coach **off** (`ANTHROPIC_API_KEY` unset → endpoint returns 503).
- No mobile stores. MapTiler + Resend on free tiers.

> **Two Lambdas deploy either way.** The web-stack module provisions both the `coach` and the
> `generate-route` Lambda. Both still deploy at rock-bottom and cost effectively nothing when
> idle (pay-per-invoke) — coach returns 503 (no Anthropic key), generate-route returns 501 (no
> engines). No action needed; just don't be surprised they exist.

> **Rock-bottom risk — Supabase Free.** The 7-day inactivity pause and absence of backups
> make Free unsuitable the moment you have users whose data you can't afford to lose. The
> upgrade is one click in the Supabase dashboard (Free → Pro, +$25) with no redeploy — treat
> it as the first thing you do when launch stops being a demo.

---

## What each deferral costs the user experience

| Deferred | What breaks | What still works | Re-enable |
|---|---|---|---|
| **OSRM** | `map_match` jobs land `status='skipped'`; no road-snapped polyline overlay | Runs record, upload, and display normally | Stand up the `osrm` Fly app, set `OSRM_URL` on the worker; stale rows re-match on next claim (no schema change) |
| **GraphHopper + graph_cycle** | "Generate a route by distance" is unconfigured: with both `GRAPHHOPPER_URL` and `GRAPH_CYCLE_URL` unset the generate-route Lambda returns 501 and the web client falls back to its client-side OSRM heuristic | Manual route drawing, search, snap-to-road; the heuristic still produces a rough loop | Stand up the `graph_cycle` and/or `graphhopper` Fly app(s) + set `GRAPH_CYCLE_URL` / `GRAPHHOPPER_URL` (and the matching sops shared-secret keys) on the generate-route Lambda |
| **Worker** (Rock-bottom) | App-notification emails, weekly digest, web push, live spectator hub, **server-side photo thumbnails + EXIF defense-in-depth** all go dark; `strava_event` / `photo_process` / email jobs queue but don't drain | Auth email (password reset / magic link) via Supabase's own SMTP; runs record + sync + display; **client-side EXIF strip still runs before upload** (`exif_strip` twin), so photos don't leak GPS — they just get no server thumbnail | Deploy the `job_worker` Fly app (+$5); queued jobs drain on first boot |
| **Coach** | `/api/coach` returns 503 | Everything else | Set the Anthropic key + console cap; re-apply the env stack |
| **Mobile stores** | No Android / iOS / Wear listings | The web app is the full-feature surface | Apple Developer + Play Console enrolment + the mobile release workflows |
| **`preview` env** | No per-PR preview URLs | Prod deploys | `terraform apply` in `infra/envs/preview` (+1 KMS key, ~$1.50/mo) |

---

## Rock-bottom deploy steps

The mechanics are a strict subset of [`infra/README.md` § First-time deploy](../../infra/README.md#first-time-deploy)
and [`apps/backend/deployment.md`](../../apps/backend/deployment.md). The only differences from the full path are:
Supabase Free instead of Pro, **stop before the Anthropic secret phase** (coach stays 503),
and **skip every Fly service**.

### 1. Backend — Supabase Free

Create the project in the dashboard on the **Free** tier (region `eu-west-2`, or match your
users). No custom domain on Free — clients use the raw `https://<ref>.supabase.co` URL
everywhere `PUBLIC_SUPABASE_URL` / `public_supabase_url` is consumed (**do not** use
`api.threkir.com`; that subdomain is a Pro-only custom domain and won't resolve on Free).

```bash
cd apps/backend
supabase link --project-ref <ref>
supabase db push          # applies every migration; a few minutes on a fresh project
```

Deploy the Edge Functions you actually use (auth flows need none; parkrun/strava/account
lifecycle do — see [`apps/backend/deployment.md`](../../apps/backend/deployment.md) § Edge Function deploys).

> **Wire a custom SMTP even at rock-bottom.** Supabase's built-in auth email sender
> (`noreply@mail.app.supabase.io`) is heavily rate-limited (a few messages/hour) and
> spam-folders for a large fraction of recipients — so signup confirmation / magic-link /
> password-reset email is a real launch blocker on the default sender. Point Supabase Auth →
> SMTP settings at a free Resend account with SPF + DKIM on your domain ($0). This is
> independent of the deferred Go worker (which handles *app-level* email, not auth email).

### 2. Web — AWS prod only

Follow the infra walkthrough but apply only `bootstrap → dns → github-oidc → envs/prod`, and
**stop after the first prod apply**. The Lambda comes up with a placeholder coach key and
returns 503 for `/api/coach` — that is the intended rock-bottom state, not a failure. Skip
`sops-init` / `secret-set` / the re-apply.

```bash
bin/aws-preflight.sh          # confirm tooling + AWS auth
bin/deploy-prod.sh            # bootstrap + dns + oidc + envs/prod, idempotent
# STOP HERE — do not run sops-init / secret-set. Coach 503 is expected.
```

Register a domain first (any registrar; ~$1/mo amortized for a `.com`) and paste the four NS
records the `dns` stack outputs.

**Required `infra/envs/prod/terraform.tfvars` values — the apply hard-fails validation without them:**

- `public_supabase_url` — the raw `https://<ref>.supabase.co` (**not** the example's
  `api.threkir.com`, which is Pro-only).
- `public_supabase_anon_key` — the publishable (anon) key, not service-role.
- `budget_alert_emails` and `alert_emails` — **both required, both reject empty and
  `@example.com` placeholders** (the committed `terraform.tfvars.example` ships `you@example.com`,
  which fails validation by design). Set a real address on each.
- `monthly_budget_limit_usd` — lower to ~$50 for a lean launch (default 200).

The account-wide budget is applied by this **local** `deploy-prod.sh` run, not by the `web@*`
CI deploy (the OIDC deploy role deliberately lacks `budgets:*`), so run the local apply at least
once.

Set the required build-input GitHub secrets (`PUBLIC_SUPABASE_URL` = the same raw
`<ref>.supabase.co` URL, `PUBLIC_SUPABASE_ANON_KEY`, `PUBLIC_MAPTILER_KEY`) before the first
`web@*` deploy, then push to trigger `release-web.yml`.

### 3. Skip Fly entirely

Do not deploy `job_worker`, `osrm`, or `graphhopper`. Leave `OSRM_URL` and the generate-route
Lambda's `GRAPHHOPPER_URL` unset — both paths fail closed and degrade as in the table above.
`flyctl` isn't even needed on the operator machine at this tier.

---

## Manual guardrails (the IaC can't set these)

Even at the floor, wire the provider-side ceilings that code cannot enforce:

- **Supabase egress/usage alert** — project settings. (Free has hard caps but set the alert.)
- **AWS budget** — Terraformed (`infra/envs/prod/budgets.tf`), fires at 50/100 % ACTUAL +
  100 % FORECASTED. Set `monthly_budget_limit_usd` low (~$50).
- **Anthropic console spend limit** — only relevant once the coach is turned on; set at
  <https://console.anthropic.com/settings/limits>.

Full ceiling inventory: [`deployment.md` § Cost-control ceilings](deployment.md#cost-ladder).

---

## Turn-it-back-on ladder (as you grow)

1. **Supabase Free → Pro** (+$25) — the first upgrade; buys backups + kills the auto-pause. One
   dashboard click, no redeploy.
2. **Worker** (+$5) — restores email, web push, live spectator, photo thumbnails. Deploy the
   `job_worker` Fly app; queued jobs drain on first boot.
3. **Coach** (+~$15 capped) — set the Anthropic key + console cap, re-apply the env stack.
4. **OSRM** (+~$33) — when the map-match skip rate becomes a visible annoyance.
5. **GraphHopper (+~$16.50) and/or graph_cycle (+~$5)** — when users ask for route-by-distance
   generation; set `GRAPHHOPPER_URL` / `GRAPH_CYCLE_URL` + the matching sops shared secrets.
6. **`preview` env** (+~$1.50) — when you want per-PR preview URLs.
7. **Apple / Play + mobile builds** (+$8.25/mo) — when web traction justifies the store overhead.

---

## Cross-references

- [`deployment.md`](deployment.md) — the full cross-service plan this trims down.
- [`infra/README.md`](../../infra/README.md) — AWS Terraform how-to-apply.
- [`bin/README.md`](../../bin/README.md) — operator scripts (`aws-preflight`, `deploy-prod`, …).
- [`apps/backend/deployment.md`](../../apps/backend/deployment.md) — Supabase project setup + Edge Function deploys.
- [`apps/job_worker/deployment.md`](../../apps/job_worker/deployment.md) — the three Fly services, for when you re-enable them.
