-- Regression pin for 20261120_001_membership_oracles_private_schema.sql.
--
-- The four club/event membership oracles must NOT live in `public`
-- (where PostgREST would expose them as anon-callable RPC oracles) and
-- MUST live in `private` (which PostgREST does not expose). anon +
-- authenticated keep EXECUTE on the private versions so RLS policies
-- still evaluate; PUBLIC must not (the grant was tightened on the move).

begin;

select plan(16);

-- ─── gone from public (no PostgREST RPC oracle) ───────────────────
select hasnt_function(
  'public', 'is_club_member', ARRAY['uuid'],
  'is_club_member must not exist in public (PostgREST RPC oracle)'
);
select hasnt_function(
  'public', 'is_club_admin', ARRAY['uuid'],
  'is_club_admin must not exist in public'
);
select hasnt_function(
  'public', 'is_event_organiser', ARRAY['uuid'],
  'is_event_organiser must not exist in public'
);
select hasnt_function(
  'public', 'is_race_director', ARRAY['uuid'],
  'is_race_director must not exist in public'
);

-- ─── present in private ───────────────────────────────────────────
select has_function(
  'private', 'is_club_member', ARRAY['uuid'],
  'is_club_member must exist in private'
);
select has_function(
  'private', 'is_club_admin', ARRAY['uuid'],
  'is_club_admin must exist in private'
);
select has_function(
  'private', 'is_event_organiser', ARRAY['uuid'],
  'is_event_organiser must exist in private'
);
select has_function(
  'private', 'is_race_director', ARRAY['uuid'],
  'is_race_director must exist in private'
);

-- ─── RLS-evaluating roles retain EXECUTE on the private versions ──
select ok(
  has_function_privilege('anon', 'private.is_club_member(uuid)', 'EXECUTE'),
  'anon can EXECUTE private.is_club_member (RLS evaluation)'
);
select ok(
  has_function_privilege('authenticated', 'private.is_club_member(uuid)', 'EXECUTE'),
  'authenticated can EXECUTE private.is_club_member'
);
select ok(
  has_function_privilege('authenticated', 'private.is_club_admin(uuid)', 'EXECUTE'),
  'authenticated can EXECUTE private.is_club_admin'
);
select ok(
  has_function_privilege('authenticated', 'private.is_event_organiser(uuid)', 'EXECUTE'),
  'authenticated can EXECUTE private.is_event_organiser'
);
select ok(
  has_function_privilege('authenticated', 'private.is_race_director(uuid)', 'EXECUTE'),
  'authenticated can EXECUTE private.is_race_director'
);

-- ─── the qualified call still resolves + returns a boolean ────────
-- (false here — no auth.uid / no membership row — but it must execute,
-- not raise "function does not exist").
select is(
  private.is_club_member('00000000-0000-0000-0000-000000000000'::uuid),
  false,
  'private.is_club_member resolves and returns boolean'
);

-- ─── a SECURITY DEFINER caller still resolves the moved oracle ────
-- get_club_invite_token calls is_club_admin from search_path; it must
-- not raise "function is_club_admin does not exist". A non-admin caller
-- gets null (not an error) for a non-existent club.
select is(
  get_club_invite_token('00000000-0000-0000-0000-000000000000'::uuid),
  null,
  'get_club_invite_token resolves the moved oracle (no missing-function error)'
);

-- ─── PUBLIC no longer holds a blanket EXECUTE ─────────────────────
select ok(
  not has_function_privilege('public', 'private.is_club_member(uuid)', 'EXECUTE'),
  'PUBLIC does not hold EXECUTE on private.is_club_member'
);

select * from finish();
rollback;
