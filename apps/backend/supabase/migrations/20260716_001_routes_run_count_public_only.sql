-- Limit `routes.run_count` increments to *public* runs only.
--
-- Audit pass 2 finding: `public_routes` exposes `run_count`, and the
-- `routes_run_count_trigger` from `20260628_001` increments the
-- counter whenever the inserting user is `is_route_visible_to(...)` —
-- which for a public route is *every authenticated user*. A user
-- logging a `is_public = false` run against a public route bumps the
-- counter, and the public viewer sees an inflated count that
-- reveals private activity occurred against that route.
--
-- Pass 2 recommendation (a): increment only when the run is itself
-- public. The visibility gate stays in place so a writer can't
-- inflate counts on a route they can't see; the new gate adds the
-- additional `is_public = true` predicate so private training runs
-- are simply not counted.
--
-- Trade-off accepted: a run flipped public → private after creation
-- still leaves the counter elevated; a run flipped private → public
-- after creation does not retroactively bump. Same drift the original
-- migration accepted for route-side flips.

create or replace function routes_run_count_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.route_id is not null
       and new.is_public = true
       and is_route_visible_to(new.route_id, new.user_id) then
      update routes set run_count = run_count + 1 where id = new.route_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.route_id is not null
       and old.is_public = true
       and is_route_visible_to(old.route_id, old.user_id) then
      update routes set run_count = greatest(run_count - 1, 0) where id = old.route_id;
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    -- Two axes can change: route_id (move) and is_public (visibility flip).
    -- Net effect: was-counted? vs is-counted? — adjust by the delta.
    declare
      v_was_counted boolean := old.route_id is not null
        and old.is_public = true
        and is_route_visible_to(old.route_id, old.user_id);
      v_is_counted boolean := new.route_id is not null
        and new.is_public = true
        and is_route_visible_to(new.route_id, new.user_id);
    begin
      if v_was_counted and not v_is_counted then
        update routes set run_count = greatest(run_count - 1, 0) where id = old.route_id;
      elsif (not v_was_counted) and v_is_counted then
        update routes set run_count = run_count + 1 where id = new.route_id;
      elsif v_was_counted and v_is_counted
            and old.route_id is distinct from new.route_id then
        update routes set run_count = greatest(run_count - 1, 0) where id = old.route_id;
        update routes set run_count = run_count + 1 where id = new.route_id;
      end if;
    end;
    return new;
  end if;
  return null;
end;
$$;

-- Recompute run_count from scratch: only count public runs whose
-- author can see the route. The original counter included private
-- runs, so existing values overcount. Rebuilding once aligns the
-- on-disk state with the new trigger semantics.
update routes r
set run_count = coalesce(sub.cnt, 0)
from (
  select runs.route_id as id, count(*)::int as cnt
  from runs
  where runs.route_id is not null
    and runs.is_public = true
    and is_route_visible_to(runs.route_id, runs.user_id)
  group by runs.route_id
) sub
where r.id = sub.id;

-- Routes with zero qualifying runs need explicit zeroing too — the
-- left-side-only update above doesn't touch them.
update routes
set run_count = 0
where id not in (
  select route_id from runs where route_id is not null and is_public = true
);
