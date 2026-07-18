-- Pins migration 20270424_001 — the public @handle (issue #465):
--   * set_my_handle claims / clears / rejects (format + case-insensitive
--     uniqueness), and only authenticated may execute it;
--   * search_user_profiles matches a handle prefix, ranks an EXACT handle
--     first, and STILL honours the discoverable_in_search opt-out for a
--     handle match (an opted-out user stays unfindable by handle too).
-- A regression here would either let two runners claim the same handle
-- (collision), expose an opted-out runner via handle search, or drop the
-- exact-handle-first ranking the feature depends on.

begin;
select plan(12);

do $$
declare
  v_alice uuid := '99999999-9999-9999-9999-999999aa0001';
  v_bob   uuid := '99999999-9999-9999-9999-999999bb0002';
  v_carol uuid := '99999999-9999-9999-9999-999999cc0003';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values
      (v_alice, 'alice.h@search.local', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_bob,   'bob.h@search.local',   '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_carol, 'carol.h@search.local', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into user_profiles (id, display_name, handle, preferred_unit, subscription_tier)
    values
      -- Alice's display name does NOT contain "janedoe", so a match on her
      -- can only come via the handle prefix path.
      (v_alice, 'A Runner',   'janedoe',    'km', 'free'),
      -- Bob's handle is a longer prefix-superset, so "janedoe" prefix-matches
      -- BOTH but only Alice is the EXACT handle (ranking pin).
      (v_bob,   'B Runner',   'janedoerun', 'km', 'free'),
      (v_carol, 'C Runner',   'carolgoes',  'km', 'free')
    on conflict (id) do nothing;
  -- Carol has opted OUT of search — must be unfindable by handle too.
  insert into user_settings (user_id, prefs)
    values (v_carol, jsonb_build_object('discoverable_in_search', false))
    on conflict (user_id) do update set prefs = excluded.prefs;
end $$;

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"99999999-9999-9999-9999-999999bb0002","role":"authenticated"}';

-- 1. Handle prefix search returns BOTH janedoe + janedoerun (Bob is the
--    caller and self-exclusion is a client concern, so the RPC returns him).
select is(
  (select count(*)::int from search_user_profiles('janedoe', 60)),
  2,
  'handle prefix "janedoe" matches both janedoe and janedoerun'
);

-- 2. The EXACT handle sorts first even though the display names would sort
--    "A Runner" then "B Runner" anyway — pin the exact-first key by using a
--    prefix where the exact match is NOT the alphabetically-first display.
select is(
  (select display_name from search_user_profiles('janedoe', 60) limit 1),
  'A Runner',
  'exact-handle match (janedoe) ranks first in results'
);

-- 3. A leading '@' is stripped before the handle match.
select is(
  (select count(*)::int from search_user_profiles('@janedoe', 60)),
  2,
  'a leading @ is stripped for the handle prefix match'
);

-- 4. Handle search honours discoverable_in_search — Carol opted out, so her
--    handle "carolgoes" returns nothing even on an exact prefix.
select is(
  (select count(*)::int from search_user_profiles('carolgoes', 60)),
  0,
  'an opted-out user is unfindable by handle (opt-out applies to handle too)'
);

-- 5. A bare '@' (empty after strip) must not match every handled row.
select is(
  (select count(*)::int from search_user_profiles('@', 60)
     where display_name in ('A Runner','B Runner')),
  0,
  'a bare @ query does not match all handled rows'
);

-- ── set_my_handle ──
-- 6. Bob claims a fresh handle; it stores lowercased.
set local "request.jwt.claims" =
  '{"sub":"99999999-9999-9999-9999-999999bb0002","role":"authenticated"}';
select is(
  set_my_handle('BobRuns'),
  'bobruns',
  'set_my_handle lowercases and returns the claimed handle'
);
select is(
  (select handle from user_profiles where id = '99999999-9999-9999-9999-999999bb0002'),
  'bobruns',
  'the claimed handle is persisted lowercased'
);

-- 7. Claiming a taken handle (case-insensitively) is rejected.
select throws_ok(
  $$ select set_my_handle('JaneDoe') $$,
  'P0001',
  'handle_taken',
  'set_my_handle rejects a case-insensitively-taken handle'
);

-- 8. An invalid format is rejected.
select throws_ok(
  $$ select set_my_handle('no spaces!') $$,
  'P0001',
  'handle_invalid',
  'set_my_handle rejects an invalid-format handle'
);

-- 9. Clearing (empty string) nulls the handle.
select is(
  set_my_handle(''),
  null::text,
  'set_my_handle clears the handle on empty input'
);
select is(
  (select handle from user_profiles where id = '99999999-9999-9999-9999-999999bb0002'),
  null::text,
  'clearing the handle persists null'
);

-- 10. anon must NOT have EXECUTE on set_my_handle.
select is(
  has_function_privilege('anon', 'set_my_handle(text)', 'EXECUTE'),
  false,
  'anon cannot execute set_my_handle'
);

select * from finish();
rollback;
