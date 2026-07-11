-- Public-routes read path with column- and metadata-key-level
-- redaction. Closes the audit/public-rows + audit/rls + audit/privacy-zones
-- High findings from /audit/all on 2026-05-03:
--
--   * The bare-table SELECT policy `"public routes are readable by
--     anyone"` (added in 20260405_001_initial_schema.sql) returns the
--     **full row** for every public route — including unclipped
--     `waypoints` (jsonb), `geom` (geography LineString), and
--     `start_point` (geography Point). For any public route whose
--     start sits at the runner's home, anon callers can recover the
--     home coordinate by `select start_point from routes where
--     is_public = true`.
--   * The `search_public_routes` and `nearby_routes` and
--     `routes_within_box` RPCs all `returns setof routes` and are
--     granted to anon — same shape, same wire-leak, additionally
--     reachable to anyone within radius / viewport.
--   * `routes.club_id` exposed on a public route reveals the link
--     to a private club (existence-leak), even though `clubs` RLS
--     hides the club itself.
--
-- The fix mirrors the runs side (20260626_001_public_runs_view.sql +
-- 20260701_001_drop_runs_public_select_policy.sql):
--
--   1. Add a `public_routes` view that strips the spatial columns
--      (`waypoints`, `geom`, `start_point`) and conditionally nulls
--      `club_id` when the linked club isn't public. Non-owner /
--      anon polyline reads must go through `clip_route_for_viewer`
--      (added in 20260625_001) — there is no other path.
--   2. Drop the bare-table public SELECT policy. Owners and club
--      members keep their existing full-row policies (per the
--      "users own their routes" + "club members read club routes"
--      policies on routes).
--   3. Refactor `search_public_routes`, `nearby_routes`, and
--      `routes_within_box` to return `setof public_routes` and
--      run as `security definer` so they can read the underlying
--      table after the public-anyone SELECT is gone.
--
-- The `is_starred` column is also dropped from the public view —
-- it's per-owner watch-curation state and shouldn't surface on
-- non-owner reads. Owners reading their own routes through the
-- base table still see it.
--
-- The view is NOT `security_invoker`. Default postgres views run
-- with the OWNER's permissions, which is what we want here: the
-- view is the *only* path that serves these rows publicly, and it
-- pre-applies the redaction. If we set `security_invoker = true`,
-- the underlying routes RLS would re-apply on top, defeating the
-- "tighter than the base table" intent.

-- ─────────────────────── 1. Helper: is_public_club_by_id ───────────────────────

-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

create or replace function is_public_club_by_id(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select is_public from clubs where id = p_club_id),
    false
  );
$$;

grant execute on function is_public_club_by_id(uuid) to anon, authenticated;

-- ─────────────────────── 2. The public_routes view ───────────────────────

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
  r.featured,
  r.featured_at,
  r.run_count,
  -- Existence-leak guard: null the club link when the club isn't public.
  case when is_public_club_by_id(r.club_id) then r.club_id else null end as club_id
from routes r
where r.is_public = true;

grant select on public_routes to anon, authenticated;

-- ─────────────────────── 3. Refactor the three public RPCs ───────────────────────

drop function if exists search_public_routes(text, numeric, numeric, text, text[], boolean, text, int, int);
create or replace function search_public_routes(
  p_query text default null,
  p_min_distance_m numeric default null,
  p_max_distance_m numeric default null,
  p_surface text default null,
  p_tags text[] default null,
  p_featured_only boolean default false,
  p_sort text default 'newest',
  p_limit int default 50,
  p_offset int default 0
) returns setof public_routes language sql stable security definer
set search_path = public, extensions as $$
  select pr.*
  from public_routes pr
  where (p_query is null or pr.name ilike '%' || p_query || '%')
    and (p_min_distance_m is null or pr.distance_m >= p_min_distance_m)
    and (p_max_distance_m is null or pr.distance_m <= p_max_distance_m)
    and (p_surface is null or pr.surface = p_surface)
    and (p_tags is null or p_tags = '{}' or pr.tags && p_tags)
    and (p_featured_only = false or pr.featured = true)
  order by
    case when p_sort = 'popular' then pr.run_count end desc nulls last,
    case when p_sort = 'featured' then pr.featured_at end desc nulls last,
    case when p_sort = 'newest' then pr.created_at end desc nulls last,
    pr.created_at desc
  limit p_limit offset p_offset;
$$;

grant execute on function search_public_routes(
  text, numeric, numeric, text, text[], boolean, text, int, int
) to authenticated, anon;

drop function if exists nearby_routes(double precision, double precision, double precision, integer);
create or replace function nearby_routes(
  lat double precision,
  lng double precision,
  radius_m double precision default 50000,
  max_results integer default 50
)
returns setof public_routes
language sql stable security definer
-- PostGIS lives under `extensions` in Supabase; explicit search_path
-- gives a security-hygiene boundary on a SECURITY DEFINER function.
set search_path = public, extensions
as $$
  -- Reads `routes.start_point` directly to drive the spatial filter
  -- (the public_routes view doesn't expose it), but only emits the
  -- redacted row shape via `public_routes` — non-owner callers can
  -- still discover routes near them, but the response carries no
  -- coordinates.
  select pr.*
  from public_routes pr
  join routes r on r.id = pr.id
  where r.start_point is not null
    and ST_DWithin(
      r.start_point,
      ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
      radius_m
    )
  order by r.start_point <-> ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
  limit max_results;
$$;

grant execute on function nearby_routes(
  double precision, double precision, double precision, integer
) to authenticated, anon;

drop function if exists routes_within_box(double precision, double precision, double precision, double precision, integer);
create or replace function routes_within_box(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision,
  max_results integer default 50
)
returns setof public_routes
language sql stable security definer
-- PostGIS lives under `extensions` in Supabase; explicit search_path
-- gives a security-hygiene boundary on a SECURITY DEFINER function.
set search_path = public, extensions
as $$
  with box as (
    select ST_SetSRID(
      ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat),
      4326
    )::geography as g
  ),
  centre as (
    select ST_SetSRID(
      ST_MakePoint(
        (min_lng + max_lng) / 2,
        (min_lat + max_lat) / 2
      ),
      4326
    )::geography as g
  )
  select pr.*
  from public_routes pr
  join routes r on r.id = pr.id, box, centre
  where r.geom is not null
    and ST_Intersects(r.geom, box.g)
  order by r.geom <-> centre.g
  limit max_results;
$$;

grant execute on function routes_within_box(
  double precision, double precision, double precision, double precision, integer
) to authenticated, anon;

-- ─────────────────────── 4. Update dependent policies ───────────────────────
--
-- Several policies on sibling tables relied on the bare-table
-- public-anyone SELECT to express "the caller can see the parent
-- route" via `exists (select 1 from routes where ...)`. Once that
-- policy is gone, the subquery returns nothing for non-owner /
-- non-club-member callers — which would silently strip review
-- visibility and segment visibility on public routes.
--
-- The fix is to route through the SECURITY DEFINER helper
-- `is_route_visible_to(route_id, user_id)` (added in
-- 20260628_001_route_run_count_visibility_gate.sql) which mirrors
-- the SELECT predicate (owner OR public OR active member of the
-- route's club) and bypasses the bare-table RLS internally.

-- route_reviews: SELECT + INSERT policies that used the bare-table
-- subquery.
drop policy if exists "reviews on public routes are readable by anyone" on route_reviews;
create policy "reviews on visible routes are readable"
  on route_reviews for select
  using (is_route_visible_to(route_reviews.route_id, auth.uid()));

drop policy if exists "users insert reviews on visible routes" on route_reviews;
create policy "users insert reviews on visible routes"
  on route_reviews for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and is_route_visible_to(route_reviews.route_id, auth.uid())
  );

-- segments: SELECT + INSERT policies that used the bare-table
-- subquery. UPDATE / DELETE policies (segment author or route
-- owner) check `routes.user_id = auth.uid()` directly, which keeps
-- working through the unchanged "users own their routes" SELECT
-- policy, so they don't need touching.
drop policy if exists "segments readable when route is readable" on segments;
create policy "segments readable when route is readable"
  on segments for select
  using (is_route_visible_to(segments.route_id, auth.uid()));

drop policy if exists "segment authors create on readable routes" on segments;
create policy "segment authors create on readable routes"
  on segments for insert
  with check (
    auth.uid() = created_by
    and is_route_visible_to(segments.route_id, auth.uid())
  );

-- popular_route_tags: function body read `from routes where is_public
-- = true` under SECURITY INVOKER, which loses access to public rows
-- after the policy drop. Switch to `from public_routes` so the view's
-- definer-mode SELECT does the heavy lifting; the view already filters
-- on is_public = true so the per-row predicate is no longer needed.
create or replace function popular_route_tags(tag_limit int default 20)
returns table (tag text, route_count bigint)
language sql
stable
security invoker
set search_path = public
as $$
  select unnest(tags) as tag, count(*) as route_count
  from public_routes
  group by tag
  order by route_count desc, tag asc
  limit tag_limit;
$$;

-- ─────────────────────── 5. Drop the wire-leak SELECT policy ───────────────────────
--
-- Non-owner / anon callers reach public routes only via the view + the
-- three RPCs above (all of which return the redacted shape) and via
-- `clip_route_for_viewer` for the polyline. The bare-table public-anyone
-- SELECT is no longer needed.
drop policy if exists "public routes are readable by anyone" on routes;
