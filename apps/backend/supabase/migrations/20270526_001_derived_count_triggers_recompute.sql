-- clubs.member_count and routes.run_count stop doing delta arithmetic and
-- recompute from the authoritative query instead (derived_state.md § Adding a
-- new derived cache, rule 2 — the shape challenges.participant_count and
-- gym_workouts.set_count already use).
--
-- Two verified drifts motivate it, one per cache:
--
--   * clubs_member_count_trigger had two non-exclusive `if` blocks on UPDATE
--     (status changed, club_id changed). A statement that changes both runs
--     both: moving a pending member into another club and activating them in
--     one UPDATE increments the destination twice (measured cache 3 against an
--     authoritative 2), and moving an active member out while demoting them
--     decrements the source twice. The trigger's own column watch list is
--     `OF status, club_id`, so the combined statement is in scope by
--     construction.
--
--   * routes_run_count_trigger decided whether a decrement was owed by
--     re-evaluating private.is_route_visible_to(old.route_id, old.user_id) at
--     trigger time. That predicate reads the route's CURRENT visibility, not
--     the visibility that was in force when the increment happened, so a route
--     that has since gone private makes `v_was_counted` false and the run
--     detaches without ever giving the count back (measured cache 1 against an
--     authoritative 0). Nothing revisits it: the counter is permanently high.
--     This is not the drift derived_state.md accepts — that one is about the
--     RUN's is_public flip, which the trigger deliberately does not watch.
--
-- No delta form can fix the second one: the "was it counted?" answer is not
-- derivable from the row's own OLD image. Recomputing the affected parent from
-- the cache's documented authoritative query is the only correct read, and it
-- also makes the accepted is_public drift self-healing on the next route_id
-- touch instead of compounding.
--
-- Both refreshers no-op when the cache already agrees, so the trigger path
-- stops writing a new row version for every unchanged parent.

create or replace function refresh_club_member_count(p_club_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  with authoritative as (
    select count(*)::int as cnt
    from club_members m
    where m.club_id = p_club_id
      and m.status = 'active'
  )
  update clubs c
  set member_count = authoritative.cnt
  from authoritative
  where c.id = p_club_id
    and c.member_count is distinct from authoritative.cnt;
$$;

create or replace function refresh_route_run_count(p_route_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  with authoritative as (
    select count(*)::int as cnt
    from runs
    where runs.route_id = p_route_id
      and runs.is_public = true
      and private.is_route_visible_to(runs.route_id, runs.user_id)
  )
  update routes r
  set run_count = authoritative.cnt
  from authoritative
  where r.id = p_route_id
    and r.run_count is distinct from authoritative.cnt;
$$;

-- Both are trigger-internal (plus an operator handle for the manual rebuild in
-- derived_state.md); a definer refresher does not belong on a client role.
revoke execute on function refresh_club_member_count(uuid) from public, anon, authenticated;
revoke execute on function refresh_route_run_count(uuid) from public, anon, authenticated;

create or replace function clubs_member_count_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform refresh_club_member_count(new.club_id);
    return new;
  elsif tg_op = 'DELETE' then
    perform refresh_club_member_count(old.club_id);
    return old;
  end if;
  perform refresh_club_member_count(old.club_id);
  if new.club_id is distinct from old.club_id then
    perform refresh_club_member_count(new.club_id);
  end if;
  return new;
end;
$$;

create or replace function routes_run_count_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.route_id is not null then
      perform refresh_route_run_count(new.route_id);
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.route_id is not null then
      perform refresh_route_run_count(old.route_id);
    end if;
    return old;
  end if;
  if old.route_id is not null then
    perform refresh_route_run_count(old.route_id);
  end if;
  if new.route_id is not null and new.route_id is distinct from old.route_id then
    perform refresh_route_run_count(new.route_id);
  end if;
  return new;
end;
$$;

-- Reconcile the rows the delta triggers already got wrong. Neither cache
-- self-heals: a route nobody runs again keeps the skipped decrement forever.
--
-- clubs is a small bounded table (migration_locks.md § The high-volume
-- tables), so one scoped pass is the online form; the `is distinct from`
-- predicate means only genuinely drifted rows take a row lock. No shipped
-- writer changes club_members.club_id today, so this is expected to touch zero
-- rows — it is here to make the invariant true as of this migration rather
-- than true-going-forward.
update clubs c
set member_count = a.cnt
from (
  select c2.id, coalesce(m.cnt, 0) as cnt
  from clubs c2
  left join (
    select club_id, count(*)::int as cnt
    from club_members
    where status = 'active'
    group by club_id
  ) m on m.club_id = c2.id
) a
where a.id = c.id
  and c.member_count is distinct from a.cnt;

-- routes is reconciled in keyset batches rather than one unbounded UPDATE:
-- each statement recomputes at most 500 routes, so no single statement holds
-- row locks across the whole table while it walks runs. The refresher's
-- no-op-when-equal guard keeps the write set to the drifted rows only.
do $$
declare
  v_last uuid := '00000000-0000-0000-0000-000000000000';
  v_ids uuid[];
  v_id uuid;
begin
  loop
    select array_agg(id order by id) into v_ids
    from (select id from routes where id > v_last order by id limit 500) batch;
    exit when v_ids is null;
    v_last := v_ids[array_length(v_ids, 1)];
    foreach v_id in array v_ids loop
      perform refresh_route_run_count(v_id);
    end loop;
  end loop;
end;
$$;
