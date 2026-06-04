-- Pins migration 20260530000001 — DNF runs excluded from PR candidates.
-- Persona-hunt Round 3 finding Ultra #3.

begin;
select plan(3);

do $$
declare
  v_user uuid := '99999999-9999-9999-9999-99999dddaaaa';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'dnf-test@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
end $$;

-- Seed a real marathon PR + a DNF-26-mile that lands in the marathon
-- bracket. Without the is_dnf gate, the DNF would beat the real
-- marathon time (7h vs 4h doesn't matter — the test seeds the DNF
-- as FASTER, which is the worst-case scenario where the bracket-
-- widening promotion goes most wrong).

insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '11111111-1111-1111-1111-11111ddddd01',
  '99999999-9999-9999-9999-99999dddaaaa',
  '2026-04-01 09:00:00+00',
  42195,
  14400,  -- 4:00:00 real marathon
  'app',
  '{"activity_type":"run"}'
);

-- DNF at mile 26 — distance 42_000 lands in the marathon bracket
-- (41,351–43,039). Duration 3:00:00 — faster than the real marathon
-- in raw seconds. Pre-fix this would beat the real PR.
-- is_dnf is now a real column (F3 / 20261207_001), not a metadata key.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_dnf, metadata)
values (
  '11111111-1111-1111-1111-11111ddddd02',
  '99999999-9999-9999-9999-99999dddaaaa',
  '2026-04-08 09:00:00+00',
  42000,
  10800,
  'app',
  true,
  '{"activity_type":"run"}'
);

do $$
begin
  perform refresh_personal_records_for_user(
    '99999999-9999-9999-9999-99999dddaaaa'::uuid
  );
end $$;

select is(
  (select count(*) from personal_records
   where user_id = '99999999-9999-9999-9999-99999dddaaaa'
     and distance = 'marathon'),
  1::bigint,
  'Exactly one marathon PR (the real one, not the DNF)'
);

select is(
  (select run_id from personal_records
   where user_id = '99999999-9999-9999-9999-99999dddaaaa'
     and distance = 'marathon'),
  '11111111-1111-1111-1111-11111ddddd01'::uuid,
  'PR points at the real 4-hour marathon, not the DNF-at-mile-26'
);

select is(
  (select best_time_s from personal_records
   where user_id = '99999999-9999-9999-9999-99999dddaaaa'
     and distance = 'marathon'),
  14400,
  'PR time is 4:00:00, not the faster-but-incomplete DNF 3:00:00'
);

rollback;
