-- Native push (FCM / APNs) delivery channel for the notifications inbox — the
-- THIRD device-delivery consumer of the same notifications rows the in-app bell,
-- the notification_email channel (20261130_001), and the web_push channel
-- (20261219_001) already read. This is the locked-phone leg: an FCM message to
-- an Android device or an APNs push to an iOS device, fanned out over the
-- device_tokens registered by the mobile clients (table 20260506_001).
--
-- It mirrors the web_push channel one-for-one, swapping the transport:
--
--   1. notifications.native_push_sent_at — the per-channel send-state guard,
--      the sibling of web_push_sent_at / email_sent_at. A notification can be
--      emailed, web-pushed, and native-pushed independently — each channel has
--      its own preference gate, its own delivery surface, and its own guard.
--
--   2. jobs.kind += 'native_push' — the new job kind. Three-file rule
--      (apps/job_worker/CLAUDE.md): this CHECK widening + the Go dispatch case
--      (worker.go) + the pgtap test (jobs_kind_allowlist_test.sql) land
--      together. Full restate of the legal set so dropping a kind here can't
--      silently break an existing enqueue trigger's insert (23514 at INSERT).
--
--   3. enqueue_notification_native_push_job() — an AFTER INSERT trigger that
--      enqueues one native_push job per notification, BUT ONLY when the
--      recipient has at least one device_tokens row with is_notifications_enabled
--      = true. Native-push adoption is a minority of (mobile) users; gating on
--      token presence here avoids a no-op job per notification for the
--      push-less majority. Same property the web_push gate has. The per-category
--      preference (push_notifications) is enforced in the worker — the coarse
--      "do they have ANY enabled token" gate lives here.
--
--   4. clear_device_token(token) — prunes a dead token when FCM reports
--      UNREGISTERED or APNs returns 410 (the token is gone). Sibling of
--      clear_push_subscription. SECURITY DEFINER + service_role-only grant: the
--      worker is the sole caller. The (user_id, token) unique constraint means a
--      token deleted here is the exact dead registration, never another user's.
--
-- The notifications row stays the single source of truth: bell + email +
-- web_push + native_push all read the same row, each with its own *_sent_at
-- guard and preference. Going LIVE is blocked only on operator-supplied
-- Firebase/APNs credentials on the worker (FCM_SERVICE_ACCOUNT_JSON /
-- APNS_* env vars); unset → the worker drains native_push jobs to done while
-- leaving the rows pending (native_push_sent_at NULL) so a later credentialed
-- deploy delivers the backlog. No new RLS: device_tokens already ships four
-- owner-scoped self CRUD policies (20260506_001) — the mobile client write
-- path is unblocked at the policy level.

-- ─────────────────── notifications: native-push send state ───────────────────

-- NULL = not yet processed by the native-push handler; non-NULL = sent OR
-- deliberately skipped (opted out, no enabled token). One column covers both
-- terminal states, mirroring web_push_sent_at / email_sent_at.
alter table notifications
  add column native_push_sent_at timestamptz;

-- ─────────────────── jobs.kind allowlist += native_push ───────────────────

-- Full restate of the legal set as of 20270108_001 (weekly_digest) plus the new
-- kind. Verified against worker.go's dispatch switch at write time.
alter table public.jobs
  drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (
    kind in (
      'map_match', 'token_refresh', 'strava_event', 'photo_process',
      'notification_email', 'lifecycle_email', 'safety_email', 'web_push',
      'weekly_digest', 'native_push'
    )
  );

-- ─────────────────── prune a dead device token ───────────────────

-- Called by the Go worker (kind='native_push') when FCM reports a token is
-- UNREGISTERED or APNs returns 410 — the token is dead. Deletes the row by
-- token. SECURITY DEFINER so the worker's service-role call writes regardless
-- of RLS; the (user_id, token) uniqueness scopes the delete to exactly one
-- registration. service_role-only grant — the worker is the sole caller.
create or replace function clear_device_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from device_tokens where token = p_token;
end;
$$;

revoke execute on function clear_device_token(text) from public;
grant execute on function clear_device_token(text) to service_role;

-- ─────────────────── enqueue trigger: notification → native_push job ───────────────────

-- One native_push job per notification, gated on the recipient having at least
-- one enabled device token. The per-category preference (push_notifications) is
-- enforced in the worker — so a user on push_notifications='all' still gets
-- social pushes while the default 'important' filters them out — but the coarse
-- "do they have ANY enabled token" gate lives here to avoid no-op jobs.
--
-- SECURITY DEFINER so it can read device_tokens (RLS-scoped to the owner) and
-- write public.jobs (service_role only). Fired by the row insert, never called
-- directly, so no public/anon/authenticated grant is needed.
create or replace function enqueue_notification_native_push_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from device_tokens d
    where d.user_id = NEW.user_id
      and d.is_notifications_enabled = true
  ) then
    insert into public.jobs (kind, payload)
    values (
      'native_push',
      jsonb_build_object('notification_id', NEW.id::text)
    );
  end if;
  return NEW;
end;
$$;

revoke execute on function enqueue_notification_native_push_job() from public;

create trigger notifications_enqueue_native_push
  after insert on notifications
  for each row execute function enqueue_notification_native_push_job();
