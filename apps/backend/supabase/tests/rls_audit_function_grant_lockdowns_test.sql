-- Pin the audit/rls (May 2026) revokes added by 20260914_002:
--
--   * clip_track_for_user(uuid, jsonb) must NOT be EXECUTE-able by anon
--     (the clip-public-track Edge Function uses service_role; anon
--     hitting the RPC directly widens the privacy-zone residual risk
--     beyond what decisions §33 documents) — nor, since 20270521_001,
--     by authenticated, for exactly the same reason (decisions §585).
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

-- 2. authenticated cannot EXECUTE clip_track_for_user either (20270521_001).
--    This assertion was inverted: it used to pin the grant, on the reasoning
--    that "legitimate in-DB callers that operate with a user JWT — none today,
--    but decisions §33 leaves room — still need access". The room was never
--    used, and the risk that justified the anon revoke applies unchanged to
--    authenticated: signup is free and unthrottled, so the role is not a trust
--    boundary against someone after a stranger's home address. The function
--    trims LEADING in-zone points, so a 3-point probe returns 2 inside a zone
--    and 3 outside — a one-bit oracle that binary-searches a zone centre to
--    metre precision in ~40 calls, with no Edge Function rate limit in the way
--    (it is a PostgREST RPC). The one direct client caller, web's
--    clipTrackForUser, had no production call sites left and was deleted with
--    this migration. Every remaining consumer (clip_route_for_viewer,
--    privacy_aware_route_geom, route_markers_for_viewer, the clip-public-track
--    EF) is SECURITY DEFINER or service-role. See decisions §585.
select ok(
  not has_function_privilege(
    'authenticated',
    'public.clip_track_for_user(uuid, jsonb)',
    'EXECUTE'
  ),
  'authenticated must NOT have EXECUTE on clip_track_for_user — '
    || 'the probe oracle that justified the anon revoke applies to any '
    || 'signed-in user too (decisions §585)'
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
