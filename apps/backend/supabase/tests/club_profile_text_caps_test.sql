-- Pins migration 20270502_001 (club + profile text length caps, decisions §545).
--
-- Two layers:
--
--   1. Each of the four constraints exists AND is validated. `20261124_001`
--      added three NOT VALID caps and never emitted a VALIDATE, so its rows
--      stay permanently unchecked — a caps migration that repeats that is a
--      constraint in name only.
--   2. Functional probes on the two columns issue #666 C12 named: an
--      over-length write is rejected with 23514, and a legal write at exactly
--      the cap is accepted (so the cap is not off by one and the composer's own
--      limit is reachable).

begin;

select plan(12);

select is(
  (select count(*)::int
     from pg_constraint
     where conname in (
       'clubs_name_len_chk',
       'clubs_description_len_chk',
       'clubs_location_label_len_chk',
       'user_profiles_display_name_len_chk'
     )
       and contype = 'c'
       and convalidated),
  4,
  'all four length CHECKs exist and are VALIDATED, not left NOT VALID'
);

-- No role switch: a table constraint binds every writer, including the
-- service-role path that bypasses RLS. That is the point — the unbounded path
-- was a direct API write, not the composer.
insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values ('aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001', 'capstest@example.com', '',
        now(), '00000000-0000-0000-0000-000000000000', 'authenticated',
        'authenticated')
on conflict (id) do nothing;

select throws_ok(
  $$ insert into user_profiles (id, display_name)
     values ('aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001', repeat('n', 61)) $$,
  '23514',
  null,
  'a 61-character display_name is rejected'
);

select lives_ok(
  $$ insert into user_profiles (id, display_name)
     values ('aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001', repeat('n', 60)) $$,
  'a 60-character display_name — the composers'' own cap — is accepted'
);

select lives_ok(
  $$ update user_profiles set display_name = null
     where id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001' $$,
  'a null display_name is still allowed'
);

select throws_ok(
  $$ update user_profiles set display_name = repeat('n', 200)
     where id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001' $$,
  '23514',
  null,
  'an UPDATE past the cap is rejected too, not only an INSERT'
);

select throws_ok(
  $$ insert into clubs (owner_id, name, slug)
     values ('aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001', repeat('c', 81),
             'caps-long-name') $$,
  '23514',
  null,
  'an 81-character club name is rejected'
);

select throws_ok(
  $$ insert into clubs (owner_id, name, slug, description)
     values ('aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001', 'Caps Club',
             'caps-long-desc', repeat('d', 2001)) $$,
  '23514',
  null,
  'a 2001-character club description is rejected'
);

select throws_ok(
  $$ insert into clubs (owner_id, name, slug, location_label)
     values ('aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001', 'Caps Club',
             'caps-long-loc', repeat('l', 81)) $$,
  '23514',
  null,
  'an 81-character club location is rejected'
);

select lives_ok(
  $$ insert into clubs (id, owner_id, name, slug, description, location_label)
     values ('aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0002',
             'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001', repeat('c', 80),
             'caps-at-cap', repeat('d', 2000), repeat('l', 80)) $$,
  'a club at exactly every cap is accepted'
);

select lives_ok(
  $$ insert into clubs (id, owner_id, name, slug)
     values ('aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0003',
             'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001', 'Caps Nulls',
             'caps-nulls') $$,
  'a club with a null description and location is still allowed'
);

-- Population: the rows the accept-side probes wrote really are there, so a
-- lives_ok over a silently-skipped insert cannot pass for the wrong reason.
select is(
  (select char_length(description)
     from clubs where id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0002'),
  2000,
  'the at-cap club really stored its 2000-character description'
);

select is(
  (select char_length(display_name)
     from user_profiles where id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001'),
  null::int,
  'the display_name probe ended on the null it was last set to'
);

select * from finish();

rollback;
