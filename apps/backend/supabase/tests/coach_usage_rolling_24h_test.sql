-- Pins migration 20261002_001 — coach-usage rolling 24h sum.
--
-- The cap RPCs (increment / get / decrement) now return the SUM of
-- message_count across daily buckets whose `usage_date` falls in the
-- last 24h instead of just today's bucket. Closes the UTC-midnight
-- gaming window flagged by audit/coach Medium #5.

begin;
select plan(3);

do $$
declare
  v_user uuid := '99999999-9999-9999-9999-99999999eeee';
  v_today_count integer;
  v_after_inc integer;
  v_after_dec integer;
begin
  perform set_config('request.jwt.claim.role', 'service_role', true);
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'rolling-coach@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;

  -- Seed yesterday's bucket with 1 message (simulates a user who
  -- chatted just before the UTC midnight rollover). With the OLD
  -- semantics, this would NOT count toward today's cap; with the
  -- rolling shape it does.
  delete from user_coach_usage where user_id = v_user;
  insert into user_coach_usage (user_id, usage_date, message_count)
    values (v_user, current_date - interval '1 day', 1);

  -- Switch to authenticated context for the RPC.
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role','authenticated','sub',v_user::text)::text,
    true
  );

  -- get_coach_usage must already include yesterday's row.
  v_today_count := get_coach_usage(v_user);
  if v_today_count <> 1 then
    raise exception 'get_coach_usage rolling: expected 1 (yesterday), got %', v_today_count;
  end if;

  -- increment_coach_usage bumps today and returns the rolling sum (=2).
  v_after_inc := increment_coach_usage(v_user);
  if v_after_inc <> 2 then
    raise exception 'increment_coach_usage rolling: expected 2 (yesterday + today), got %', v_after_inc;
  end if;

  -- decrement_coach_usage drops today by 1; rolling sum = 1.
  v_after_dec := decrement_coach_usage(v_user);
  if v_after_dec <> 1 then
    raise exception 'decrement_coach_usage rolling: expected 1, got %', v_after_dec;
  end if;

  -- Cleanup.
  perform set_config('request.jwt.claim.role', 'service_role', true);
  delete from auth.users where id = v_user;
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

select pass(
  'get_coach_usage rolling: counts yesterday + today buckets'
);
select pass(
  'increment_coach_usage rolling: returns the 24h sum, not just today'
);
select pass(
  'decrement_coach_usage rolling: returns the 24h sum after the decrement'
);

select * from finish();
rollback;
