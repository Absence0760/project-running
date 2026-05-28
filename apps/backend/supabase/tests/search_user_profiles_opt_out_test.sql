-- Pins migration 20261015_001 — search_user_profiles SECURITY DEFINER
-- RPC + discoverable_in_search opt-out pref.
--
-- Persona-hunt Round 3 finding Woman #2. A regression here would
-- mean a runner who flipped the opt-out pref still surfaced in
-- the People-tab search — exposing them to the kind of low-effort
-- name-based stalking the pref was introduced to defend against.

begin;
select plan(7);

do $$
declare
  v_alice uuid := '99999999-9999-9999-9999-999999aaaaaa';
  v_bob   uuid := '99999999-9999-9999-9999-999999bbbbbb';
  v_carol uuid := '99999999-9999-9999-9999-999999cccccc';
  v_dan   uuid := '99999999-9999-9999-9999-999999dddddd';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values
      (v_alice, 'alice@search.local', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_bob,   'bob@search.local',   '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_carol, 'carol@search.local', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_dan,   'dan@search.local',   '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into user_profiles (id, display_name, preferred_unit, subscription_tier)
    values
      (v_alice, 'Alice Searcher', 'km', 'free'),
      (v_bob,   'Bob Searcher',   'km', 'free'),
      (v_carol, 'Carol Searcher', 'km', 'free'),
      (v_dan,   'Dan Other',      'km', 'free')
    on conflict (id) do nothing;
  -- Bob has opted out via the new pref.
  insert into user_settings (user_id, prefs)
    values (v_bob, jsonb_build_object('discoverable_in_search', false))
    on conflict (user_id) do update
      set prefs = excluded.prefs;
  -- Carol has user_settings with prefs but no opt-out key (default
  -- discoverable). Tests the COALESCE default-true branch.
  insert into user_settings (user_id, prefs)
    values (v_carol, jsonb_build_object('preferred_unit', 'mi'))
    on conflict (user_id) do update
      set prefs = excluded.prefs;
  -- Alice has no user_settings row at all. Tests the LEFT JOIN
  -- null-prefs branch.
  -- Dan exists but his name doesn't match "Searcher" — tests that
  -- the ILIKE filter still gates results.
end $$;

-- All RPC calls run as an authenticated user (Dan, an outside viewer).
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"99999999-9999-9999-9999-999999dddddd","role":"authenticated"}';

-- 1. Sanity: searching "Searcher" returns Alice + Carol (opted-in by
--    default) but NOT Bob (opted out via discoverable_in_search=false).
select results_eq(
  $$ select display_name from search_user_profiles('Searcher', 60)
      order by display_name $$,
  $$ values ('Alice Searcher'::text), ('Carol Searcher'::text) $$,
  'search_user_profiles excludes opted-out users from results'
);

-- 2. Result count drops by exactly 1 when Bob opts out — count-based
--    pin so a regression that flipped the polarity of the filter
--    would surface a row count of 1 (instead of 2) or 3 (if the
--    filter were skipped entirely).
select is(
  (select count(*)::int from search_user_profiles('Searcher', 60)),
  2,
  'search returns 2 opted-in users (Alice + Carol) — Bob filtered out'
);

-- 3. ILIKE filter still works — query targeting Dan returns Dan,
--    confirming the opt-out filter doesn't accidentally exclude
--    users with no opt-out pref.
select results_eq(
  $$ select display_name from search_user_profiles('Other', 60) $$,
  $$ values ('Dan Other'::text) $$,
  'search_user_profiles ILIKE filter is preserved'
);

-- 4. The opt-out key value "true" (explicit-discoverable) does not
--    accidentally filter the row. Flip Bob's opt-out to "true"
--    and verify he comes back.
set local role postgres;
update user_settings
  set prefs = jsonb_build_object('discoverable_in_search', true)
  where user_id = '99999999-9999-9999-9999-999999bbbbbb';
set local role authenticated;
select is(
  (select count(*)::int from search_user_profiles('Searcher', 60)
    where display_name = 'Bob Searcher'),
  1,
  'opting back IN (discoverable_in_search=true) restores Bob to search results'
);

-- 5. The limit cap is enforced (not bypassable by a huge int).
--    Pass 999999 → cap at 200. Hard to assert directly without 200+
--    fixtures; instead pass a small limit and verify it's honoured.
select is(
  (select count(*)::int from search_user_profiles('Searcher', 1)),
  1,
  'search_user_profiles honours the p_limit cap'
);

-- 6. anon must NOT have EXECUTE — only authenticated viewers can
--    enumerate the search surface. Anon paths use the share-page
--    + public_profile_by_id contract for known-uuid lookups.
select is(
  has_function_privilege(
    'anon',
    'search_user_profiles(text, int)',
    'EXECUTE'
  ),
  false,
  'anon does not have EXECUTE on search_user_profiles'
);

-- 7. authenticated DOES have EXECUTE — the People tab must work for
--    signed-in users.
select is(
  has_function_privilege(
    'authenticated',
    'search_user_profiles(text, int)',
    'EXECUTE'
  ),
  true,
  'authenticated has EXECUTE on search_user_profiles'
);

select * from finish();
rollback;
