-- Pins the per-statement granularity of the personal_records triggers
-- (migration 20270315_001): a multi-row INSERT/UPDATE/DELETE on `runs`
-- runs refresh_personal_records_for_user ONCE per statement per
-- affected user — not once per row — and the cache still lands on the
-- authoritative result. Refresh invocations are counted by renaming the
-- real refresher and interposing a counting wrapper with the same
-- signature (all rolled back), so a regression back to FOR EACH ROW
-- fails the count assertions, not just performance.
--
-- Also pins the in-function watched-column filter that replaced the
-- UPDATE trigger's OF list (transition tables forbid column lists): an
-- UPDATE that changes none of distance_m / duration_s / source /
-- user_id / is_dnf / metadata triggers no refresh, and an owner-change
-- UPDATE refreshes both the old and new owner.

begin;

select plan(17);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('57a70000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
   'prs-a@test.local', '', now(), now()),
  ('57a70000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated',
   'prs-b@test.local', '', now(), now());

alter function refresh_personal_records_for_user(uuid)
  rename to refresh_personal_records_for_user_real;

create function refresh_personal_records_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('test.pr_refresh_calls',
    (coalesce(nullif(current_setting('test.pr_refresh_calls', true), ''), '0')::int + 1)::text,
    false);
  perform refresh_personal_records_for_user_real(p_user_id);
end;
$$;

discard plans;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"57a70000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select set_config('test.pr_refresh_calls', '0', false);

insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata)
values
  ('57a70001-0000-0000-0000-000000000001', '57a70000-0000-0000-0000-0000000000a1',
   '2026-04-01 09:00:00+00', 1200, 5000, 'app', '{"activity_type":"run"}'),
  ('57a70001-0000-0000-0000-000000000002', '57a70000-0000-0000-0000-0000000000a1',
   '2026-04-02 09:00:00+00', 1100, 5000, 'app', '{"activity_type":"run"}'),
  ('57a70001-0000-0000-0000-000000000003', '57a70000-0000-0000-0000-0000000000a1',
   '2026-04-03 09:00:00+00', 1300, 5000, 'app', '{"activity_type":"run"}'),
  ('57a70001-0000-0000-0000-000000000004', '57a70000-0000-0000-0000-0000000000a1',
   '2026-04-04 09:00:00+00', 2500, 10000, 'app', '{"activity_type":"run"}');

select is(
  current_setting('test.pr_refresh_calls'), '1',
  'a 4-row INSERT runs the refresher once, not once per row'
);
select is(
  (select best_time_s from personal_records
   where user_id = '57a70000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1100,
  'batch INSERT lands the correct 5k best'
);
select is(
  (select best_time_s from personal_records
   where user_id = '57a70000-0000-0000-0000-0000000000a1' and distance = '10k'),
  2500,
  'batch INSERT lands the correct 10k best'
);
select is(
  (select count(*)::int from personal_records
   where user_id = '57a70000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1,
  'batch INSERT still collapses to one row per distance'
);

select set_config('test.pr_refresh_calls', '0', false);
insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata)
values ('57a70001-0000-0000-0000-000000000005', '57a70000-0000-0000-0000-0000000000a1',
        '2026-04-05 09:00:00+00', 1000, 5000, 'app', '{"activity_type":"run"}');

select is(
  current_setting('test.pr_refresh_calls'), '1',
  'a single-row INSERT still refreshes exactly once'
);
select is(
  (select best_time_s from personal_records
   where user_id = '57a70000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1000,
  'single INSERT updates the 5k best'
);

select set_config('test.pr_refresh_calls', '0', false);
update runs set duration_s = duration_s + 600
  where id in ('57a70001-0000-0000-0000-000000000002',
               '57a70001-0000-0000-0000-000000000005');

select is(
  current_setting('test.pr_refresh_calls'), '1',
  'a 2-row UPDATE runs the refresher once'
);
select is(
  (select best_time_s from personal_records
   where user_id = '57a70000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1200,
  'multi-row UPDATE re-ranks the cache correctly'
);

select set_config('test.pr_refresh_calls', '0', false);
update runs set duration_s = duration_s
  where user_id = '57a70000-0000-0000-0000-0000000000a1';

select is(
  current_setting('test.pr_refresh_calls'), '0',
  'an UPDATE changing no watched value triggers no refresh'
);

select set_config('test.pr_refresh_calls', '0', false);
delete from runs where id in ('57a70001-0000-0000-0000-000000000001',
                              '57a70001-0000-0000-0000-000000000005');

select is(
  current_setting('test.pr_refresh_calls'), '1',
  'a 2-row DELETE runs the refresher once'
);
select is(
  (select best_time_s from personal_records
   where user_id = '57a70000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1300,
  'multi-row DELETE promotes the next-best run'
);

delete from runs where user_id = '57a70000-0000-0000-0000-0000000000a1';

select is(
  (select count(*)::int from personal_records
   where user_id = '57a70000-0000-0000-0000-0000000000a1'),
  0,
  'deleting the last qualifying runs removes the PB rows'
);

reset role;
set local "request.jwt.claims" to '';

select set_config('test.pr_refresh_calls', '0', false);
insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata)
values
  ('57a70002-0000-0000-0000-000000000001', '57a70000-0000-0000-0000-0000000000a1',
   '2026-04-06 09:00:00+00', 1500, 5000, 'app', '{"activity_type":"run"}'),
  ('57a70002-0000-0000-0000-000000000002', '57a70000-0000-0000-0000-0000000000b2',
   '2026-04-06 09:00:00+00', 900, 5000, 'app', '{"activity_type":"run"}');

select is(
  current_setting('test.pr_refresh_calls'), '2',
  'one INSERT statement spanning two users refreshes each user once'
);
select is(
  (select best_time_s from personal_records
   where user_id = '57a70000-0000-0000-0000-0000000000b2' and distance = '5k'),
  900,
  'second user gets their own PB row from the shared statement'
);

select set_config('test.pr_refresh_calls', '0', false);
update runs set user_id = '57a70000-0000-0000-0000-0000000000a1'
  where id = '57a70002-0000-0000-0000-000000000002';

select is(
  current_setting('test.pr_refresh_calls'), '2',
  'an owner-change UPDATE refreshes both the old and new owner'
);
select is(
  (select best_time_s from personal_records
   where user_id = '57a70000-0000-0000-0000-0000000000a1' and distance = '5k'),
  900,
  'the moved run becomes the new owner PB'
);
select is(
  (select count(*)::int from personal_records
   where user_id = '57a70000-0000-0000-0000-0000000000b2'),
  0,
  'the old owner loses the PB row the moved run held'
);

select * from finish();

rollback;
