-- Caller guard for get_integration_tokens / set_integration_tokens.
--
-- These SECURITY DEFINER functions decrypt + return (and write) a user's
-- OAuth access/refresh tokens from vault.secrets, and are granted to
-- `authenticated` — so any logged-in user can invoke them for an arbitrary
-- p_user_id. The ONLY cross-user protection is the in-body role/owner gate;
-- a leak is third-party (Strava/Garmin) account takeover, not a stale list.
--
-- The gate regressed once already (20260919_001): the original body checked
-- only the legacy `request.jwt.claim.role` setting, which modern PostgREST no
-- longer populates, so the service-role delete-account deauthorize path got
-- "forbidden" and broke. This pins both halves so it can't silently re-break:
--   1. an authenticated user cannot read/write another user's tokens, and
--   2. service_role (via the MODERN jsonb `role` claim) can — the deauth path.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000fa01', 'authenticated', 'authenticated',
   'a@vault.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000fa02', 'authenticated', 'authenticated',
   'b@vault.local', '', now(), now());

-- Seed user B's tokens through the service-role path (also exercises the
-- vault.create_secret write side of set_integration_tokens).
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select set_integration_tokens(
  '00000000-0000-0000-0000-00000000fa02', 'strava', 'acc-B', 'ref-B',
  now() + interval '1 hour');

-- 1. Authenticated user A cannot READ user B's tokens (raise fires before any
--    vault access).
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000fa01","role":"authenticated"}';
select throws_ok(
  $$ select * from get_integration_tokens('00000000-0000-0000-0000-00000000fa02', 'strava') $$,
  'P0001',
  'forbidden: cannot read tokens for another user',
  'authenticated user cannot read another user''s OAuth tokens'
);

-- 2. Authenticated user A cannot WRITE user B's tokens.
select throws_ok(
  $$ select set_integration_tokens('00000000-0000-0000-0000-00000000fa02','strava','x','y',null) $$,
  'P0001',
  'forbidden: cannot write tokens for another user',
  'authenticated user cannot write another user''s OAuth tokens'
);

-- 3. Owner B reads their OWN decrypted tokens.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000fa02","role":"authenticated"}';
select results_eq(
  $$ select access_token, refresh_token
       from get_integration_tokens('00000000-0000-0000-0000-00000000fa02', 'strava') $$,
  $$ values ('acc-B'::text, 'ref-B'::text) $$,
  'owner reads their own decrypted tokens'
);

-- 4. service_role via the MODERN jsonb `role` claim (no legacy claim set) can
--    read any user's tokens — the delete-account deauthorize path. This is the
--    exact case that regressed in 20260919_001.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select results_eq(
  $$ select access_token
       from get_integration_tokens('00000000-0000-0000-0000-00000000fa02', 'strava') $$,
  $$ values ('acc-B'::text) $$,
  'service_role (modern jsonb claim) reads any user''s tokens'
);

-- 5. service_role can rotate any user's tokens in place.
select lives_ok(
  $$ select set_integration_tokens('00000000-0000-0000-0000-00000000fa02','strava',
       'acc-B2','ref-B2', now() + interval '2 hours') $$,
  'service_role can rotate any user''s tokens (token-refresh path)'
);

-- 6. The rotation took effect (secret updated in place, still one row).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000fa02","role":"authenticated"}';
select results_eq(
  $$ select access_token
       from get_integration_tokens('00000000-0000-0000-0000-00000000fa02', 'strava') $$,
  $$ values ('acc-B2'::text) $$,
  'the rotated access token is what a later read returns'
);

select * from finish();

rollback;
