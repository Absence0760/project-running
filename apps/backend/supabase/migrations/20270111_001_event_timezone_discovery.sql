-- Time-of-day discovery filter for search_public_events (decisions §147 follow-up).
--
-- "find a class at 7pm" was deferred because events.starts_at is a bare
-- timestamptz (a UTC instant) with no record of the local wall-clock the
-- organiser meant — extracting hour-of-day from it is ambiguous across zones.
-- Fix: anchor each event to an IANA timezone captured at create time, so
-- `starts_at AT TIME ZONE events.timezone` recovers the intended local hour
-- (and for a recurring series, the anchor's local hour IS the fixed weekly
-- time — DST shifts the UTC instant, not the 19:00 intent).

alter table events add column timezone text;

comment on column events.timezone is
  'IANA timezone (e.g. America/New_York) the event''s local wall-clock time is '
  'expressed in, captured from the organiser''s browser at create time. Null on '
  'legacy rows (pre-20270111_001); discovery time-of-day filtering falls back to '
  'UTC for those.';

-- events is column-SELECT-locked (20260818_001): a new column is deny-by-default,
-- so the security-invoker discovery RPC (running as anon/authenticated) can't
-- read timezone until it's granted. Mirrors the category/discipline grants
-- (20261228_001) — a non-sensitive IANA string, safe to expose cross-user.
grant select (timezone) on events to authenticated, anon;

-- Recreate the discovery RPC with a time-of-day bucket. The signature changes
-- (new p_time arg), so drop the 6-arg version first.
drop function if exists search_public_events(text, text, text, text, text, int);

create or replace function search_public_events(
  p_query    text default null,   -- matches discipline OR title (ILIKE)
  p_category text default null,   -- 'run' | 'cycle' | 'class' | 'social'
  p_cadence  text default null,   -- 'one_off' | 'weekly' | 'biweekly' | 'monthly'
  p_byday    text default null,   -- ISO weekday code 'MO'..'SU'
  p_paid     text default null,   -- 'free' | 'paid'
  p_time     text default null,   -- 'morning' | 'afternoon' | 'evening' (local)
  p_limit    int  default 60
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
  currency        text
) language sql stable security invoker as $$
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
    pr.currency
  from events e
  join clubs c on c.id = e.club_id and c.is_public = true
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
           -- Local hour at the event's timezone (UTC fallback for legacy rows).
           when extract(hour from e.starts_at at time zone coalesce(e.timezone, 'UTC'))::int
                between 5 and 11 then 'morning'
           when extract(hour from e.starts_at at time zone coalesce(e.timezone, 'UTC'))::int
                between 12 and 16 then 'afternoon'
           else 'evening'   -- 17:00–04:59 (covers evening + late night)
         end = p_time
    )
  order by e.starts_at asc nulls last, e.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

grant execute on function search_public_events(
  text, text, text, text, text, text, int
) to authenticated, anon;
