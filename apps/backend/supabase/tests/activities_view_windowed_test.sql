-- MM1 (Round 5): pin the `activities` view as the cross-modality contract.
--
-- The view is the single read-time unifier for the multi-modal History
-- timeline (multi_modal.md). Three things must hold and stay held:
--
--   1. CONTRACT COLUMNS. The view projects (id, user_id, kind, started_at,
--      summary, is_public). is_public was added in 20261209_001 so the owner
--      timeline can badge public/private and a same-user public filter is one
--      query, not a re-join. If a future view rewrite drops a column the
--      History list silently breaks; the has_column assertions catch it.
--
--   2. THE WINDOWED-QUERY PATH. History reads the view windowed (limit +
--      started_at cursor), never unbounded (multi_modal.md § "activities view
--      at scale"). This exercises that exact access path — an ordered limit,
--      then a started_at cursor for the next page — so the pagination contract
--      the client depends on can't regress.
--
--   3. THE REDACTION BOUNDARY (decisions §33). The view is security_invoker, so
--      base-table RLS decides cross-user visibility. gym_workouts / food_log
--      keep an "owner or public" read policy, so their public rows surface to
--      non-owners (and anon) through the view. runs DELIBERATELY has no
--      public-read policy (dropped in 20260701_001) — non-owner run reads must
--      go through the redacted `public_runs` view, never the base table. So a
--      public RUN is NOT visible through `activities` to anyone but its owner.
--      That asymmetry is intentional; this test pins it so nobody "fixes" the
--      view by re-adding a runs public-read policy that would leak unredacted
--      run columns (track_url, route_id, …).
--
-- Fixture for owner A, newest-first:
--   f1   2026-03-10 12:00  meal  private
--   run1 2026-03-10 08:00  run   public
--   w1   2026-03-09 18:00  lift  public   (2 sets)
--   run2 2026-03-08 08:00  run   private
--   f2   2026-03-07 12:00  meal  public

begin;

select plan(15);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('0000000a-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
   'a@activities.local', '', now(), now()),
  ('0000000b-0000-0000-0000-00000000000b', 'authenticated', 'authenticated',
   'b@activities.local', '', now(), now());

insert into public.runs (id, user_id, started_at, duration_s, distance_m, source, is_public)
values
  ('a1111111-1111-1111-1111-111111111111', '0000000a-0000-0000-0000-00000000000a',
   '2026-03-10 08:00:00+00', 2520, 8200, 'app', true),
  ('a2222222-2222-2222-2222-222222222222', '0000000a-0000-0000-0000-00000000000a',
   '2026-03-08 08:00:00+00', 1800, 5000, 'app', false);

insert into public.gym_workouts (id, user_id, started_at, title, is_public)
values
  ('b1111111-1111-1111-1111-111111111111', '0000000a-0000-0000-0000-00000000000a',
   '2026-03-09 18:00:00+00', 'Push day', true);

insert into public.gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values
  ('b1111111-1111-1111-1111-111111111111', 0, 'Bench', 5, 80),
  ('b1111111-1111-1111-1111-111111111111', 1, 'Bench', 5, 80);

insert into public.food_log (id, user_id, started_at, item_name, is_public)
values
  ('c1111111-1111-1111-1111-111111111111', '0000000a-0000-0000-0000-00000000000a',
   '2026-03-10 12:00:00+00', 'Chicken bowl', false),
  ('c2222222-2222-2222-2222-222222222222', '0000000a-0000-0000-0000-00000000000a',
   '2026-03-07 12:00:00+00', 'Oats', true);

-- ── 1-5. Contract columns the timeline / feed / recommender read ──
select has_column('public', 'activities', 'id', 'activities exposes id');
select has_column('public', 'activities', 'kind', 'activities exposes kind');
select has_column('public', 'activities', 'started_at', 'activities exposes started_at');
select has_column('public', 'activities', 'summary', 'activities exposes summary');
select has_column('public', 'activities', 'is_public',
  'activities exposes is_public (feed-path contract column, MM1)');

-- ── Owner context ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"0000000a-0000-0000-0000-00000000000a"}';

-- 6. The owner sees all five activities across the three modalities.
select is(
  (select count(*)::int from public.activities
   where user_id = '0000000a-0000-0000-0000-00000000000a'),
  5,
  'owner sees every modality row in the unified view'
);

-- 7. Windowed page 1: ordered DESC + limit 3 returns the newest three, in order.
select results_eq(
  $$ select id from public.activities
     where user_id = '0000000a-0000-0000-0000-00000000000a'
     order by started_at desc
     limit 3 $$,
  $$ values ('c1111111-1111-1111-1111-111111111111'::uuid),
            ('a1111111-1111-1111-1111-111111111111'::uuid),
            ('b1111111-1111-1111-1111-111111111111'::uuid) $$,
  'windowed limit returns the newest 3 activities in started_at-desc order'
);

-- 8. Windowed page 2: started_at cursor (< the last row of page 1) returns the
-- remaining two with no overlap — the pagination contract the client uses.
select results_eq(
  $$ select id from public.activities
     where user_id = '0000000a-0000-0000-0000-00000000000a'
       and started_at < '2026-03-09 18:00:00+00'
     order by started_at desc
     limit 3 $$,
  $$ values ('a2222222-2222-2222-2222-222222222222'::uuid),
            ('c2222222-2222-2222-2222-222222222222'::uuid) $$,
  'started_at cursor pages to the next slice without overlap'
);

-- 9. is_public is projected per-row from each base table.
select results_eq(
  $$ select id, is_public from public.activities
     where user_id = '0000000a-0000-0000-0000-00000000000a'
     order by started_at desc $$,
  $$ values ('c1111111-1111-1111-1111-111111111111'::uuid, false),
            ('a1111111-1111-1111-1111-111111111111'::uuid, true),
            ('b1111111-1111-1111-1111-111111111111'::uuid, true),
            ('a2222222-2222-2222-2222-222222222222'::uuid, false),
            ('c2222222-2222-2222-2222-222222222222'::uuid, true) $$,
  'is_public reflects each row''s own table value'
);

-- 10. The lift summary subqueries compute under the caller's RLS.
select is(
  (select summary ->> 'set_count' from public.activities
   where id = 'b1111111-1111-1111-1111-111111111111'),
  '2',
  'lift summary set_count is computed in the view'
);

-- ── Non-owner context (RLS via security_invoker) ──
set local "request.jwt.claims" = '{"sub":"0000000b-0000-0000-0000-00000000000b"}';

-- 11. A non-owner sees the public LIFT + MEAL — those base tables allow public
-- read — but NOT the public run (redaction boundary, decisions §33).
select results_eq(
  $$ select id, kind from public.activities
     where user_id = '0000000a-0000-0000-0000-00000000000a'
     order by started_at desc $$,
  $$ values ('b1111111-1111-1111-1111-111111111111'::uuid, 'lift'),
            ('c2222222-2222-2222-2222-222222222222'::uuid, 'meal') $$,
  'non-owner sees public lifts + meals, not runs'
);

-- 12. No private row of A's leaks to B through the view.
select is_empty(
  $$ select 1 from public.activities
     where user_id = '0000000a-0000-0000-0000-00000000000a'
       and is_public = false $$,
  'non-owner never sees a private activity row'
);

-- 13. Public RUNS are not reachable through activities — the §33 boundary.
-- public_runs is the only non-owner path to a run, and it redacts columns.
select is_empty(
  $$ select 1 from public.activities
     where user_id = '0000000a-0000-0000-0000-00000000000a'
       and kind = 'run' $$,
  'non-owner cannot read any run (public or private) via the view'
);

-- ── Anon (logged-out share / feed surface) ──
set local role anon;
set local "request.jwt.claims" = '';

-- 14. Anon sees the same public non-run rows the base RLS allows — and nothing
-- else. (The view is granted broadly; base-table RLS is the real gate.)
select results_eq(
  $$ select id, kind from public.activities
     where user_id = '0000000a-0000-0000-0000-00000000000a'
     order by started_at desc $$,
  $$ values ('b1111111-1111-1111-1111-111111111111'::uuid, 'lift'),
            ('c2222222-2222-2222-2222-222222222222'::uuid, 'meal') $$,
  'anon sees only public lifts + meals'
);

-- 15. Anon gets no private row and no run — the redaction boundary holds even
-- logged out.
select is_empty(
  $$ select 1 from public.activities
     where user_id = '0000000a-0000-0000-0000-00000000000a'
       and (is_public = false or kind = 'run') $$,
  'anon never sees a private row or any run via the view'
);

select * from finish();

rollback;
