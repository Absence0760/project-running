-- Live-run spectator feed.
--
-- The `/live/{run_id}` URL on the web shares a runner's in-progress GPS
-- track with anyone who has the link. The recording client (phone or
-- watch) inserts one row per sample (~every 3–10 seconds) into
-- `live_run_pings`; the spectator page subscribes to the table via
-- Supabase Realtime filtered by run_id and renders the incoming
-- positions on a map in real time.
--
-- This table is ephemeral. When the run finishes, the recorder deletes
-- its pings (or a cleanup job runs — the `pg_cron` sweep below handles
-- stragglers if the client never came back). A completed run's history
-- lives in `runs.track` (Storage-hosted JSON), so keeping pings past
-- the end of the run would just duplicate data.
--
-- RLS: anyone can SELECT a ping for a run that is itself readable —
-- the visibility of the spectator page falls out of whether the run
-- is public (`runs.is_public = true`) or visible via a direct share
-- link. Inserts and deletes are the run owner only.

create table live_run_pings (
  id bigserial primary key,
  run_id uuid not null references runs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  at timestamptz not null default now(),
  lat double precision not null,
  lng double precision not null,
  ele double precision,
  elapsed_s integer,
  distance_m double precision,
  bpm integer
);

-- The spectator map wants all pings for a run in chronological order;
-- the recorder's delete-on-finish wants to wipe pings by run cheaply.
create index live_run_pings_by_run
  on live_run_pings(run_id, at asc);

alter table live_run_pings enable row level security;

-- Spectator visibility is gated on the parent run being visible to the
-- caller. The `runs` RLS already encodes "public or owner" — we
-- piggyback on that via an existence check.
create policy live_run_pings_visible_when_run_is
  on live_run_pings for select
  using (
    exists (
      select 1 from runs r
      where r.id = live_run_pings.run_id
        and (
          r.is_public = true
          or r.user_id = auth.uid()
        )
    )
  );

-- Only the owner of the run can emit pings for it.
create policy live_run_pings_insert_self
  on live_run_pings for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from runs r
      where r.id = live_run_pings.run_id
        and r.user_id = auth.uid()
    )
  );

-- Owner deletes their own pings (typically on finish).
create policy live_run_pings_delete_self
  on live_run_pings for delete
  using (auth.uid() = user_id);

-- Broadcast changes over WebSockets to subscribed clients.
alter publication supabase_realtime add table live_run_pings;

-- Safety net: a recording client that crashes / loses network before
-- deleting its pings should not leave them stuck in the table forever.
-- Wipe anything older than 4 hours — longer than any realistic run —
-- on each invocation of the cleanup helper. The helper can be wired
-- to pg_cron in a follow-up migration; exposing it as a callable
-- function keeps this migration self-contained.
create or replace function cleanup_stale_live_run_pings()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  delete from live_run_pings
   where at < now() - interval '4 hours';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function cleanup_stale_live_run_pings() from public;
grant execute on function cleanup_stale_live_run_pings() to service_role;
