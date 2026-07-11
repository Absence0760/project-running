-- Redact race_listings.submitted_by from the public calendar surface
-- (audit/rls 2026-07-03; source 20270214_001).
--
-- The calendar's `for select using (true)` policy let anon read every column,
-- including submitted_by — a user-id crosswalk ("this account submitted the
-- Riverside 5K near their home town") on an otherwise non-personal table. The
-- search_race_listings RPC already projects a submitted_by-free column list;
-- only the raw REST read leaked.
--
-- Same medicine as 20270313_001: the base table becomes owner-read
-- (submitters keep full-row access to their own listings — the edit surface
-- and the INSERT ... RETURNING path both need it) and everyone else reads
-- through a redacted view. search_race_listings stays security invoker but is
-- re-pointed at the view so anon discovery keeps working; the import EF /
-- admin tooling write with service_role, which bypasses RLS.

-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

drop policy "race listings readable by all" on race_listings;

create policy "submitters read own listings"
  on race_listings for select to authenticated
  using (submitted_by = auth.uid());

create view public_race_listings as
select
  l.id,
  l.provider,
  l.provider_race_id,
  l.name,
  l.race_date,
  l.distance_m,
  l.location_label,
  l.location_point,
  l.entry_url,
  l.results_url,
  l.is_verified,
  l.created_at,
  l.updated_at
from race_listings l;

grant select on public_race_listings to anon, authenticated;

-- Full body carried forward from 20270214_001; only the FROM changes.
create or replace function search_race_listings(
  p_query      text default null,
  p_distance   text default null,
  p_from       date default null,
  p_to         date default null,
  p_center_lng double precision default null,
  p_center_lat double precision default null,
  p_radius_m   double precision default 50000,
  p_limit      int  default 60
) returns table (
  id               uuid,
  provider         text,
  provider_race_id text,
  name             text,
  race_date        date,
  distance_m       integer,
  location_label   text,
  entry_url        text,
  results_url      text,
  is_verified      boolean,
  distance_m_away  double precision
) language sql stable security invoker as $$
  with center as (
    select case
      when p_center_lng is not null and p_center_lat is not null
      then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
    end as pt
  )
  select
    l.id,
    l.provider,
    l.provider_race_id,
    l.name,
    l.race_date,
    l.distance_m,
    l.location_label,
    l.entry_url,
    l.results_url,
    l.is_verified,
    case when center.pt is not null and l.location_point is not null
      then ST_Distance(l.location_point, center.pt)
      else null
    end as distance_m_away
  from public_race_listings l
  cross join center
  where
    (p_from is not null or p_to is not null or l.race_date >= current_date)
    and (p_from is null or l.race_date >= p_from)
    and (p_to is null or l.race_date <= p_to)
    and (
      p_query is null
      or l.name ilike '%' || p_query || '%'
    )
    and (
      p_distance is null
      or (p_distance = '5k'       and l.distance_m between 4500 and 5500)
      or (p_distance = '10k'      and l.distance_m between 9000 and 11000)
      or (p_distance = 'half'     and l.distance_m between 20000 and 22000)
      or (p_distance = 'marathon' and l.distance_m between 41000 and 43000)
      or (p_distance = 'ultra'    and l.distance_m > 43000)
    )
    and (
      center.pt is null
      or (
        l.location_point is not null
        and ST_DWithin(l.location_point, center.pt, p_radius_m)
      )
    )
  order by
    case when center.pt is not null and l.location_point is not null
      then ST_Distance(l.location_point, center.pt)
      else null
    end asc nulls last,
    l.race_date asc,
    l.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;
