---
description: Sweep every logging + error-response path across the server tiers for PII, location data, health data, or secrets leaking into log lines, error bodies, or an external log sink (SOC 2 / GovRAMP)
---

Audit every log call and error-response path on the server side for personal data, location, health metrics, and secrets that must never be written to stdout/stderr, returned to a client, or shipped to an external log/error sink. Under the org's SOC 2 (all five TSCs) + GovRAMP posture, a token, an email, or a home GPS coordinate in a log line is a real finding, not a nit.

## Goal

Logs are the easiest place for regulated data to escape: they're verbose by default, they fan out to places the data model never intended (CloudWatch, the Supabase function logs, the Fly.io job-worker logs, the Sentry sink), and they outlive the row they describe. This app handles exactly the data that must not leak — email + auth identity, **precise GPS tracks and home location** (the whole point of `/audit/privacy-zones`), heart-rate / health metrics, and third-party OAuth tokens (Strava, RevenueCat, Stripe). This audit finds where any of that reaches a log line or an error body.

It is distinct from:
- `/audit/secrets` — secrets committed to git or inlined into a *client bundle*. This audit is about data emitted at *runtime* into logs.
- `/audit/third-party-data-flows` — the *intended* sub-processor map. This audit is about *unintended* leakage into a log/observability sink.
- `/audit/privacy-zones` — track clipping for *display* to non-owners. This audit is about tracks/coordinates landing in *logs*.

**Do not re-report** findings that belong to those — cross-reference instead.

## What this app must never log

- **Identity**: email, full name, `auth.uid()` paired with email, IP address tied to a user.
- **Location**: latitude/longitude, GPS track points, the home/privacy-zone centre, route start coordinates, `live_run_pings` / `race_pings` payloads.
- **Health**: heart-rate series, weight / `body_metrics`, age tied to identity.
- **Secrets / tokens**: Strava OAuth access+refresh tokens, RevenueCat/Stripe IDs and webhook payloads, JWTs, the service-role key, any `Deno.env`/`process.env` secret echoed into a log.
- **Bulk dumps**: `console.log(req.body)`, `console.error(err)` where `err` carries a full row or request, `JSON.stringify(user)`, logging an entire Supabase response.

## What to check

Sweep each server tier — the log surfaces differ per runtime:

1. **Edge Functions (Deno) — `apps/backend/supabase/functions/`.** `console.log/error/warn/info` go to Supabase's function logs. Highest-risk functions touch exactly the regulated data: `strava-webhook`, `strava-import`, `_shared/strava.ts` (OAuth tokens + imported GPS), `export-data` (the full DSAR bundle), `delete-account` (identity), `revenuecat-webhook` (billing identity). Flag any `console.*` that interpolates an email, token, coordinate, or a whole request/row.

2. **The Sentry sink — `apps/backend/supabase/functions/_shared/sentry.ts`.** This is the worst blast radius: anything attached to a Sentry event (error message, breadcrumb, `extra`, `tags`, request context) leaves the box for a third-party processor. Verify the captured payload is scrubbed — no email/token/coordinate in the error context, no raw request body. A leak here is **Critical**, not High, because the data crosses a trust boundary.

3. **Web server routes + Lambdas — `apps/web/src/routes/api/`, `apps/web/lambda/{coach,share-route,share-run}/src/`.** `console.*` here lands in CloudWatch. The coach route handles the user's prompt (which can contain personal context); the share-* lambdas resolve a run/route owner. Flag logged request bodies, prompts, owner identity, or error objects that carry a row.

4. **Go job worker — `apps/job_worker/internal/`.** `log.`/`slog.`/`fmt.Print*` go to Fly.io logs. The handlers process exactly the sensitive jobs: `handler_notification_email.go`, `handler_safety_email.go` (safety-contact identity + location!), `handler_web_push.go`, `handler_token_refresh.go` (OAuth tokens), `supabase.go`. Flag any recipient email, safety-contact detail, token, or coordinate written to a log. Confirm errors are logged by *kind/id*, not by dumping the payload.

5. **Error responses to the client.** A 500 that returns `err.message` or the stack to the browser/app can leak a SQL fragment, a row, or an internal path. Confirm the server tiers return a generic error to the caller and keep detail server-side (and that the server-side detail is itself scrubbed per the above). Check `_shared/handler_envelope.ts` and the web error handlers for the shape.

6. **Mobile `debugPrint` (`apps/mobile_android/lib/`, ~54 files).** Lower stakes (on-device, stripped in release by Flutter's `debugPrint` no-op-in-release behaviour — *verify that holds*), but a `debugPrint` of a GPS point or token can still surface in `adb logcat` / device logs during a crash or a connected-debug session. Flag debug logging of coordinates, HR, or tokens; note severity is Low–Medium unless it survives a release build.

## Report

- **Critical** — regulated data (email, coordinate, token, health metric) reaches an *external* sink (Sentry, and any third-party log shipper) or is returned in a client-facing error body.
- **High** — regulated data written to a server log (Supabase function logs, CloudWatch, Fly.io) that staff and infra can read; a bulk `req.body` / full-row / `console.error(err)` dump on a path that carries personal data.
- **Medium** — over-verbose logging that *could* carry personal data depending on input (logging an arg that's usually an id but can be an email); a `debugPrint` of sensitive data that may survive release.
- **Low** — undocumented logging intent; identifiers logged that are pseudonymous (`run_id`, `user_id` alone) where a redaction policy should still be written down.

For each finding: the `file:line`, the exact log/return statement, *which* regulated field it exposes, the sink it reaches, and the fix (log an id not the value; scrub the Sentry payload; return a generic client error; gate behind a redaction helper). Never paste a real captured value into the report — identify the field by name.

## Useful starting points

- `apps/backend/supabase/functions/_shared/sentry.ts` — the external sink; scrubbing here is the highest-value check
- `apps/backend/supabase/functions/_shared/strava.ts`, `functions/strava-webhook/index.ts`, `functions/strava-import/index.ts` — OAuth tokens + imported GPS
- `apps/backend/supabase/functions/{export-data,delete-account,revenuecat-webhook}/index.ts` — DSAR bundle, identity, billing
- `apps/job_worker/internal/handler_safety_email.go`, `handler_notification_email.go`, `handler_token_refresh.go` — safety-contact PII, recipient email, tokens
- `apps/web/src/routes/api/coach/+server.ts`, `apps/web/lambda/{coach,share-route,share-run}/src/index.ts` — user prompt + owner identity → CloudWatch
- `apps/backend/supabase/functions/_shared/handler_envelope.ts` — the error-response shape
- `docs/features/integrations.md`, `docs/backend/api_database.md` — where the regulated columns live

## Delegate to

Use the `compliance-auditor` agent: `"Audit every server-side logging and error-response path for PII, location, health data, or secrets leaking into logs or an external sink (SOC 2 / GovRAMP). Write the report to reviews/audit-pii-in-logs.md."` Read-only on the codebase — recommendations only, and never paste a found value into the report; identify the leaking field by name + location.

## Output → `reviews/`

Persist findings to `reviews/audit-pii-in-logs.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), one finding per entry with a `[ ]` status box, grouped by severity. If the file exists from a prior run, update it in place (`[x]` resolved with fix commit, `[~]` deferred with reason) rather than overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
