# Web app deployment plan

How `apps/web/` (SvelteKit 2 + Svelte 5) ships to production.

Operational counterpart of [`apps/web/CLAUDE.md`](CLAUDE.md) (stack, conventions, file layout) and [`apps/web/local_testing.md`](local_testing.md) (running it locally). For the cross-service overview see [`docs/deployment.md`](../../docs/deployment.md). For the rationale behind hosting choices see [`docs/decisions.md § 53`](../../docs/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages).

**Status: plan.** Today the web app exists as a working dev server only.

---

## Provider — AWS (S3 + CloudFront + Lambda + Route 53)

The web app has two parts:

1. **Static site** — every route except `/api/coach`. SvelteKit prerenders / SPA-renders these. Served from S3 (private bucket) via CloudFront with Origin Access Control (OAC).
2. **Server-side `/api/coach/+server.ts`** — needs a runtime that can stream Anthropic responses back to the client. Deployed as a Node 20 Lambda Function URL; CloudFront routes `/api/coach/*` to it as a separate behaviour on the same distribution.

Same domain, same CORS posture for both halves. No API Gateway in front of the Lambda — Function URLs are free, support response streaming, and skip the per-request API Gateway cost. ACM cert lives in `us-east-1` (CloudFront only reads from there, regardless of where the rest of the stack runs).

**Region:** `us-east-1` (N. Virginia) for everything, including the cert. CloudFront is global. The cert *must* live in `us-east-1` regardless of where the rest sits — the per-env stacks expose a `us_east_1` provider alias for that, which collapses to a no-op when the primary region is also `us-east-1`.

---

## Architecture

```
Route 53 (runonward.com, www.runonward.com)
   │  ALIAS / A
   ▼
CloudFront distribution (one per env: prod, preview)
   ├── default behaviour       → S3 origin (private, OAC) — SvelteKit static build
   ├── /api/coach/* behaviour  → Lambda Function URL (Node 20, response streaming)
   └── response headers policy → CSP / HSTS / X-Content-Type-Options / Referrer-Policy
                                 / Permissions-Policy

ACM cert (us-east-1) — auto-renew via DNS validation in Route 53

GitHub Actions
   │  OIDC AssumeRole (no long-lived AWS keys in GH Secrets)
   ▼
IAM role  s3:PutObject       on the env's artifacts bucket prefix
          cloudfront:CreateInvalidation  on the env's distribution
          lambda:UpdateFunctionCode      on the coach Lambda
          (and nothing else — least-privilege)
```

**Per-environment stacks**, never one bucket with prefixes — that mistake is too easy to make destructive. Two CloudFront distributions, two S3 buckets, two Lambdas. The Terraform setup uses one shared module (`infra/modules/web-stack`) consumed by per-env root modules (`infra/envs/{prod,preview}`) so the two stacks can't drift.

---

## Domain and routing

| Hostname | Routed to | TTL |
|---|---|---|
| `runonward.com` | Route 53 ALIAS → CloudFront (prod distribution) | 300 |
| `www.runonward.com` | Route 53 ALIAS → CloudFront (prod distribution) | 300 |
| `preview.runonward.com` | Route 53 ALIAS → CloudFront (preview distribution) | 300 |

ACM provisions the cert via DNS validation against Route 53 — no email validation, no manual cert renewal. Cert covers `runonward.com`, `www.runonward.com`, `preview.runonward.com`.

**Domain registration.** Either register `runonward.com` directly in Route 53 (~$12/year for `.app`), or register at Cloudflare Registrar / Porkbun and delegate the NS records to Route 53. Both are fine; Route-53-native is simpler since DNS + cert renewal use the same hosted zone.

---

## Terraform layout

Provisioned via Terraform — matches the workstation toolchain (`/home/jhoward/CLAUDE.md` lists `dnf via HashiCorp's official Fedora repo`). All infrastructure code lives under `infra/`:

```
infra/
├── modules/
│   └── web-stack/         # Reusable: S3 + CloudFront + Lambda + Function URL +
│                          # IAM + per-env KMS key + sops integration
├── envs/
│   ├── prod/              # Root module — calls web-stack module
│   │   ├── main.tf
│   │   ├── backend.tf     # Remote state in S3 with native lockfile
│   │   ├── terraform.tfvars
│   │   └── secrets.enc.yaml   # sops-encrypted (KMS key from this env's stack)
│   └── preview/           # Same shape, separate state, separate resources
├── dns/                   # Route 53 hosted zone, ACM cert in us-east-1
│   └── ...                # One stack — both envs share the zone
├── github-oidc/           # OIDC provider + per-env deploy IAM role
│   └── ...                # One stack — trust policies scoped per env
├── bootstrap/             # ONE-TIME: creates the S3 state bucket
│   │                      # the other stacks use as their backend.
│   │                      # State locking is S3-native (use_lockfile,
│   │                      # since Terraform 1.10) — no DynamoDB table
│   │                      # required. Run once with local state, then
│   │                      # ignored.
│   └── ...
└── .sops.yaml             # Routes each env's secrets.enc.yaml to that env's KMS key
```

**Bootstrap** (one-time, before any other Terraform runs):

```bash
cd infra/bootstrap
terraform init                              # local state — only the bootstrap uses it
terraform apply                              # creates: tfstate S3 bucket
```

**Per-stack init / apply** (after bootstrap):

```bash
cd infra/dns
terraform init
terraform apply                              # creates the hosted zone + ACM cert

cd ../github-oidc
terraform init
terraform apply -var "github_repo=<owner>/<repo>"

cd ../envs/prod
terraform init
terraform apply                              # creates the prod web stack
```

The `dns` stack outputs the hosted zone ID and cert ARN; per-env stacks read those via `terraform_remote_state`. Same pattern for the OIDC role ARN (consumed at GitHub Actions runtime, not at Terraform-apply time, so this is just for surfacing the value).

**Region.** Everything sits in `us-east-1`. The ACM cert for CloudFront *has* to live there regardless of where the rest of the stack runs, so `dns/main.tf` declares an explicit `us_east_1` provider alias — that's a no-op while the primary region is also `us-east-1`, but it's load-bearing if the stack ever moves.

**Runtime secrets via sops + AWS KMS.** `infra/envs/<env>/secrets.enc.yaml` is sops-encrypted with that env's KMS key (created by `web-stack`). Terraform reads it via the [`carlpett/sops`](https://registry.terraform.io/providers/carlpett/sops/latest) provider at apply time and writes the values into the Lambda's `environment.variables` block. Rotation is `sops infra/envs/prod/secrets.enc.yaml` → save → `terraform apply` — the Lambda config update happens in seconds. For non-interactive rotation use [`bin/secret-set.sh <env> <KEY> < value-file`](../../bin/README.md) (value comes via stdin/file, never argv, so it doesn't land in shell history).

---

## Build-time env vars (injected by CI before `npm run build`)

The static SvelteKit build inlines `PUBLIC_*` vars at build time. The CI workflow reads them from GitHub Secrets and writes a `.env.production` file before the build step:

| Variable | Source (GitHub Secrets) | Notes |
|---|---|---|
| `PUBLIC_SUPABASE_URL` | `PUBLIC_SUPABASE_URL` | once custom domain is live, use `https://api.runonward.com` |
| `PUBLIC_SUPABASE_ANON_KEY` | `PUBLIC_SUPABASE_ANON_KEY` | the **publishable** key, not service-role |
| `PUBLIC_MAPTILER_KEY` | `PUBLIC_MAPTILER_KEY` | shared with mobile + Wear OS |
| `PUBLIC_REVENUECAT_WEB_API_KEY` | `PUBLIC_REVENUECAT_WEB_API_KEY` | client-side web SDK key |
| `PUBLIC_SENTRY_DSN` | `PUBLIC_SENTRY_DSN` | optional — empty disables client-side capture |
| `PUBLIC_APP_RELEASE` | derived from CI tag (e.g. `web@1.2.3`) | tags Sentry events |

**Anything that should stay server-side does NOT have the `PUBLIC_` prefix and lives in the Lambda's env**, set by Terraform from the sops-encrypted file — not in the SvelteKit build, not in GitHub Secrets. The coach Lambda reads:

| Lambda env var | Source | Notes |
|---|---|---|
| `ANTHROPIC_API_KEY` | sops-encrypted at `infra/envs/<env>/secrets.enc.yaml` (env-specific AWS KMS key) | server-only — `/api/coach` reads it |
| `SENTRY_DSN` | same sops file | optional — server-side capture |
| `APP_RELEASE` | passed at deploy time as a Terraform variable, derived from the CI tag | tags Sentry events |
| `COACH_PROVIDER` / `OPENAI_BASE_URL` | optional — set in `terraform.tfvars` per env | for self-hosted Ollama / OpenAI-compatible service |
| `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY` | non-secret — passed as Terraform vars from CI environment, written to Lambda env directly | the Lambda needs them to validate the user's JWT and call `is_pro()` / `increment_coach_usage` RPCs |

---

## CI deploy path

Triggered by tagging `web@*`. The workflow at `.github/workflows/release-web.yml` (to be rewritten as part of the AWS migration):

1. Checks out the tag.
2. `aws-actions/configure-aws-credentials` with OIDC role assumption — never a long-lived `AWS_ACCESS_KEY_ID`.
3. `npm ci` at the workspace root.
4. Write `.env.production` from GitHub Secrets (the `PUBLIC_*` vars table above). Strip after build.
5. `npm run check --workspace=apps/web`.
6. `npm run build --workspace=apps/web` → produces `apps/web/build/` (static).
7. Build the coach Lambda zip — bundle `src/routes/api/coach/+server.ts` into a single `index.mjs` Node 20 handler, zip it.
8. `aws s3 sync apps/web/build/ s3://<bucket>/ --delete` — sync the static build.
9. `aws lambda update-function-code --function-name web-coach-prod --zip-file fileb://coach.zip` — update the Lambda.
10. `aws cloudfront create-invalidation --distribution-id <id> --paths "/*"` — invalidate the cache.
11. Attach the build zip to a GitHub Release for rollback.

Preview environment fires on every push to `main` against the `preview` env's bucket / distribution / Lambda, scoped to `preview.runonward.com`. Tags only deploy to `prod`.

---

## Coach `/api/coach` specifics — Lambda

The only SSR route in the app, and the only one that costs money to run.

**Cost model.** Each chat turn is a streaming call to `claude-sonnet-4-5` (`apps/web/src/lib/coach/providers.ts:49`). At ~3k input tokens + 1k output per turn × ~5k turns/month at launch ≈ $15. The hard ceiling is the per-user daily cap in `TIER_LIMITS.free.dailyLimit` (5/day for free, unlimited for pro per [paywall.md](../../docs/paywall.md)), enforced server-side in the Lambda via `is_pro()` + `increment_coach_usage` before any provider call streams. Per-turn token spend is bounded by `TIER_LIMITS.{free,pro}.maxTokens` (768 / 2048). Adjust either knob in `apps/web/src/lib/coach/types.ts` if Anthropic costs spike.

**Anthropic console hard spend cap — REQUIRED before first prod traffic.** Set a workspace-level monthly spend ceiling at <https://console.anthropic.com/settings/limits> on the production API key. This is the second of two ceilings on Anthropic spend — the first is the Lambda-level cap (`lambda_reserved_concurrency = 50` × per-turn `maxTokens` × per-day cap = bounded burst even with a leaked WAF). The console-side cap is the only thing that bounds spend if the key itself leaks: an attacker with the key reaches Anthropic directly, never touches CloudFront / WAF / the Lambda. Suggested initial cap: $50/mo (≈ 3× the projected at-launch spend of $15). Tracked in [audit/cost-controls](../../.claude/commands/audit/cost-controls.md) — that audit re-flags this each pass until the cap is confirmed set in the console (no programmatic check possible).

**Latency.** First-token latency is ~300-500 ms from `us-east-1` Lambda → Anthropic. Lambda response streaming is enabled (`InvokeMode = RESPONSE_STREAM` on the Function URL); CloudFront passes the stream through without buffering on the `/api/coach/*` behaviour by setting `OriginRequestPolicy.AllViewerExceptHostHeader` and disabling response buffering on the cache policy.

**Cold starts.** Node 20 Lambda cold start at 1 GB memory is ~400 ms. For a chat endpoint that's already streaming a multi-second response, cold-start overhead is barely visible. Provisioned concurrency is *not* configured — the cost isn't justified at pre-launch traffic.

**Memory + timeout.** 1024 MB memory (gives proportional CPU headroom for the Anthropic SDK), 30 s timeout (max for streaming through CloudFront — Function URL hard cap is 15 min but CloudFront cuts off long connections). If a user's coach turn truly runs longer than 30 s the response was already in trouble; surface the timeout cleanly client-side.

**Rate limit response.** When the Lambda returns 429, `apps/web/src/routes/coach/+page.svelte` surfaces a "Daily limit reached, upgrade to Pro for higher limits" toast. Verify this on every deploy that touches the coach surface.

**Self-hosted alternative.** Set `COACH_PROVIDER=openai` + `OPENAI_BASE_URL=http://...` in the Lambda env to point at an Ollama instance. We don't run one in production today, but local dev uses this path against a workstation Ollama for fast iteration.

---

## Push notifications service worker

`apps/web/static/sw.js` registers as the push-notification service worker (decisions §38). Two prerequisites for it to work in production:

1. **HTTPS only.** CloudFront + ACM handle this — the distribution forces `redirect-to-https` and serves a valid cert.
2. **VAPID keys.** Generated once with `npx web-push generate-vapid-keys`. The public key is checked into `apps/web/src/lib/push.ts`; the private key lives in Supabase EF env (`VAPID_PRIVATE_KEY`) so the EF can sign push messages. Update both halves together if rotated.

The `Notifications` row in the database carries the user's subscription endpoint (in `user_device_settings.prefs.push_subscription`); EF triggers (`notify_run_kudos` etc.) issue HTTP POSTs to those endpoints.

---

## Observability

| Surface | Tool | What |
|---|---|---|
| Static request logs | CloudFront access logs → S3 → Athena query when needed | request volume, status codes, cache hit ratio |
| Lambda logs | CloudWatch Logs (`/aws/lambda/web-coach-prod`) | every invocation, structured JSON, source-mapped errors |
| Lambda metrics | CloudWatch — `Errors`, `Duration` (p50/p95/p99), `ConcurrentExecutions`, `Throttles`, `InitDuration` (cold-start latency) | tied to alarms |
| Web Vitals | client-side via `@sentry/sveltekit` performance monitoring | LCP, CLS, INP, page views |
| Client errors | Sentry (frontend project) | bundled via `@sentry/sveltekit`, source-mapped |
| Server errors | Sentry (server) — bundled into the coach Lambda | grouped exceptions on coach failures |
| Coach usage | Anthropic console | per-key spend, request rate, model mix |

**CloudWatch alarms (wired by the `web-stack` module):**

- Lambda error rate >2% over 5 min → SNS topic `web-prod-alerts`
- Lambda p95 duration >25 s over 5 min (approaching the 30 s timeout) → same topic
- Lambda throttles >0 in any 1 min window → same topic
- 4xx rate at the CloudFront distribution >5% over 5 min → same topic (catches mass auth failures, SPA fallback misconfig, etc.)
- 5xx rate at the distribution >1% over 5 min → same topic

The SNS topic forks to email (oncall) and PagerDuty if/when set up. For pre-launch a single email subscription is enough; route to `oncall@runonward.com` once the team is real.

**Other alerts:**

- Sentry: any new error class with >10 events in 5 min
- Better Stack probe of `https://runonward.com/` returning non-200 for >2 min
- Anthropic cost above $X/day (Console → Usage → Alerts)

---

## Cost projection

| Component | Tier | Monthly |
|---|---|---|
| S3 | <1 GB storage + PUTs at deploy time | <$0.20 |
| CloudFront | Free tier 1 TB egress + 10M HTTPS req for the first 12 months; ~$0.085/GB after | $0 → ~$3 |
| Lambda | Free tier 1M req + 400k GB-s/mo; coach is paywalled + tier-rate-limited so requests are bounded | $0 |
| Lambda Function URL | Free | $0 |
| Route 53 | $0.50/mo per hosted zone + $0.40/M queries | ~$0.60 |
| ACM cert | $0 | $0 |
| CloudWatch Logs | <1 GB ingest at pre-launch | <$1 |
| Secrets Manager | $0.40/secret/mo × ~3 secrets (Anthropic, Sentry, Sentry DSN) | $1.20 |
| Anthropic API | Coach usage at launch | ~$15 |
| Sentry | Free tier (5k errors/month) | $0 |
| AWS WAF v2 | Web ACL $5 + rule $1 + ~$0.60/M requests | ~$6 |
| **Subtotal — launch** | | **~$23–26** |

**Egress is the variable that grows with users.** 1k users × 5 sessions/month × ~300 KB each ≈ 1.5 GB — far below the free tier. Once we're past 1 TB/month (≈ 3M sessions depending on cache hit rate), CloudFront billing kicks in at ~$0.085/GB.

---

## Rollback

Two layers:

1. **Static site rollback** — re-`aws s3 sync` from the build zip attached to the previous green tag's GitHub Release, then `aws cloudfront create-invalidation`. ~60 s end-to-end.
2. **Lambda rollback** — Lambda versions are auto-incremented on every `update-function-code`. Terraform creates an alias `live` that points at the most recent version; rolling back is `aws lambda update-alias --function-name web-coach-prod --name live --function-version <previous>`. ~10 s.

For the *git* rollback (so the next push doesn't re-deploy the broken version), tag a revert commit and let the workflow pick it up.

**Database-coupled rollback.** If a web release relied on a backend migration, rolling back the web deploy without rolling back the schema is fine (newer schema is read-compatible). The reverse — rolling back the schema while leaving the new web deploy serving — is what causes 500s. Always roll forward on the backend, even if the symptom looks like a backend issue.

---

## Disaster recovery

The web app is stateless from our side — the build is reproducible from any tagged commit, and the deployment artifact is downloadable from the GitHub Release for a year. There's nothing to back up that isn't in git.

The dependent services that *do* hold state (Supabase, RevenueCat, Anthropic) have their own DR stories.

If the AWS account itself is lost, recovery is roughly:

1. Spin up a new AWS account.
2. `cd infra/bootstrap && terraform init && terraform apply` — recreates the state bucket.
3. `cd ../dns && terraform init && terraform apply` — recreates the hosted zone + ACM cert.
4. `cd ../github-oidc && terraform init && terraform apply -var "github_repo=<owner>/<repo>"` — recreates the OIDC trust + deploy roles.
5. `cd ../envs/prod && terraform init && terraform apply` — recreates the prod web stack. **The KMS key for runtime secrets is recreated; the existing `secrets.enc.yaml` files are encrypted with the OLD KMS key and unrecoverable.** Re-issue the secrets fresh (Anthropic key, Sentry DSN), `sops` them against the new KMS key ARN, then re-apply.
6. Update the domain registrar's NS records to point at the new Route 53 hosted zone.
7. Push the desired tag to trigger a deploy.

For an interactive walkthrough that probes which phases are already done and resumes mid-flow, run [`bin/disaster-recovery.sh`](../../bin/README.md) — it wraps the same six steps with idempotent probes (`--status` for a read-only state check, no flag for the full walkthrough). The sequence above remains the canonical reference.

RTO: ~2 hours from a cold-start of a new account if the domain is at a registrar we control. Most of that is DNS propagation. RPO: 0 — there's no data on AWS.

---

## Production readiness checklist

- [ ] AWS account created (or sub-account in an org), root MFA enabled
- [ ] `infra/envs/prod/terraform.tfvars` sets `monthly_budget_limit_usd` + `budget_alert_emails` (Terraformed in `infra/envs/prod/budgets.tf`; fires at 50 % / 100 % ACTUAL + 100 % FORECASTED)
- [ ] `infra/bootstrap` applied (S3 state bucket created; locking is S3-native)
- [ ] AWS provider configured for `us-east-1` (the cert provider alias resolves to the same region; harmless)
- [ ] Domain `runonward.com` registered (Route 53 or external + delegated)
- [ ] Route 53 hosted zone live, NS records propagated
- [ ] ACM cert issued in `us-east-1`, DNS-validated
- [ ] Terraform applied (in order): `infra/dns`, `infra/github-oidc`, `infra/envs/preview`, `infra/envs/prod`
- [ ] GitHub OIDC role trust policy verified (only the repo + ref scopes intended can assume it)
- [ ] sops file populated: `infra/envs/prod/secrets.enc.yaml` (with `ANTHROPIC_API_KEY`, `SENTRY_DSN`); same for `preview/`
- [ ] GitHub Secrets populated: `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY`, `PUBLIC_MAPTILER_KEY`, `PUBLIC_REVENUECAT_WEB_API_KEY`, `PUBLIC_SENTRY_DSN`, `AWS_DEPLOY_ROLE_ARN_PROD`, `AWS_DEPLOY_ROLE_ARN_PREVIEW`
- [ ] First preview deploy green; smoke test sign-in + dashboard + run detail at `preview.runonward.com`
- [ ] First prod deploy green via tag `web@0.1.0`
- [ ] Coach endpoint responds (try a free user → expect a successful streamed reply, then a 4th request → expect 429)
- [ ] Push notification flow verified end-to-end (subscribe in Settings, trigger via a kudos on another account)
- [ ] CloudWatch alarms wired to SNS → email (or PagerDuty)
- [ ] Sentry frontend + server projects receiving events
- [ ] Better Stack probe configured
- [ ] Anthropic cost alert set
- [ ] Rollback drill: deploy a known-bad commit, run the rollback procedure, confirm the site recovers within 60 s
