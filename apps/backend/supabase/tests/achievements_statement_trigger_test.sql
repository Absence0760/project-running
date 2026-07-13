-- Pins the per-statement granularity of the achievement award triggers
-- (migration 20270404_001): a multi-row INSERT/UPDATE/DELETE on a source
-- table runs award_achievements_for_user ONCE per statement per affected
-- user — not once per row — and the awards still land on the authoritative
-- (idempotent full-rebuild) result. Award invocations are counted by
-- renaming the real function and interposing a counting wrapper with the
-- same signature (all rolled back), so a regression back to FOR EACH ROW
-- fails the count assertions, not just performance.
--
-- The count assertions drive training_plans: unlike runs (whose insert also
-- fires the personal_records refresh, which in turn fires the PR-source
-- award trigger) a training_plans change cascades into no further award
-- calls, so the counter isolates the training_plans trigger's own dispatch.
-- The final assertion drives the runs bulk-import path to prove a batch
-- insert still awards the identical badge the per-row trigger would have.

begin;
select plan(11);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('ac000000-0000-0000-0000-0000000000a1', 'ach-stmt-a@test.local', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('ac000000-0000-0000-0000-0000000000b2', 'ach-stmt-b@test.local', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('ac000000-0000-0000-0000-0000000000c3', 'ach-stmt-c@test.local', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

alter function award_achievements_for_user(uuid)
  rename to award_achievements_for_user_real;

create function award_achievements_for_user(p_user uuid)
returns setof achievements
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('test.award_calls',
    (coalesce(nullif(current_setting('test.award_calls', true), ''), '0')::int + 1)::text,
    false);
  return query select * from award_achievements_for_user_real(p_user);
end;
$$;

discard plans;

-- ── Batch INSERT collapses to one award per user ─────────────────────────────
select set_config('test.award_calls', '0', false);
insert into training_plans (id, user_id, name, goal_event, goal_distance_m,
                            start_date, end_date, status)
values
  ('ac000001-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-0000000000a1',
   'Plan 1', 'distance_5k', 5000, '2026-04-01', '2026-05-01', 'completed'),
  ('ac000001-0000-0000-0000-000000000002', 'ac000000-0000-0000-0000-0000000000a1',
   'Plan 2', 'distance_5k', 5000, '2026-04-01', '2026-05-01', 'completed'),
  ('ac000001-0000-0000-0000-000000000003', 'ac000000-0000-0000-0000-0000000000a1',
   'Plan 3', 'distance_5k', 5000, '2026-04-01', '2026-05-01', 'completed');

select is(
  current_setting('test.award_calls'), '1',
  'a 3-row INSERT runs the award once, not once per row'
);
select is(
  (select tier from achievements
     where user_id = 'ac000000-0000-0000-0000-0000000000a1'
       and badge_key = 'plan_finisher'
     order by case tier when 'platinum' then 4 when 'gold' then 3
                        when 'silver' then 2 else 1 end desc limit 1),
  'silver',
  '3 completed plans in one statement earn the silver plan_finisher badge'
);
select is(
  (select count(*)::int from achievements
     where user_id = 'ac000000-0000-0000-0000-0000000000a1'
       and badge_key = 'plan_finisher'),
  1,
  'batch INSERT collapses to one plan_finisher row (top tier only)'
);

-- ── Idempotency: a re-derive inserts nothing new ─────────────────────────────
select is(
  (select count(*)::int from (
     select award_achievements_for_user('ac000000-0000-0000-0000-0000000000a1')
   ) s),
  0,
  'a re-derive returns zero newly-inserted awards (idempotent full rebuild)'
);

-- ── Single-row INSERT still awards exactly once ──────────────────────────────
select set_config('test.award_calls', '0', false);
insert into training_plans (id, user_id, name, goal_event, goal_distance_m,
                            start_date, end_date, status)
values
  ('ac000001-0000-0000-0000-000000000004', 'ac000000-0000-0000-0000-0000000000a1',
   'Plan 4', 'distance_5k', 5000, '2026-04-01', '2026-05-01', 'completed');
select is(
  current_setting('test.award_calls'), '1',
  'a single-row INSERT still awards exactly once'
);

-- ── Multi-row UPDATE of a watched column awards once ─────────────────────────
select set_config('test.award_calls', '0', false);
update training_plans set status = 'abandoned'
  where id in ('ac000001-0000-0000-0000-000000000001',
               'ac000001-0000-0000-0000-000000000002');
select is(
  current_setting('test.award_calls'), '1',
  'a 2-row status UPDATE runs the award once'
);

-- ── UPDATE of no watched column awards not at all ────────────────────────────
select set_config('test.award_calls', '0', false);
update training_plans set name = 'renamed'
  where id = 'ac000001-0000-0000-0000-000000000003';
select is(
  current_setting('test.award_calls'), '0',
  'an UPDATE changing no watched value (name only) triggers no award'
);

-- ── Multi-row DELETE awards once ─────────────────────────────────────────────
select set_config('test.award_calls', '0', false);
delete from training_plans
  where id in ('ac000001-0000-0000-0000-000000000001',
               'ac000001-0000-0000-0000-000000000002');
select is(
  current_setting('test.award_calls'), '1',
  'a 2-row DELETE runs the award once'
);

-- ── One statement spanning two users awards each once ────────────────────────
select set_config('test.award_calls', '0', false);
insert into training_plans (id, user_id, name, goal_event, goal_distance_m,
                            start_date, end_date, status)
values
  ('ac000001-0000-0000-0000-000000000005', 'ac000000-0000-0000-0000-0000000000a1',
   'Plan 5', 'distance_5k', 5000, '2026-04-01', '2026-05-01', 'completed'),
  ('ac000001-0000-0000-0000-000000000006', 'ac000000-0000-0000-0000-0000000000b2',
   'Plan B', 'distance_5k', 5000, '2026-04-01', '2026-05-01', 'completed');
select is(
  current_setting('test.award_calls'), '2',
  'one INSERT statement spanning two users awards each user once'
);
select is(
  (select tier from achievements
     where user_id = 'ac000000-0000-0000-0000-0000000000b2'
       and badge_key = 'plan_finisher' limit 1),
  'bronze',
  'the second user earns their own bronze plan_finisher from the shared statement'
);

-- ── Bulk run import still awards the identical badge (result unchanged) ───────
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values
  ('ac000002-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-0000000000c3',
   '2026-04-01 09:00:00+00', 42450, 14400, 'app', '{"activity_type":"run"}'),
  ('ac000002-0000-0000-0000-000000000002', 'ac000000-0000-0000-0000-0000000000c3',
   '2026-04-02 09:00:00+00', 30000, 10800, 'app', '{"activity_type":"run"}'),
  ('ac000002-0000-0000-0000-000000000003', 'ac000000-0000-0000-0000-0000000000c3',
   '2026-04-03 09:00:00+00', 30000, 10800, 'app', '{"activity_type":"run"}');
select is(
  (select tier from achievements
     where user_id = 'ac000000-0000-0000-0000-0000000000c3'
       and badge_key = 'distance_single'
     order by case tier when 'platinum' then 4 when 'gold' then 3
                        when 'silver' then 2 else 1 end desc limit 1),
  'gold',
  'a batch run INSERT still earns the gold single-run distance badge'
);

select * from finish();
rollback;
