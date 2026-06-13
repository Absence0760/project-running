-- Proximity ("near me" / "near a place") filter for search_public_events —
-- the deferred geo slice of decisions §147.
--
-- Filters by the CLUB's geocoded location (clubs.location_point), NOT the
-- event's precise meeting point. events.meet_lat/meet_lng are deliberately
-- REVOKED (members-only via get_event_meet_point, 20261027_001) so discovery
-- can't scrape a class's exact studio/home address. clubs.location_point is
-- public, already geocoded by ClubEditor, GiST-indexed
-- (clubs_location_point_gist), and the right granularity for "near me" — a
-- studio's classes are at the studio. (Location never lives on
-- gym_workouts/session_plans; a logged workout/template can happen anywhere.)
--
-- Mirrors search_clubs (20260905_001): a `center` CTE, ST_DWithin radius gate,
-- distance-ascending order, graceful text fallback when no center is given.
-- Stays `security invoker` + scoped to clubs.is_public = true. distance_m is
-- public-safe — it's derived from the already-public club point.

-- Signature changes (3 new geo params + distance_m in the return), so drop the
-- 7-arg p_time version (20270111_001) first.
drop function if exists search_public_events(text, text, text, text, text, text, int);

create or replace function search_public_events(
  p_query      text default null,             -- matches discipline OR title (ILIKE)
  p_category   text default null,             -- 'run' | 'cycle' | 'class' | 'social'
  p_cadence    text default null,             -- 'one_off' | 'weekly' | 'biweekly' | 'monthly'
  p_byday      text default null,             -- ISO weekday code 'MO'..'SU'
  p_paid       text default null,             -- 'free' | 'paid'
  p_time       text default null,             -- 'morning' | 'afternoon' | 'evening' (local)
  p_center_lng double precision default null, -- "near me / near a place" centroid
  p_center_lat double precision default null,
  p_radius_m   double precision default 50000,
  p_limit      int  default 60
) returns table (
  id              uuid,
  club_id         uuid,
  club_name       text,
  club_slug       text,
  title           text,
  category        text,
  discipline      text,
  starts_at       timestamptz,
  timezone        text,
  duration_min    integer,
  recurrence_freq text,
  recurrence_byday text[],
  capacity        integer,
  price_cents     integer,
  currency        text,
  distance_m      double precision
) language sql stable security invoker as $$
  with center as (
    select case
      when p_center_lng is not null and p_center_lat is not null
      then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
    end as pt
  )
  select
    e.id,
    e.club_id,
    c.name,
    c.slug,
    e.title,
    e.category,
    e.discipline,
    e.starts_at,
    e.timezone,
    e.duration_min,
    e.recurrence_freq,
    e.recurrence_byday,
    e.capacity,
    pr.price_cents,
    pr.currency,
    case when center.pt is not null and c.location_point is not null
      then ST_Distance(c.location_point, center.pt)
      else null
    end as distance_m
  from events e
  join clubs c on c.id = e.club_id and c.is_public = true
  cross join center
  left join lateral (
    select min(price_cents) as price_cents,
           (array_agg(currency order by price_cents))[1] as currency
    from event_pricing ep
    where ep.event_id = e.id
  ) pr on true
  where
    (e.recurrence_freq is not null or e.starts_at >= now())
    and (
      p_query is null
      or e.discipline ilike '%' || p_query || '%'
      or e.title ilike '%' || p_query || '%'
    )
    and (p_category is null or e.category = p_category)
    and (
      p_cadence is null
      or (p_cadence = 'one_off' and e.recurrence_freq is null)
      or (p_cadence <> 'one_off' and e.recurrence_freq = p_cadence)
    )
    and (
      p_byday is null
      or (e.recurrence_byday is not null and e.recurrence_byday @> array[p_byday])
      or (
        e.recurrence_freq is null
        and case extract(isodow from e.starts_at)::int
              when 1 then 'MO' when 2 then 'TU' when 3 then 'WE'
              when 4 then 'TH' when 5 then 'FR' when 6 then 'SA'
              when 7 then 'SU' end = p_byday
      )
    )
    and (
      p_paid is null
      or (p_paid = 'paid' and pr.price_cents is not null)
      or (p_paid = 'free' and pr.price_cents is null)
    )
    and (
      p_time is null
      or case
           when extract(hour from e.starts_at at time zone coalesce(e.timezone, 'UTC'))::int
                between 5 and 11 then 'morning'
           when extract(hour from e.starts_at at time zone coalesce(e.timezone, 'UTC'))::int
                between 12 and 16 then 'afternoon'
           else 'evening'
         end = p_time
    )
    -- Proximity gate: only when a center is supplied. Clubs with a null
    -- location_point are correctly excluded under "near me" (we can't place
    -- them); they still surface on every other (text/category/…) search.
    and (
      center.pt is null
      or (
        c.location_point is not null
        and ST_DWithin(c.location_point, center.pt, p_radius_m)
      )
    )
  order by
    -- Nearest-first when a center is given; otherwise the original
    -- soonest-first ordering.
    case when center.pt is not null and c.location_point is not null
      then ST_Distance(c.location_point, center.pt)
      else null
    end asc nulls last,
    e.starts_at asc nulls last,
    e.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

grant execute on function search_public_events(
  text, text, text, text, text, text, double precision, double precision, double precision, int
) to authenticated, anon;
