-- Auto-hide after N reports from vetted reporters (anti-spam backlog E1 + E3).
--
-- Decisions settled (roadmap.md § Anti-spam / moderation — Deferred):
--   * N = 3 DISTINCT vetted reporters with PENDING reports on one target
--     trigger an auto-hide.
--   * A reporter counts only if they have M >= 5 PUBLIC runs (the
--     reputation weighting, E3) — a drive-by puppet account with no
--     history doesn't move the needle.
--   * Auto-hide flips a `shadow_hidden boolean` on the target
--     (clubs / routes / user_profiles). Shadow-hidden targets drop out of
--     every PUBLIC / SEARCH / DISCOVERY surface, but the owner + admins
--     still see their own row (it's a soft-hide pending review, not a
--     deletion).
--   * The owner IS notified ("hidden pending review") via a new
--     `content_hidden` notification kind.
--   * Admins revert from /admin/reports via admin_unhide_target().
--
-- CISO review was RECOMMENDED for this moderation surface; the owner chose
-- to proceed without it. Recorded in the build PR + decisions.md.
--
-- Only the three shadow-hideable kinds (user / club / route) participate.
-- A report against a comment / club_post / run does NOT auto-hide anything
-- (those have no shadow_hidden column and v1 takedown stays a manual admin
-- step) — the trigger early-returns for them.

-- ─── 1. shadow_hidden columns ─────────────────────────────────────
-- NOT NULL DEFAULT false keeps generated Insert types optional and means
-- existing rows are visible until the trigger / an admin flips them.
-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

alter table clubs         add column shadow_hidden boolean not null default false;
alter table routes        add column shadow_hidden boolean not null default false;
alter table user_profiles add column shadow_hidden boolean not null default false;

-- ─── 2. notifications.kind: add 'content_hidden' ──────────────────
-- Re-emit the full union (the "create or replace strips prior fixes" rule
-- applies to CHECK rebuilds too — 20270211_001 is the live list).
alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder', 'plan_assigned',
      'achievement', 'challenge_complete', 'content_hidden'
    )
  );

-- ─── 3. auto_hide_target(): the counting rule ─────────────────────
-- SECURITY DEFINER so it can read across users' runs (the reputation
-- gate reads other reporters' public-run counts, which base-table RLS
-- blocks) and flip a target it doesn't own. Invoked by the AFTER INSERT
-- trigger on reports. Idempotent: a target already shadow_hidden is left
-- alone (no duplicate notification).
--
-- "Vetted reporter" = a reporter whose count of is_public runs >= 5,
-- the SAME is_public gate public_run_counts() uses (20270118_001).
create or replace function auto_hide_target(
  p_target_kind text,
  p_target_id   uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vetted_count int;
  v_already_hidden boolean;
  v_owner uuid;
begin
  -- Only user / club / route can be shadow-hidden. Anything else is a
  -- no-op (comment / club_post / run have no shadow_hidden column).
  if p_target_kind not in ('user', 'club', 'route') then
    return;
  end if;

  -- Count DISTINCT vetted reporters with a PENDING report on this target.
  -- A reporter is vetted iff they have >= 5 public runs. The distinct is
  -- redundant with reports_no_duplicate_pending (one pending row per
  -- reporter/target) but kept explicit so the counting rule is legible.
  select count(distinct r.reporter_id)
    into v_vetted_count
  from reports r
  where r.target_kind = p_target_kind
    and r.target_id = p_target_id
    and r.status = 'pending'
    and (
      select count(*) from runs run
      where run.user_id = r.reporter_id
        and run.is_public = true
    ) >= 5;

  if v_vetted_count < 3 then
    return;
  end if;

  -- Flip the target's shadow_hidden, but only on the transition
  -- false -> true so the owner is notified exactly once.
  if p_target_kind = 'user' then
    update user_profiles set shadow_hidden = true
      where id = p_target_id and shadow_hidden = false
      returning id into v_owner;
  elsif p_target_kind = 'club' then
    update clubs set shadow_hidden = true
      where id = p_target_id and shadow_hidden = false
      returning owner_id into v_owner;
  elsif p_target_kind = 'route' then
    update routes set shadow_hidden = true
      where id = p_target_id and shadow_hidden = false
      returning user_id into v_owner;
  end if;

  -- No row returned => already hidden (or vanished) => nothing to notify.
  if v_owner is null then
    return;
  end if;

  -- Notify the owner: hidden pending review. actor_id null (system).
  insert into notifications (user_id, actor_id, kind)
  values (v_owner, null, 'content_hidden');
end;
$$;

revoke all on function auto_hide_target(text, uuid) from public;
-- No grant to anon / authenticated: the only legitimate caller is the
-- AFTER INSERT trigger (which runs as the table owner). A user cannot
-- invoke it directly to hide a rival.

-- ─── 4. Trigger on reports insert ─────────────────────────────────
create or replace function reports_auto_hide_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform auto_hide_target(NEW.target_kind, NEW.target_id);
  return NEW;
end;
$$;

create trigger reports_auto_hide
  after insert on reports
  for each row
  execute function reports_auto_hide_trigger();

-- ─── 5. admin_unhide_target(): the revert action ──────────────────
-- Admin-gated via private.is_admin (mirrors resolve_target_reports).
-- Clears shadow_hidden on the target; returns true if a row flipped.
create or replace function admin_unhide_target(
  p_target_kind text,
  p_target_id   uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_rows integer;
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'admin_unhide_target: not authorized'
      using errcode = '42501';
  end if;

  if p_target_kind not in ('user', 'club', 'route') then
    raise exception 'admin_unhide_target: invalid target_kind %', p_target_kind
      using errcode = '22023';
  end if;

  if p_target_kind = 'user' then
    update user_profiles set shadow_hidden = false
      where id = p_target_id and shadow_hidden = true;
  elsif p_target_kind = 'club' then
    update clubs set shadow_hidden = false
      where id = p_target_id and shadow_hidden = true;
  elsif p_target_kind = 'route' then
    update routes set shadow_hidden = false
      where id = p_target_id and shadow_hidden = true;
  end if;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

revoke all on function admin_unhide_target(text, uuid) from public;
grant execute on function admin_unhide_target(text, uuid) to authenticated;

-- ─── 6. Surface the hidden state to the admin queue ───────────────
-- fetch_pending_reports gains a `shadow_hidden boolean` column so the
-- /admin/reports queue can badge a hidden target + offer Unhide. Full
-- body re-emitted (the bare-body rule) — 20270105_001 is the live body,
-- with the shadow_hidden lookup added per target kind. The return type
-- grows a column, so the old signature must be dropped first (create or
-- replace cannot change a function's return type).
drop function if exists fetch_pending_reports();
create or replace function fetch_pending_reports()
returns table (
  target_kind     text,
  target_id       uuid,
  report_count    bigint,
  reporter_count  bigint,
  reasons         jsonb,
  latest_at       timestamptz,
  shadow_hidden   boolean
)
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'fetch_pending_reports: not authorized'
      using errcode = '42501';
  end if;

  return query
    with pending as (
      select r.target_kind as tk, r.target_id as tid,
             r.reporter_id as rid, r.reason as rsn, r.created_at as cat
      from reports r
      where r.status = 'pending'
    ),
    by_reason as (
      select g.tk, g.tid, jsonb_object_agg(g.rsn, g.n) as reasons
      from (
        select p.tk, p.tid, p.rsn, count(*) as n
        from pending p
        group by p.tk, p.tid, p.rsn
      ) g
      group by g.tk, g.tid
    )
    select
      p.tk,
      p.tid,
      count(*)                      as report_count,
      count(distinct p.rid)         as reporter_count,
      br.reasons,
      max(p.cat)                    as latest_at,
      coalesce(
        case p.tk
          when 'user'  then (select up.shadow_hidden from user_profiles up where up.id = p.tid)
          when 'club'  then (select c.shadow_hidden  from clubs c          where c.id = p.tid)
          when 'route' then (select rt.shadow_hidden from routes rt        where rt.id = p.tid)
          else false
        end,
        false
      )                             as shadow_hidden
    from pending p
    join by_reason br on br.tk = p.tk and br.tid = p.tid
    group by p.tk, p.tid, br.reasons
    order by max(p.cat) desc;
end;
$$;

revoke execute on function fetch_pending_reports() from public;
grant execute on function fetch_pending_reports() to authenticated;

-- ─── 7. Exclude shadow-hidden targets from public surfaces ────────
-- Each public/search/discovery read path gains `and not <t>.shadow_hidden`.
-- Owner + admin reads go through OTHER paths (owner RLS on the base table,
-- admin RPCs) which are untouched, so a hidden owner still sees their row.

-- 7a. public_routes view — single cascade point for search_public_routes /
-- nearby_routes / routes_within_box. Re-emitted with the CURRENT (post-F17)
-- column set: `featured` was renamed to `is_featured` in 20261217_001 via
-- `alter view ... rename column`, so the live output column is is_featured.
-- create or replace view cannot rename/reorder columns, so the projection
-- must keep the exact live order/names; only the WHERE clause changes.
create or replace view public_routes as
select
  r.id,
  r.user_id,
  r.name,
  r.distance_m,
  r.elevation_m,
  r.surface,
  r.is_public,
  r.slug,
  r.created_at,
  r.updated_at,
  r.tags,
  r.is_featured,
  r.featured_at,
  r.run_count,
  case when is_public_club_by_id(r.club_id) then r.club_id else null end as club_id
from routes r
where r.is_public = true
  and r.shadow_hidden = false;

-- 7b. discoverable_routes_in_bbox — heatmap pins; reads routes directly
-- (not via the view). Full body re-emitted (20270128_001 is the live one,
-- with the GEOMETRY bbox fix + is_featured F17 rename) + the shadow filter.
create or replace function discoverable_routes_in_bbox(
  p_min_lng double precision,
  p_min_lat double precision,
  p_max_lng double precision,
  p_max_lat double precision,
  p_limit int default 100,
  p_filter text default 'popular',
  p_dist_min numeric[] default null,
  p_dist_max numeric[] default null
)
returns table (
  id uuid,
  name text,
  slug text,
  is_featured boolean,
  distance_m numeric,
  elevation_m numeric,
  surface text,
  run_count int,
  lng double precision,
  lat double precision
)
language sql
stable
parallel safe
security definer
set search_path = public, extensions
as $$
  with bbox as (
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326) as g
  )
  select
    r.id,
    r.name,
    r.slug,
    r.is_featured,
    r.distance_m,
    r.elevation_m,
    r.surface,
    r.run_count,
    ST_X(r.start_point::geometry) as lng,
    ST_Y(r.start_point::geometry) as lat
  from routes r, bbox
  where r.is_public = true
    and r.shadow_hidden = false
    and r.start_point is not null
    and r.start_point::geometry && bbox.g
    and case p_filter
      when 'featured' then r.is_featured = true
      when 'friends' then r.user_id in (
        select uf.followee_id from user_follows uf where uf.follower_id = auth.uid()
      )
      when 'hidden_gems' then
        r.is_featured = false and coalesce(r.run_count, 0) = 0 and r.distance_m >= 1000
      else
        (r.is_featured = true or r.run_count > 0)
    end
    and (
      p_dist_min is null
      or cardinality(p_dist_min) = 0
      or exists (
        select 1
        from unnest(p_dist_min, p_dist_max) as band(lo, hi)
        where r.distance_m >= band.lo
          and (band.hi is null or r.distance_m < band.hi)
      )
    )
  order by r.is_featured desc, r.run_count desc, r.created_at desc
  limit p_limit;
$$;

-- 7c. search_clubs — `returns setof clubs`, security INVOKER. Adding the
-- column to clubs already widens the rowtype; the explicit projection must
-- gain the new column (in clubs column order — shadow_hidden is the last
-- column, position 21) AND the filter. Full body re-emitted (20270202_001
-- is the live one). The invoker mode needs a column-level select grant so
-- a caller can read shadow_hidden through the rowtype (precedent:
-- is_verified / member_count grants).
grant select (shadow_hidden) on clubs to authenticated, anon;

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
  select
    c.id,
    c.owner_id,
    c.name,
    c.slug,
    c.description,
    c.avatar_url,
    c.location_label,
    c.is_public,
    c.created_at,
    c.updated_at,
    c.join_policy,
    null::text,
    c.location_point,
    c.member_count,
    c.is_verified,
    c.requires_activity_waiver,
    c.website_url,
    c.instagram_url,
    c.strava_url,
    c.facebook_url,
    c.shadow_hidden
  from clubs c, center
  where c.is_public = true
    and c.shadow_hidden = false
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
    case when center.pt is not null and c.location_point is not null
      then ST_Distance(c.location_point, center.pt)
      else null
    end asc nulls last,
    c.member_count desc,
    c.created_at desc
  limit p_limit;
$$;

grant execute on function search_clubs(
  text, double precision, double precision, double precision, int
) to authenticated, anon;

-- 7d. clubs_in_bbox — club heatmap pins; reads clubs directly. Full body
-- re-emitted (20270128_001 is the live one) + the shadow filter.
create or replace function clubs_in_bbox(
  p_min_lng double precision,
  p_min_lat double precision,
  p_max_lng double precision,
  p_max_lat double precision,
  p_limit int default 100
)
returns table (
  id uuid,
  name text,
  slug text,
  avatar_url text,
  location_label text,
  member_count int,
  lng double precision,
  lat double precision
)
language sql
stable
parallel safe
security definer
set search_path = public, extensions
as $$
  with bbox as (
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326) as g
  )
  select
    c.id,
    c.name,
    c.slug,
    c.avatar_url,
    c.location_label,
    c.member_count,
    ST_X(c.location_point::geometry) as lng,
    ST_Y(c.location_point::geometry) as lat
  from clubs c, bbox
  where c.is_public = true
    and c.shadow_hidden = false
    and c.location_point is not null
    and c.location_point::geometry && bbox.g
  order by c.member_count desc, c.created_at desc
  limit p_limit;
$$;

-- 7e. public_profile_by_id — the only public profile lookup path. Full
-- body re-emitted (20261011_001 is the live one) + the shadow filter.
create or replace function public_profile_by_id(p_id uuid)
returns table (
  id uuid,
  display_name text,
  avatar_url text
)
language sql
security definer
set search_path = public
stable
as $$
  select id, display_name, avatar_url
  from user_profiles
  where id = p_id
    and shadow_hidden = false;
$$;

revoke all on function public_profile_by_id(uuid) from public;
grant execute on function public_profile_by_id(uuid) to anon, authenticated;

-- 7f. search_user_profiles — People-tab search. Full body re-emitted from
-- the LIVE definition 20261104_001 (canonical-column minor floor + the
-- prefs-bag fallback + the anon revoke) + the shadow filter. The earlier
-- 20261017_001 checked only the prefs bag; 20261104_001 added the canonical
-- user_profiles.date_of_birth arm — re-emitting that whole body keeps the
-- child-safety floor intact (the bare-body strip trap).
create or replace function search_user_profiles(
  p_query text,
  p_limit int default 60
)
returns table (
  id uuid,
  display_name text,
  avatar_url text
)
language sql
security definer
set search_path = public
stable
as $$
  with capped as (
    select least(greatest(coalesce(p_limit, 60), 1), 200) as v
  )
  select
    u.id,
    u.display_name,
    u.avatar_url
  from user_profiles u
  left join user_settings s on s.user_id = u.id
  where u.display_name ilike '%' || p_query || '%'
    and u.shadow_hidden = false
    and coalesce(s.prefs->>'discoverable_in_search', 'true') <> 'false'
    and not (
      (u.date_of_birth is not null
        and u.date_of_birth > (current_date - interval '18 years'))
      or coalesce(
        s.prefs ? 'date_of_birth'
        and (s.prefs->>'date_of_birth') ~ '^\d{4}-\d{2}-\d{2}$'
        and (s.prefs->>'date_of_birth')::date > (current_date - interval '18 years'),
        false
      )
    )
  order by u.display_name
  limit (select v from capped);
$$;

revoke all on function search_user_profiles(text, int) from public;
revoke execute on function search_user_profiles(text, int) from anon;
grant execute on function search_user_profiles(text, int) to authenticated;
