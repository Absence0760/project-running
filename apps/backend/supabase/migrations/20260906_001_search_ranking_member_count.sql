-- Anti-spam phase 1: search ranking by reputation signals.
--
-- The search-scalability audit flagged that a bot mass-creating clubs
-- or registering accounts would push real users off the top of
-- /social Browse + the People tab, because both pages sort by
-- created_at desc with no quality signal. This migration adds the
-- ranking infrastructure for clubs; the people-side ranking happens
-- entirely client-side in `data.ts#searchPeople` against the existing
-- `is_public` runs count.
--
-- Changes:
--
--   1. `clubs.member_count integer not null default 0` — denormalised
--      count of `club_members` where `status = 'active'`. The
--      `enrichClubs` helper in `apps/web/src/lib/data.ts` was already
--      computing this with a post-query aggregate; the column lets
--      the `search_clubs` RPC use it for sorting and saves a round
--      trip on every list render.
--
--   2. A trigger on `club_members` that maintains the count on
--      INSERT / UPDATE / DELETE. `UPDATE` is the interesting case —
--      flipping `status` from `'pending'` to `'active'` (an admin
--      approval) increments; the reverse decrements.
--
--   3. The `search_clubs` RPC sort is widened from
--          (distance, created_at desc)
--      to
--          (distance, member_count desc, created_at desc)
--      so a bot newly creating 60 empty clubs can't outrank an old
--      established club within the same geographic match.

-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

alter table clubs
  add column member_count integer not null default 0;

-- Backfill from the existing rows.
update clubs c
set member_count = coalesce(sub.cnt, 0)
from (
  select club_id, count(*)::int as cnt
  from club_members
  where status = 'active'
  group by club_id
) sub
where sub.club_id = c.id;

-- Maintenance trigger. Same shape as `routes_run_count_trigger`
-- from `20260426_001_route_discovery.sql`.
create or replace function clubs_member_count_trigger()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'active' then
      update clubs set member_count = member_count + 1 where id = new.club_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.status = 'active' then
      update clubs set member_count = greatest(member_count - 1, 0) where id = old.club_id;
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    -- Status flips +/- 1 if either side is 'active'. Identical
    -- statuses are a no-op.
    if old.status is distinct from new.status then
      if old.status = 'active' then
        update clubs set member_count = greatest(member_count - 1, 0) where id = old.club_id;
      end if;
      if new.status = 'active' then
        update clubs set member_count = member_count + 1 where id = new.club_id;
      end if;
    end if;
    -- club_id move (rare — would be a rebind, not currently exposed)
    -- mirrors routes_run_count_trigger's pattern.
    if old.club_id is distinct from new.club_id then
      if old.status = 'active' then
        update clubs set member_count = greatest(member_count - 1, 0) where id = old.club_id;
      end if;
      if new.status = 'active' then
        update clubs set member_count = member_count + 1 where id = new.club_id;
      end if;
    end if;
    return new;
  end if;
  return null;
end;
$$;

create trigger club_members_maintain_count
  after insert or update of status, club_id or delete on club_members
  for each row execute function clubs_member_count_trigger();

-- Extend the column grants (20260818_001) to expose member_count to
-- anon + authenticated. The number isn't sensitive — it's already
-- visible via the live aggregate that `enrichClubs` runs today.
grant select (member_count) on clubs to authenticated, anon;

-- Re-create search_clubs with member_count in the sort.
create or replace function search_clubs(
  p_query text default null,
  p_center_lng double precision default null,
  p_center_lat double precision default null,
  p_radius_m double precision default 80000,
  p_limit int default 60
) returns setof clubs language sql stable security invoker as $$
  with center as (
    select case
      when p_center_lng is not null and p_center_lat is not null
      then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
    end as pt
  )
  select c.*
  from clubs c, center
  where c.is_public = true
    and (
      p_query is null
      or c.name ilike '%' || p_query || '%'
      or c.location_label ilike '%' || p_query || '%'
      or (
        center.pt is not null
        and c.location_point is not null
        and ST_DWithin(c.location_point, center.pt, p_radius_m)
      )
    )
  order by
    -- Geographic matches first, sorted by distance.
    case when center.pt is not null and c.location_point is not null
      then ST_Distance(c.location_point, center.pt)
      else null
    end asc nulls last,
    -- Within the same distance tier (or text-only matches), prefer
    -- clubs with more active members. A brand-new spam club starts
    -- at 1 member (the bot itself, via the owner-enroll trigger), so
    -- this naturally deprioritises low-reputation rows.
    c.member_count desc,
    c.created_at desc
  limit p_limit;
$$;
