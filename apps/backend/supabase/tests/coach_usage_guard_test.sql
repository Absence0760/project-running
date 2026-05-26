-- Pins migration 20260930_001 — the closed `v_role <> ''` short-circuit
-- in increment_coach_usage / get_coach_usage. Without this the only
-- thing holding back a future `grant ... to anon` (or service-role
-- caller without a `role` claim) is the EXECUTE grant; this test
-- asserts the in-function defence is also live.

begin;
select plan(4);

-- An empty role claim must be rejected when auth.uid() doesn't
-- match p_user_id. Pre-fix this was a silent no-op (the v_role <> ''
-- short-circuit skipped the guard); post-fix it raises 42501.
do $$
declare
  v_user uuid := '99999999-9999-9999-9999-99999999aaaa';
  v_other uuid := '99999999-9999-9999-9999-99999999bbbb';
begin
  -- Seed two synthetic auth.users so the FK on user_coach_usage
  -- doesn't fight us. Service-role for the inserts.
  perform set_config('request.jwt.claim.role', 'service_role', true);
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'coach-guard-a@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_other, 'coach-guard-b@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;

  -- Mimic the "neither claim form populated" context: empty role,
  -- empty sub. Pre-fix the function fell through and bumped the
  -- arbitrary p_user_id's counter; post-fix it raises 42501.
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  begin
    perform increment_coach_usage(v_other);
    raise exception 'increment_coach_usage must reject empty-role caller';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform get_coach_usage(v_other);
    raise exception 'get_coach_usage must reject empty-role caller';
  exception when insufficient_privilege then
    null;
  end;

  -- An authenticated caller whose auth.uid() matches must still
  -- succeed — closing the bypass shouldn't tighten the legitimate
  -- path. Set both legacy + modern claim forms so the coalesce
  -- works regardless of which PostgREST baseline is active.
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'role', 'authenticated',
      'sub', v_user::text
    )::text,
    true
  );

  if increment_coach_usage(v_user) < 1 then
    raise exception 'increment_coach_usage must return >= 1 for self';
  end if;
  if get_coach_usage(v_user) < 1 then
    raise exception 'get_coach_usage must return the incremented count';
  end if;

  -- Service-role bypass still works — the documented escape hatch.
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('role','service_role')::text, true);
  -- Should not raise even though auth.uid() is now null vs v_other.
  perform increment_coach_usage(v_other);
  perform get_coach_usage(v_other);

  -- Cleanup. user_coach_usage rows cascade via FK to auth.users.
  delete from auth.users where id in (v_user, v_other);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

select pass(
  'increment_coach_usage rejects empty-role cross-user attempt (42501)'
);
select pass(
  'get_coach_usage rejects empty-role cross-user attempt (42501)'
);
select pass(
  'increment_coach_usage allows self when auth.uid matches p_user_id'
);
select pass(
  'service_role bypass still functions across arbitrary p_user_id'
);

select * from finish();
rollback;
