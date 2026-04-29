-- Segments + segment efforts (decisions.md § 37).
--
-- A segment is a named slice of a saved route — (route_id,
-- start_distance_m, end_distance_m). An effort records one runner's
-- elapsed time over the slice. Auto-effort generation is *client*-
-- side in v1 (we do not have pg_net wired so the trigger cannot
-- download the run track from Storage); the client computes efforts
-- after `saveRun` succeeds and inserts them via the RLS-gated path.
--
-- Visibility on both tables tracks the parent route via EXISTS —
-- the same pattern run_kudos / run_comments / run_photos use.

-- ─────────────────────── segments table ───────────────────────

create table segments (
  id                 uuid primary key default gen_random_uuid(),
  route_id           uuid references routes(id) on delete cascade not null,
  name               text not null check (length(name) between 1 and 120),
  start_distance_m   numeric not null check (start_distance_m >= 0),
  end_distance_m     numeric not null,
  length_m           numeric generated always as (end_distance_m - start_distance_m) stored,
  created_by         uuid references auth.users(id) on delete set null,
  created_at         timestamptz not null default now(),
  check (end_distance_m > start_distance_m),
  check (end_distance_m - start_distance_m >= 100)  -- ≥ 100 m (decisions §37)
);

create index segments_route_id on segments (route_id, start_distance_m);
create index segments_created_by on segments (created_by);

alter table segments enable row level security;

-- Inherit visibility from the parent route. The routes RLS already
-- enforces `is_public = true OR user_id = auth.uid() OR club admin`,
-- so this EXISTS pulls in all of those branches.
create policy "segments readable when route is readable"
  on segments for select
  using (exists (select 1 from routes where routes.id = segments.route_id));

-- Anyone who can read the parent route can create a segment on it
-- (Strava-style — segments are a community contribution). The
-- created_by field is enforced as auth.uid() so a user can't forge
-- attribution.
create policy "segment authors create on readable routes"
  on segments for insert
  with check (
    auth.uid() = created_by
    and exists (select 1 from routes where routes.id = segments.route_id)
  );

-- Author or route owner can rename / adjust bounds.
create policy "segment author or route owner edits"
  on segments for update
  using (
    auth.uid() = created_by
    or exists (
      select 1 from routes
      where routes.id = segments.route_id and routes.user_id = auth.uid()
    )
  )
  with check (
    auth.uid() = created_by
    or exists (
      select 1 from routes
      where routes.id = segments.route_id and routes.user_id = auth.uid()
    )
  );

-- Same for delete.
create policy "segment author or route owner deletes"
  on segments for delete
  using (
    auth.uid() = created_by
    or exists (
      select 1 from routes
      where routes.id = segments.route_id and routes.user_id = auth.uid()
    )
  );

-- ─────────────────────── segment_efforts table ───────────────────────

create table segment_efforts (
  id            uuid primary key default gen_random_uuid(),
  segment_id    uuid references segments(id) on delete cascade not null,
  run_id        uuid references runs(id) on delete cascade not null,
  user_id       uuid references auth.users(id) on delete cascade not null,
  time_seconds  numeric not null check (time_seconds > 0),
  started_at    timestamptz not null,
  created_at    timestamptz not null default now(),
  unique (segment_id, run_id)
);

create index segment_efforts_segment on segment_efforts (segment_id, time_seconds asc);
create index segment_efforts_user on segment_efforts (user_id, started_at desc);
create index segment_efforts_run on segment_efforts (run_id);

alter table segment_efforts enable row level security;

-- Effort visibility = segment visibility AND run visibility. Both
-- are EXISTS subqueries against tables that have their own RLS, so
-- private runs don't show up on a public segment's leaderboard.
create policy "efforts readable when segment AND run are readable"
  on segment_efforts for select
  using (
    exists (select 1 from segments where segments.id = segment_efforts.segment_id)
    and exists (select 1 from runs where runs.id = segment_efforts.run_id)
  );

-- A user inserts efforts on their own behalf for runs they own. We
-- don't allow third parties to compute efforts on someone else's
-- run — that's the run owner's job (or the client when the owner
-- opens the detail page).
create policy "run owner inserts efforts on their runs"
  on segment_efforts for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from runs
      where runs.id = segment_efforts.run_id and runs.user_id = auth.uid()
    )
    and exists (select 1 from segments where segments.id = segment_efforts.segment_id)
  );

-- Effort owner can rescind (e.g. wrong segment match, manual
-- recompute). Segment author can also delete on their segment for
-- moderation (matches the run-comments shape).
create policy "effort owner deletes"
  on segment_efforts for delete
  using (auth.uid() = user_id);

create policy "segment author deletes any effort on their segment"
  on segment_efforts for delete
  using (
    exists (
      select 1 from segments
      where segments.id = segment_efforts.segment_id
        and segments.created_by = auth.uid()
    )
  );
