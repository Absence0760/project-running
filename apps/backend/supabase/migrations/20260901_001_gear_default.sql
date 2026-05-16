-- Gear: "current / default" concept + auto-tag-on-run-insert.
--
-- The v1 gear feature (migration 20260827_001) shipped manual run-by-run
-- tagging — every run requires opening the picker and checking the gear
-- you wore. In practice users rotate through one or two pairs of shoes
-- at a time and tag every run with the same pair, so the manual step
-- is pure friction. Strava + Garmin both ship a "default gear" concept
-- that auto-tags new activities; this migration adds the same.
--
-- Surface:
--   - One non-retired gear item per (owner, kind) can be marked as the
--     user's current default. Partial unique index enforces it.
--   - Trigger on `runs insert` looks up the owner's default gear of the
--     kind that matches the run's activity_type (run/walk/hike → shoe,
--     cycle → bike) and creates a `run_gear` row. Idempotent via
--     `on conflict do nothing`.
--   - The trigger is SECURITY DEFINER because the inserting role is the
--     end-user (not service_role), and `run_gear` has RLS that requires
--     the gear's owner_id matches. The DEFINER path bypasses that —
--     safe because we anchor every insert on `new.user_id` which is the
--     row the user just authored.
--
-- User-visible effect: a fresh runner who registered a shoe and marked
-- it as their current pair sees that shoe chip on every subsequent run
-- without lifting a finger. Manual edits via the per-run picker still
-- override (the picker writes / deletes `run_gear` directly).
--
-- Retirement nuance: if a user retires the default, the partial unique
-- index doesn't prevent it (retired rows are filtered out of the
-- index), so the row's `is_default` flag stays true on the historical
-- record but the trigger filters it out via `retired_at is null`. The
-- user can then mark a different one as default cleanly.

alter table public.gear
  add column is_default boolean not null default false;

-- Republish the gear_with_distance view so PostgREST surfaces the new
-- column to the client. CREATE OR REPLACE can't reorder columns (PG
-- 42P16), so we DROP + CREATE — losing the GRANT, which we re-issue
-- at the end.
drop view public.gear_with_distance;
create view public.gear_with_distance
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
  g.is_default,
  g.created_at,
  g.updated_at,
  coalesce(sum(r.distance_m), 0)::bigint as total_distance_m,
  count(r.id) as run_count
from public.gear g
left join public.run_gear rg on rg.gear_id = g.id
left join public.runs r on r.id = rg.run_id
group by g.id;

grant select on public.gear_with_distance to authenticated;

-- At most one default per (owner, kind) among non-retired rows. The
-- partial filter is important: retiring a default and registering a
-- new one shouldn't trip the constraint just because the old one's
-- is_default flag was never cleared.
create unique index gear_owner_kind_default
  on public.gear (owner_id, kind)
  where is_default = true and retired_at is null;

-- Auto-tag trigger. Maps the run's activity_type to a gear kind and
-- inserts a run_gear row for every matching non-retired default gear
-- (in practice at most one — the unique index above enforces it).
create or replace function auto_tag_default_gear()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  activity_kind text;
begin
  -- Default to 'shoe' when activity_type is missing — most runs are
  -- runs, and a bike default tag-stamping a foot-powered run is more
  -- surprising than the reverse.
  activity_kind := case coalesce(new.metadata->>'activity_type', 'run')
    when 'cycle' then 'bike'
    else 'shoe'
  end;

  insert into run_gear (run_id, gear_id)
  select new.id, g.id
  from gear g
  where g.owner_id = new.user_id
    and g.kind = activity_kind
    and g.is_default = true
    and g.retired_at is null
  on conflict (run_id, gear_id) do nothing;

  return new;
end;
$$;

grant execute on function auto_tag_default_gear() to authenticated;

create trigger runs_auto_tag_default_gear
  after insert on runs
  for each row
  execute function auto_tag_default_gear();

-- Backfill: stamp existing runs that have no run_gear rows yet with the
-- owner's current default gear (if any). One-shot — newly-created runs
-- from this point on are handled by the trigger above.
insert into run_gear (run_id, gear_id)
select r.id, g.id
from runs r
join gear g
  on g.owner_id = r.user_id
 and g.is_default = true
 and g.retired_at is null
 and g.kind = case coalesce(r.metadata->>'activity_type', 'run')
   when 'cycle' then 'bike'
   else 'shoe'
 end
where not exists (
  select 1 from run_gear rg where rg.run_id = r.id and rg.gear_id = g.id
);
