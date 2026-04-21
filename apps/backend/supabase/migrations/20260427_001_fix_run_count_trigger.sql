-- Bug fix: `routes_run_count_trigger` updated `routes.run_count` as the
-- inserting user, which hit the owner-only UPDATE policy on `routes`
-- when a run referenced a public route owned by someone else. That
-- aborted the run insert with a permission error, surfacing to the user
-- as a silent sync failure.
--
-- The fix is to run the counter-maintenance function as `security
-- definer`. The logic is unchanged — only the permissions model shifts
-- so the trigger can UPDATE any route's `run_count`, regardless of
-- ownership. We also pin `search_path` to public so a malicious schema
-- in the caller's path can't intercept the `routes` name.

create or replace function routes_run_count_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
