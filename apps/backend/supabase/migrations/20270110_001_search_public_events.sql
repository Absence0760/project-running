-- Cross-club activity / event discovery (the first global "find a class / group
-- run / ride / social" surface). Until now events were reachable only inside a
-- club you already knew or belonged to (fetchUpcomingEvents is club-scoped);
-- there was no way to search "paid pilates class, Sundays" or "weekly group run"
-- across clubs. This adds one search RPC over the typed-events model
-- (category run/cycle/class/social + discipline + recurrence + pricing).
--
-- Visibility: mirrors search_clubs exactly — `security invoker`, scoped to
-- `clubs.is_public = true`, so it surfaces only public clubs' events to anyone
-- (incl. anon). Events RLS (20260416_001) already permits reading a public
-- club's events, so no SECURITY DEFINER and no new exposure: the RPC can only
-- return rows the caller could already read.

-- Trigram index so discipline search ("pilates" -> "Reformer Pilates") stays an
-- index scan, not a seq scan, as public class listings grow.
-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

create extension if not exists pg_trgm with schema extensions;

create index if not exists events_discipline_trgm
  on events using gin (discipline extensions.gin_trgm_ops)
  where discipline is not null;

-- Supports the public-discovery filter + soonest-first ordering.
create index if not exists events_discovery_idx
  on events (category, starts_at)
  where club_id is not null;

create or replace function search_public_events(
  p_query    text default null,   -- matches discipline OR title (ILIKE)
  p_category text default null,   -- 'run' | 'cycle' | 'class' | 'social'
  p_cadence  text default null,   -- 'one_off' | 'weekly' | 'biweekly' | 'monthly'
  p_byday    text default null,   -- ISO weekday code 'MO'..'SU'
  p_paid     text default null,   -- 'free' | 'paid'
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
    e.duration_min,
    e.recurrence_freq,
    e.recurrence_byday,
    e.capacity,
    pr.price_cents,
    pr.currency
  from events e
  join clubs c on c.id = e.club_id and c.is_public = true
  -- Cheapest current price, if any (per-instance pricing collapses to a "from").
  left join lateral (
    select min(price_cents) as price_cents,
           (array_agg(currency order by price_cents))[1] as currency
    from event_pricing ep
    where ep.event_id = e.id
  ) pr on true
  where
    -- Upcoming one-offs, plus any recurring series (which are ongoing).
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
      -- Recurring: the organiser's explicit ISO weekday (timezone-safe).
      or (e.recurrence_byday is not null and e.recurrence_byday @> array[p_byday])
      -- One-off: weekday derived from starts_at (UTC; approximate near midnight).
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
  order by e.starts_at asc nulls last, e.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

grant execute on function search_public_events(
  text, text, text, text, text, int
) to authenticated, anon;
