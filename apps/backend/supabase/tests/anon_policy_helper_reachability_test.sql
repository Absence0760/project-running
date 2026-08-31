-- The five functions decisions § 799 kept anon-executable because something
-- anon can already reach NAMES them, exercised through the thing that names
-- them.
--
-- A policy expression and a view body are privilege-checked against the
-- QUERYING role, not against their owner — § 746's trap, one object class over.
-- So a sweep that withheld `is_challenge_visible` would not merely hide a row:
-- an anonymous read of a public challenge's participants would raise `42501:
-- permission denied for function is_challenge_visible`, and the same for
-- `is_event_visible` on three event tables and the three `is_public_*_by_id`
-- helpers inside the two public views.
--
-- Two of the five are load-bearing and three are not, and the difference is
-- measured here rather than assumed. A POLICY expression is privilege-checked
-- against the querying role, so `is_challenge_visible` and `is_event_visible`
-- genuinely need anon's EXECUTE — withholding either turns a logged-out read
-- into a 42501, which the mutation below reproduces. A VIEW body is not, unless
-- the view is `security_invoker`: `public_runs` and `public_routes` are not, so
-- their three `is_public_*_by_id` calls are evaluated as the view's owner and
-- anon's grant on them is belt-and-braces. § 799's allowlist gives "named by
-- the public_runs view" as the reason to keep those three, which is true of the
-- reference and not of the privilege. The coupling is asserted at the end, so
-- flipping either view to `security_invoker` — a plausible hardening change —
-- cannot silently make three unneeded grants load-bearing without anything
-- saying so.
--
-- `anon_execute_contract_test` asserts the grants are held, which is the shape
-- of the rule. This asserts the surfaces answer, which is the rule's reason —
-- and the two fail differently: a blanket `revoke ... from public, anon` over
-- the schema leaves the contract test's allowlist entry stale (it fails, loudly
-- and correctly) while THIS file names the logged-out page that went dark.
--
-- Every read is issued as `anon` with no claims, which is what PostgREST does
-- for a request bearing the publishable key. Each is paired with a private
-- sibling the same read must NOT return, so a helper that started answering
-- `true` unconditionally is caught here too rather than read as health.

begin;
select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a0000000-0000-0000-0000-000000000f11', 'authenticated', 'authenticated',
   'apr-owner@anon.local', '', now(), now()),
  ('a0000000-0000-0000-0000-000000000f12', 'authenticated', 'authenticated',
   'apr-joiner@anon.local', '', now(), now());

insert into user_profiles (id, display_name, preferred_unit)
values ('a0000000-0000-0000-0000-000000000f11', 'Apr Owner', 'km'),
       ('a0000000-0000-0000-0000-000000000f12', 'Apr Joiner', 'km');

select tests.confirm_consent();

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('a0000000-0000-0000-0000-000000000f11', 'acct_apr_owner', true);

insert into clubs (id, owner_id, name, slug, is_public)
values ('a0000000-0000-0000-0000-000000000b11', 'a0000000-0000-0000-0000-000000000f11',
        'Apr Public Club', 'apr-public', true),
       ('a0000000-0000-0000-0000-000000000b12', 'a0000000-0000-0000-0000-000000000f11',
        'Apr Private Club', 'apr-private', false);

-- One public challenge and one private one, each with the same participant.
insert into challenges (id, creator_id, title, metric, scope, goal_value,
                        starts_at, ends_at, is_public)
values ('a0000000-0000-0000-0000-000000000c11', 'a0000000-0000-0000-0000-000000000f11',
        'Apr Public Challenge', 'distance', 'individual', 100000,
        now() - interval '1 day', now() + interval '30 days', true),
       ('a0000000-0000-0000-0000-000000000c12', 'a0000000-0000-0000-0000-000000000f11',
        'Apr Private Challenge', 'distance', 'individual', 100000,
        now() - interval '1 day', now() + interval '30 days', false);

insert into challenge_participants (challenge_id, user_id)
values ('a0000000-0000-0000-0000-000000000c11', 'a0000000-0000-0000-0000-000000000f12'),
       ('a0000000-0000-0000-0000-000000000c12', 'a0000000-0000-0000-0000-000000000f12');

-- A public event on the public club, and a private-club event nobody may see.
insert into events (id, club_id, title, starts_at, author_id, host_user_id, category)
values ('a0000000-0000-0000-0000-000000000e11', 'a0000000-0000-0000-0000-000000000b11',
        'Apr Public Event', '2026-07-01 18:00+00', 'a0000000-0000-0000-0000-000000000f11',
        'a0000000-0000-0000-0000-000000000f11', 'class'),
       ('a0000000-0000-0000-0000-000000000e12', 'a0000000-0000-0000-0000-000000000b12',
        'Apr Private Event', '2026-07-01 18:00+00', 'a0000000-0000-0000-0000-000000000f11',
        'a0000000-0000-0000-0000-000000000f11', 'class');

insert into event_checkpoints (id, event_id, name, ordinal, created_by)
values ('a0000000-0000-0000-0000-000000000cc1', 'a0000000-0000-0000-0000-000000000e11',
        'Apr Aid 1', 1, 'a0000000-0000-0000-0000-000000000f11'),
       ('a0000000-0000-0000-0000-000000000cc2', 'a0000000-0000-0000-0000-000000000e12',
        'Apr Hidden Aid', 1, 'a0000000-0000-0000-0000-000000000f11');

insert into event_pricing (event_id, price_cents, platform_fee_bps)
values ('a0000000-0000-0000-0000-000000000e11', 2200, 500),
       ('a0000000-0000-0000-0000-000000000e12', 3300, 500);

-- A public route on the public club and a private run on it, plus their
-- hidden siblings, for the two views.
insert into routes (id, user_id, name, waypoints, distance_m, is_public, club_id)
values ('a0000000-0000-0000-0000-000000000a11', 'a0000000-0000-0000-0000-000000000f11',
        'Apr Public Route', '[{"lat":40.0,"lng":-73.0},{"lat":40.01,"lng":-73.0}]',
        10000, true, 'a0000000-0000-0000-0000-000000000b11'),
       ('a0000000-0000-0000-0000-000000000a12', 'a0000000-0000-0000-0000-000000000f11',
        'Apr Private Route', '[{"lat":40.0,"lng":-73.0},{"lat":40.01,"lng":-73.0}]',
        10000, false, 'a0000000-0000-0000-0000-000000000b12');

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public,
                  route_id, metadata)
values ('a0000000-0000-0000-0000-000000000d11', 'a0000000-0000-0000-0000-000000000f11',
        now(), 10000, 3000, 'app', true, 'a0000000-0000-0000-0000-000000000a11',
        '{"activity_type":"run"}'),
       ('a0000000-0000-0000-0000-000000000d12', 'a0000000-0000-0000-0000-000000000f11',
        now(), 10000, 3000, 'app', false, 'a0000000-0000-0000-0000-000000000a12',
        '{"activity_type":"run"}');

-- ── as a logged-out reader ──────────────────────────────────────────────────
set local role anon;
set local "request.jwt.claims" = '';

-- Every read below dies at the GRANT rather than at the row filter if its
-- helper is withheld, and a refusal aborts the transaction. So the four
-- can-we-ask-at-all guards run first: a file that reported one of them and
-- then went quiet would name only the first surface that went dark.

select lives_ok(
  $$ select count(*) from challenge_participants
      where challenge_id = 'a0000000-0000-0000-0000-000000000c11' $$,
  'a logged-out reader can ask about a public challenge''s participants at all'
);

select lives_ok(
  $$ select count(*) from event_checkpoints
      where event_id = 'a0000000-0000-0000-0000-000000000e11' $$,
  'a logged-out reader can ask about a public event''s checkpoints at all'
);

select lives_ok(
  $$ select count(*) from public_runs
      where id = 'a0000000-0000-0000-0000-000000000d11' $$,
  'a logged-out reader can query the public_runs view at all'
);

select lives_ok(
  $$ select count(*) from public_routes
      where id = 'a0000000-0000-0000-0000-000000000a11' $$,
  'a logged-out reader can query the public_routes view at all'
);

-- is_challenge_visible: § 799 measured this one both ways before deciding to
-- keep the grant, because withholding turns the read into a 42501 rather than
-- into an empty result.
select is(
  (select count(*)::int from challenge_participants
    where challenge_id = 'a0000000-0000-0000-0000-000000000c11'),
  1,
  'and gets the participant back'
);

select is(
  (select count(*)::int from challenge_participants
    where challenge_id = 'a0000000-0000-0000-0000-000000000c12'),
  0,
  'a private challenge''s participants stay invisible to a logged-out reader'
);

-- is_event_visible, named by three SELECT policies `to public`.
select is(
  (select count(*)::int from event_checkpoints
    where event_id = 'a0000000-0000-0000-0000-000000000e11'),
  1,
  'and gets the checkpoint back'
);

select is(
  (select count(*)::int from event_checkpoints
    where event_id = 'a0000000-0000-0000-0000-000000000e12'),
  0,
  'a private club''s event checkpoints are not exposed to a logged-out reader'
);

select is(
  (select count(*)::int from event_pricing
    where event_id = 'a0000000-0000-0000-0000-000000000e11'),
  1,
  'the public event''s price is readable logged out'
);

select is(
  (select count(*)::int from event_pricing
    where event_id = 'a0000000-0000-0000-0000-000000000e12'),
  0,
  'the private event''s price is not readable logged out'
);

-- is_public_route_by_id + is_public_event_by_id, named by the public_runs view.
select is(
  (select count(*)::int from public_runs
    where id = 'a0000000-0000-0000-0000-000000000d11'),
  1,
  'and the public run is in it'
);

-- is_public_club_by_id, named by the public_routes view.
select is(
  (select count(*)::int from public_routes
    where id = 'a0000000-0000-0000-0000-000000000a12'),
  0,
  'the private route is absent from the public view'
);

-- ── which of the five grants the surfaces actually depend on ───────────────
reset role;

select is(
  (select count(*)::int
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    where c.relname in ('public_runs', 'public_routes')
      and coalesce(array_to_string(c.reloptions, ','), '') like '%security_invoker=true%'),
  0,
  'the two public views run as their owner, so their is_public_*_by_id calls '
  'are not privilege-checked against anon'
);

-- The policies are the other half, and they are the half that IS checked
-- against the caller. Both are `to public`, which is what puts an anonymous
-- reader inside them at all.
select is(
  (select count(*)::int
     from pg_policy p
     join pg_class c on c.oid = p.polrelid
    where c.relname in ('challenge_participants', 'event_checkpoints',
                        'event_pricing', 'checkpoint_crossings')
      and p.polcmd in ('r', '*')
      and p.polroles = '{0}'::oid[]
      and pg_get_expr(p.polqual, p.polrelid) ~ 'is_(challenge|event)_visible'),
  4,
  'four SELECT policies to public name a visibility helper, which is why those '
  'two grants are load-bearing where the view''s three are not'
);

select * from finish();
rollback;
