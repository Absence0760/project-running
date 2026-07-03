-- Personal-records triggers: per-row → per-statement.
--
-- refresh_personal_records_for_user recomputes the caller's ENTIRE PR
-- history (7 UNION ALL branches over all their runs), and the three
-- runs_personal_records_* triggers from 20260508_001 fired it FOR EACH
-- ROW. A bulk import of N runs (Strava backfill loop, saveRunsBatch
-- chunks — up to ~1,500 rows for a heavy migrant) therefore did N full
-- recomputes: O(batch × total_user_runs). Converting to statement-level
-- AFTER triggers with transition tables collapses that to one recompute
-- per statement per affected user, with identical cache results — the
-- refresher is a full per-user rebuild, so running it once after a batch
-- yields the same rows as running it after every row.
--
-- refresh_personal_records_for_user itself is untouched (per the
-- bare-body trap, its live body stays 20261207_001). Postgres rejects
-- transition tables on triggers with column lists, so the UPDATE
-- trigger's watch-list from 20261221_001 moves into the function as a
-- changed-value filter over the same six columns — a run whose watched
-- values didn't change triggers no refresh, matching (strictly
-- tightening: value-diff instead of SET-clause mention) the old OF-list
-- gate. There were no row WHEN clauses to carry over. The UPDATE path
-- refreshes old ∪ new owners so the owner-change case (previously
-- handled per-row in the shim) still rebuilds both users' caches.

drop trigger if exists runs_personal_records_insert on runs;
drop trigger if exists runs_personal_records_update on runs;
drop trigger if exists runs_personal_records_delete on runs;

create or replace function trigger_refresh_personal_records()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if tg_op = 'INSERT' then
    for v_user_id in select distinct user_id from changed_runs loop
      perform refresh_personal_records_for_user(v_user_id);
    end loop;
  elsif tg_op = 'UPDATE' then
    for v_user_id in
      select u.user_id
      from (
        select n.user_id
        from changed_runs n
        join old_runs o on o.id = n.id
        where (n.distance_m, n.duration_s, n.source, n.user_id, n.is_dnf, n.metadata)
          is distinct from
          (o.distance_m, o.duration_s, o.source, o.user_id, o.is_dnf, o.metadata)
        union
        select o.user_id
        from old_runs o
        join changed_runs n on n.id = o.id
        where (n.distance_m, n.duration_s, n.source, n.user_id, n.is_dnf, n.metadata)
          is distinct from
          (o.distance_m, o.duration_s, o.source, o.user_id, o.is_dnf, o.metadata)
      ) u
    loop
      perform refresh_personal_records_for_user(v_user_id);
    end loop;
  else
    for v_user_id in select distinct user_id from old_runs loop
      perform refresh_personal_records_for_user(v_user_id);
    end loop;
  end if;
  return null;
end;
$$;

create trigger runs_personal_records_insert
  after insert on runs
  referencing new table as changed_runs
  for each statement
  execute function trigger_refresh_personal_records();

create trigger runs_personal_records_update
  after update on runs
  referencing old table as old_runs new table as changed_runs
  for each statement
  execute function trigger_refresh_personal_records();

create trigger runs_personal_records_delete
  after delete on runs
  referencing old table as old_runs
  for each statement
  execute function trigger_refresh_personal_records();
