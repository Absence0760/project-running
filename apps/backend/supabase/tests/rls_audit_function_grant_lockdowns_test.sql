-- Pin the audit/rls (May 2026) revokes added by 20260914_002:
--
--   * clip_track_for_user(uuid, jsonb) must NOT be EXECUTE-able by anon
--     (the clip-public-track Edge Function uses service_role; anon
--     hitting the RPC directly widens the privacy-zone residual risk
--     beyond what decisions §33 documents).
--   * auto_tag_default_gear() must NOT be EXECUTE-able by authenticated
--     (it's a SECURITY DEFINER trigger function; grants to a user role
--     are vestigial and violate the trigger-internal contract).
--
-- Negative-grant pgtap tests use pg_catalog directly via has_function_privilege.

begin;

select plan(4);

-- 1. anon cannot EXECUTE clip_track_for_user.
select ok(
  not has_function_privilege(
    'anon',
    'public.clip_track_for_user(uuid, jsonb)',
    'EXECUTE'
  ),
  'anon must NOT have EXECUTE on clip_track_for_user — '
    || 'clip-public-track EF uses service_role; anon access widens '
    || 'the privacy-zone residual risk'
);

-- 2. authenticated still CAN EXECUTE clip_track_for_user
--    (the EF authenticates via service_role today, but legitimate
--    in-DB callers that operate with a user JWT — none today, but
--    decisions §33 leaves room — still need access; preserve it).
select ok(
  has_function_privilege(
    'authenticated',
    'public.clip_track_for_user(uuid, jsonb)',
    'EXECUTE'
  ),
  'authenticated must still have EXECUTE on clip_track_for_user '
    || '(only the anon grant is the audit finding)'
);

-- 3. authenticated cannot EXECUTE auto_tag_default_gear.
select ok(
  not has_function_privilege(
    'authenticated',
    'public.auto_tag_default_gear()',
    'EXECUTE'
  ),
  'authenticated must NOT have EXECUTE on auto_tag_default_gear — '
    || 'trigger functions don''t need a user-facing grant'
);

-- 4. The trigger itself is still wired (revoke shouldn't affect
--    trigger execution because trigger contexts use the function
--    owner's privileges, not the invoking user's).
select ok(
  exists(
    select 1
      from pg_trigger
     where tgname = 'runs_auto_tag_default_gear'
       and not tgisinternal
  ),
  'runs_auto_tag_default_gear trigger must still exist after the revoke '
    || '(triggers fire on the table, not via a user-side grant)'
);

select * from finish();
rollback;
