-- Pins migration 20261221_001 — toggling runs.is_dnf fires the
-- personal_records UPDATE trigger so the cache doesn't drift.
--
-- Distinct from personal_records_dnf_test.sql, which calls the refresher
-- directly with is_dnf pre-set. This exercises the TRIGGER path: an
-- UPDATE that touches only is_dnf (+ metadata), mirroring the web
-- run-detail DNF toggle, must recompute the cache.

begin;
select plan(2);

do $$
declare
  v_user uuid := '88888888-8888-8888-8888-8888dddd0001';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'dnf-trigger@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
end $$;

-- A real marathon. The INSERT trigger seeds the PR.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '88888888-8888-8888-8888-8888dddd0a01',
  '88888888-8888-8888-8888-8888dddd0001',
  '2026-04-01 09:00:00+00',
  42195,
  14400,
  'app',
  '{"activity_type":"run"}'
);

select is(
  (select count(*) from personal_records
   where user_id = '88888888-8888-8888-8888-8888dddd0001' and distance = 'marathon'),
  1::bigint,
  'baseline: the marathon is a PR after insert'
);

-- Toggle DNF the way the web run-detail page does: UPDATE only metadata
-- + is_dnf. Pre-fix this UPDATE didn't fire the trigger, so the PR
-- lingered. Post-fix the trigger recomputes and drops it.
update runs
  set is_dnf = true,
      metadata = metadata || '{"dnf_reason":"injury"}'::jsonb
  where id = '88888888-8888-8888-8888-8888dddd0a01';

select is(
  (select count(*) from personal_records
   where user_id = '88888888-8888-8888-8888-8888dddd0001' and distance = 'marathon'),
  0::bigint,
  'marking the run DNF (metadata + is_dnf only) fires the trigger and clears the PR'
);

rollback;
