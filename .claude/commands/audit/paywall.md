---
description: Verify paywalled features check tier; BYPASS_PAYWALL gated to dev only
---

Audit every paywall-gated feature for missing or weak `is_pro` checks. Confirm `BYPASS_PAYWALL` only takes effect in development.

## Goal

Per `docs/paywall.md`: features in the Pro tier should refuse access for free users at the API boundary, not just hide a UI element. Hiding a button without RLS or a server-side gate means anyone who knows the schema can call the same RPC and get the feature.

## What to check

1. **Feature registry.** Read `docs/paywall.md` for the canonical list of paywalled features (training plans beyond N, advanced training-load views, AI Coach quotas, etc.). For each: identify the client-side gate (`<ProGate>` or equivalent), the server-side gate (RLS / RPC body / Edge Function), and confirm both exist.
2. **Server-side gate is load-bearing.** Grep for `is_pro`, `subscription_tier`, `paywall`, `pro_only`. Trace where the check happens. **Hiding the UI is not a gate** — the API call must reject when called directly.
3. **`BYPASS_PAYWALL` env.** Grep for `BYPASS_PAYWALL`. Verify it's:
   - Only honored in development (`import.meta.env.DEV` or equivalent)
   - Never read on the server side without an explicit dev-mode check
   - Not in `PUBLIC_*` env (a `PUBLIC_BYPASS_PAYWALL` in prod is a public feature flag)
4. **RevenueCat / receipt validation.** If subscription state is set client-side then synced, confirm the server doesn't trust the client claim — a `subscriptions.tier = 'pro'` write must come from a webhook with HMAC verification, not from the user's own session.
5. **Coach quota (specific concern).** `get_coach_usage` + `is_pro` gate the daily cap. Verify the function body actually does the math server-side and the client doesn't pass a "remaining" count that the server trusts.
6. **Race conditions.** A user upgrades → calls Pro feature → downgrades. Is there a window where the gate uses a stale tier? `is_pro` should be a function over the latest `subscriptions` row, not a cached column on `user_profiles`.

## Report

- **High** — a paywalled feature is reachable by a free user via direct RPC / Edge Function call.
- **Medium** — gate exists but is bypassable (e.g. the RPC checks `is_pro` against a client-supplied user id rather than `auth.uid()`).
- **Low** — UI hides the feature but the function would reject anyway (defence-in-depth, not strictly required).

For each: feature name, the missing or weak gate, the file:line of both client and server.

## Useful starting points

- `docs/paywall.md` — feature registry + tier definitions
- `apps/web/src/lib/components/ProGate.svelte` — the canonical client-side gate pattern
- Edge Functions and RPC migrations that mention `is_pro`
- `apps/backend/supabase/migrations/20260429_001_subscription_paywall.sql`
- `docs/decisions.md` — search "subscription", "paywall", "tier"

Read-only audit.
