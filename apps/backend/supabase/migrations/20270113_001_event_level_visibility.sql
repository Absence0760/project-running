-- Event-level visibility: a PUBLIC club can mark an individual event
-- members-only.
--
-- Until now event visibility was inherited entirely from the parent club
-- (20260416_001): an event was readable iff its club was readable
-- (is_public OR owner OR member). So every event in a public club was
-- world-readable — and, since 20270110_001, globally discoverable — with no
-- way to run a members-only committee meeting / private members' social /
-- draft event inside an otherwise-public club. (A PRIVATE club's events were
-- already members-only, and stay so; this only changes the public-club case.)
--
-- Adds events.is_public (default true → preserves today's behaviour) and
-- threads it through the ONE events SELECT policy, which is the single source
-- of truth. Every other event-delegating surface — event_attendees (read +
-- self-RSVP insert), event_results, race_pings, run_photos (table + storage
-- bytes), event_photo_gallery — gates visibility via an `exists (… from
-- events …)` subquery, so the calling role's RLS on `events` is applied
-- inside that subquery and they ALL inherit this tightening automatically.
-- The lone exception is an event-tied club_posts row, whose SELECT policy
-- checks the CLUB only (a post need not belong to an event); that one is
-- re-gated here too.
--
-- meet_lat/meet_lng stay members-only via get_event_meet_point (unchanged —
-- already gated on is_club_member, which is exactly the right gate for a
-- private event). search_public_events gets an explicit is_public filter
-- (defence-in-depth: it is `security invoker`, so anon RLS already hides a
-- private event, but the explicit filter also keeps a *member's* own private
-- events out of global discovery, which is the correct discovery semantic).

-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

alter table events add column is_public boolean not null default true;

comment on column events.is_public is
  'When false, the event is members-only: readable only by members/admins/owner '
  'of its club (via the events SELECT policy + the exists(...from events...) '
  'subqueries every delegating surface uses) and excluded from '
  'search_public_events discovery. Default true preserves the pre-20270113_001 '
  'club-inherited behaviour. For a PRIVATE club the club gate already forces '
  'membership, so this only changes behaviour for an individual private event '
  'inside a PUBLIC club.';

-- events is column-SELECT-locked (20260818_001): a new column is deny-by-default
-- for anon/authenticated. Grant it so clients can render the visibility toggle +
-- "members only" badge, AND so the security-invoker discovery RPC can filter on
-- it (a function body under SECURITY INVOKER is subject to the caller's
-- column-level grants; an RLS policy expression is not). Non-sensitive — whether
-- an event is members-only is fine to expose, and a private event's row is
-- unreadable to a non-member anyway.
grant select (is_public) on events to authenticated, anon;

-- Tighten the single source of truth: the events SELECT policy. The club gate
-- is unchanged; the event-level gate is added. is_club_member covers owner +
-- admins + members uniformly (the owner is enrolled as an 'owner' club_members
-- row by enroll_club_owner), so a private event stays visible to everyone who
-- runs the club and to its members, and is hidden from non-member / anon
-- viewers of an otherwise-public club.
drop policy "events readable with their club" on events;

create policy "events readable with their club"
  on events for select using (
    exists (
      select 1 from clubs
      where clubs.id = events.club_id
        and (clubs.is_public = true or clubs.owner_id = auth.uid() or private.is_club_member(clubs.id))
    )
    and (
      events.is_public = true
      or private.is_club_member(events.club_id)
    )
  );

-- club_posts is the one delegating surface whose SELECT policy checks the CLUB
-- only, so an event-tied post on a private event would otherwise leak to any
-- viewer of the (public) club. Re-gate: a post tied to an event is visible only
-- when that event is (the `exists (… from events …)` inherits the events RLS
-- above); a club-level post (event_id is null) stays club-gated as before.
drop policy "posts readable with their club" on club_posts;

create policy "posts readable with their club"
  on club_posts for select using (
    exists (
      select 1 from clubs
      where clubs.id = club_posts.club_id
        and (clubs.is_public = true or clubs.owner_id = auth.uid() or private.is_club_member(clubs.id))
    )
    and (
      club_posts.event_id is null
      or exists (select 1 from events e where e.id = club_posts.event_id)
    )
  );

-- event_pricing's SELECT policy gates on is_event_visible (20261229_001) — a
-- SECURITY DEFINER helper that, because it bypasses the caller's RLS, does NOT
-- inherit the events tightening above (unlike the exists(...from events...)
-- surfaces). With only the club-level gate it would still leak a members-only
-- event's pricing (price_cents / currency / modality) to a non-member who has
-- the event UUID. Recreate it (COMPLETE body per the bare-body rule) so it
-- mirrors the events SELECT policy's event-level gate: members-only-event
-- pricing stays readable to members (so they can register) and hidden from
-- non-members. is_event_visible is used only by the event_pricing SELECT policy.
create or replace function is_event_visible(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select exists (
    select 1 from events e
    join clubs c on c.id = e.club_id
    where e.id = p_event_id
      and (c.is_public = true or c.owner_id = auth.uid() or is_club_member(c.id))
      and (e.is_public = true or is_club_member(c.id))
  );
$$;

revoke all on function is_event_visible(uuid) from public;
grant execute on function is_event_visible(uuid) to authenticated, anon;

-- Discovery: exclude members-only events. Recreated with the COMPLETE body of
-- 20270112_001 (per the bare-body rule) plus `and e.is_public = true`. Signature
-- unchanged, so no drop; existing grants are preserved by create-or-replace.
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
