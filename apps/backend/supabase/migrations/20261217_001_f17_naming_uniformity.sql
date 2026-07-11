-- F17 naming uniformity (remediation plan 2d). Rename the owner-column +
-- boolean-flag outliers onto the house convention documented in
-- conventions.md § Column naming:
--   * created_by  -> author_id  (events, segments: user-created objects,
--     aligning with club_posts / run_comments / reports)
--   * <flag>      -> is_<flag>  (device_tokens.notifications_enabled,
--     routes.featured, race_sessions.auto_approve)
--
-- This renames cleanly end-to-end: base columns AND the view / RPC OUTPUT
-- columns that surface them, so there is no column-vs-output mismatch.
-- RLS policies, CHECK constraints, column-level GRANTs and indexes
-- reference columns by attnum and follow a RENAME COLUMN automatically.
-- View bodies also follow the base rename automatically; ALTER VIEW
-- RENAME COLUMN then moves the OUTPUT label without dropping the view, so
-- every grant the view carries is preserved. Only function BODIES (stored
-- as text) and a RETURNS TABLE output column need explicit reworking.

-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

alter table events        rename column created_by            to author_id;
alter table segments      rename column created_by            to author_id;
alter table device_tokens rename column notifications_enabled to is_notifications_enabled;
alter table routes        rename column featured              to is_featured;
alter table race_sessions rename column auto_approve          to is_auto_approve;

-- View output labels. ALTER VIEW RENAME COLUMN keeps the view (and all its
-- grants + the redaction logic in its body) intact; it only renames the
-- exposed column. The body's reference to the base column already followed
-- the table rename above.
alter view public_routes          rename column featured     to is_featured;
alter view race_sessions_redacted rename column auto_approve to is_auto_approve;

-- events.author_id inside the RSVP-notification trigger (body is text).
create or replace function public.notify_event_rsvp()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_club uuid;
  v_creator uuid;
begin
  if NEW.status is distinct from 'going' then
    return NEW;
  end if;

  if TG_OP = 'UPDATE' and OLD.status = 'going' then
    return NEW;
  end if;

  select club_id, author_id into v_club, v_creator
  from events where id = NEW.event_id;
  if v_club is null then
    return NEW;
  end if;

  insert into notifications (user_id, actor_id, kind, event_id)
  select recipient, NEW.user_id, 'event_rsvp', NEW.event_id
  from (
    select v_creator as recipient
    union
    select cm.user_id
    from club_members cm
    where cm.club_id = v_club
      and cm.status = 'active'
      and cm.role in ('event_organiser', 'race_director')
  ) recipients
  where recipient is not null
    and recipient <> NEW.user_id
  on conflict do nothing;

  return NEW;
end;
$function$;

-- race_sessions.is_auto_approve in the result-approval default.
create or replace function public.event_results_set_approval_default()
 returns trigger
 language plpgsql
as $function$
declare
  v_auto boolean;
begin
  -- Only fire on insert; updates shouldn't silently flip approval.
  if (tg_op <> 'INSERT') then
    return new;
  end if;
  select is_auto_approve into v_auto
  from race_sessions
  where event_id = new.event_id and instance_start = new.instance_start;
  if v_auto is not null and v_auto = false then
    new.organiser_approved := false;
    new.organiser_approved_by := null;
    new.organiser_approved_at := null;
  else
    new.organiser_approved := true;
    new.organiser_approved_by := new.user_id;  -- self-approved implicit
    new.organiser_approved_at := now();
  end if;
  return new;
end;
$function$;

-- search_public_routes reads the renamed view column (pr.is_featured).
create or replace function public.search_public_routes(p_query text default null::text, p_min_distance_m numeric default null::numeric, p_max_distance_m numeric default null::numeric, p_surface text default null::text, p_tags text[] default null::text[], p_featured_only boolean default false, p_sort text default 'newest'::text, p_limit integer default 50, p_offset integer default 0)
 returns setof public_routes
 language sql
 stable security definer
 set search_path to 'public', 'extensions'
as $function$
  select pr.*
  from public_routes pr
  where (p_query is null or pr.name ilike '%' || p_query || '%')
    and (p_min_distance_m is null or pr.distance_m >= p_min_distance_m)
    and (p_max_distance_m is null or pr.distance_m <= p_max_distance_m)
    and (p_surface is null or pr.surface = p_surface)
    and (p_tags is null or p_tags = '{}' or pr.tags && p_tags)
    and (p_featured_only = false or pr.is_featured = true)
  order by
    case when p_sort = 'popular' then pr.run_count end desc nulls last,
    case when p_sort = 'featured' then pr.featured_at end desc nulls last,
    case when p_sort = 'newest' then pr.created_at end desc nulls last,
    pr.created_at desc
  limit p_limit offset p_offset;
$function$;

-- discoverable_routes_in_bbox exposes the flag as a RETURNS TABLE column,
-- which can't be renamed in place — drop + recreate, then restore grants.
drop function if exists public.discoverable_routes_in_bbox(double precision, double precision, double precision, double precision, integer, text, numeric[], numeric[]);
create function public.discoverable_routes_in_bbox(p_min_lng double precision, p_min_lat double precision, p_max_lng double precision, p_max_lat double precision, p_limit integer default 100, p_filter text default 'popular'::text, p_dist_min numeric[] default null::numeric[], p_dist_max numeric[] default null::numeric[])
 returns table(id uuid, name text, slug text, is_featured boolean, distance_m numeric, elevation_m numeric, surface text, run_count integer, lng double precision, lat double precision)
 language sql
 stable parallel safe security definer
 set search_path to 'public', 'extensions'
as $function$
  with bbox as (
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)::geography as g
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
    and r.start_point is not null
    and r.start_point && bbox.g
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
$function$;
grant execute on function public.discoverable_routes_in_bbox(double precision, double precision, double precision, double precision, integer, text, numeric[], numeric[]) to anon, authenticated, service_role;
