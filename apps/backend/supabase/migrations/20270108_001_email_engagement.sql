-- Email engagement (weekly digest) — FOUNDATION ONLY. Built behind the gate:
-- the schema + suppression rail land here, but NO digest send is scheduled and
-- the consent defaults OFF. Enabling an actual marketing send is gated on
-- CISO + counsel sign-off (CAN-SPAM + GDPR/ePrivacy — this is promotional, not
-- transactional, mail). See docs/features/email.md § Engagement.
--
-- This migration adds:
--   1. the `weekly_digest` jobs.kind (so the scheduler — built later, NOT yet
--      scheduled — can enqueue per-recipient digest jobs).
--   2. `email_suppressions` — a hard-block list (bounce / complaint / explicit
--      unsubscribe) the digest handler MUST consult before sending.
--
-- NOT in a migration (by design):
--   * Consent pref `email_weekly_digest` (default 'off' — opt-IN, marketing).
--     It's a `user_settings.prefs` jsonb key (registry: docs/backend/settings.md),
--     read by the worker defaulting OFF — never folded into `email_notifications`
--     (you cannot infer marketing consent from a transactional-email setting).
--   * The RFC 8058 one-click unsubscribe token — a STATELESS keyed HMAC over
--     (user_id, 'weekly_digest') signed with an operator secret, so the unauth
--     unsubscribe endpoint is non-guessable and leaks no PII. No token table.

-- ─────────────────────── jobs.kind: + weekly_digest ───────────────────────
-- Full re-statement at the chain end (the pattern docs in 20261211_001).
alter table public.jobs drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (
    kind in (
      'map_match', 'token_refresh', 'strava_event', 'photo_process',
      'notification_email', 'lifecycle_email', 'safety_email', 'web_push',
      'weekly_digest'
    )
  );

-- ─────────────────────── email_suppressions ───────────────────────
-- Keyed by email (bounces/complaints arrive by address, not user id). The
-- digest handler hard-blocks any send to an address present here.
create table public.email_suppressions (
  email      text primary key,
  reason     text not null check (reason in ('bounce', 'complaint', 'unsubscribe', 'manual')),
  created_at timestamptz not null default now()
);

-- Fail-closed: RLS on, NO policy → anon/authenticated are denied entirely. The
-- Go worker (service_role, which bypasses RLS) is the sole reader/writer — the
-- provider bounce/complaint webhook + the unsubscribe endpoint. A user must
-- never read another user's suppression status.
alter table public.email_suppressions enable row level security;
