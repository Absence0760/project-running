-- Gear tracking — shoes + bikes with per-item mileage accrual.
--
-- The user-facing surface: a Settings tab where the runner registers
-- each pair of shoes (or bike) they want to track, sets an optional
-- retirement target (say 800 km for road shoes), and tags individual
-- runs with the gear they wore. The app then shows a mileage bar +
-- a "consider retiring" nudge when the total accrued distance crosses
-- the target. Strava + Garmin have this; the parity backlog
-- (`docs/roadmap.md` § Competitor-parity item #7) sizes it at one
-- week. This v1 ships the schema + CRUD + per-run assignment + the
-- mileage rollup view in one migration; thumbnails, retirement
-- notifications, and a "automatically assign default gear" feature
-- are deferred.
--
-- Two tables:
--   `gear`     — one row per owned item, owner-scoped via RLS.
--   `run_gear` — join (run_id, gear_id). Visibility follows the parent
--                run via the standard is_run_visible_to() helper, so a
--                public run leaks its gear list to anyone who can see
--                the run (matching kudos / comments / photos shape).
--                Inserts are owner-only on BOTH the run AND the gear
--                to keep one user from tagging another user's run.
--
-- Plus a `gear_with_distance` view: for each gear row, sums the
-- `runs.distance_m` of every assigned run. Read-side only; updates
-- happen by inserting/deleting `run_gear` rows. Postgres is fast
-- enough at this aggregate that materialising it isn't worth the
-- staleness window — at 1k runs/user × maybe 5 gear items each, the
-- view query is sub-millisecond and runs once per Settings render.

-- ─────────────────── gear ───────────────────

create table public.gear (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid references auth.users(id) on delete cascade not null,
  kind                text not null check (kind in ('shoe', 'bike')),
  name                text not null check (length(name) between 1 and 80),
  brand               text check (brand is null or length(brand) <= 60),
  model               text check (model is null or length(model) <= 60),
  purchased_at        date,
  retired_at          date,
  target_distance_m   bigint check (target_distance_m is null or target_distance_m > 0),
  notes               text check (notes is null or length(notes) <= 500),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index gear_owner on public.gear (owner_id, kind, retired_at nulls first);

alter table public.gear enable row level security;

create policy "owners read their gear"
  on public.gear for select
  using (owner_id = auth.uid());

create policy "owners insert their gear"
  on public.gear for insert
  with check (owner_id = auth.uid());

create policy "owners update their gear"
  on public.gear for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "owners delete their gear"
  on public.gear for delete
  using (owner_id = auth.uid());

-- updated_at bump on every UPDATE.
create or replace function gear_set_updated_at()
returns trigger language plpgsql as $$
begin
  NEW.updated_at = now();
  return NEW;
end;
$$;

create trigger gear_updated_at
  before update on public.gear
  for each row execute function gear_set_updated_at();

-- ─────────────────── run_gear (join) ───────────────────

create table public.run_gear (
  run_id    uuid references public.runs(id) on delete cascade not null,
  gear_id   uuid references public.gear(id) on delete cascade not null,
  created_at timestamptz not null default now(),
  primary key (run_id, gear_id)
);

create index run_gear_gear on public.run_gear (gear_id);

alter table public.run_gear enable row level security;

-- SELECT mirrors the run-visibility rule used by kudos / comments /
-- photos: anyone who can see the run can see what gear was assigned.
-- Drives the gear chip on the public share page.
create policy "run_gear visible when parent run is visible"
  on public.run_gear for select
  using (
    exists (
      select 1 from public.runs r
      where r.id = run_gear.run_id
        and private.is_run_visible_to(r.id, auth.uid())
    )
  );

-- INSERT requires the caller to own BOTH the run and the gear. Stops
-- a user from tagging someone else's gear onto their own run (or
-- vice-versa).
create policy "owners assign their gear to their runs"
  on public.run_gear for insert
  with check (
    exists (
      select 1 from public.runs r
      where r.id = run_gear.run_id and r.user_id = auth.uid()
    )
    and exists (
      select 1 from public.gear g
      where g.id = run_gear.gear_id and g.owner_id = auth.uid()
    )
  );

create policy "owners unassign gear from their runs"
  on public.run_gear for delete
  using (
    exists (
      select 1 from public.runs r
      where r.id = run_gear.run_id and r.user_id = auth.uid()
    )
  );

-- ─────────────────── gear_with_distance view ───────────────────

-- Aggregates per-gear accrued mileage by summing `runs.distance_m`
-- across the join. LEFT JOIN so brand-new gear with zero assigned
-- runs still surfaces (distance_m = 0). The view inherits RLS from
-- its base tables: a non-owner can't see another user's gear or
-- their assignments, so the SUM stays scoped automatically.
create or replace view public.gear_with_distance
with (security_invoker = true) as
select
  g.id,
  g.owner_id,
  g.kind,
  g.name,
  g.brand,
  g.model,
  g.purchased_at,
  g.retired_at,
  g.target_distance_m,
  g.notes,
  g.created_at,
  g.updated_at,
  coalesce(sum(r.distance_m), 0)::bigint as total_distance_m,
  count(r.id) as run_count
from public.gear g
left join public.run_gear rg on rg.gear_id = g.id
left join public.runs r on r.id = rg.run_id
group by g.id;

grant select on public.gear_with_distance to authenticated;
