-- Map matching pipeline. Two new tables, one trigger, one worker API.
--
-- The roadmap calls for storing both raw and matched tracks so future
-- re-matching with better data / algorithms is possible (roadmap.md
-- §515-531). The worker that does the actual matching lives in the
-- planned Go service (roadmap.md §205-214); this migration is the
-- Postgres half — schema, status state, job queue, RLS, indexes.
--
-- Design notes:
--
-- * `run_matched_tracks` is one row per run rather than two columns on
--   `runs` so the rarely-read state lives outside the hot list-query
--   path. Owner reads it via RLS; only the worker (service role)
--   writes to it.
-- * `jobs` is a generic Postgres-backed queue (River-style) — first
--   tenant is map matching, but the same table will host
--   strava-webhook / token-refresh / data-export workers when those
--   move off Edge Functions per roadmap §214.
-- * Idempotency is enforced by indexes, not application logic: the
--   trigger blindly INSERTs and ON CONFLICTs out, the worker claim
--   uses `for update skip locked` so two workers can drain in
--   parallel without thrashing each other.
-- * Security is deny-by-default RLS plus revoke-execute-from-public
--   on the worker functions; the Go service authenticates with the
--   service role key and bypasses RLS, owners read their own state
--   through a single SELECT policy.
-- * Performance is partial indexes — full-table scans on a queue grow
--   linearly with finished jobs, partial indexes stay constant on
--   the active set.

-- ============================================================
-- 1. run_matched_tracks
-- ============================================================
--
-- Per-run matched-track state. PK on run_id makes the owner read a
-- direct lookup; the FK with on-delete-cascade means deleting a run
-- (or its user) cleans up the matched-track row automatically without
-- the application needing to remember.

create table run_matched_tracks (
  run_id uuid primary key references runs(id) on delete cascade,
  status text not null default 'pending',
  matched_track_url text,
  attempts smallint not null default 0,
  matched_at timestamptz,
  algorithm text,
  algorithm_version text,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint run_matched_tracks_status_check
    check (status in ('pending', 'matched', 'failed', 'skipped'))
);

-- The worker's "what's next" scan. Partial so it stays O(active set)
-- regardless of how many runs have already been matched. Ordered by
-- created_at so the queue drains FIFO.
create index run_matched_tracks_pending
  on run_matched_tracks (created_at)
  where status = 'pending';

-- updated_at maintenance. Same shape as user_profiles_set_updated_at
-- elsewhere in the schema.
create or replace function run_matched_tracks_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  NEW.updated_at := now();
  return NEW;
end;
$$;

create trigger run_matched_tracks_updated_at
  before update on run_matched_tracks
  for each row
  execute function run_matched_tracks_set_updated_at();

-- ============================================================
-- 2. jobs (generic Postgres-backed queue)
-- ============================================================
--
-- `bigint generated always as identity` instead of `bigserial` so the
-- Dart codegen's narrow type parser picks up the column (bigserial
-- isn't in _pgToDart and gets dropped from the generated row). Not
-- that any client reads jobs.id — the table is service-role only —
-- but losing the PK from a generated row is the kind of silent drift
-- that bites later.

create table jobs (
  id bigint generated always as identity primary key,
  kind text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued',
  attempts smallint not null default 0,
  max_attempts smallint not null default 5,
  scheduled_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  finished_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint jobs_status_check
    check (status in ('queued', 'running', 'done', 'failed', 'cancelled')),
  constraint jobs_attempts_nonneg check (attempts >= 0),
  constraint jobs_max_attempts_pos check (max_attempts > 0)
);

-- The hot path: the worker's claim query. Filters on status='queued'
-- and orders by scheduled_at. Partial index keeps the b-tree small
-- (finished jobs accumulate but don't bloat the worker's scan).
-- Including `kind` lets the worker filter by job type without an
-- extra index lookup.
create index jobs_queued
  on jobs (scheduled_at, kind)
  where status = 'queued';

-- For monitoring: stuck-job detection ("running for >5min" alerts).
create index jobs_running
  on jobs (locked_at)
  where status = 'running';

-- Idempotency for the map_match enqueue path. While a previous job
-- for the same run is still queued or running, a re-enqueue is a
-- no-op via ON CONFLICT. Once the previous one finishes the partial
-- index lets a fresh attempt land — that's the desired behaviour for
-- re-matching when a run's track_url is updated.
create unique index jobs_dedupe_map_match
  on jobs (kind, ((payload->>'run_id')::uuid))
  where kind = 'map_match' and status in ('queued', 'running');

create or replace function jobs_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  NEW.updated_at := now();
  return NEW;
end;
$$;

create trigger jobs_updated_at
  before update on jobs
  for each row
  execute function jobs_set_updated_at();

-- ============================================================
-- 3. Auto-enqueue trigger on runs
-- ============================================================
--
-- Fires after every run insert and after every track_url update. The
-- `update of track_url` clause means unrelated UPDATEs (renaming a
-- run, editing notes, ...) don't pay the trigger cost. SECURITY
-- DEFINER lets the trigger bypass jobs RLS without making the table
-- readable by all authed users.

create or replace function runs_enqueue_match_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- A track is required. Manual-entry runs and indoor / no-GPS
  -- recordings post with track_url = null; they have nothing to
  -- match against.
  if NEW.track_url is null or NEW.track_url = '' then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    insert into run_matched_tracks (run_id, status)
    values (NEW.id, 'pending')
    on conflict (run_id) do nothing;
  elsif TG_OP = 'UPDATE'
        and NEW.track_url is distinct from OLD.track_url then
    -- The runner re-uploaded the run with a new track. Reset state so
    -- the matcher re-processes against the fresh data — the previous
    -- matched_track_url is stale and the previous algorithm output
    -- doesn't apply.
    insert into run_matched_tracks (run_id, status)
    values (NEW.id, 'pending')
    on conflict (run_id) do update
    set status = 'pending',
        matched_track_url = null,
        attempts = 0,
        matched_at = null,
        error_message = null,
        algorithm = null,
        algorithm_version = null;
  else
    -- track_url unchanged on this UPDATE — nothing to do.
    return NEW;
  end if;

  -- Queue the matcher. Idempotent against jobs_dedupe_map_match.
  insert into jobs (kind, payload)
  values (
    'map_match',
    jsonb_build_object('run_id', NEW.id, 'user_id', NEW.user_id)
  )
  on conflict do nothing;

  return NEW;
end;
$$;

create trigger runs_enqueue_match_job_trigger
  after insert or update of track_url on runs
  for each row
  execute function runs_enqueue_match_job();

-- ============================================================
-- 4. Backfill: enqueue jobs for runs that already have tracks
-- ============================================================
--
-- The trigger only catches future inserts/updates. Existing runs need
-- their state rows + jobs created once. ON CONFLICT keeps it
-- idempotent so re-running the migration (or replaying it on a
-- branch) doesn't double-queue.

insert into run_matched_tracks (run_id, status)
select id, 'pending'
from runs
where track_url is not null and track_url <> ''
on conflict (run_id) do nothing;

insert into jobs (kind, payload)
select
  'map_match',
  jsonb_build_object('run_id', r.id, 'user_id', r.user_id)
from runs r
left join jobs j
  on j.kind = 'map_match'
  and (j.payload->>'run_id')::uuid = r.id
  and j.status in ('queued', 'running')
where r.track_url is not null
  and r.track_url <> ''
  and j.id is null;

-- ============================================================
-- 5. Worker API (SECURITY DEFINER)
-- ============================================================
--
-- The Go worker authenticates with the service role key and bypasses
-- RLS, but goes through these named functions anyway so the public
-- surface is typed and the internal column shape can evolve without
-- breaking workers. PUBLIC EXECUTE is revoked; only service_role
-- gets in.

-- Claim the next ready job. `for update skip locked` is what makes
-- this safe under concurrent workers — two workers calling
-- claim_next_job simultaneously each get a different row instead of
-- blocking on each other or claiming the same job. Returns 0 rows
-- when the queue is empty so the worker can sleep + retry.
create or replace function claim_next_job(
  worker_id text,
  kind_filter text default null
)
returns table (
  id bigint,
  kind text,
  payload jsonb,
  attempts smallint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  update jobs j
  set status = 'running',
      attempts = j.attempts + 1,
      locked_at = now(),
      locked_by = worker_id
  where j.id = (
    select j2.id
    from jobs j2
    where j2.status = 'queued'
      and j2.scheduled_at <= now()
      and (kind_filter is null or j2.kind = kind_filter)
      and j2.attempts < j2.max_attempts
    order by j2.scheduled_at, j2.id
    limit 1
    for update skip locked
  )
  returning j.id, j.kind, j.payload, j.attempts;
end;
$$;

-- Mark a job done or failed. `result_status` must be 'done' or
-- 'failed' — a CHECK on the function arg fails fast if the worker
-- mis-encodes a state. The body uses the same CHECK that's on the
-- table so a malformed state never lands as data.
create or replace function finish_job(
  job_id bigint,
  result_status text,
  err text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if result_status not in ('done', 'failed', 'cancelled') then
    raise exception 'finish_job: bad result_status %', result_status
      using errcode = '22023';
  end if;
  update jobs
  set status = result_status,
      finished_at = now(),
      last_error = err
  where id = job_id;
end;
$$;

-- Re-queue a transient failure with backoff. The worker calls this
-- when the matching engine is temporarily unavailable; the row stays
-- 'queued' but won't be picked up again until `delay_seconds` from
-- now. attempts isn't incremented here — the caller already bumped it
-- on claim, so the max_attempts ceiling applies normally.
create or replace function defer_job(
  job_id bigint,
  delay_seconds integer,
  err text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if delay_seconds < 0 then
    raise exception 'defer_job: delay_seconds must be >= 0'
      using errcode = '22023';
  end if;
  update jobs
  set status = 'queued',
      scheduled_at = now() + (delay_seconds || ' seconds')::interval,
      locked_at = null,
      locked_by = null,
      last_error = err
  where id = job_id;
end;
$$;

revoke execute on function claim_next_job(text, text) from public;
revoke execute on function finish_job(bigint, text, text) from public;
revoke execute on function defer_job(bigint, integer, text) from public;
grant execute on function claim_next_job(text, text) to service_role;
grant execute on function finish_job(bigint, text, text) to service_role;
grant execute on function defer_job(bigint, integer, text) to service_role;

-- ============================================================
-- 6. RLS
-- ============================================================
--
-- run_matched_tracks: owner-of-run can SELECT. No INSERT/UPDATE/DELETE
-- policies, so nothing reaches the table from anon/authenticated; the
-- worker uses the service role key which bypasses RLS.
--
-- jobs: deny everything. No policies, no public access. Service role
-- bypasses RLS for direct queries; the SECURITY DEFINER worker
-- functions above provide the typed surface for everything else.

alter table run_matched_tracks enable row level security;

create policy "owners read their match status"
  on run_matched_tracks
  for select
  using (
    exists (
      select 1 from runs r
      where r.id = run_matched_tracks.run_id
        and r.user_id = auth.uid()
    )
  );

alter table jobs enable row level security;
