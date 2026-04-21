-- Server-side aggregate for the route-explore tag chips. The client used
-- to fetch up to 500 `routes.tags` arrays and count them in memory — fine
-- for the current dataset but O(routes) on the wire every time someone
-- opens the Explore tab. Pushing the aggregate down to Postgres lets the
-- GIN index on `routes.tags` actually earn its keep and returns a few
-- kilobytes instead of potentially hundreds.
--
-- `stable` because it's pure read-only aggregation on committed data;
-- `security invoker` so the function runs under the caller's RLS (public
-- routes only). `unnest` + `group by` is the idiomatic text[] aggregation
-- in Postgres — the GIN index on tags accelerates the scan.

create or replace function popular_route_tags(tag_limit int default 20)
returns table (tag text, route_count bigint)
language sql
stable
security invoker
as $$
  select unnest(tags) as tag, count(*) as route_count
  from routes
  where is_public = true
  group by tag
  order by route_count desc, tag asc
  limit tag_limit;
$$;

-- Allow authenticated and anon clients to call the RPC. RLS on `routes`
-- (public rows readable by anyone) is still the gate on which rows the
-- aggregate sees.
grant execute on function popular_route_tags(int) to anon, authenticated;
