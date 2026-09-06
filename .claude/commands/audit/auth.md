---
description: Sweep every server-side trust boundary (SvelteKit +server / Edge Functions / Lambda) for caller-identity verification before doing work on user data
---

Audit auth gating across every server trust boundary in the project: SvelteKit server endpoints, Supabase Edge Functions, and the production AWS Lambda (`apps/web/lambda/coach/`).

## Goal

A trust boundary that does work on user data without first verifying who's calling it is a mass-exfil or impersonation bug. RLS catches a lot of this at the data layer (`/audit/rls`), but it does **not** save you from:

- A `+server.ts` handler that uses the service-role client (which bypasses RLS) without re-checking ownership.
- An Edge Function with `verify_jwt = false` that reads `request.body.user_id` and trusts it.
- A Lambda that reads a Supabase JWT from the Authorization header but never verifies the signature.
- A `:resourceId` handler that fetches the row without confirming the caller owns it.
- A streaming endpoint (SSE / WebSocket) that accepts `?token=` in the query string and skips the same verification the header path runs.

`/audit/auth` is the cross-cutting sweep over every boundary; `/audit/rls` is the data-layer complement; `/audit/edge-functions` is the per-function deep-dive (input validation, HMAC, body limits) that this audit links to but doesn't duplicate.

## What to check

1. **SvelteKit server endpoints.** Walk every `+server.ts` and `+page.server.ts` under `apps/web/src/routes/`. For each:
   - Identify the request handler (`GET`/`POST`/`PUT`/`DELETE`/`load`).
   - Confirm the handler resolves the caller via `locals.supabase` / `locals.session` (which is set in `hooks.server.ts` from the Supabase auth cookie) **before** touching user data.
   - Public-by-design endpoints (sitemap, OG image renderers, public-route lookups, OAuth callbacks) are an explicit allowlist — flag any that *aren't* documented as public but skip the auth check.
   - Any use of the service-role client (`createClient(..., SERVICE_ROLE_KEY)` or `serverSupabase()`) in a handler is a finding **unless** the handler re-validates the caller's ownership of the targeted row.

2. **Edge Functions `verify_jwt` discipline.** Read `apps/backend/supabase/config.toml`. For every `[functions.<name>]` block:
   - `verify_jwt = false` requires a documented reason (cron-only, webhook with HMAC verification, public-by-design). Cross-check the function's `index.ts` confirms the alternative auth mechanism.
   - `verify_jwt = true` (or the default) still requires the function to derive caller identity from the verified JWT — never from `request.body.user_id` or a header the client supplies.
   - Functions known to use the service-role key (`delete-account`, `export-data`, `refresh-tokens`, `strava-import`) must re-validate the caller's ownership of every row they touch before mutating it.

3. **AWS Lambda (production coach proxy).** Read `apps/web/lambda/coach/`. The Lambda receives the user's Supabase JWT in the Authorization header. Confirm:
   - The handler verifies the JWT signature (not just decoding the claims).
   - The `user_id` used to enforce the coach paywall + quota comes from the verified JWT subject, never from the request body.
   - The transport-agnostic core in `apps/web/src/lib/coach/` is the same logic the Lambda wraps — drift between the two would let the Lambda accept requests `/api/coach` would reject.

4. **Resource-ownership checks on path-param handlers.** Endpoints with a resource id in the URL (`/runs/[id]`, `/routes/[id]`, `/clubs/[id]/...`, `/og/run/[id].png`) must verify ownership/visibility **before** doing the work. The canonical pattern is `fetchClippedTrackForRun` for a run's track and `clipRouteForViewer` for a route's waypoints (decisions §33) and `auth.uid() = user_id` for owner-only routes — but at the boundary, you still need the explicit row read with the right RLS context.
   - The streaming/event-emitter endpoints (`live-broadcaster` in Edge Functions, any planned SSE in SvelteKit) are the canonical footgun — verify ownership on subscribe, not just on initial connect.

5. **Token-in-query-string.** Grep for `?token=` / `searchParams.get('token')` / similar. For any endpoint that accepts a token outside the Authorization header (browser `EventSource`, `<img>` with credentials, OG card share-links), verify the token-from-query path runs through the same Supabase JWT verification as the header path. Token-in-URL is an accepted footgun for SSE; the mitigation is short TTL + HTTPS + scoping to that single endpoint.

6. **Webhook receivers.** `strava-webhook` and `revenuecat-webhook` don't have a Supabase JWT — they authenticate via HMAC / shared secret + provider IP. Confirm each:
   - Verifies the signature with `crypto.subtle.timingSafeEqual` (not raw `===`).
   - Maps the incoming external user id to a project `user_id` via a stored mapping table, never via a header.
   - This overlaps `/audit/edge-functions` step 3 — call it out but defer detail.

## Report

Group findings by severity:

- **Critical** — a boundary lets an anonymous caller act on user data; a path-param handler doesn't verify ownership and lets one user read/modify another user's row; the Lambda accepts a JWT without verifying the signature.
- **High** — service-role client used in a handler with no caller-identity re-check; Edge Function with `verify_jwt = false` that trusts `request.body.user_id`; webhook handler uses `===` for signature comparison.
- **Medium** — public endpoint missing a comment explaining why it's public; token-in-query path that re-implements verification instead of reusing the header path.
- **Low** — undocumented public mount; verbose error responses that leak schema.

For each: file:line, the specific missing check, the worst-case blast radius (one-line). Don't fix without explicit confirmation — report only.

## Useful starting points

- `apps/web/src/routes/` — every SvelteKit server endpoint
- `apps/web/src/hooks.server.ts` — where `locals.supabase` / `locals.session` are populated
- `apps/web/lambda/coach/` — production Lambda wrapper, plus its transport-agnostic core in `apps/web/src/lib/coach/`
- `apps/backend/supabase/functions/` + `apps/backend/supabase/config.toml` — Edge Functions + their `verify_jwt` settings
- `docs/features/web_app_auth.md` — the documented web auth flow
- `apps/backend/CLAUDE.md` — function-by-function notes
- `docs/architecture/decisions.md` §33 (privacy-zone clipping), §53 (Lambda for coach) — relevant boundary ADRs
- The recent `fix(backend): auth-guard refresh-tokens Edge Function` commit (b3373c6) — canonical pattern for retrofitting JWT verification

## Delegate to

Use the `repo-security-auditor` agent: `"Audit every server-side trust boundary for caller-identity verification before doing work on user data."`

Read-only. Findings only.

## Output → `reviews/`

Persist the findings to `reviews/audit-auth.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
