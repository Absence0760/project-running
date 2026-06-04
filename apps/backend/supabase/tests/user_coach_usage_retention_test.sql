-- Pins F9: user_coach_usage has a retention purge
-- (cleanup_stale_user_coach_usage, 20261215_001).
--
-- Seed a stale bucket (older than the 7-day cutoff) and a fresh one, run
-- the cleanup, and assert only the stale bucket is dropped — and that the
-- rolling-24h cap RPC still reads the fresh bucket. Runs as superuser.

begin;

select plan(3);

insert into user_coach_usage (user_id, usage_date, message_count)
values
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', (now() - interval '10 days')::date, 5),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', current_date, 1);

select is(
  (select cleanup_stale_user_coach_usage()),
  1,
  'cleanup_stale_user_coach_usage purges exactly the one stale bucket'
);
select is(
  (select count(*)::int from user_coach_usage
     where user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
  1,
  'the fresh bucket survives the sweep'
);
-- The rolling-24h cap still sees today's bucket after the purge. The cap
-- RPC is SECURITY DEFINER with a service_role / self guard, so set the
-- service_role claim before calling it.
set local "request.jwt.claims" = '{"role":"service_role"}';
select is(
  (select get_coach_usage('a1b2c3d4-e5f6-7890-abcd-ef1234567890')),
  1,
  'the cap RPC still reads today''s bucket after a purge'
);

select * from finish();
rollback;
