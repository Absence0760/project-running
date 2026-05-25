-- Pin the audit/self-audit follow-up RPC delete_user_integration_secrets.
--
-- Authorization is enforced by the EXECUTE grant, not by a check
-- inside the function (Postgres 17 segfaults if you actually call
-- a function without EXECUTE — separate bug, but the upshot is the
-- right enforcement mechanism is the grant alone). The tests verify
-- the grant shape rather than calling from unprivileged roles.
--
-- Coverage:
--   1. anon does NOT have EXECUTE.
--   2. authenticated does NOT have EXECUTE.
--   3. service_role DOES have EXECUTE.
--   4. service_role calling on a no-integrations user returns 0.

begin;

select plan(4);

-- 1-3. Grant shape.
select ok(
  not has_function_privilege(
    'anon', 'public.delete_user_integration_secrets(uuid)', 'EXECUTE'
  ),
  'anon must NOT have EXECUTE on delete_user_integration_secrets'
);

select ok(
  not has_function_privilege(
    'authenticated', 'public.delete_user_integration_secrets(uuid)', 'EXECUTE'
  ),
  'authenticated must NOT have EXECUTE on delete_user_integration_secrets '
    || '(a user-side wipe path would bypass the regular disconnect flow audit)'
);

select ok(
  has_function_privilege(
    'service_role', 'public.delete_user_integration_secrets(uuid)', 'EXECUTE'
  ),
  'service_role MUST have EXECUTE on delete_user_integration_secrets '
    || '(this is the delete-account Edge Function''s caller)'
);

-- 4. Happy path: service_role on a user with no integrations.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000000d1', 'authenticated', 'authenticated',
   'vault-cleanup@forge.local', '', now(), now());

set local role service_role;
do $$
declare
  v_count int;
begin
  v_count := delete_user_integration_secrets('00000000-0000-0000-0000-0000000000d1');
  if v_count <> 0 then
    raise exception 'expected 0, got %', v_count;
  end if;
end $$;
select pass('service_role call on a no-integrations user returns 0');

select * from finish();
rollback;
