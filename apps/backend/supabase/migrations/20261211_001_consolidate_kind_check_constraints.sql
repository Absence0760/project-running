-- F16 (continued): consolidate the fragmented notifications.kind and jobs.kind
-- allowlists into one authoritative re-statement each.
--
-- Both CHECKs are already single constraints (each migration that widened the
-- list did drop-and-recreate), so there is no duplicate-constraint cleanup to
-- do. The debt the audit flagged is that the authoritative legal set is
-- scattered: notifications.kind grew across six migrations
-- (20260528000001, 20260903_001, 20261019_001, 20261024_001, 20261026_001,
-- 20261101_001, 20261130_001) and jobs.kind across five
-- (20260822_001, 20260823_001, 20260825_001, 20261130_001, 20261202_001).
-- Re-stating the complete list here, at the end of the chain, gives one place
-- to read "what is legal today" and a stable anchor for the pgtap that pins it.
--
-- These two lists are the SAME as what 20261130_001 (notifications) and
-- 20261202_001 (jobs) already enforce — this migration is a no-op on the legal
-- domain, intentionally. Widening either set still requires a NEW migration at
-- the chain end plus the matching client/worker/TS-union/pgtap updates; do not
-- edit this file to add a value.

-- ─────────── notifications.kind ───────────
alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder'
    )
  );

-- ─────────── jobs.kind ───────────
alter table public.jobs drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (
    kind in (
      'map_match', 'token_refresh', 'strava_event',
      'photo_process', 'notification_email', 'lifecycle_email'
    )
  );
