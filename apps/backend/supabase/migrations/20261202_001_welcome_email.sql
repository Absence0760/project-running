-- Lifecycle email: a "thanks for signing up" welcome on first signup.
--
-- The notification-email channel (20261130_001) delivers rows that already
-- exist in the in-app bell. A welcome email is a different shape: it's
-- transactional (fires once when an account is created), has no
-- notifications row, and isn't gated on the email_notifications preference
-- (you can't opt out of the email that confirms you signed up). So it rides
-- a NEW job kind, `lifecycle_email`, carrying {user_id, template} — the Go
-- worker's handler_lifecycle_email.go renders the named template and sends.
-- Future scheduled/engagement mail (weekly digest, re-engagement) will reuse
-- this kind with their own templates + their own opt-in preferences.
--
-- Trigger point: AFTER INSERT on user_profiles. The row is created exactly
-- once per user by confirm_age_and_terms() (20260929_001) — a brand-new user
-- INSERTs it right after auth.signUp; a returning user hits that function's
-- `on conflict do update` branch, which does NOT fire an INSERT trigger. So
-- this fires once per real signup, in the public schema, with no auth-schema
-- trigger to maintain.

-- ─────────────────── jobs.kind allowlist += lifecycle_email ───────────────────

-- Three-file rule (apps/job_worker/CLAUDE.md): widen the CHECK here + add the
-- Go dispatch case (worker.go) + extend the pgtap test, all this commit.
-- Re-list every existing kind (full set as of 20261130_001) plus the new one.
alter table public.jobs
  drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (kind in ('map_match', 'token_refresh', 'strava_event', 'photo_process', 'notification_email', 'lifecycle_email'));

-- ─────────────────── send-once log ───────────────────

-- One row per (user, template) the worker has sent. The handler checks this
-- before sending and records after, so a job retry (or a crash between send
-- and finish_job) can't re-send a welcome. Service-role only — the worker is
-- the sole reader/writer; RLS denies everyone else.
create table lifecycle_email_log (
  user_id   uuid not null references auth.users(id) on delete cascade,
  template  text not null,
  sent_at   timestamptz not null default now(),
  primary key (user_id, template)
);

alter table lifecycle_email_log enable row level security;
-- No policies → no anon/authenticated access. The worker uses the service
-- role key, which bypasses RLS.

-- ─────────────────── enqueue trigger ───────────────────

-- New user_profiles row → enqueue one welcome email. SECURITY DEFINER so it
-- can write public.jobs (RLS-denied to all but service_role). Fired by the
-- row insert, never called directly, so no grant to public/anon/authenticated
-- is needed. Same shape as enqueue_photo_process_job / enqueue_notification_
-- email_job.
create or replace function enqueue_welcome_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.jobs (kind, payload)
  values (
    'lifecycle_email',
    jsonb_build_object('user_id', NEW.id::text, 'template', 'welcome')
  );
  return NEW;
end;
$$;

revoke execute on function enqueue_welcome_email() from public;

create trigger user_profiles_enqueue_welcome
  after insert on user_profiles
  for each row execute function enqueue_welcome_email();
