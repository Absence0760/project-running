# Email & notification delivery

The single source of truth for the app's outbound email. For the **in-app**
notification inbox (the bell + Notifications tab) see `decisions.md § 38`; this
doc is the **email** layer that delivers a subset of those notifications plus
transactional / lifecycle mail.

## Architecture

All email is sent **server-side by the Go worker** (`apps/job_worker/`), never
from a client. Three job kinds on the `jobs` queue drive it:

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

A fourth, **non-email** job kind reuses the same notifications rows over a
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
  no third-party web-push library. Native FCM/APNs is a further sibling, still
  operator-credential-blocked (below).

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
| Branded HTML + inbox preview text | — | all email of the above | ✓ | — |

All shipped emails are end-to-end tested against the local Docker Mailpit
(`http://127.0.0.1:54324`); none required Firebase/APNs credentials.

## Planned / not built

- [~] **Weekly digest** (engagement) — **WORKER BACKEND BUILT, SEND STILL GATED
  (2026-06-12, migration `20270108_001`).** Foundation: the `weekly_digest`
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
- [ ] **Lifecycle drip** (engagement) — re-engagement, onboarding drip,
  streak/goal nudges. Reuse the `lifecycle_email` kind + the digest's opt-in /
  suppression / unsubscribe rails. Not built. Same CISO/counsel gate.
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
- [ ] **Native push (FCM / APNs)** — the remaining device-delivery leg (push to a
  locked phone). Same `notifications` source of truth + sibling-consumer pattern
  the `web_push` kind now demonstrates; an FCM/APNs sender is another sibling.
  Blocked on operator-supplied Firebase/APNs credentials + mobile
  `firebase_messaging` token registration. roadmap Phase 4b.

### Not planned (with reason)

- **Data-export-ready email** — the export endpoint is **synchronous** and
  returns a 10-minute signed URL inline; an async email would arrive stale.
  Revisit only if export moves to an async/job model.
- **Password-changed / new-device sign-in** — no GoTrue auth hooks are
  configured and there's no sign-in/device tracking (the `device_tokens` table
  has no write path). That's separate infrastructure, not an email.

## Production ops (required before any email actually sends)

None of this sends in prod until an operator:

1. **Provisions SMTP** on the worker — `SMTP_HOST/PORT/USERNAME/PASSWORD/FROM`
   + `APP_BASE_URL` (Resend or SES). Until then `notification_email` /
   `lifecycle_email` jobs finish without sending.
2. **Confirms the pg_cron schedules** are live in the deployed Supabase
   (`enqueue-event-reminders`).
2b. (For **web push**) sets `VAPID_PUBLIC_KEY` (the same key the browser
   subscribed with — apps/web's `PUBLIC_VAPID_PUBLIC_KEY`), `VAPID_PRIVATE_KEY`,
   and `VAPID_SUBJECT` (`mailto:` contact) on the worker. Until then `web_push`
   jobs finish done while leaving the notification rows pending.
3. **Sets up domain auth** — SPF / DKIM / DMARC for `threkir.com` so mail isn't
   spam-filed.
4. (Before any **bulk/engagement** mail) the RFC 8058 one-click unsubscribe
   endpoint (set `WEEKLY_DIGEST_UNSUB_SECRET`) + the bounce/complaint
   suppression webhook (set `EMAIL_BOUNCE_WEBHOOK_SECRET`, ≥32 chars, and point
   the provider's bounce/complaint webhook at `POST /v1/email/bounce?secret=…`).
   Both are built behind their secrets; unset → the endpoints return 503.

## Where the code lives

- Worker: `apps/job_worker/internal/` — `mailer.go` (transport + HTML/text
  render incl. `renderWeeklyDigest`), `email_i18n.go` (catalogue),
  `handler_notification_email.go`, `handler_lifecycle_email.go`,
  `handler_safety_email.go`. Web push: `handler_web_push.go`, `push_render.go`
  (pref gate + payload), and the `internal/webpush/` RFC 8291/8292 sender.
  Weekly digest (behind the gate): `handler_weekly_digest.go` (gate + render),
  `digest_builder.go` (`EnqueueAllWeeklyDigests` — UNSCHEDULED),
  `internal/digesttoken/` (the stateless RFC 8058 HMAC token),
  `internal/unsubscribe/` (the unauth `/unsubscribe/weekly-digest` endpoint),
  and `internal/bouncehook/` (the provider bounce/complaint webhook at
  `POST /v1/email/bounce` that writes `bounce`/`complaint` suppression rows).
- Migrations: `20261130_001` (notification channel + reminders), `20261202_001`
  (welcome), `20261203_001` (subscription emails), `20261218_001` (safety
  contacts + the `safety_email` kind), `20261219_001` (web-push channel + the
  `web_push` kind + `clear_push_subscription`), `20270108_001` (weekly-digest
  foundation — `weekly_digest` kind + `email_suppressions` + the opt-in pref +
  the stateless-HMAC unsubscribe design), `20270217_001` (account-deletion
  receipt — the non-cascading `account_deletion_receipts` send-once table; the
  `account_deleted` template rides the existing `lifecycle_email` kind, so no
  jobs.kind CHECK change).
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
- ADRs: `decisions.md` §117 (channel), §119 (lifecycle kind), §120 (i18n),
  §121 (subscription emails), §131 (safety-contact alerts).
