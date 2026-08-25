-- The Art 20 export becomes a queued job, so no client connection is
-- held open for the build.
--
-- Before this, `POST /v1/export` on the Go worker built the whole
-- archive inline: the caller waited while every section was walked and
-- every 6 MiB chunk pushed to Storage, so their timeout, a disconnect,
-- or a backgrounded mobile app could end an export that would otherwise
-- have completed. decisions.md § 708 removed that rail's memory caps and
-- named the held connection as the honest remaining bound; this closes
-- it. decisions.md § 717.
--
-- Two rows per export, which is the shape `run_matched_tracks` already
-- established for "a queued job whose outcome the owner must read":
-- the generic `jobs` row is the queue entry the worker claims, and a
-- `data_export_jobs` row is the durable state the status endpoint
-- reads. They are inserted in one statement by `enqueue_data_export`
-- below, because two round-trips from the Go handler could leave a
-- state row nothing will ever build (the caller then polls forever).
--
-- The artifact's SIGNED URL is deliberately NOT stored here. Only the
-- object path is. A 10-minute URL minted when the build finished would
-- already be spent by the time a subject who closed the tab comes back,
-- so the URL is minted at READ time by `GET /v1/export/jobs/latest` and
-- its TTL starts when the subject asks for it, not when the worker
-- happened to finish. Storing a URL would also have put a live download
-- credential in a database row, where the path is inert on its own —
-- the `exports` bucket carries no `storage.objects` policies at all
-- (20270602_001), so a path is reachable through a signed URL and
-- nothing else.

-- ─────────────────── 1. data_export_jobs ───────────────────

create table data_export_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  format text not null,
  status text not null default 'queued',
  -- Storage key of the finished artifact in the `exports` bucket.
  -- Written only after the tus session's Finish has returned, so a row
  -- carrying a path is a row whose object exists; a build that died
  -- mid-stream materialises nothing and leaves this null.
  object_path text,
  run_count integer,
  total_runs integer,
  complete boolean,
  -- Machine token, never prose: build_failed / upload_failed /
  -- signed_url_failed / <section>_fetch_failed. The client renders it
  -- through its own copy.
  error_code text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint data_export_jobs_format_chk
    check (format in ('csv', 'gpx', 'backup')),
  constraint data_export_jobs_error_code_len_chk
    check (error_code is null or length(error_code) <= 64),
  constraint data_export_jobs_status_chk
    check (status in ('queued', 'running', 'ready', 'failed', 'expired'))
);

-- One in-flight export per subject. This is what makes a re-POST
-- idempotent rather than a second full archive build: `enqueue_data_export`
-- returns the row already in flight, and if two requests race past that
-- check the index rejects the loser, which the function catches and
-- resolves to the same row. Without it, a mobile app retrying through a
-- flaky connection would charge Storage for one archive per tap.
create unique index data_export_jobs_one_in_flight
  on data_export_jobs (user_id)
  where status in ('queued', 'running');

-- The status read: newest job for this subject.
create index data_export_jobs_latest
  on data_export_jobs (user_id, created_at desc);

create or replace function data_export_jobs_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  NEW.updated_at := now();
  return NEW;
end;
$$;

create trigger data_export_jobs_updated_at
  before update on data_export_jobs
  for each row
  execute function data_export_jobs_set_updated_at();

-- Deny everything, same posture as `jobs`. No policies at all is the
-- tightest expression: the row is useless to a client without a signed
-- URL, which only the service role can mint, so the whole read goes
-- through the Go worker's JWT-authed status endpoint. An owner-SELECT
-- policy would add a surface with no consumer.
alter table data_export_jobs enable row level security;

-- 20270408_001 version-controlled the public-schema grant matrix, so a new
-- table inherits nothing. service_role needs full DML (it is the only
-- writer); `authenticated` is granted NOTHING at all, which puts this table
-- on the same deliberately-service_role-only footing as `app_quota` and
-- `deletion_audit_log` and is why `role_grant_matrix_test.sql`'s allow-list
-- names it. Denying at the grant level as well as through RLS means a policy
-- added by mistake later still cannot open a client read path.
grant select, insert, update, delete on data_export_jobs to service_role;

comment on table data_export_jobs is
  'Durable state of one Art 20 export request. Enqueued by '
  'enqueue_data_export (alongside a jobs row of kind=data_export), '
  'built by the Go worker, read back through GET /v1/export/jobs/latest '
  'which mints the signed URL at read time. Operational metadata about '
  'fulfilling a subject request, not Art 20 portable data itself; '
  'cascades away with the account (Art 17).';

-- ─────────────────── 2. jobs.kind allowlist += data_export ───────────────────

-- Three-file rule (20260822_001): widen the CHECK here + add the Go
-- dispatch case (worker.go) + extend the pgtap suite. Full set as of
-- 20270410_001 plus the new kind.
--
-- `jobs` is a guarded high-volume table, so the widen takes the online
-- two-step (migration_locks.md § CHECK constraints) rather than the
-- single-step drop-and-recreate every previous kind migration used: a
-- validating ADD holds ACCESS EXCLUSIVE while it scans every row of a
-- queue that accumulates finished jobs. Every existing row already
-- satisfies the wider set — this only ever ADDS a kind — so the scan is
-- pure waste, and VALIDATE runs it under SHARE UPDATE EXCLUSIVE instead,
-- with reads and writes proceeding. Both halves are here rather than
-- split across migrations because the scan is of a queue table, not of
-- `runs`; the lock class is what mattered.
alter table public.jobs
  drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (
    kind in (
      'map_match', 'token_refresh', 'strava_event', 'photo_process',
      'notification_email', 'lifecycle_email', 'safety_email', 'web_push',
      'weekly_digest', 'native_push', 'lifecycle_drip', 'route_photo_process',
      'club_photo_process', 'safety_sms', 'data_export'
    )
  )
  not valid;
alter table public.jobs
  validate constraint jobs_kind_chk;

-- ─────────────────── 3. enqueue_data_export ───────────────────

-- Atomic: the state row and its queue entry land together or not at
-- all. Returns the row already in flight rather than starting a second
-- build, so a retried POST is free.
--
-- max_attempts is 2, not the table default of 5. An export retry is not
-- cheap the way a push retry is — every attempt that gets as far as the
-- tus Finish uploads a whole archive, so five attempts at a deep history
-- is five archives' worth of Storage for one request. One retry covers
-- the transient blip; past that the subject is told it failed and can
-- ask again, which is the honest outcome.
create or replace function enqueue_data_export(
  p_user_id uuid,
  p_format text
)
returns table (
  id uuid,
  status text,
  format text,
  created_at timestamptz,
  reused boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row data_export_jobs;
begin
  if p_format not in ('csv', 'gpx', 'backup') then
    raise exception 'enqueue_data_export: bad format %', p_format
      using errcode = '22023';
  end if;

  select d.* into v_row
  from data_export_jobs d
  where d.user_id = p_user_id
    and d.status in ('queued', 'running')
  order by d.created_at desc
  limit 1;

  if found then
    return query select v_row.id, v_row.status, v_row.format, v_row.created_at, true;
    return;
  end if;

  begin
    insert into data_export_jobs (user_id, format)
    values (p_user_id, p_format)
    returning * into v_row;
  exception when unique_violation then
    -- Lost the race against a concurrent enqueue. The winner's row is
    -- the answer; returning it is the same reuse the check above does.
    select d.* into v_row
    from data_export_jobs d
    where d.user_id = p_user_id
      and d.status in ('queued', 'running')
    order by d.created_at desc
    limit 1;
    return query select v_row.id, v_row.status, v_row.format, v_row.created_at, true;
    return;
  end;

  insert into jobs (kind, payload, max_attempts)
  values (
    'data_export',
    jsonb_build_object(
      'export_job_id', v_row.id,
      'user_id', p_user_id,
      'format', p_format
    ),
    2
  );

  return query select v_row.id, v_row.status, v_row.format, v_row.created_at, false;
end;
$$;

revoke execute on function enqueue_data_export(uuid, text) from public, anon, authenticated;
grant execute on function enqueue_data_export(uuid, text) to service_role;

comment on function enqueue_data_export(uuid, text) is
  'Enqueue one Art 20 export for p_user_id, or return the one already '
  'in flight. service_role only — the per-tier rate limit lives in the '
  'POST /v1/export/jobs handler, so an authenticated caller reaching '
  'this directly would bypass it.';

-- ─────────────────── 4. retention: the row expires with its artifact ───────────────────

-- `cleanup_stale_export_blobs` (20260720_001, widened by 20270602_001)
-- deletes export artifacts after 7 days. A `ready` row outliving its own
-- object would keep offering a download that 404s, so the row is flipped
-- to `expired` against the same window. Doing it here rather than deriving
-- it from a failed sign keeps ONE account of whether an export is still
-- collectable, and means a genuine Storage outage reads as an outage
-- rather than as an expiry.
--
-- Split out as its own function rather than inlined into the blob sweep so
-- it is testable: `storage.objects` refuses a direct DELETE on a current
-- local stack ("Use the Storage API instead"), which makes the sweep itself
-- unreachable from pgtap. The composition below is what runs in production;
-- this half is what the suite can actually assert.
create or replace function expire_stale_export_jobs()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expired integer;
begin
  update data_export_jobs
  set status = 'expired',
      object_path = null
  where status = 'ready'
    and finished_at < now() - interval '7 days';
  get diagnostics v_expired = row_count;
  return v_expired;
end;
$$;

revoke execute on function expire_stale_export_jobs() from public, anon, authenticated;
grant execute on function expire_stale_export_jobs() to service_role;

create or replace function cleanup_stale_export_blobs()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer;
begin
  delete from storage.objects
  where (
      (bucket_id = 'runs' and name like '%/exports/%')
      or bucket_id = 'exports'
    )
    and created_at < now() - interval '7 days';
  get diagnostics v_deleted = row_count;

  perform expire_stale_export_jobs();

  return v_deleted;
end;
$$;

comment on function cleanup_stale_export_blobs() is
  'Daily sweep of Art 20 export artifacts older than 7 days, across '
  'both the `exports` bucket (20270602_001) and the legacy '
  '`runs/{user_id}/exports/*` prefix, then expire_stale_export_jobs() '
  'for the data_export_jobs rows that pointed at them (20270603_001). '
  'SECURITY DEFINER + executes as the postgres role, which has bypassrls '
  'on Supabase Cloud so the direct DELETE on storage.objects fires '
  'regardless of the storage schema RLS. pg_cron runs the job; '
  'service_role grant lets ops invoke manually if needed. Sibling '
  'pattern: cleanup_stale_live_run_pings (20260509_001) and '
  'cleanup_stale_rate_limits (20260604_001).';
