-- pgtap suite for `gym_routine_history` (migration 20270528_001).
--
-- The RPC replaces a 500-row client window over gym_workouts with a server-side
-- aggregate, so the panel's session count stops capping at a number nothing in
-- the UI states. These assertions pin the count past the PostgREST `db.max-rows`
-- ceiling and the two exclusions that ARE the contract (mirrored in
-- gym/routine_history.ts ↔ routine_history.dart, decisions § 617).
--
-- Covers:
--   * a routine with more sessions than the PostgREST cap reports the TRUE count
--   * an in-flight `gym_session_draft` row is excluded from count AND page
--   * a NON-object under that key is not a draft — the exclusion is
--     `jsonb_typeof(...) = 'object'`, matched by Dart's `is Map` and web's
--     `hasSessionDraft`, so an array there leaves the row a session performed
--   * a "save as is" row counts as a session but not in the graded denominator
--   * last_performed_at is the max over every session, not over the page
--   * the recent page is newest-first and honours p_recent_limit (incl. the clamp)
--   * another routine's sessions never leak in
--   * RLS — a caller cannot aggregate another user's sessions, not even public ones

begin;

select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000b0001'::uuid, 'authenticated', 'authenticated',
   'lifter@routinehistory.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000b0099'::uuid, 'authenticated', 'authenticated',
   'stranger@routinehistory.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000b0001', 'Lifter'),
  ('00000000-0000-0000-0000-0000000b0099', 'Stranger');

-- Synthetic fixture users stand in for signed-up accounts, which always
-- carry the GDPR Art 8 stamp before they can write (20270424000004).
select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b0001"}';

insert into gym_routines (id, author_id, title, exercise_count)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', '00000000-0000-0000-0000-0000000b0001', 'Push A', 3),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02', '00000000-0000-0000-0000-0000000b0001', 'Pull B', 3);

-- 1200 graded sessions of Push A — deliberately past both the 500-row client
-- window this RPC replaces and PostgREST's 1000-row db.max-rows ceiling. 900
-- completed, 300 partial, so the completed-of-graded ratio is 0.75.
insert into gym_workouts (user_id, title, started_at, metadata)
select
  '00000000-0000-0000-0000-0000000b0001',
  'Push A ' || i,
  timestamptz '2026-01-01 08:00:00+00' + (i || ' hours')::interval,
  jsonb_build_object(
    'routine_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01',
    'gym_adherence', case when i % 4 = 0 then 'partial' else 'completed' end
  )
from generate_series(1, 1200) as i;

-- 1. The count is the true total, not the old 500-row window.
select is(
  (select session_count from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01')),
  1200,
  'session_count reports every session, past the 500-row window and the PostgREST cap'
);

-- 2. The graded tallies are complete too.
select is(
  (select graded_count || '/' || completed_count
     from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01')),
  '1200/900',
  'graded + completed tallies are aggregated over every session'
);

-- 3. last_performed_at is the max over all sessions (the 1200th, not the page's).
select is(
  (select last_performed_at from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01')),
  timestamptz '2026-01-01 08:00:00+00' + interval '1200 hours',
  'last_performed_at is the max over every session'
);

-- 4. The default page is 5 rows, newest first.
select is(
  (select jsonb_array_length(recent_sessions)
     from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01')),
  5,
  'the recent page defaults to 5 rows, not to everything'
);

select is(
  (select (recent_sessions -> 0 ->> 'title')
     from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01')),
  'Push A 1200',
  'the recent page is ordered newest first'
);

-- 5. p_recent_limit is honoured, and clamped so a caller cannot re-open the
--    unbounded read the RPC exists to close.
select is(
  (select jsonb_array_length(recent_sessions)
     from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', 3)),
  3,
  'p_recent_limit bounds the page'
);

select is(
  (select jsonb_array_length(recent_sessions)
     from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', 5000)),
  50,
  'p_recent_limit is clamped at 50 — an unbounded page is what this RPC replaces'
);

-- An in-flight draft, stamped LATER than every performed session, plus a
-- "save as is" row that kept routine_id but claims no adherence verdict.
insert into gym_workouts (id, user_id, title, started_at, metadata)
values
  ('cccccccc-cccc-cccc-cccc-ccccccccccc1',
   '00000000-0000-0000-0000-0000000b0001', 'In flight',
   timestamptz '2026-06-01 08:00:00+00',
   jsonb_build_object(
     'routine_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01',
     'gym_session_draft', jsonb_build_object('saved_at', '2026-06-01T08:05:00Z', 'results', '[]'::jsonb)
   )),
  ('cccccccc-cccc-cccc-cccc-ccccccccccc2',
   '00000000-0000-0000-0000-0000000b0001', 'Saved as is',
   timestamptz '2026-05-01 08:00:00+00',
   jsonb_build_object('routine_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01'));

-- 6. The draft is not a session performed — a resume must not inflate usage.
select is(
  (select session_count from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01')),
  1201,
  'an in-flight gym_session_draft row is excluded from the count'
);

-- 7. …and it never reaches the page either, despite being the newest row.
select is(
  (select (recent_sessions -> 0 ->> 'title')
     from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01')),
  'Saved as is',
  'the draft row is excluded from the recent page, so page and count agree'
);

-- 8. The save-as-is row counted as a session but stayed out of the denominator.
select is(
  (select graded_count || '/' || completed_count
     from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01')),
  '1200/900',
  'a save-as-is row counts as a session but sits outside the graded denominator'
);

-- 9. Another routine's sessions do not leak in.
select is(
  (select session_count from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02')),
  0,
  'a routine that has never been run reports zero, not the sibling routine''s sessions'
);

-- 9b. A marker that is not a JSON OBJECT is not a draft. `typeof x === 'object'`
--     is true for an array in JS, which is exactly how web drifted from this
--     RPC and from Dart's `is Map`; a row like this is a session performed on
--     all three rails. Its own routine, so the tallies above stay untouched.
insert into gym_routines (id, author_id, title, exercise_count)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb03', '00000000-0000-0000-0000-0000000b0001', 'Legs C', 2);

insert into gym_workouts (id, user_id, title, started_at, metadata)
values
  ('cccccccc-cccc-cccc-cccc-ccccccccccc3',
   '00000000-0000-0000-0000-0000000b0001', 'Array marker',
   timestamptz '2026-07-01 08:00:00+00',
   jsonb_build_object(
     'routine_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb03',
     'gym_session_draft', '[]'::jsonb
   ));

select is(
  (select session_count from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb03')),
  1,
  'a non-object under gym_session_draft is not a draft — the row still counts as performed'
);

-- 10. RLS: a stranger sees none of the lifter's sessions. The gym_workouts
--     select policy also admits `is_public` rows, so make one public first —
--     the explicit auth.uid() filter is what keeps it out.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b0001"}';
update gym_workouts set is_public = true
  where id = 'cccccccc-cccc-cccc-cccc-ccccccccccc2';

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b0099"}';
select is(
  (select session_count from gym_routine_history('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01')),
  0,
  'a different user aggregates none of the lifter''s sessions, public ones included'
);

select * from finish();
rollback;
