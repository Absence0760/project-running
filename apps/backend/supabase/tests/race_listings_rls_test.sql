-- RLS + integrity for race_listings (migration 20270214_001).
-- A race calendar is public-read; authenticated users may submit a listing but
-- can't self-verify (the force_unverified trigger forces is_verified=false on a
-- non-service-role write); a submitter may edit only their own UNVERIFIED
-- listing; the entry/results URLs must be http(s).

begin;

select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000ddc01', 'authenticated', 'authenticated',
   'submitter@races.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ddc02', 'authenticated', 'authenticated',
   'other@races.local', '', now(), now());

-- A service-role verified listing (the import / admin path).
set local role service_role;
insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, is_verified)
values ('11111111-1111-1111-1111-1111000ddc01', 'runsignup', 'rs-9001',
        'Verified City Marathon', current_date + 30, 42195, true);
select is(
  (select is_verified from race_listings where id = '11111111-1111-1111-1111-1111000ddc01'),
  true,
  'service_role may set is_verified=true'
);

-- ── submitter context ──────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ddc01","role":"authenticated"}';

-- 2. anon/authenticated read sees the public calendar.
select is(
  (select count(*)::int from race_listings),
  1,
  'authenticated user reads the public race calendar'
);

-- 3. A user may submit a listing.
insert into race_listings (id, provider, name, race_date, submitted_by)
values ('11111111-1111-1111-1111-1111000ddc02', 'manual', 'My Local 5K',
        current_date + 14, '00000000-0000-0000-0000-0000000ddc01');
select pass('user submits a manual listing');

-- 4. Self-submitted listing is forced unverified even if the user tries true.
insert into race_listings (id, provider, name, race_date, submitted_by, is_verified)
values ('11111111-1111-1111-1111-1111000ddc03', 'manual', 'Sneaky Verified Race',
        current_date + 21, '00000000-0000-0000-0000-0000000ddc01', true);
select is(
  (select is_verified from race_listings where id = '11111111-1111-1111-1111-1111000ddc03'),
  false,
  'a user INSERT cannot self-verify (trigger forces is_verified=false)'
);

-- 5. Submitter may edit their own unverified listing.
update race_listings set name = 'My Local 5K (updated)'
  where id = '11111111-1111-1111-1111-1111000ddc02';
select is(
  (select name from race_listings where id = '11111111-1111-1111-1111-1111000ddc02'),
  'My Local 5K (updated)',
  'submitter edits own unverified listing'
);

-- 6. A user cannot flip is_verified on their own listing via UPDATE.
update race_listings set is_verified = true
  where id = '11111111-1111-1111-1111-1111000ddc02';
select is(
  (select is_verified from race_listings where id = '11111111-1111-1111-1111-1111000ddc02'),
  false,
  'a user UPDATE cannot forge is_verified=true (trigger re-forces false)'
);

-- 7. A user cannot edit someone else's listing (the verified one is service-owned).
update race_listings set name = 'Hijacked'
  where id = '11111111-1111-1111-1111-1111000ddc01';
select is(
  (select name from race_listings where id = '11111111-1111-1111-1111-1111000ddc01'),
  'Verified City Marathon',
  'a user cannot edit a verified listing they did not submit'
);

-- 8. A javascript: entry_url is rejected by the scheme CHECK.
select throws_ok(
  $$ insert into race_listings (provider, name, race_date, submitted_by, entry_url)
     values ('manual', 'Bad URL Race', current_date + 5,
             '00000000-0000-0000-0000-0000000ddc01', 'javascript:alert(1)') $$,
  '23514',
  null,
  'javascript: entry_url is rejected by the scheme CHECK'
);

-- 9. A submitted_by mismatch is blocked by the INSERT policy.
select throws_ok(
  $$ insert into race_listings (provider, name, race_date, submitted_by)
     values ('manual', 'Forged Owner Race', current_date + 6,
             '00000000-0000-0000-0000-0000000ddc02') $$,
  '42501',
  null,
  'a user cannot submit a listing attributed to another user'
);

-- 10. An invalid provider value is rejected by the provider CHECK.
set local role service_role;
select throws_ok(
  $$ insert into race_listings (provider, name, race_date)
     values ('garmin', 'Wrong Provider Race', current_date + 7) $$,
  '23514',
  null,
  'an out-of-union provider is rejected by the CHECK'
);

select * from finish();

rollback;
