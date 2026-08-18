-- p_byday must read the event's own timezone, like p_time already does.
--
-- The weekday branch for one-off events derived `extract(isodow from
-- e.starts_at)` straight off the timestamptz, which resolves in the
-- CALLER's session timezone (UTC for PostgREST). A 20:00 New York event
-- is 01:00 the next day in UTC, so it was filed under Monday and a
-- runner filtering Discover to Sunday never saw it; east of UTC the same
-- derivation loses a day the other way. The sibling p_time branch has
-- always coalesced through `e.timezone`.
--
-- Recreated with the COMPLETE body of 20270113_001 (bare-body rule) plus
-- the `at time zone` correction, and carrying the `search_path` pin that
-- 20270415_001 attached via ALTER (a body replace would otherwise drop
-- proconfig). Signature unchanged, so no drop and grants are preserved.
create or replace function search_public_events(
  p_query      text default null,
  p_category   text default null,
  p_cadence    text default null,
  p_byday      text default null,
  p_paid       text default null,
  p_time       text default null,
  p_center_lng double precision default null,
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
) language sql stable security invoker set search_path = public, extensions as $$
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
    e.is_public = true
    and (e.recurrence_freq is not null or e.starts_at >= now())
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
        and case extract(
                   isodow from e.starts_at at time zone coalesce(e.timezone, 'UTC')
                 )::int
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
    and (
      center.pt is null
      or (
        c.location_point is not null
        and ST_DWithin(c.location_point, center.pt, p_radius_m)
      )
    )
  order by
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
