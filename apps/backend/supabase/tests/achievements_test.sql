-- Pins migration 20270206_001_achievements.
--
-- The badge thresholds in award_achievements_for_user are a lockstep contract
-- with apps/web/src/lib/social/badges.ts. This test pins the numeric boundaries
-- (a refactor that drifts a threshold fails here), the idempotency of the
-- full-rebuild + on-conflict-do-nothing path, the RLS read/write boundaries,
-- and the 'achievement' notification on a new award.

begin;
select plan(16);

-- ── Synthetic users ─────────────────────────────────────────────────────────
do $$
declare
  v_u uuid := '99999999-9999-9999-9999-9999aaaa0001';
  v_other uuid := '99999999-9999-9999-9999-9999aaaa0002';
begin
  insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                          instance_id, aud, role)
    values
      (v_u, 'ach-owner@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_other, 'ach-other@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;
end $$;

-- A single marathon-distance run (42.45 km) → distance_single gold, and a
-- 5-day-spanning set so lifetime distance clears bronze (100 km).
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values
  ('a0000001-0000-0000-0000-000000000001', '99999999-9999-9999-9999-9999aaaa0001',
   '2026-04-01 09:00:00+00', 42450, 14400, 'app', '{"activity_type":"run"}'),
  ('a0000001-0000-0000-0000-000000000002', '99999999-9999-9999-9999-9999aaaa0001',
   '2026-04-02 09:00:00+00', 30000, 10800, 'app', '{"activity_type":"run"}'),
  ('a0000001-0000-0000-0000-000000000003', '99999999-9999-9999-9999-9999aaaa0001',
   '2026-04-03 09:00:00+00', 30000, 10800, 'app', '{"activity_type":"run"}');

-- The runs trigger has already awarded. Assert the single-run distance badge.
select is(
  (select tier from achievements
     where user_id = '99999999-9999-9999-9999-9999aaaa0001'
       and badge_key = 'distance_single'
     order by case tier when 'platinum' then 4 when 'gold' then 3
                        when 'silver' then 2 else 1 end desc limit 1),
  'gold',
  'a 42.45 km run earns the gold single-run distance badge'
);

-- Lifetime = 42450 + 30000 + 30000 = 102450 m > 100000 → bronze lifetime badge.
select is(
  (select tier from achievements
     where user_id = '99999999-9999-9999-9999-9999aaaa0001'
       and badge_key = 'distance_lifetime'
     order by case tier when 'platinum' then 4 when 'gold' then 3
                        when 'silver' then 2 else 1 end desc limit 1),
  'bronze',
  '102 km lifetime earns the bronze lifetime badge'
);

-- Streak: 3 consecutive days < 7 → no streak badge.
select is(
  (select count(*)::int from achievements
     where user_id = '99999999-9999-9999-9999-9999aaaa0001' and badge_key = 'streak'),
  0,
  'a 3-day streak earns no streak badge (bronze is 7)'
);

-- PR row exists (the 42.45 km run is a marathon PR) → pr bronze.
select is(
  (select tier from achievements
     where user_id = '99999999-9999-9999-9999-9999aaaa0001' and badge_key = 'pr' limit 1),
  'bronze',
  'holding one PR earns the bronze PR badge'
);

-- ── Idempotency ──────────────────────────────────────────────────────────────
-- A re-derive returns no newly-inserted awards (on conflict do nothing).
select is(
  (select count(*)::int from (
     select award_achievements_for_user('99999999-9999-9999-9999-9999aaaa0001')
   ) s),
  0,
  'a re-derive returns zero newly-inserted awards'
);

-- ...and the total award count is unchanged after several re-derives.
do $$
begin
  perform award_achievements_for_user('99999999-9999-9999-9999-9999aaaa0001');
  perform award_achievements_for_user('99999999-9999-9999-9999-9999aaaa0001');
end $$;
select is(
  (select count(*)::int from achievements
     where user_id = '99999999-9999-9999-9999-9999aaaa0001' and badge_key = 'pr'),
  1,
  'repeated derives do not duplicate the pr award'
);

-- ── Notification ─────────────────────────────────────────────────────────────
select ok(
  exists (
    select 1 from notifications n
    join achievements a on a.id = n.achievement_id
    where n.user_id = '99999999-9999-9999-9999-9999aaaa0001'
      and n.kind = 'achievement'
  ),
  'a new award wrote an achievement notification for the owner'
);

select is(
  (select count(distinct kind)::int from notifications
     where user_id = '99999999-9999-9999-9999-9999aaaa0001' and kind <> 'achievement'),
  0,
  'achievement awards only emit the achievement notification kind'
);

-- ── RLS: owner reads own (incl. private) ─────────────────────────────────────
update achievements set is_public = false
  where user_id = '99999999-9999-9999-9999-9999aaaa0001' and badge_key = 'pr';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-9999aaaa0001","role":"authenticated"}';

select ok(
  (select count(*) from achievements where user_id = '99999999-9999-9999-9999-9999aaaa0001') >= 1,
  'owner reads their own badges including private ones'
);
select ok(
  exists (select 1 from achievements
            where user_id = '99999999-9999-9999-9999-9999aaaa0001'
              and badge_key = 'pr' and is_public = false),
  'owner can see their own private badge'
);

-- Owner can flip is_public.
select lives_ok(
  $$update achievements set is_public = true
      where user_id = '99999999-9999-9999-9999-9999aaaa0001' and badge_key = 'pr'$$,
  'owner can toggle is_public on their own badge'
);

-- No client INSERT.
select throws_ok(
  $$insert into achievements (user_id, badge_key, tier, source_kind, value_num)
      values ('99999999-9999-9999-9999-9999aaaa0001', 'fake', 'bronze', 'distance', 1)$$,
  '42501',
  null,
  'a client cannot INSERT an achievement (no insert policy)'
);

-- No client DELETE: with no DELETE policy, RLS makes the rows invisible to the
-- delete (0 rows affected) rather than raising — fail-closed. Assert the row
-- survives the attempted delete.
delete from achievements where user_id = '99999999-9999-9999-9999-9999aaaa0001';
select ok(
  exists (select 1 from achievements
            where user_id = '99999999-9999-9999-9999-9999aaaa0001'),
  'a client DELETE removes nothing (no delete policy, fail-closed)'
);

reset role;

-- ── RLS: another user reads only public badges ───────────────────────────────
-- Make the pr badge private again, then read as the other user.
update achievements set is_public = false
  where user_id = '99999999-9999-9999-9999-9999aaaa0001' and badge_key = 'pr';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-9999aaaa0002","role":"authenticated"}';

select ok(
  not exists (select 1 from achievements
                where user_id = '99999999-9999-9999-9999-9999aaaa0001'
                  and badge_key = 'pr'),
  'another user cannot see U''s private badge'
);
select ok(
  exists (select 1 from achievements
            where user_id = '99999999-9999-9999-9999-9999aaaa0001' and is_public = true),
  'another user can see U''s public badges'
);

-- Non-owner cannot flip U's visibility (update affects 0 rows → silently no-op,
-- so assert the row is unchanged rather than expecting an error).
update achievements set is_public = true
  where user_id = '99999999-9999-9999-9999-9999aaaa0001' and badge_key = 'pr';
reset role;

select ok(
  exists (select 1 from achievements
            where user_id = '99999999-9999-9999-9999-9999aaaa0001'
              and badge_key = 'pr' and is_public = false),
  'a non-owner UPDATE does not change U''s badge visibility'
);

select * from finish();
rollback;
