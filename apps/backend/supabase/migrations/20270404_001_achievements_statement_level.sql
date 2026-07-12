-- Achievement award triggers: per-row → per-statement.
--
-- award_achievements_for_user recomputes the caller's ENTIRE earned set
-- (longest/lifetime distance + best-streak + PR + completed-plan scans,
-- guarded by a per-user advisory lock). The three source-table triggers
-- from 20270208_001 fired it FOR EACH ROW. A bulk import of N runs
-- (Strava backfill loop, saveRunsBatch chunks — up to ~1,500 rows for a
-- heavy migrant), and each PR-cache DELETE+INSERT the refresher does,
-- therefore ran that full rebuild once per row: O(batch × total_user_runs),
-- serialized on the per-user lock. Converting to statement-level AFTER
-- triggers with transition tables collapses that to one rebuild per
-- statement per affected user, with identical awards — the function is an
-- idempotent full rebuild (insert ... on conflict do nothing), so running
-- it once after a batch yields the same rows as running it after each row.
--
-- Mirrors 20270315_001 (which gave the personal_records triggers the same
-- treatment). Postgres forbids transition tables on a trigger with a column
-- list, and forbids one trigger firing on more than one of INSERT/UPDATE/
-- DELETE when it uses transition tables, so each old combined trigger splits
-- into an insert/update/delete trio and each old OF-column watch-list
-- (runs: distance_m/source/is_dnf/user_id; training_plans: status) moves
-- into the function as a changed-value filter over the same columns — an
-- UPDATE that changes none of them triggers no rebuild, matching (strictly
-- tightening: value-diff instead of SET-clause mention) the old OF gate.
-- The UPDATE path rebuilds old ∪ new owners so an owner-change still
-- refreshes both users (the old per-row shim only refreshed the new owner).
-- award_achievements_for_user itself is untouched (bare-body trap; its live
-- body stays 20270208_001).

drop trigger if exists runs_award_achievements on runs;
drop trigger if exists personal_records_award_achievements on personal_records;
drop trigger if exists training_plans_award_achievements on training_plans;
drop function if exists trigger_award_achievements();

-- runs: watch distance_m / source / is_dnf / user_id (the old OF list).
create or replace function trigger_award_achievements_runs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if tg_op = 'INSERT' then
    for v_user_id in select distinct user_id from new_runs loop
      perform award_achievements_for_user(v_user_id);
    end loop;
  elsif tg_op = 'UPDATE' then
    for v_user_id in
      select u.user_id
      from (
        select n.user_id
        from new_runs n
        join old_runs o on o.id = n.id
        where (n.distance_m, n.source, n.is_dnf, n.user_id)
          is distinct from (o.distance_m, o.source, o.is_dnf, o.user_id)
        union
        select o.user_id
        from old_runs o
        join new_runs n on n.id = o.id
        where (n.distance_m, n.source, n.is_dnf, n.user_id)
          is distinct from (o.distance_m, o.source, o.is_dnf, o.user_id)
      ) u
    loop
      perform award_achievements_for_user(v_user_id);
    end loop;
  else
    for v_user_id in select distinct user_id from old_runs loop
      perform award_achievements_for_user(v_user_id);
    end loop;
  end if;
  return null;
end;
$$;

create trigger runs_award_achievements_insert
  after insert on runs
  referencing new table as new_runs
  for each statement
  execute function trigger_award_achievements_runs();

create trigger runs_award_achievements_update
  after update on runs
  referencing old table as old_runs new table as new_runs
  for each statement
  execute function trigger_award_achievements_runs();

create trigger runs_award_achievements_delete
  after delete on runs
  referencing old table as old_runs
  for each statement
  execute function trigger_award_achievements_runs();

-- personal_records: the old trigger had no column list, so every UPDATE
-- rebuilds; dispatch the union of old ∪ new owners to cover an owner change.
create or replace function trigger_award_achievements_prs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if tg_op = 'INSERT' then
    for v_user_id in select distinct user_id from new_prs loop
      perform award_achievements_for_user(v_user_id);
    end loop;
  elsif tg_op = 'UPDATE' then
    for v_user_id in
      select distinct user_id from (
        select user_id from new_prs
        union
        select user_id from old_prs
      ) u
    loop
      perform award_achievements_for_user(v_user_id);
    end loop;
  else
    for v_user_id in select distinct user_id from old_prs loop
      perform award_achievements_for_user(v_user_id);
    end loop;
  end if;
  return null;
end;
$$;

create trigger personal_records_award_achievements_insert
  after insert on personal_records
  referencing new table as new_prs
  for each statement
  execute function trigger_award_achievements_prs();

create trigger personal_records_award_achievements_update
  after update on personal_records
  referencing old table as old_prs new table as new_prs
  for each statement
  execute function trigger_award_achievements_prs();

create trigger personal_records_award_achievements_delete
  after delete on personal_records
  referencing old table as old_prs
  for each statement
  execute function trigger_award_achievements_prs();

-- training_plans: watch status (the old OF list) + user_id for owner change.
create or replace function trigger_award_achievements_plans()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if tg_op = 'INSERT' then
    for v_user_id in select distinct user_id from new_plans loop
      perform award_achievements_for_user(v_user_id);
    end loop;
  elsif tg_op = 'UPDATE' then
    for v_user_id in
      select u.user_id
      from (
        select n.user_id
        from new_plans n
        join old_plans o on o.id = n.id
        where (n.status, n.user_id) is distinct from (o.status, o.user_id)
        union
        select o.user_id
        from old_plans o
        join new_plans n on n.id = o.id
        where (n.status, n.user_id) is distinct from (o.status, o.user_id)
      ) u
    loop
      perform award_achievements_for_user(v_user_id);
    end loop;
  else
    for v_user_id in select distinct user_id from old_plans loop
      perform award_achievements_for_user(v_user_id);
    end loop;
  end if;
  return null;
end;
$$;

create trigger training_plans_award_achievements_insert
  after insert on training_plans
  referencing new table as new_plans
  for each statement
  execute function trigger_award_achievements_plans();

create trigger training_plans_award_achievements_update
  after update on training_plans
  referencing old table as old_plans new table as new_plans
  for each statement
  execute function trigger_award_achievements_plans();

create trigger training_plans_award_achievements_delete
  after delete on training_plans
  referencing old table as old_plans
  for each statement
  execute function trigger_award_achievements_plans();
