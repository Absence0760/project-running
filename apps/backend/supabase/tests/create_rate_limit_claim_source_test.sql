-- WHICH claim `enforce_create_rate_limit` reads to decide a caller is the
-- service role (migration 20270629000001).
--
-- 20260907_001 wrote the function reading only `request.jwt.claim.role`, the
-- per-claim setting current PostgREST stopped writing, so `v_role` was the
-- empty string on every deployment and skip 1 was dead code for two years.
-- Skip 2 covered the same callers by accident — a service-role JWT usually
-- carries no `sub`, so `auth.uid()` is null and the next line returns — which
-- is exactly why nobody noticed.
--
-- `create_rate_limits_test` and `direct_message_rate_limit_test` both assert
-- the skip fires, and neither can tell which mechanism fired it: each sets
-- `set local role service_role` AND a `role` key in the JSON blob in the same
-- breath, so an implementation reading `current_user`, or one reading only the
-- legacy setting, or one reading only the blob, passes all three identically.
--
-- This file separates the three sources and drives each one alone, on a bucket
-- that is already spent — so an assertion that the insert LANDS is a statement
-- about the skip rather than about the window having room.
--
-- The fail-closed direction is assertion (3) and it is the one that matters:
-- a session whose ROLE is service_role but whose JWT does not say so is
-- throttled. A service-role caller acting for a named user — which is what
-- skip 1's own comment describes — must be recognised by its claim, because
-- the claim is what PostgREST derives from the key that was presented.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('c1000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
        'claim-source@rl.local', '', now(), now());

select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1000000-0000-0000-0000-0000000000a1"}';

-- Spend the create_club window: the cap is 5/hour.
do $spend$
declare i int;
begin
  for i in 1..5 loop
    insert into clubs (owner_id, name, slug, is_public, join_policy)
      values ('c1000000-0000-0000-0000-0000000000a1',
              'Claim Source ' || i, 'cs-club-' || i, true, 'open');
  end loop;
end
$spend$;

-- (1) The window really is spent. Every "it landed" below is measured against
-- this, so without it they would all be statements about an empty bucket.
select throws_matching(
  $$ insert into clubs (owner_id, name, slug, is_public, join_policy)
       values ('c1000000-0000-0000-0000-0000000000a1',
               'Claim Source 6', 'cs-club-6', true, 'open') $$,
  '^rate limit exceeded for create_club, retry in [0-9]+s$',
  'the create_club window is spent for this user');

-- (2) The JSON blob alone, with the legacy setting explicitly empty. This is
-- the shape every current PostgREST deployment presents, and the one the
-- function was blind to until 20270629000001.
select set_config('request.jwt.claim.role', '', true);
set local "request.jwt.claims" =
  '{"sub":"c1000000-0000-0000-0000-0000000000a1","role":"service_role"}';

select lives_ok(
  $$ insert into clubs (owner_id, name, slug, is_public, join_policy)
       values ('c1000000-0000-0000-0000-0000000000a1',
               'Blob Claim', 'cs-club-blob', true, 'open') $$,
  'a service_role claim in the JSON blob skips a spent window — the arm 20260907_001 could not see');

-- (3) The fail-closed control. The SESSION role is service_role, and the JWT
-- does not say so. The skip must not fire: PostgREST derives the claim from
-- the key that was presented, so the claim is the evidence and the session
-- role is not.
set local role service_role;
select set_config('request.jwt.claim.role', '', true);
set local "request.jwt.claims" = '{"sub":"c1000000-0000-0000-0000-0000000000a1"}';

select throws_matching(
  $$ insert into clubs (owner_id, name, slug, is_public, join_policy)
       values ('c1000000-0000-0000-0000-0000000000a1',
               'Session Only', 'cs-club-session', true, 'open') $$,
  '^rate limit exceeded for create_club, retry in [0-9]+s$',
  'a session running AS service_role but carrying no role claim is still throttled — the skip reads the claim, not current_user');

-- (4) The legacy per-claim setting alone, under a plain `authenticated`
-- session. A deployment still writing it keeps working.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1000000-0000-0000-0000-0000000000a1"}';
select set_config('request.jwt.claim.role', 'service_role', true);

select lives_ok(
  $$ insert into clubs (owner_id, name, slug, is_public, join_policy)
       values ('c1000000-0000-0000-0000-0000000000a1',
               'Legacy Claim', 'cs-club-legacy', true, 'open') $$,
  'the legacy per-claim setting alone still skips a spent window — the coalesces first arm');

-- (5) A role claim naming something else is not a skip. Without this, an
-- implementation that skipped on ANY non-empty role claim would pass (2) and
-- (4) and be wide open.
select set_config('request.jwt.claim.role', '', true);
set local "request.jwt.claims" =
  '{"sub":"c1000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_matching(
  $$ insert into clubs (owner_id, name, slug, is_public, join_policy)
       values ('c1000000-0000-0000-0000-0000000000a1',
               'Wrong Claim', 'cs-club-wrong', true, 'open') $$,
  '^rate limit exceeded for create_club, retry in [0-9]+s$',
  'a role claim that is not service_role is not a skip');

-- (6) An unparseable claims blob fails the write rather than the check. The
-- `::jsonb` cast is unguarded, so a malformed blob aborts the INSERT with
-- 22P02 — the fail-CLOSED direction, and the one worth pinning: a body that
-- swallowed the parse error would fall through to `v_role = ''` and hand the
-- caller whatever the remaining skips allow.
set local "request.jwt.claims" = 'not json';

select throws_ok(
  $$ insert into clubs (owner_id, name, slug, is_public, join_policy)
       values ('c1000000-0000-0000-0000-0000000000a1',
               'Bad Blob', 'cs-club-bad', true, 'open') $$,
  '22P02',
  null,
  'an unparseable claims blob aborts the write rather than resolving to no role');

select * from finish();

rollback;
