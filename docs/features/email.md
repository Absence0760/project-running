# Email & notification delivery

The single source of truth for the app's outbound email. For the **in-app**
notification inbox (the bell + Notifications tab) see `decisions.md § 38`; this
doc is the **email** layer that delivers a subset of those notifications plus
transactional / lifecycle mail — and the GoTrue **auth** emails (signup
confirmation, recovery, magic link, email change), which are rendered by the
`auth-email` Edge Function via GoTrue's send-email hook (see § GoTrue auth
emails below).

## Architecture

All product email is sent **server-side by the Go worker**
(`apps/job_worker/`), never from a client; auth email is sent server-side by
the `auth-email` Edge Function (below). These job kinds on the `jobs` queue
drive the worker:

- **`notification_email`** — mirrors a row in the `notifications` table (the
  same row the in-app bell renders). An AFTER-INSERT trigger on `notifications`
  enqueues one job per recipient; the handler gates on the recipient's
  `email_notifications` preference, then sends. `decisions.md § 117`.
- **`lifecycle_email`** — transactional / relationship mail that has **no**
  `notifications` row, keyed by a `template` name (`{user_id, template}`). The
  welcome (signup), the Pro-purchase receipt, and the payment-failed dunning.
  The **account-deletion receipt** (`account_deleted`) reuses this kind but is
  the one inline-address template: its payload carries `{email, locale}` and no
  `user_id` (the user is gone, so the worker can't resolve the address), and it
  dedups on the non-cascading `account_deletion_receipts` table instead of
  `lifecycle_email_log`. `decisions.md § 119` + `§ 121`.
- **`safety_email`** — safety-contact mail. Neither of the above: no
  `notifications` row, and the recipient may be a **non-user identified only by
  an email**, with per-finish context in the copy. Two templates — `confirm`
  (the opt-in request, enqueued by the `safety_contacts` AFTER INSERT trigger)
  and `finish` (the finish alert, enqueued by a `runs` AFTER INSERT trigger for
  every **confirmed** contact **regardless of `is_public`**, with the same 24h
  recency guard `run_completed` uses). Crucially **not** gated on the runner's
  `email_notifications` preference — a safety contact opted in explicitly and
  must not be silenced by the runner's social-email setting. `decisions.md § 131`.
- **`weekly_digest`** — the opt-in weekly engagement summary
  (`{user_id}`). Enqueued by a Monday pg_cron over opted-in recipients;
  the handler gates on the opt-IN `email_weekly_digest` pref + the
  `email_suppressions` hard-block, then sends a bounded localized summary with
  an RFC 8058 one-click unsubscribe. `decisions.md § 174`.
- **`lifecycle_drip`** — staged engagement nudges keyed off the user's own
  activity timeline (`{user_id, template}` — `drip_onboarding`,
  `drip_reengagement`, `drip_streak`). The third engagement stream, built on the
  SAME rails as the digest. A daily `enqueue_lifecycle_drip()` pg_cron does ALL
  the cohort selection in SQL (onboarding = account 2–6 days old with no run;
  re-engagement = had a run >30 d ago, no cross-modal activity in 30 d; streak =
  ran the last two days, not yet today), writing the chosen template into the
  payload. The handler gates on a **separate** opt-IN `email_lifecycle_drip`
  pref (default off, never inferred from the digest opt-in) + the same
  `email_suppressions` hard-block, then renders the fixed per-template copy with
  an RFC 8058 one-click unsubscribe scoped to the drip stream. `decisions.md § 177`.

A **non-email** job kind reuses the same notifications rows over a
different transport:

- **`web_push`** — the browser Web Push channel (migration `20261219_001`). The
  sibling of `notification_email`: an AFTER-INSERT trigger on `notifications`
  enqueues one `web_push` job per recipient **who has a browser subscription**
  (the trigger gates on `user_device_settings.prefs.push_subscription` presence
  to avoid no-op jobs for the push-less majority). The handler
  (`handler_web_push.go`) gates on a **separate** `push_notifications`
  preference (same `all|important|off` shape as `email_notifications`, but
  independent — muting one channel doesn't mute the other), then POSTs an
  encrypted Web Push message (RFC 8291) to each of the user's subscribed
  browsers, signed with the operator's VAPID key (RFC 8292). A dead endpoint
  (404/410) is pruned via the `clear_push_subscription` RPC; a 429/5xx defers.
  `web_push_sent_at` is the per-channel idempotency guard. The crypto is
  stdlib + the worker's existing `golang-jwt` (package `internal/webpush/`) —
  no third-party web-push library.
- **`native_push`** — the locked-phone leg (migration `20270212_001`). The
  THIRD device-delivery sibling: the SAME notifications AFTER-INSERT fan-out, a
  DIFFERENT enqueue trigger (gated on the recipient having an enabled
  `device_tokens` row), the SAME `push_notifications` preference web-push gates on
  (one "push" channel covers browser + native — no separate pref), and a SEPARATE
  `native_push_sent_at` send-state guard. The handler (`handler_native_push.go`)
  fans out over the user's enabled device tokens, routing on
  `device_tokens.platform`: `android` → FCM HTTP v1, `ios` → APNs HTTP/2 (sender
  package `internal/nativepush/`, stdlib + `golang-jwt`, no Firebase Admin SDK).
  A dead token (FCM `UNREGISTERED` 404 / APNs 410) is pruned via
  `clear_device_token`; a 429/5xx defers. Gated on operator-supplied
  Firebase/APNs credentials (below) — unset → jobs finish done, rows stay
  pending. `decisions.md § 161`.

Shared pieces:

- **Transport** — `internal/mailer.go` `SMTPSender` (Mailpit in local dev on
  `127.0.0.1:54325`; a provider's SMTP — Resend / SES — in prod). Sent as
  **multipart/alternative**: a branded, email-client-safe HTML part (table
  layout, inline styles, ≤600 px card, teal header matching app.css
  `--color-primary`, H1, CTA button, footer, inbox preheader) + a plain-text
  fallback. Gated on `SMTP_HOST` — unset → the worker drains the jobs without
  sending (so existing deploys are unaffected).
- **Address** — resolved via the GoTrue admin API (email lives only in
  `auth.users`, not a public table).
- **Localization** — `internal/email_i18n.go` holds a per-locale catalogue for
  all six app locales (`en/de/fr/es/ja/pt-BR`). The recipient's language comes
  from `user_settings.prefs.locale`, which web + mobile write as a side effect
  of the language picker (`decisions.md § 120`). Unknown/region tags normalize
  to a supported locale; English is the per-key fallback. `<html lang>` is set.
  A catalogue-parity test mirrors the web/mobile l10n-parity tests.
- **Preference** — `user_settings.prefs.email_notifications` (`all | important
  | off`, default `important`) gates the **notification** channel only;
  transactional/lifecycle mail ignores it (you can't opt out of a receipt).
  Toggle on web `/settings/preferences` + mobile Settings → Preferences.
  Registry: `docs/backend/settings.md`.
- **Idempotency** — `lifecycle_email_log (user_id, template)` is a send-once
  guard for **once-per-account** templates (welcome only). Recurring
  transactional templates (Pro receipt, dunning) deliberately skip it — the
  enqueue trigger's transition guard is the dedupe. The **account-deletion
  receipt** can't use `lifecycle_email_log` (it FK-cascades away with the
  deleted user), so it dedups on the non-cascading `account_deletion_receipts`
  table keyed by a hash of the address. Delivery is at-least-once.

## Shipped

| Email | Kind | Trigger | Localized | ADR |
|---|---|---|---|---|
| Notification → email (kudos, comment, follow, event RSVP/cancel/reminder, plan update, message, club post, run completed) | `notification_email` | `notifications` AFTER INSERT, gated on `email_notifications` | ✓ | §117 |
| **Event-day reminders** (scheduled) | `notification_email` (`event_reminder`) | hourly pg_cron `enqueue_event_reminders()` over `going` RSVPs in the next 24 h | ✓ | §117 |
| **Welcome** ("thanks for signing up") | `lifecycle_email` (`welcome`) | `user_profiles` AFTER INSERT | ✓ | §119 |
| **Pro-purchase receipt** | `lifecycle_email` (`pro_welcome`) | `user_profiles` AFTER UPDATE, `subscription_tier` → paid | ✓ | §121 |
| **Payment-failed dunning** | `lifecycle_email` (`payment_failed`) | `user_profiles` AFTER UPDATE, `billing_issue_at` null→non-null | ✓ | §121 |
| **Safety-contact confirm** (opt-in request) | `safety_email` (`confirm`) | `safety_contacts` AFTER INSERT | ✓ | §131 |
| **Safety-contact finish alert** (any finish, incl. private) | `safety_email` (`finish`) | `runs` AFTER INSERT, per confirmed contact, 24h recency, **no `is_public` gate, no preference gate** | ✓ | §131 |
| **Account-deletion receipt** | `lifecycle_email` (`account_deleted`) | `delete-account` EF enqueues it **inline** (address + locale in payload, no `user_id`) AFTER the cascade; send-once via the non-cascading `account_deletion_receipts` table | ✓ | §121 |
| **Web push** (browser system notification, same notification rows) | `web_push` | `notifications` AFTER INSERT, gated on a registered `push_subscription` + the separate `push_notifications` pref | n/a (title/body from the shared catalogue) | §133 |
| **Native push** (locked-phone FCM/APNs, same notification rows) | `native_push` | `notifications` AFTER INSERT, gated on an enabled `device_tokens` row + the same `push_notifications` pref | gated on operator FCM/APNs creds (title/body from the shared catalogue) | §166 |
| **Lifecycle drip** (onboarding / first-week / re-engagement / streak nudges) | `lifecycle_drip` (`drip_onboarding`, `drip_first_week`, `drip_reengagement`, `drip_streak`) | daily pg_cron `enqueue_lifecycle_drip()` selects the cohort in SQL; handler gates on the opt-IN `email_lifecycle_drip` pref + `email_suppressions`; RFC 8058 one-click unsubscribe (`/unsubscribe/lifecycle-drip`). **SEND fail-closed on the unset SMTP credential + CISO/counsel sign-off** (built, migration `20270223_001`) | ✓ | §177 |
| Branded HTML + inbox preview text | — | all email of the above | ✓ | — |

All shipped emails are end-to-end tested against the local Docker Mailpit
(`http://127.0.0.1:54324`); none required Firebase/APNs credentials.

## GoTrue auth emails (`auth-email` Edge Function)

GoTrue's own transactional emails — signup confirmation, password recovery,
magic link / email OTP, invite, email change, reauthentication — used to be
GoTrue's built-in English-only templates, a separate surface from the localized
worker pipeline above (the 2026-07 i18n-readiness audit's one High finding).
They are now rendered and sent by the `auth-email` Edge Function
(`apps/backend/supabase/functions/auth-email/`), wired in as GoTrue's
**send-email auth hook** (`config.toml [auth.hook.send_email]` locally;
Dashboard → Auth → Hooks in prod):

- **Trust boundary** — GoTrue signs each hook POST per the Standard Webhooks
  spec (`webhook-id` / `webhook-timestamp` / `webhook-signature` over the raw
  body, HMAC-SHA256 keyed by the base64 payload of the `v1,whsec_…` secret in
  `SEND_EMAIL_HOOK_SECRET`; `|`-separated secrets for rotation). The function
  is `verify_jwt = false` (GoTrue sends no Supabase JWT), so the signature
  check is the entire gate and it fails closed: missing secret → 503, missing
  or invalid signature / >5-min-stale timestamp → 401, 64 KB body cap.
  Hook-supplied recipients (`user.email` / `user.new_email`) pass
  `isValidRecipient` before reaching the MIME `To:` header or the SMTP
  `RCPT TO` command (no control chars / brackets / delimiters, single `@`,
  RFC 5321 length cap — header/command-injection defence in depth on top of
  GoTrue's own format validation); an invalid recipient is a 400
  `invalid_recipient`, never a silent skip, and `smtpSend` re-checks at the
  wire as a last-line guard. Pinned by `lib.test.ts` + `handler.test.ts`
  (45 deno tests) and three wire-level cases in
  `_shared/handler_envelope.test.ts`.
- **Locale** — `user_settings.prefs.locale` (service-role read, the same
  §120 pref the worker uses) → signup-time `user_metadata.locale` → `en`. The
  settings read is auxiliary: if it fails the mail still goes out in the
  fallback locale, never blocks the auth flow. The catalogue covers the same
  six locales as `email_i18n.go` (`en/de/fr/es/ja/pt-BR`), same normalization
  (region collapse, `pt* → pt-BR`, unknown → `en`), and the HTML/text layout
  is a port of the worker's renderer so auth mail is visually identical to
  product mail.
- **Actions** — one catalogue entry per `email_action_type`: `signup`,
  `invite`, `magiclink`, `recovery` (+ `email` OTP reusing the magic-link
  copy), `email_change` (a secure email change sends TWO mails from one hook
  invocation — the current address pairs `token` + `token_hash_new`, the new
  address `token_new` + `token_hash`; the field names are reversed upstream
  for backwards compatibility), `reauthentication` (code-only, no link), and
  `password_changed_notification`. Unknown/future action types fall through
  to an informational default and never fail the hook — a hook failure
  surfaces as a GoTrue API error to the user mid-signup/reset.
- **Verify link** — built byte-compatible with GoTrue's own
  `{base}/auth/v1/verify?token={token_hash}&type={action}&redirect_to=…`
  (including GoTrue's leave-unencoded-unless-`&=#` redirect quirk), so the web
  e2e reset flow's `extractLink` + `/auth/reset` greps keep working. The OTP
  code rides along as the link alternative. The base is `API_EXTERNAL_URL`
  when set, else the runtime-injected `SUPABASE_URL`: the local stack injects
  the Docker-internal `http://kong:8000` as `SUPABASE_URL`, which no browser
  resolves (CI run 28707481878 broke every reset-password e2e this way), so
  the committed `supabase/functions/.env` pins `API_EXTERNAL_URL` to
  `http://127.0.0.1:54321`. Prod leaves it unset — the hosted runtime's
  `SUPABASE_URL` is already the public project URL. (The name mirrors
  GoTrue's `api_external_url`; a `SUPABASE_`-prefixed name can't be used —
  the CLI reserves the prefix and drops such vars from env files.)
- **Transport** — the same SMTP env contract as the worker (`SMTP_HOST/PORT/
  USERNAME/PASSWORD/FROM`): a minimal Deno SMTP client (`smtp.ts` — implicit
  TLS on 465, opportunistic STARTTLS otherwise, AUTH PLAIN when credentials
  are set), multipart/alternative with RFC 2047 subjects. Unset SMTP → 503
  (fail-closed; GoTrue reports the send failure rather than silently
  dropping).
- **Local wiring** — `config.toml [auth.hook.send_email]` carries a committed
  local-dev secret (an `env()` reference would break `supabase start` on any
  machine without the var exported), mirrored in the committed
  `supabase/functions/.env`, which the CLI auto-loads into the local edge
  runtime on `supabase start` — so signup/recovery mail lands in Mailpit
  localized with zero setup. `.env.development` carries the same values for
  a manual `supabase functions serve --env-file` run.
- **Prod deploy** — the function ships with the normal `deploy-functions` CI
  job, but the hook itself must be configured on the hosted project: generate
  a secret in Dashboard → Auth → Hooks (send email hook, HTTPS, pointed at
  the deployed function URL), and set the SAME value as the function secret
  (`supabase secrets set SEND_EMAIL_HOOK_SECRET=v1,whsec_…`) along with the
  `SMTP_*` vars (the worker's provider credentials work as-is). Until the
  hook is enabled there, prod keeps GoTrue's built-in templates — enabling it
  is a pre-launch ops checklist item (see § Production ops).
- **Manual verification** (one step, after any config.toml change): restart
  the local stack (`cd apps/backend && supabase stop && supabase start`),
  trigger a mail-sending auth flow from the web app (e.g. `/login?reset=1` →
  send reset link for `runner@test.com`), and check Mailpit at
  `http://127.0.0.1:54324` for the branded, localized message whose verify
  link round-trips.

## Planned / not built

- [~] **Weekly digest** (engagement) — **FULLY BUILT INCL. SCHEDULER, SEND STILL GATED
  ON SMTP + CISO/COUNSEL (2026-06-20, scheduler migration `20270220_001`; decisions §174).**
  The missing piece — a `pg_cron` `enqueue_weekly_digests()` (Monday 08:00 UTC,
  opt-in-only, dedupe-safe) — now ships; the send is fail-closed on the unset
  SMTP credential (jobs drain to `done` without `SMTP_HOST`). The one-click
  `List-Unsubscribe-Post` header is digest-only. Foundation (2026-06-12, migration `20270108_001`): the `weekly_digest`
  jobs.kind, the `email_suppressions` hard-block table (fail-closed RLS,
  worker-only), the **opt-IN** `email_weekly_digest` pref (default `off`,
  separate key — never folded into `email_notifications`), and a **stateless
  keyed-HMAC RFC 8058 unsubscribe token** (non-guessable, no PII, no token
  table). Worker backend now built **behind the gate**: the `weekly_digest`
  handler (`handler_weekly_digest.go` — gates on the opt-in pref, hard-blocks
  on `email_suppressions`, builds a bounded weekly mileage/PB/kudos summary,
  renders localized HTML+text with a `List-Unsubscribe` header + footer token),
  the per-recipient digest **builder** (`EnqueueAllWeeklyDigests` in
  `digest_builder.go` — selects opted-in recipients, enqueues one job each),
  and the unauth one-click **unsubscribe endpoint** (`internal/unsubscribe/` →
  `/unsubscribe/weekly-digest`, verifies the HMAC, flips the pref off + inserts
  a suppression row, fail-closed on a bad/missing token; keyed by
  `WEEKLY_DIGEST_UNSUB_SECRET`). **NOT enabled:** the builder is
  **UNSCHEDULED** — no `pg_cron` ships (no marketing send fires). The **opt-in
  preference toggle** ships on web `/settings/preferences` + mobile Settings →
  Preferences (default off). The **provider bounce/complaint suppression
  webhook** is now built (`POST /v1/email/bounce`, worker
  `internal/bouncehook/` — parses Resend event JSON / SES-over-SNS
  notifications, writes a `bounce`/`complaint` row to `email_suppressions` per
  affected address, soft bounces are a no-op; shared-secret authed +
  rate-limited like the Strava hook, gated on `EMAIL_BOUNCE_WEBHOOK_SECRET`
  unset → 503). Enabling an actual send (wiring the builder's `pg_cron`) is
  **gated on CISO + counsel sign-off** (bulk/promotional mail under CAN-SPAM +
  GDPR/ePrivacy, unlike the transactional kinds) — the only remaining work for
  an enabled send is that operator-side `pg_cron` schedule + the sign-off.
- [~] **Lifecycle drip** (engagement) — **FULLY BUILT INCL. SCHEDULER, SEND STILL
  GATED ON SMTP + CISO/COUNSEL (2026-06-20, migration `20270223_001`; decisions
  §177).** Onboarding / re-engagement / streak nudges on the SAME rails as the
  weekly digest — a new `lifecycle_drip` jobs.kind carrying `{user_id, template}`
  (`drip_onboarding`, `drip_reengagement`, `drip_streak`). A daily
  `enqueue_lifecycle_drip()` pg_cron (09:00 UTC) does ALL the cohort selection in
  SQL — onboarding = opted-in account 2–6 days old with no run yet;
  first-week = 1–2 runs total with the latest 2–5 days ago (the habit-formation
  lapse window between onboarding and re-engagement; one-shot per user — its
  enqueue dedupe includes `done`, migration `20270331_001`);
  re-engagement = had a run >30 d ago but no cross-modal `activities` row in 30 d;
  streak = ran the last two calendar days but not yet today — writing the chosen
  template into the payload, dedupe-safe per `(user_id, template)`. The worker
  handler (`handler_lifecycle_drip.go`) gates on a **separate** opt-IN
  `email_lifecycle_drip` pref (default off — NEVER folded into the digest opt-in;
  opting into one engagement stream is not consent to the other) + the shared
  `email_suppressions` hard-block, then renders the fixed per-template localized
  copy with an RFC 8058 one-click unsubscribe at `/unsubscribe/lifecycle-drip`.
  The unsubscribe endpoint + the stateless HMAC token are now **stream-aware**
  (one mechanism, one `WEEKLY_DIGEST_UNSUB_SECRET`, the token scope namespaces
  the streams so one stream's link can't unsubscribe another); a suppression row
  blocks every stream to that address. **Fail-closed on the unset SMTP
  credential** (jobs drain to `done` without `SMTP_HOST`); enabling an actual
  send is the operator's SMTP provisioning + the CISO/counsel sign-off (the cron
  is harmless no-op churn until then). The **opt-in preference toggle** ships on
  web Settings → Preferences (`email-lifecycle-drip` checkbox) + mobile
  Settings → Preferences (`prefsEmailLifecycleDrip` switch, default off),
  i18n'd across all six locales — the in-app equivalent of the one-click
  unsubscribe, mirroring the digest toggle.
- [x] **Account-deletion receipt** — SHIPPED 2026-06-20 (migration
  `20270217_001`, `account_deleted` template). Built as **enqueue-with-inline-
  address + a non-cascading send-once record** (not inline-send-from-EF — that
  would mean a second SMTP transport + a duplicate i18n catalogue in Deno).
  The `delete-account` EF captures `user.email` + the locale BEFORE the
  cascade, then AFTER `admin.deleteUser` succeeds enqueues a `lifecycle_email`
  job whose payload carries `{template, email, locale}` and **no `user_id`** —
  so the EF's `payload->>user_id` job-drain leaves it untouched (no drain-exempt
  special-casing needed). The worker's `handleLifecycleEmail` dispatches the
  inline-address template to `handleAccountDeletionReceipt`, which dedups on a
  SHA-256 hash of the address via the non-cascading `account_deletion_receipts`
  table (`lifecycle_email_log` would have cascaded away with the user). The
  receipt copy carries no `/settings/preferences` link (the account is gone).
  The deleted address lingers in `jobs.payload` only until the job drains
  (minutes), then in `account_deletion_receipts` only as a hash, pruned at 30
  days. `decisions.md § 121`.
- [x] **Web push server-side delivery** — SHIPPED 2026-06-04 (migration
  `20261219_001`, `web_push` kind). See the architecture note above. Gated on the
  operator-generated `VAPID_PUBLIC_KEY`/`VAPID_PRIVATE_KEY` (self-generated, not a
  third-party credential); unset → jobs finish done, rows stay pending. A
  `push_notifications` category UI toggle (web + mobile) is the small remaining
  follow-up — gating works on the `important` default without it.
- [~] **Native push (FCM / APNs)** — backend + client BUILT 2026-06-19 (migration
  `20270212_001`, `native_push` kind), **send gated on operator credentials**. Same
  `notifications` source of truth + sibling-consumer pattern the `web_push` kind
  demonstrates; the FCM/APNs sender (`internal/nativepush/`) + handler
  (`handler_native_push.go`) + the mobile `firebase_messaging` device-token
  registration (`push_messaging_bridge.dart`, both twins) all ship. Going live is
  blocked only on operator-supplied Firebase/APNs credentials on the worker
  (`FCM_*` / `APNS_*`) + the per-app config files (`google-services.json` /
  `GoogleService-Info.plist`); unset → jobs finish done, rows stay pending. roadmap
  Phase 4b. See the architecture sibling note above + `decisions.md § 161`.

### Not planned (with reason)

- **Data-export-ready email** — the export endpoint is **synchronous** and
  returns a 10-minute signed URL inline; an async email would arrive stale.
  Revisit only if export moves to an async/job model.
- **New-device sign-in alerts** — there's no sign-in/device tracking to key
  them off. The send-email hook IS now configured (§ GoTrue auth emails) and
  its catalogue already carries `password_changed_notification` copy, so if
  GoTrue's security-notification sends are ever enabled they arrive localized
  — but we don't enable them today.

## Production ops (required before any email actually sends)

None of this sends in prod until an operator:

1. **Provisions SMTP** on the worker — `SMTP_HOST/PORT/USERNAME/PASSWORD/FROM`
   + `APP_BASE_URL` (Resend or SES). Until then `notification_email` /
   `lifecycle_email` jobs finish without sending.
2. **Confirms the pg_cron schedules** are live in the deployed Supabase
   (`enqueue-event-reminders`, `enqueue-weekly-digest`, `enqueue-lifecycle-drip`).
   The two engagement crons (`enqueue-weekly-digest`, `enqueue-lifecycle-drip`)
   enqueue harmless no-op jobs until SMTP is provisioned — the send leg is the
   gate, not the schedule.
2b. (For **web push**) sets `VAPID_PUBLIC_KEY` (the same key the browser
   subscribed with — apps/web's `PUBLIC_VAPID_PUBLIC_KEY`), `VAPID_PRIVATE_KEY`,
   and `VAPID_SUBJECT` (`mailto:` contact) on the worker. Until then `web_push`
   jobs finish done while leaving the notification rows pending.
2c. (For **native push**) provisions a Firebase project + an APNs auth key, then:
   on the **worker**, sets `FCM_SERVICE_ACCOUNT_JSON` + `FCM_PROJECT_ID` (Android)
   and/or `APNS_KEY_P8` + `APNS_KEY_ID` + `APNS_TEAM_ID` + `APNS_TOPIC`
   (+ `APNS_SANDBOX=1` for dev builds) (iOS); on the **mobile apps**, drops
   `google-services.json` into `apps/mobile_android/android/` and
   `GoogleService-Info.plist` + the APNs push entitlement into
   `apps/mobile_ios/ios/`. Either credential group alone enables that platform;
   neither set → `native_push` jobs finish done while leaving the rows pending,
   and the mobile bridge no-ops (compiles + runs without the config files). A
   configured-but-invalid credential fails the worker loudly at startup.
2d. (For **auth emails**) enables the send-email hook on the hosted project —
   Dashboard → Auth → Hooks pointed at the deployed `auth-email` function URL
   with a generated secret, plus `supabase secrets set
   SEND_EMAIL_HOOK_SECRET=… SMTP_HOST=… SMTP_PORT=… SMTP_USERNAME=…
   SMTP_PASSWORD=… SMTP_FROM=…` on the functions side. Until then prod auth
   mail falls back to GoTrue's built-in English templates (functional, just
   unlocalized/unbranded).
3. **Sets up domain auth** — SPF / DKIM / DMARC for `threkir.com` so mail isn't
   spam-filed.
4. (Before any **bulk/engagement** mail — the weekly digest AND the lifecycle
   drip) the RFC 8058 one-click unsubscribe endpoints (set
   `WEEKLY_DIGEST_UNSUB_SECRET` — the one shared secret keys both
   `/unsubscribe/weekly-digest` and `/unsubscribe/lifecycle-drip`) + the
   bounce/complaint suppression webhook (set `EMAIL_BOUNCE_WEBHOOK_SECRET`,
   ≥32 chars, and point the provider's bounce/complaint webhook at
   `POST /v1/email/bounce?secret=…`). Both are built behind their secrets;
   unset → the endpoints return 503.
5. (For the **lifecycle drip** + **weekly digest** specifically) **CISO +
   counsel sign-off** — bulk/promotional mail under CAN-SPAM + GDPR/ePrivacy,
   unlike the transactional kinds. This is a pre-deploy checklist item; the
   code path is built and fail-closed (SMTP unset → nothing sends, and even
   with SMTP every recipient is hard-gated on the per-stream opt-IN pref + the
   suppression block).

## Where the code lives

- Worker: `apps/job_worker/internal/` — `mailer.go` (transport + HTML/text
  render incl. `renderWeeklyDigest`), `email_i18n.go` (catalogue),
  `handler_notification_email.go`, `handler_lifecycle_email.go`,
  `handler_safety_email.go`. Web push: `handler_web_push.go`, `push_render.go`
  (pref gate + payload), and the `internal/webpush/` RFC 8291/8292 sender.
  Native push: `handler_native_push.go` (reuses `push_render.go`'s `pushMode` /
  `shouldPush` pref gate + the shared title/body catalogue), and the
  `internal/nativepush/` FCM HTTP v1 + APNs HTTP/2 sender (stdlib + `golang-jwt`).
  Weekly digest (behind the gate): `handler_weekly_digest.go` (gate + render),
  `digest_builder.go` (`EnqueueAllWeeklyDigests` — UNSCHEDULED),
  `internal/digesttoken/` (the stateless RFC 8058 HMAC token, now **stream-aware**:
  `Mint(secret, stream, userID)` / `Verify(...)` over the `weekly_digest` /
  `lifecycle_drip` scopes), `internal/unsubscribe/` (the unauth endpoint, now
  **stream-aware** — mounts `/unsubscribe/weekly-digest` AND
  `/unsubscribe/lifecycle-drip` off one shared secret), and `internal/bouncehook/`
  (the provider bounce/complaint webhook at `POST /v1/email/bounce` that writes
  `bounce`/`complaint` suppression rows). Lifecycle drip (behind the same gate):
  `handler_lifecycle_drip.go` (the digest's sibling — opt-in `email_lifecycle_drip`
  + suppression gate, per-template render via `renderLifecycleDrip` in `mailer.go`;
  cohort selection is in SQL, not the handler).
- Migrations: `20261130_001` (notification channel + reminders), `20261202_001`
  (welcome), `20261203_001` (subscription emails), `20261218_001` (safety
  contacts + the `safety_email` kind), `20261219_001` (web-push channel + the
  `web_push` kind + `clear_push_subscription`), `20270108_001` (weekly-digest
  foundation — `weekly_digest` kind + `email_suppressions` + the opt-in pref +
  the stateless-HMAC unsubscribe design), `20270212_001` (native-push channel —
  `native_push` kind + `native_push_sent_at` + the device-token-gated enqueue
  trigger + `clear_device_token`), `20270217_001` (account-deletion receipt — the
  non-cascading `account_deletion_receipts` send-once table; the `account_deleted`
  template rides the existing `lifecycle_email` kind, so no jobs.kind CHECK change),
  `20270220_001` (weekly-digest scheduler — the `enqueue-weekly-digest` pg_cron),
  `20270223_001` (lifecycle drip — the `lifecycle_drip` jobs.kind + the
  `enqueue_lifecycle_drip()` cohort-selection function + the daily
  `enqueue-lifecycle-drip` pg_cron; the opt-in `email_lifecycle_drip` pref is a
  jsonb key with no migration, like the digest pref).
- Native-push client leg: the mobile device-token registration —
  `apps/mobile_android/lib/push_messaging_bridge.dart` +
  `firebase_push_messaging.dart` (byte-identical iOS twins), wired in `main.dart`,
  with the `device_tokens` upsert/enable/remove methods on `packages/api_client`.
  The `device_tokens` table (platform-checked rows, the `is_notifications_enabled`
  per-device flag, owner-scoped RLS) shipped in migration `20260506_001`.
- Web push client leg: `apps/web/src/lib/util/push.ts` (subscribe/unsubscribe) +
  `apps/web/static/sw.js` (service worker render). The subscription lives on
  `user_device_settings.prefs.push_subscription` — `docs/backend/settings.md`.
- Safety contacts: web Settings → Safety (`apps/web/src/routes/settings/safety/`)
  + the logged-out email-link confirm page (`apps/web/src/routes/safety/confirm/`);
  mobile Settings → Safety contacts (`apps/mobile_android/lib/screens/settings_safety_screen.dart`,
  byte-identical iOS twin) add/confirm/remove + incoming-request confirm/decline;
  schema in `docs/backend/api_database.md`. The email-link confirm page stays
  web-only (no mobile deep-link route).
- Clients (locale write): web `apps/web/src/routes/settings/preferences/`,
  mobile `apps/mobile_android/lib/screens/settings_preferences_screen.dart`.
- Auth emails: `apps/backend/supabase/functions/auth-email/` — `lib.ts`
  (Standard Webhooks verification + the six-locale catalogue + send plan +
  render + MIME), `smtp.ts` (Deno SMTP client), `handler.ts` (the injectable
  request path), `index.ts` (env + service-role locale lookup wiring); hook
  config in `apps/backend/supabase/config.toml [auth.hook.send_email]` +
  the committed `supabase/functions/.env`.
- ADRs: `decisions.md` §117 (channel), §119 (lifecycle kind), §120 (i18n),
  §121 (subscription emails), §131 (safety-contact alerts), §203 (auth-email
  hook).
