-- Pins migration 20261001_001 — decrement_coach_usage RPC.
-- audit:coach May 2026 High #3 — handler's unhappy path refunds the
-- daily slot via this RPC; the test covers (a) it actually
-- decrements, (b) it floors at zero (defence against double-call),
-- (c) it honours the same caller-identity guard as
-- increment_coach_usage post-20260930_001.

begin;
select plan(5);

select has_function(
  'public', 'decrement_coach_usage', ARRAY['uuid'],
  'decrement_coach_usage(uuid) must exist'
);

select function_privs_are(
  'public', 'decrement_coach_usage', ARRAY['uuid'],
  'authenticated', ARRAY['EXECUTE'],
  'authenticated must EXECUTE decrement_coach_usage'
);

select function_privs_are(
  'public', 'decrement_coach_usage', ARRAY['uuid'],
  'anon', ARRAY[]::text[],
  'anon must NOT execute decrement_coach_usage'
);

do $$
declare
  v_user uuid := '99999999-9999-9999-9999-99999999cccc';
  v_other uuid := '99999999-9999-9999-9999-99999999dddd';
  v_after_inc integer;
  v_after_dec integer;
  v_floor integer;
begin
  -- Seed two synthetic auth.users for the FK + guard tests.
  perform set_config('request.jwt.claim.role', 'service_role', true);
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'dec-coach-a@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_other, 'dec-coach-b@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;

  -- Authenticated, matching auth.uid — should succeed.
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role','authenticated','sub',v_user::text)::text,
    true
  );

  v_after_inc := increment_coach_usage(v_user);
  if v_after_inc <> 1 then
    raise exception 'increment should be 1, got %', v_after_inc;
  end if;

  v_after_dec := decrement_coach_usage(v_user);
  if v_after_dec <> 0 then
    raise exception 'decrement should floor at 0, got %', v_after_dec;
  end if;

  -- Double-decrement at 0 stays at 0 (defence-in-depth retry).
  v_floor := decrement_coach_usage(v_user);
  if v_floor <> 0 then
    raise exception 'double-decrement should still be 0, got %', v_floor;
  end if;

  -- Cross-user attempt must raise 42501 — same guard shape as
  -- increment_coach_usage post-20260930_001.
  begin
    perform decrement_coach_usage(v_other);
    raise exception 'decrement_coach_usage must reject cross-user';
  exception when insufficient_privilege then
    null;
  end;

  -- Cleanup.
  perform set_config('request.jwt.claim.role', 'service_role', true);
  delete from auth.users where id in (v_user, v_other);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

select pass(
  'decrement_coach_usage decrements + floors at 0 + rejects cross-user'
);

select pass(
  'decrement_coach_usage is idempotent at the zero floor'
);

select * from finish();
rollback;
