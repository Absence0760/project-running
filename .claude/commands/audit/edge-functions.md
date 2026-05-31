---
description: Audit every Edge Function for JWT verification, input validation, body limits, and webhook HMAC
---

Audit every Edge Function under `apps/backend/supabase/functions/` for the standard auth and input-validation contract.

## Goal

`refresh-tokens` was the bug we just fixed (b3373c6) — a function that performed work without checking who called it. Find any other function with the same shape: missing JWT verification, accepting unbounded input, calling external APIs without HMAC verification, or trusting the request body without schema validation.

## The contract every function must meet

1. **Auth.** Either verifies a Supabase JWT (`Deno.env.get('SUPABASE_ANON_KEY')` + `verify_jwt: true` in `config.toml` or manual `getUser()` from the authorization header) **or** explicitly opts out with a documented reason (e.g. cron-only, or webhook from a trusted external service that authenticates with HMAC).
2. **Input validation.** Body parsed via Zod / manual checks. Rejects missing fields, invalid types, oversized payloads. Implicit limit: `Deno.serve` accepts up to ~6 MB by default; functions that don't need that should cap earlier.
3. **HMAC for webhooks.** Strava, parkrun, RevenueCat, Apple/Google push receipts — anything posted by an external service must verify a signature using `crypto.subtle.timingSafeEqual` (or equivalent), not raw `===` on the digest.
4. **Error shape.** Errors return JSON `{ error: string }` with 4xx/5xx status — not raw exception messages that leak schema or stack traces.
5. **Service-role key boundary.** `SUPABASE_SERVICE_ROLE_KEY` only used for operations that genuinely need to bypass RLS. Anywhere it's used in a code path that touches the caller's data, the caller's identity must be re-validated against the resource owner.

## What to check

1. List every directory under `apps/backend/supabase/functions/`. Cross-check `config.toml` `[functions.<name>]` blocks for `verify_jwt = true/false`.
2. For each function: read `index.ts`, identify the request entry point, walk the auth path, walk the input-parsing path, walk the external-call path. Score against the contract above.
3. Pay particular attention to: `coach` (LLM proxy — caller's quota?), `strava-import` (per-user OAuth tokens), `live-broadcaster`, `map-match`, `refresh-tokens` (already fixed — verify the fix held), any webhook receiver.
4. **Logging.** Grep for `console.log` of headers / tokens / bodies — leaked tokens in Supabase logs are a credential exposure even without a bug at the request level.

## Report

- **High** — function performs privileged work (DB writes, external API call with stored credentials, money movement) without verifying caller identity or HMAC.
- **Medium** — missing input validation that allows oversized payloads, missing rate-limiting on a costly path (LLM proxy without per-user cap).
- **Low** — verbose error responses, unstructured logging.

For each: function name, file:line, the missing check, what an attacker could do.

## Useful starting points

- `apps/backend/supabase/functions/` — every function
- `apps/backend/supabase/config.toml` — per-function `verify_jwt` settings
- `apps/backend/CLAUDE.md` — function-by-function notes
- `docs/features/integrations.md` — third-party integration shapes (Strava OAuth, parkrun)
- `docs/architecture/decisions.md` — search "Edge Function" for relevant ADRs
- The recent `fix(backend): auth-guard refresh-tokens Edge Function` commit (b3373c6) — the canonical pattern to mirror

## Delegate to

Use the `repo-security-auditor` agent: `"Audit every Edge Function for JWT verification, input validation, body limits, and webhook HMAC."`

Read-only. Don't edit function code without explicit instruction.

## Output → `reviews/`

Persist the findings to `reviews/audit-edge-functions.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
