-- Gate `routes_run_count_trigger` on route visibility.
--
-- Pre-prod RLS audit Medium. The trigger from 20260427_001 is
-- SECURITY DEFINER (it has to be — it UPDATEs `routes.run_count`
-- on rows the inserting user doesn't own when running a public
-- route) but it bumps the counter unconditionally on any
-- runs INSERT that has a `route_id`.
--
-- `runs.route_id` has no FK-side visibility gate, and the runs
-- INSERT policy only checks that the writer owns the run (not
-- that they can SELECT the route). So a malicious user can
-- enumerate / guess UUIDs and INSERT runs against private
-- routes belonging to other users; the trigger fires once per
-- insert and inflates `run_count` arbitrarily on a route the
-- attacker cannot even see.
--
-- Worst case is leaderboard / popularity inflation, not data
-- exfil. But `run_count` feeds the Popular Routes ranking and
-- the per-route detail screen, so an attacker can falsely
-- promote a route or just grief a victim.
--
-- The fix introduces a small helper `is_route_visible_to(route,
-- user)` that mirrors the SELECT predicate (owner OR public OR
-- active member of the route's club) but takes the user
-- explicitly so the trigger can check the run's user_id rather
-- than reading auth.uid() from session state — which would be
-- wrong for service-role inserts (Strava webhook, parkrun
-- import) where there's no JWT.
--
-- Counter semantics: increment iff the run's user could see the
-- route at the moment of the insert. Decrement iff they could
-- see it at the moment of the delete. UPDATEs that move
-- route_id apply the same rule per side. We don't try to
-- reconcile retroactive privacy flips (route flips public →
-- private after a run was logged); the count drifts in those
-- corner cases and that's acceptable — the alternative would
-- mean recomputing on every routes UPDATE.

create or replace function is_route_visible_to(p_route_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from routes r
    where r.id = p_route_id
      and (
        r.user_id = p_user_id
        or r.is_public = true
        or (
          r.club_id is not null
          and exists (
            select 1 from club_members
            where club_id = r.club_id
              and user_id = p_user_id
              and status = 'active'
          )
        )
      )
  );
$$;

grant execute on function is_route_visible_to(uuid, uuid) to authenticated, service_role;

create or replace function routes_run_count_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.route_id is not null
       and is_route_visible_to(new.route_id, new.user_id) then
      update routes set run_count = run_count + 1 where id = new.route_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.route_id is not null
       and is_route_visible_to(old.route_id, old.user_id) then
      update routes set run_count = greatest(run_count - 1, 0) where id = old.route_id;
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    if old.route_id is distinct from new.route_id then
      if old.route_id is not null
         and is_route_visible_to(old.route_id, old.user_id) then
        update routes set run_count = greatest(run_count - 1, 0) where id = old.route_id;
      end if;
      if new.route_id is not null
         and is_route_visible_to(new.route_id, new.user_id) then
        update routes set run_count = run_count + 1 where id = new.route_id;
      end if;
    end if;
    return new;
  end if;
  return null;
end;
$$;
