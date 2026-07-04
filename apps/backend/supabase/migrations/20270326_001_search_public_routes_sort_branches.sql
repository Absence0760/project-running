-- db-performance High: search_public_routes ordered every call through three
-- CASE-wrapped ORDER BY arms (popular -> run_count, featured -> featured_at,
-- newest -> created_at, plus a trailing created_at tie-break). A CASE
-- expression is not a plain column reference, so no b-tree leaf order can
-- ever serve it — every Explore/route-search call materialized and fully
-- sorted the whole public-routes candidate set before limit/offset, with cost
-- growing in both the public-route count and the paging depth.
--
-- Fix: re-emit the function (live body: 20261217_001, reading the post-F17
-- pr.is_featured column; the underlying public_routes view is 20270218_001's,
-- which added the shadow_hidden filter) as plpgsql with one CASE-free branch
-- per sort mode, each with a genuine column ORDER BY the planner can match to
-- an index, plus the matching partial indexes below. Ordering semantics are
-- preserved exactly, including the nulls placement the old arms produced:
--
--   popular  -> run_count   desc nulls last, created_at desc
--   featured -> featured_at desc nulls last, created_at desc
--   newest   -> created_at  desc nulls last
--   (other)  -> created_at  desc            -- the old trailing arm alone
--
-- created_at is nullable (default now(), no NOT NULL), so "newest" (nulls
-- last, from the CASE arm) and the unknown-sort fallback (bare desc = nulls
-- first, from the trailing arm) genuinely differ and both are kept.
--
-- Filter expressions, signature, return shape, and row visibility are
-- untouched — every branch still reads public_routes (is_public = true and
-- shadow_hidden = false, club_id existence-leak guard in the view). CREATE OR
-- REPLACE on the identical signature preserves the anon/authenticated EXECUTE
-- grants.

-- ─────────────────── 1. Per-branch partial indexes ───────────────────
-- All partial on the view's predicate so they index only the publicly
-- browsable rows. The existing routes_featured (featured_at desc nulls last
-- WHERE is_featured AND is_public) cannot serve the featured branch: that
-- branch sorts ALL public routes with non-featured ones trailing, not just
-- the featured subset. The existing routes_public (is_public, created_at
-- desc) is nulls-FIRST, so it serves the unknown-sort fallback but not the
-- nulls-last "newest" branch.
--
-- Lock trade-off: plain (non-CONCURRENT) builds — CREATE INDEX CONCURRENTLY
-- cannot run through the Supabase CLI migration path (transaction/pipeline
-- wrap, SQLSTATE 25001). For a zero-downtime prod build, run the equivalent
-- CREATE INDEX CONCURRENTLY manually in a maintenance window and
-- `supabase migration repair` this version as applied — same procedure as
-- 20270312_001 / 20270316_001.

create index if not exists routes_public_popular_sort
  on routes (run_count desc nulls last, created_at desc)
  where is_public = true and shadow_hidden = false;

create index if not exists routes_public_featured_sort
  on routes (featured_at desc nulls last, created_at desc)
  where is_public = true and shadow_hidden = false;

create index if not exists routes_public_newest_sort
  on routes (created_at desc nulls last)
  where is_public = true and shadow_hidden = false;

-- ─────────────────── 2. Branch-per-sort function body ───────────────────

create or replace function public.search_public_routes(
  p_query text default null,
  p_min_distance_m numeric default null,
  p_max_distance_m numeric default null,
  p_surface text default null,
  p_tags text[] default null,
  p_featured_only boolean default false,
  p_sort text default 'newest',
  p_limit int default 50,
  p_offset int default 0
) returns setof public_routes
language plpgsql stable security definer
set search_path = public, extensions
as $$
begin
  if p_sort = 'popular' then
    return query
      select pr.*
      from public_routes pr
      where (p_query is null or pr.name ilike '%' || p_query || '%')
        and (p_min_distance_m is null or pr.distance_m >= p_min_distance_m)
        and (p_max_distance_m is null or pr.distance_m <= p_max_distance_m)
        and (p_surface is null or pr.surface = p_surface)
        and (p_tags is null or p_tags = '{}' or pr.tags && p_tags)
        and (p_featured_only = false or pr.is_featured = true)
      order by pr.run_count desc nulls last, pr.created_at desc
      limit p_limit offset p_offset;
  elsif p_sort = 'featured' then
    return query
      select pr.*
      from public_routes pr
      where (p_query is null or pr.name ilike '%' || p_query || '%')
        and (p_min_distance_m is null or pr.distance_m >= p_min_distance_m)
        and (p_max_distance_m is null or pr.distance_m <= p_max_distance_m)
        and (p_surface is null or pr.surface = p_surface)
        and (p_tags is null or p_tags = '{}' or pr.tags && p_tags)
        and (p_featured_only = false or pr.is_featured = true)
      order by pr.featured_at desc nulls last, pr.created_at desc
      limit p_limit offset p_offset;
  elsif p_sort = 'newest' then
    return query
      select pr.*
      from public_routes pr
      where (p_query is null or pr.name ilike '%' || p_query || '%')
        and (p_min_distance_m is null or pr.distance_m >= p_min_distance_m)
        and (p_max_distance_m is null or pr.distance_m <= p_max_distance_m)
        and (p_surface is null or pr.surface = p_surface)
        and (p_tags is null or p_tags = '{}' or pr.tags && p_tags)
        and (p_featured_only = false or pr.is_featured = true)
      order by pr.created_at desc nulls last
      limit p_limit offset p_offset;
  else
    return query
      select pr.*
      from public_routes pr
      where (p_query is null or pr.name ilike '%' || p_query || '%')
        and (p_min_distance_m is null or pr.distance_m >= p_min_distance_m)
        and (p_max_distance_m is null or pr.distance_m <= p_max_distance_m)
        and (p_surface is null or pr.surface = p_surface)
        and (p_tags is null or p_tags = '{}' or pr.tags && p_tags)
        and (p_featured_only = false or pr.is_featured = true)
      order by pr.created_at desc
      limit p_limit offset p_offset;
  end if;
end;
$$;
