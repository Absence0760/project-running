-- Pins migration 20270421_001 — parkrun + race runs count toward distance
-- achievements (#378).
--
-- Before the fix, award_achievements_for_user filtered
--   source in ('app','watch','strava','garmin','healthkit','healthconnect')
-- so a runner whose entire history is parkrun (or official 'race') runs never
-- earned distance_single / distance_lifetime badges even after clearing the
-- thresholds. Both are valid runs.source values.

begin;
select plan(2);

do $$
declare
  v_user uuid := '77777777-7777-7777-7777-7777aaaa0378';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'ach-parkrun@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
end $$;

-- 21 parkrun 5Ks → single-run max 5000 m (distance_single bronze, thr 5000) and
-- lifetime 105000 m (distance_lifetime bronze, thr 100000). Parkrun-only user.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
select
  ('a0000378-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '77777777-7777-7777-7777-7777aaaa0378',
  '2026-04-01 09:00:00+00'::timestamptz + (n || ' days')::interval,
  5000, 1200, 'parkrun', '{"activity_type":"run"}'::jsonb
from generate_series(1, 21) as n;

do $$
begin
  perform award_achievements_for_user(
    '77777777-7777-7777-7777-7777aaaa0378'::uuid
  );
end $$;

select is(
  (select tier from achievements
     where user_id = '77777777-7777-7777-7777-7777aaaa0378'
       and badge_key = 'distance_single'
     order by case tier when 'platinum' then 4 when 'gold' then 3
                        when 'silver' then 2 else 1 end desc limit 1),
  'bronze',
  'a parkrun-only runner earns the bronze single-run distance badge'
);

select is(
  (select tier from achievements
     where user_id = '77777777-7777-7777-7777-7777aaaa0378'
       and badge_key = 'distance_lifetime'
     order by case tier when 'platinum' then 4 when 'gold' then 3
                        when 'silver' then 2 else 1 end desc limit 1),
  'bronze',
  '105 km of parkrun runs earns the bronze lifetime distance badge'
);

select * from finish();
rollback;
