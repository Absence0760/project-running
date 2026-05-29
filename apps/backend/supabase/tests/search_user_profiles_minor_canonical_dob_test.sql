-- Pins migration 20261104_001 -- the minor-discoverability floor must read
-- the canonical user_profiles.date_of_birth column, not only the prefs bag.
--
-- Regression target: a declared minor whose DOB lives in
-- user_profiles.date_of_birth (the always-written column) but NOT in
-- user_settings.prefs (the inconsistently-mirrored bag) used to stay
-- name-searchable -- a fail-open child-safety hole. These cases would FAIL
-- against 20261017_001 and pass against 20261104_001.
begin;
select plan(6);

do $$
declare
  v_viewer   uuid := '99999999-9999-9999-9999-99999cd00001';  -- outside searcher
  v_colkid   uuid := '99999999-9999-9999-9999-99999cd00002';  -- minor: DOB in column only
  v_coladult uuid := '99999999-9999-9999-9999-99999cd00003';  -- adult: DOB in column only
  v_prefskid uuid := '99999999-9999-9999-9999-99999cd00004';  -- minor: DOB in prefs only (legacy)
  v_edgekid  uuid := '99999999-9999-9999-9999-99999cd00005';  -- exactly-18-minus-1-day: minor
  v_exact18  uuid := '99999999-9999-9999-9999-99999cd00006';  -- exactly 18 today: adult
begin
  insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                          instance_id, aud, role)
    values
      (v_viewer,   'viewer@cdob.local',   '', now(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_colkid,   'colkid@cdob.local',   '', now(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_coladult, 'coladult@cdob.local', '', now(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_prefskid, 'prefskid@cdob.local', '', now(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_edgekid,  'edgekid@cdob.local',  '', now(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_exact18,  'exact18@cdob.local',  '', now(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;

  -- DOB on the canonical column. colkid is ~10y old, coladult ~40y.
  insert into user_profiles (id, display_name, preferred_unit, subscription_tier, date_of_birth)
    values
      (v_viewer,   'Viewer Cdob',   'km', 'free', null),
      (v_colkid,   'Colkid Cdob',   'km', 'free', (current_date - interval '10 years')::date),
      (v_coladult, 'Coladult Cdob', 'km', 'free', (current_date - interval '40 years')::date),
      (v_prefskid, 'Prefskid Cdob', 'km', 'free', null),
      -- One day short of 18 -> still a minor.
      (v_edgekid,  'Edgekid Cdob',  'km', 'free', (current_date - interval '18 years' + interval '1 day')::date),
      -- Exactly 18 today -> adult (strict `>` boundary).
      (v_exact18,  'Exact18 Cdob',  'km', 'free', (current_date - interval '18 years')::date)
    on conflict (id) do update set date_of_birth = excluded.date_of_birth;

  -- prefskid: DOB only in the prefs bag (legacy mirror), nothing on the column.
  insert into user_settings (user_id, prefs)
    values (v_prefskid, jsonb_build_object('date_of_birth',
              to_char(current_date - interval '9 years', 'YYYY-MM-DD')))
    on conflict (user_id) do update set prefs = excluded.prefs;
  -- colkid/coladult deliberately have NO user_settings row -> prefs is NULL
  -- via LEFT JOIN, so only the canonical column can exclude them.
end $$;

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"99999999-9999-9999-9999-99999cd00001","role":"authenticated"}';

-- 1. THE BUG: minor with DOB only on the canonical column is excluded.
select is(
  (select count(*)::int from search_user_profiles('Cdob', 60)
    where display_name = 'Colkid Cdob'),
  0,
  'a minor with DOB only in user_profiles.date_of_birth is excluded from search');

-- 2. Adult with DOB only on the canonical column is still returned.
select is(
  (select count(*)::int from search_user_profiles('Cdob', 60)
    where display_name = 'Coladult Cdob'),
  1,
  'an adult with DOB only on the canonical column is still discoverable');

-- 3. Legacy fallback: minor with DOB only in prefs is still excluded.
select is(
  (select count(*)::int from search_user_profiles('Cdob', 60)
    where display_name = 'Prefskid Cdob'),
  0,
  'the prefs-bag DOB fallback still excludes a legacy-mirror minor');

-- 4. Off-by-one boundary: one day short of 18 is a minor (excluded).
select is(
  (select count(*)::int from search_user_profiles('Cdob', 60)
    where display_name = 'Edgekid Cdob'),
  0,
  'a runner one day short of 18 is still a minor and is excluded');

-- 5. Boundary: exactly 18 today is an adult (strict `>` -> not excluded).
select is(
  (select count(*)::int from search_user_profiles('Cdob', 60)
    where display_name = 'Exact18 Cdob'),
  1,
  'a runner who turns exactly 18 today is an adult and is discoverable');

-- 6. Net: of the 6 "Cdob" accounts, only the viewer + the adult + the
--    exactly-18 account surface (3); the three minors are all filtered.
select is(
  (select count(*)::int from search_user_profiles('Cdob', 60)),
  3,
  'only the non-minor Cdob accounts surface (viewer + adult + exactly-18)');

select * from finish();
rollback;
