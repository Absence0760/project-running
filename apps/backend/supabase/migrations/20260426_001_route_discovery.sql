-- Turn the public-routes list into something you can actually browse:
--   * `tags` — free-form labels ("5k", "loop", "hill", "parkrun_course",
--     "beginner"). Indexed with GIN so `tags && ARRAY['5k','hill']` scans
--     are cheap. Not a constrained enum — the point of tags is to grow
--     organically; any curation / deduping we decide to do later is a
--     client-side merge, not a schema change.
--   * `featured` — editor's pick. A partial index keeps the common
--     "browse the picks" query fast without bloating inserts on the
--     other 99% of rows.
--   * `run_count` — materialised counter maintained by a trigger on
--     `runs`. Lets the explore page show "234 runs" as a social-proof
--     signal without a join or a COUNT(*) per card.
--
-- Author curation for `featured` is admin-only (service role) for now;
-- there's no user-facing "promote to featured" button. When we decide on
-- a curation flow, that policy gets edited rather than the column.

alter table routes
  add column tags text[] not null default '{}',
  add column featured boolean not null default false,
  add column featured_at timestamptz,
  add column run_count integer not null default 0;

create index routes_tags_gin on routes using gin (tags);
create index routes_featured
  on routes (featured_at desc nulls last)
  where featured = true and is_public = true;

-- Allow public reads of feature tags / run_count already flow through
-- the existing `routes` RLS (anyone reads `is_public = true`). Owner
-- writes continue to flow through their existing UPDATE policy, so no
-- new policies needed — they can edit their own tags. A follow-up
-- migration can add a `is_app_admin()` branch to permit curators to
-- edit `featured` on routes they don't own.

-- run_count maintenance. `runs.route_id` is nullable — most runs aren't
-- tied to a saved route. We only increment when a run is inserted with
-- a non-null route_id, decrement on delete, and handle UPDATE cases
-- where the column changes between routes.
create or replace function routes_run_count_trigger()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if new.route_id is not null then
      update routes set run_count = run_count + 1 where id = new.route_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.route_id is not null then
      update routes set run_count = greatest(run_count - 1, 0) where id = old.route_id;
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    if old.route_id is distinct from new.route_id then
      if old.route_id is not null then
        update routes set run_count = greatest(run_count - 1, 0) where id = old.route_id;
      end if;
      if new.route_id is not null then
        update routes set run_count = run_count + 1 where id = new.route_id;
      end if;
    end if;
    return new;
  end if;
  return null;
end;
$$;

create trigger runs_maintain_route_run_count
  after insert or update of route_id or delete on runs
  for each row execute function routes_run_count_trigger();

-- Backfill current counts. Idempotent — a follow-up migration that
-- re-runs this is safe.
update routes r
set run_count = coalesce(sub.cnt, 0)
from (
  select route_id, count(*)::int as cnt
  from runs
  where route_id is not null
  group by route_id
) sub
where sub.route_id = r.id;

-- Server-side searcher. The existing client-side filter in `data.ts`
-- does text + distance + surface; this RPC adds tags (any-overlap) and
-- a featured-only flag, plus sorting options. Called from both web and
-- Android — keeps the filter logic one place as it grows.
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
) returns setof routes language sql stable security invoker as $$
  select *
  from routes
  where is_public = true
    and (p_query is null or name ilike '%' || p_query || '%')
    and (p_min_distance_m is null or distance_m >= p_min_distance_m)
    and (p_max_distance_m is null or distance_m <= p_max_distance_m)
    and (p_surface is null or surface = p_surface)
    and (p_tags is null or p_tags = '{}' or tags && p_tags)
    and (p_featured_only = false or featured = true)
  order by
    case when p_sort = 'popular' then run_count end desc nulls last,
    case when p_sort = 'featured' then featured_at end desc nulls last,
    case when p_sort = 'newest' then created_at end desc nulls last,
    created_at desc
  limit p_limit offset p_offset;
$$;

grant execute on function search_public_routes(
  text, numeric, numeric, text, text[], boolean, text, int, int
) to authenticated, anon;
