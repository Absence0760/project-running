-- Pins migration 20260528000003 — runs.external_id is per-user unique,
-- not globally unique.
--
-- Pre-fix, two users importing the same Strava activity ID (or any
-- external-id collision across users) hit a 23505 unique-constraint
-- violation, surfacing as a silent failed++ in the importer with no
-- diagnostic. Persona-hunt finding Intermediate #2.

begin;
select plan(2);

-- Synthetic users + same external_id across both. The migration
-- changes the scope to (user_id, external_id) so this must succeed.
do $$
declare
  v_user_a uuid := '99999999-9999-9999-9999-99999999dddd';
  v_user_b uuid := '99999999-9999-9999-9999-99999999eeee';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user_a, 'extid-a@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user_b, 'extid-b@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;

  -- Same Strava-ish external_id for two different users — must NOT
  -- collide post-fix.
  insert into runs (user_id, started_at, distance_m, duration_s, source, external_id, metadata)
    values (v_user_a, '2026-04-01 09:00:00+00', 5000, 1500, 'strava', 'strava:99001', '{"activity_type":"run"}');
  insert into runs (user_id, started_at, distance_m, duration_s, source, external_id, metadata)
    values (v_user_b, '2026-04-01 10:00:00+00', 5000, 1500, 'strava', 'strava:99001', '{"activity_type":"run"}');
end $$;

select is(
  (select count(*) from runs where external_id = 'strava:99001'),
  2::bigint,
  'Two different users can hold runs with the same external_id'
);

-- Within a single user, duplicates DO still collide. This pins the
-- per-user uniqueness so a refactor that drops the index altogether
-- (regression toward no dedupe) surfaces here.
do $$
declare
  v_collided boolean := false;
begin
  begin
    insert into runs (user_id, started_at, distance_m, duration_s, source, external_id, metadata)
      values ('99999999-9999-9999-9999-99999999dddd'::uuid,
              '2026-04-02 09:00:00+00', 5000, 1500, 'strava', 'strava:99001', '{"activity_type":"run"}');
  exception when unique_violation then
    v_collided := true;
  end;
  perform set_config('persona.collided', case when v_collided then 'true' else 'false' end, true);
end $$;

select is(
  current_setting('persona.collided', true),
  'true',
  'Within a single user, duplicate external_id is still rejected (per-user unique)'
);

rollback;
