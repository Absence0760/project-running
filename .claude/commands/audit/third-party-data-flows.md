---
description: Map every outbound personal-data hop into a sub-processor list ready for the Privacy Policy
---

Audit every outbound flow of personal data to a third-party processor. Output is the input to a GDPR Art 30 Record of Processing Activities and the sub-processor list of a Privacy Policy.

## Goal

A regulator's first ask in any incident is "show me your sub-processor list". A user's most-clicked Privacy Policy section is "who does my data go to?". Both need the same artefact: a table of provider × data × purpose × region × DPA + opt-out path. This audit produces it by walking the codebase.

## What to check

1. **Provider inventory.** Grep for every outbound endpoint by base URL:
   - `strava.com`, `connect.garmin.com`, `parkrun.com`
   - `api.anthropic.com`, `api.openai.com` (or `OPENAI_BASE_URL` for local Ollama)
   - `api.revenuecat.com`, `api.stripe.com`
   - `api.maptiler.com`, `*.tiles.mapbox.com` if any
   - `sentry.io`, `*.ingest.sentry.io`
   - Open-Meteo (`api.open-meteo.com` — elevation for route builder)
   - Google APIs (`googleapis.com`, `accounts.google.com`)
   - Apple (`appleid.apple.com`)
   - AWS endpoints (S3, CloudFront, Lambda, KMS, Route 53) — surfaced via Terraform
   - Supabase Cloud
   - Fly.io (`fly.io`, `fly.dev`) — Go worker + OSRM internal
2. **Per-flow analysis.** For each:
   - What user data leaves? (email, ip, run track, hr, payment intent, prompt text, error stack)
   - From where? (web client, Edge Function, Go worker, mobile native)
   - To which region? (US east-1, EU west-1, ap-southeast-2)
   - DPA / SCC URL?
   - Opt-out mechanism if any? (user disconnects integration, disables Sentry replay, etc.)
   - Legal basis? (consent / contract / legitimate interest)
3. **Tiles.** MapTiler logs the requesting IP + viewport coordinates. Every web map render → MapTiler log. Treat tile fetches as a personal-data hop.
4. **Coach prompts.** `apps/web/src/lib/coach/handler.ts` + the Lambda variant build a prompt that includes recent runs + plan + HR + weekly goal. That's HEALTH data sent to Anthropic / OpenAI. Confirm:
   - JWT-gated (only owner's data goes out)
   - Region of the API endpoint
   - Anthropic data-retention statement
   - OpenAI fallback (if used) data-retention statement
5. **Sentry.** Sentry sees `user_id` (pseudonymous uuid), URL paths, error stack traces. Replay (if enabled) sees DOM. Confirm replay is OFF by default + opt-in.
6. **Strava webhook payloads.** Strava POSTs activity ids to our webhook endpoint. Each event triggers a fetch of the full activity. The data goes from Strava → Go worker → Supabase. The flow direction is *inbound*, but it creates a *retention* obligation here that mirrors Strava's source.
7. **OAuth handoffs.** Google + Apple OAuth ID tokens are presented to Supabase Auth, which validates against the provider. Personal data exposed = email + uid + provider profile fields. Confirm the validation flow doesn't log the token.
8. **Email.** Local dev uses Mailpit. Prod uses Supabase's default email provider — confirm which (Resend? Postmark? in-house?). Each is a sub-processor.
9. **Sub-sub-processors.** AWS uses sub-processors of its own (CloudFront edge nodes by region). The project's Privacy Policy needs to point users to AWS's sub-processor list rather than enumerate it.

## Report

Output two artefacts:

### (A) Sub-processor table

| Provider | Data | Region | Purpose | DPA / SCC | Opt-out |
|---|---|---|---|---|---|

One row per flow. The user pastes this into the Privacy Policy.

### (B) Findings

- **Critical** — a sub-processor on the list that the user does not currently disclose anywhere.
- **High** — a flow that bypasses an opt-out the user has asserted in Settings (e.g. user disabled Sentry but it still fires).
- **Medium** — missing region detail or unclear data-retention period.
- **Low** — undocumented sub-sub-processor chain.

End with a **clean** section: outbound endpoints in the codebase where you confirmed no personal data leaves.

## Delegate to

Use the `compliance-auditor` agent: `"Map every outbound personal-data flow in this monorepo into a sub-processor list."`

Read-only. Output the table + findings. Don't recommend a default Privacy Policy — that's `intl-legal-doc-reviewer`'s job once the user drafts one.
