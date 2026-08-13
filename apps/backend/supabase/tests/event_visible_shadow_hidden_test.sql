-- Pins migration 20270524_001 on `is_event_visible` + `claim_event_result`:
-- two SECURITY DEFINER bodies that pasted the events visibility predicate and
-- so never received the shadow-hidden gate the events RLS policy got in
-- 20270328_001.
--
-- `is_event_visible` is the oracle behind the `event_pricing`,
-- `event_checkpoints` and `checkpoint_crossings` SELECT policies, so the stale
-- copy kept a moderation-hidden club's pricing, checkpoints and runner
-- crossing times readable through base tables the events policy had already
-- closed.
--
--   1. A stranger cannot see a hidden club's event, and the child rows the
--      oracle gates go with it.
--   2. The club's owner and its active members still can — only the
--      club-public branch moved.
--   3. An ordinary public club's event is untouched.
--   4. claim_event_result's inline mirror of the same predicate refuses a
--      stranger on a hidden club's event.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000fd001', 'authenticated', 'authenticated',
   'owner@evb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000fd002', 'authenticated', 'authenticated',
   'member@evb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000fd003', 'authenticated', 'authenticated',
   'stranger@evb.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000fd001', 'Club Owner'),
  ('00000000-0000-0000-0000-0000000fd002', 'Club Member'),
  ('00000000-0000-0000-0000-0000000fd003', 'Stranger');

select tests.confirm_consent();

-- One moderation-hidden public club and one ordinary public club, same owner.
insert into clubs (id, owner_id, name, slug, is_public, shadow_hidden)
values
  ('cdcdcdcd-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000fd001',
   'Hidden CC', 'hidden-cc', true, true),
  ('cdcdcdcd-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000fd001',
   'Open CC', 'open-cc', true, false);
-- Owner membership rows come from the club-insert trigger.
insert into club_members (club_id, user_id, role, status)
values ('cdcdcdcd-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000fd002', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id, is_public)
values
  ('eeeeeeee-0000-0000-0000-0000000000d1', 'cdcdcdcd-0000-0000-0000-0000000000d1',
   'Hidden Club Race', now() + interval '7 days', '00000000-0000-0000-0000-0000000fd001', true),
  ('eeeeeeee-0000-0000-0000-0000000000d2', 'cdcdcdcd-0000-0000-0000-0000000000d2',
   'Open Club Race', now() + interval '7 days', '00000000-0000-0000-0000-0000000fd001', true);

-- A child row whose SELECT policy leans on the oracle.
insert into event_checkpoints (event_id, name, ordinal, created_by)
values ('eeeeeeee-0000-0000-0000-0000000000d1', 'Aid 1', 1,
        '00000000-0000-0000-0000-0000000fd001');

-- An unclaimed result on the hidden club's event, for the claim path.
insert into event_results (id, event_id, instance_start, user_id, bib, finisher_name,
                           duration_s, distance_m)
values ('efefefef-0000-0000-0000-0000000000d1', 'eeeeeeee-0000-0000-0000-0000000000d1',
        now() - interval '7 days', null, '101', 'Unclaimed Finisher', 3600, 10000);

set local role authenticated;

-- ── 1-3. Read as a stranger ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fd003"}';

select is(
  is_event_visible('eeeeeeee-0000-0000-0000-0000000000d1'::uuid),
  false,
  'a stranger cannot see an event of a shadow-hidden club'
);

-- The oracle is what the event_checkpoints policy leans on, so the child rows
-- it was keeping readable close with it.
select is(
  (select count(*)::int from event_checkpoints
     where event_id = 'eeeeeeee-0000-0000-0000-0000000000d1'),
  0,
  'the hidden club''s event checkpoints go with the oracle'
);

select is(
  is_event_visible('eeeeeeee-0000-0000-0000-0000000000d2'::uuid),
  true,
  'an ordinary public club''s event is untouched'
);

-- 4. The claim path pastes the same predicate; it must refuse too.
select throws_ok(
  $$ select claim_event_result('efefefef-0000-0000-0000-0000000000d1'::uuid) $$,
  'Not authorised to claim this result',
  'claim_event_result refuses a stranger on a hidden club''s event'
);

-- ── 5-6. The club's own people are unaffected ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fd001"}';
select is(
  is_event_visible('eeeeeeee-0000-0000-0000-0000000000d1'::uuid),
  true,
  'the hidden club''s owner still sees its events (soft-hide, not deletion)'
);

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fd002"}';
select is(
  is_event_visible('eeeeeeee-0000-0000-0000-0000000000d1'::uuid),
  true,
  'an active member of the hidden club still sees its events'
);

select * from finish();
rollback;
