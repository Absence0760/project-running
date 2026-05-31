---
description: Verify spend safeguards across AWS, Anthropic, Supabase, and the coach paywall — no single failure should produce a runaway bill
---

Audit every layer that bounds runaway spend across the stack. The product can be hit by four cost-vector accidents — a leaked Anthropic key, an unauthenticated Lambda burst, a CloudFront / Storage egress flood, a Supabase quota overrun — and each one should be capped by **at least two** independent ceilings (one in code / IaC, one in the provider console). Anything with a single point of failure is a finding.

## Goal

Per the deployment plan ([`docs/ops/deployment.md`](../../../docs/ops/deployment.md), [`apps/web/deployment.md`](../../../apps/web/deployment.md)) and the paywall plan ([`docs/features/paywall.md`](../../../docs/features/paywall.md)): a misconfigured deploy, a leaked credential, or an abusive user must not be able to run unbounded spend for hours before someone notices. The expected baseline is ~$70/mo at launch; a finding is anything that lets the bill exceed that by an order of magnitude before any alarm fires.

## What to check

### 1. Coach endpoint — per-user caps

The `/api/coach` Lambda is the single biggest spend lever (Anthropic per-token billing × no human in the loop). Verify:

- **Daily cap for free users.** `apps/web/src/lib/coach/types.ts` → `TIER_LIMITS.free.dailyLimit` is finite and ≤ 10. Pinned by `apps/web/src/lib/coach/types.test.ts` ("free — keeps a daily cap so anonymous abuse cannot drain quota"). If that test is gone or the value is `Infinity`, that's **High**.
- **Server-side enforcement, not UI.** `apps/web/src/lib/coach/handler.ts` calls `is_pro()` + `increment_coach_usage` and returns 429 *before* any provider streaming starts. Grep for `dailyLimit` — every check must be in the request handler, never on the client.
- **Per-turn token cap.** `TIER_LIMITS.{free,pro}.maxTokens` are finite and reasonable (≤ 4096). Both `providers.ts` and `handler.ts` must pass `limits.maxTokens` to the Anthropic SDK on every call — no path that omits it.
- **Pro tier still has a per-turn cap even though daily is uncapped.** Pro users pay $9.99/mo via RevenueCat — that's the soft revenue ceiling, but if a single Pro account chats 24/7 we still want bounded per-turn spend. `TIER_LIMITS.pro.maxTokens` ≤ 4096.
- **Rate limit DB function.** `check_rate_limit_tiered` in `apps/backend/supabase/migrations/20260605_001_rate_limits_tiered.sql` is wired into the Edge Functions that need it. SECURITY DEFINER + `auth.uid()` enforced (see `20260614_001_rls_hardening_pt2.sql`).

### 2. Coach endpoint — global circuit breakers

Per-user caps fail open if 10 000 stolen accounts each spend their daily quota at the same time. The global ceilings:

- **Lambda reserved concurrency.** `infra/modules/web-stack/variables.tf` → `lambda_reserved_concurrency` default is non-null and small (≤ 10). Per-env stacks (`infra/envs/{prod,preview}/main.tf`) pass explicit values; flag any env that omits it.
- **Lambda timeout.** `aws_lambda_function.coach` has `timeout` ≤ 30 s (per `apps/web/deployment.md` § Coach `/api/coach` specifics).
- **CloudWatch throttle alarm.** `infra/modules/web-stack/alarms.tf` has a `lambda_throttles` alarm (the cap being hit *should* page someone — a hit cap that no one notices means abuse went undetected).
- **Anthropic console spend limit.** This one can't be enforced in code. The audit report must call out whether the Anthropic console has a hard monthly spend ceiling on the production API key — if the user hasn't confirmed it, flag as **High** because key leak → unbounded spend regardless of every IaC guard.

### 3. AWS account — billing ceiling

- **`aws_budgets_budget` resource exists.** `infra/envs/prod/budgets.tf` defines an account-wide monthly budget. Three notifications minimum: `ACTUAL > 50 %`, `ACTUAL > 100 %`, `FORECASTED > 100 %`. Anything less is **High** (forecast is the only one that catches a runaway *during* the month — actual lags by up to 24 h).
- **`budget_alert_emails` is non-empty in `terraform.tfvars`.** A budget with zero subscribers is a no-op. The `validation` block in `variables.tf` should enforce `length(...) > 0`. If it doesn't, that's a **Medium**.
- **The budget limit is sane.** `monthly_budget_limit_usd` of `200` is the documented default; multi-thousand limits without an explanation are a finding (the point of a budget is to fire *before* it hurts).
- **Budgets is declared once, not per-env.** Account-wide budgets fire account-wide; declaring it in both `prod` and `preview` causes duplicate notifications. The current model is "prod stack owns it, preview doesn't"; flag any drift.

### 4. CloudFront + S3 — egress denial-of-wallet

A static site with poor cache-hit ratio can be drained by a bot. The protections:

- **CloudFront `price_class`.** `PriceClass_100` or `_200` (not `_All`). PriceClass_All bills from every edge location regardless of where users actually live.
- **S3 bucket is private + OAC-only.** No `Principal: "*"` policy, all four Public Access Block flags `true`. (Cross-references `/audit/infra` § 4 — if that audit is clean, this one is too.)
- **Lifecycle rule on non-current versions.** `aws_s3_bucket_lifecycle_configuration` on the site bucket expires old versions; missing = unbounded version growth at $0.023/GB/month forever.
- **CloudWatch log retention.** Every `aws_cloudwatch_log_group` has `retention_in_days` ≤ 90. Default = forever = $0.50/GB/month forever.
- **AWS WAF / rate-limit rule on the coach path.** `infra/modules/web-stack/waf.tf` declares an `aws_wafv2_web_acl` (CLOUDFRONT scope, `us_east_1` provider) with a single `rate_based_statement` (default 100 req / 5 min / IP) scope-down-statement-filtered to `/api/coach*`. Verify it's still attached via `web_acl_id` on `aws_cloudfront_distribution.this` (gated by `var.waf_enabled`, default `true`). If the resource is missing, the toggle is `false` in prod, or the scope-down filter is gone (so the rule rate-limits static-asset traffic too): **Medium**.

### 5. Supabase — quota overrun

Supabase Pro is $25 base + per-resource overage. The protections:

- **Per-user rate limits on every Edge Function** that does non-trivial work. `apps/backend/supabase/functions/*/index.ts` — every function that calls a third party (Strava, Anthropic, RevenueCat-aware writes) must call `check_rate_limit_tiered` first. Cross-references `/audit/edge-functions`.
- **Pg cron jobs aren't in tight loops.** `pg_cron.schedule` calls in migrations — verify intervals are reasonable (`* * * * *` minutely is suspicious; hourly / daily is the norm).
- **Storage quota.** No automated check available, but the report should call out whether Supabase project settings have a daily-egress alert configured (manual click-through in the Supabase console).
- **`runs` bucket has no public-read policy.** Storage objects are pulled via signed URLs with TTL. Cross-references `/audit/storage`.

### 6. Mobile / watch clients — feedback loops

A buggy retry loop on a million devices is the same as a denial-of-wallet attack. Spot-check:

- **Sync retry backoff.** `apps/mobile_android/lib/sync_service.dart` and `apps/watch_wear/.../SupabaseClient.kt` — failed uploads must back off (exponential or fixed-interval), not retry on every connectivity ping. A user offline for 8 hours then online with 50 queued runs should produce 50 sequential uploads, not 50 × N retries.
- **Coach client doesn't auto-retry on 429.** A 429 response returning to the client must NOT trigger an automatic resend — the user's quota is already exhausted, retrying just produces another 429. `apps/web/src/routes/coach/+page.svelte` and `apps/mobile_android/lib/screens/coach_screen.dart` — verify the error path surfaces a toast, not a retry.
- **Background sync intervals.** WorkManager (`apps/mobile_android/lib/background_sync.dart`) is hourly per the project doc; tighter intervals × millions of devices = Supabase quota burn.

### 7. Documentation matches reality

This audit's value depends on the docs being honest:

- **`apps/web/deployment.md` § Cost projection** matches the actual configured tiers (Anthropic model name, free-tier dailyLimit value, Lambda concurrency).
- **`docs/features/paywall.md`** free-tier dailyLimit value matches `TIER_LIMITS.free.dailyLimit` in code.
- **`infra/README.md` § Phase-0** does not still tell the user to set up billing alerts manually if they're now Terraformed.

## Report

- **Critical** — a known credential or token leak path with no monthly spend ceiling at the provider (e.g. Anthropic key in a sops file with no console-side cap), `lambda_reserved_concurrency` unbounded in prod, no `aws_budgets_budget` declared anywhere.
- **High** — `TIER_LIMITS.free.dailyLimit` removed or set to `Infinity`, daily cap not server-enforced (UI-only), AWS budget exists but `budget_alert_emails` empty / placeholder, no FORECASTED notification (only ACTUAL — fires too late), CloudFront `PriceClass_All` without justification, log retention infinite.
- **Medium** — WAF web ACL missing or detached from the distribution, scope-down filter gone (whole-site rate-limit), mobile retry loop without backoff, Supabase storage egress alert not configured, missing S3 lifecycle for non-current versions.
- **Low** — doc drift between `paywall.md` / `deployment.md` and the configured value, missing `validation` block enforcing non-empty `budget_alert_emails`, alarm exists but not subscribed to a real email.

For each finding: file:line + the concrete change. Don't apply fixes without explicit confirmation.

## Useful starting points

- `apps/web/src/lib/coach/types.ts` — `TIER_LIMITS` (the single source of truth for per-user caps)
- `apps/web/src/lib/coach/handler.ts` — server-side enforcement of those caps
- `apps/web/src/lib/coach/limits.ts` + `limits.test.ts` — header derivation + the test that pins the daily cap
- `infra/envs/prod/budgets.tf` — account-wide spend ceiling
- `infra/modules/web-stack/variables.tf` + `alarms.tf` — Lambda concurrency cap + throttle alarm
- `infra/modules/web-stack/main.tf` — CloudFront + S3 + Lambda + log group config
- `apps/backend/supabase/migrations/20260604_001_rate_limits.sql` + `20260605_001_rate_limits_tiered.sql` — DB-side rate limiter
- `docs/ops/deployment.md` § Cost ladder + § Observability — the cost projection these guards defend
- `apps/web/deployment.md` § Coach `/api/coach` specifics + § Cost projection — Lambda-specific spend math
- `docs/features/paywall.md` — tier definitions

## Delegate to

`general-purpose` agent with this file as the prompt body. Cross-cuts code + IaC + migrations + docs + provider-console gaps, so it doesn't fit one of the specialised auditors.

Read-only. Findings only. The audit must NOT mutate IaC, run `terraform plan`, hit AWS / Anthropic / Supabase APIs, or test the rate-limit endpoints (a load test against `/api/coach` is itself a small spend event).

## Output → `reviews/`

Persist the findings to `reviews/audit-cost-controls.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
