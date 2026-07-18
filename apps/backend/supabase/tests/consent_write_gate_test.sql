-- Pins migration 20270425_002 — server-side GDPR Art 8 consent write gate.
--
-- Behaviour pinned:
--   1. private.enforce_consent() exists + a BEFORE INSERT trigger is
--      attached to each core personal-data table.
--   2. An authenticated caller whose user_profiles.age_confirmed_at is
--      NULL is REJECTED (42501) inserting into runs — the bypass this
--      issue closes.
--   3. A consented caller (age_confirmed_at stamped) is ALLOWED.
--   4. The consent-stamping path itself (confirm_age_and_terms) is not
--      locked out: a brand-new unstamped user can stamp, then write.
--   5. A service_role / null-auth.uid() write passes through (async
--      importers/webhooks have no interactive consent context).

begin;
select plan(9);

-- ─── structure ─────────────────────────────────────────────────────
select has_function(
  'private', 'enforce_consent', ARRAY[]::text[],
  'private.enforce_consent() must exist'
);
select has_trigger(
  'public', 'runs', 'runs_require_consent',
  'runs must carry the consent BEFORE INSERT trigger'
);
select has_trigger(
  'public', 'gym_workouts', 'gym_workouts_require_consent',
  'gym_workouts must carry the consent BEFORE INSERT trigger'
);
select has_trigger(
  'public', 'food_log', 'food_log_require_consent',
  'food_log must carry the consent BEFORE INSERT trigger'
);
select has_trigger(
  'public', 'body_metrics', 'body_metrics_require_consent',
  'body_metrics must carry the consent BEFORE INSERT trigger'
);

-- ─── behaviour ─────────────────────────────────────────────────────
do $$
declare
  v_unconsented uuid := '77777777-7777-7777-7777-777777777771';
  v_consented   uuid := '77777777-7777-7777-7777-777777777772';
begin
  perform set_config('request.jwt.claim.role', 'service_role', true);

  insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                          instance_id, aud, role)
    values
      (v_unconsented, 'consent-gate-none@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_consented, 'consent-gate-ok@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;

  delete from public.user_profiles where id in (v_unconsented, v_consented);

  -- The unconsented user exists (curl-to-signup bypass) but has NO
  -- user_profiles row at all — the harshest null-consent case.
  -- The consented user has a stamped profile.
  insert into public.user_profiles (id, age_confirmed_at, terms_accepted_at,
                                     preferred_unit, subscription_tier)
    values (v_consented, now(), now(), 'km', 'free');

  -- (2) Unconsented authenticated caller is rejected inserting a run.
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_unconsented::text, true);
  begin
    insert into public.runs (user_id, started_at, duration_s, distance_m, source)
      values (v_unconsented, now(), 600, 1000, 'app');
    raise exception 'unconsented insert must have been rejected';
  exception when insufficient_privilege then
    null; -- expected: 42501 from the consent guard
  end;

  -- (3) Consented caller is allowed.
  perform set_config('request.jwt.claim.sub', v_consented::text, true);
  insert into public.runs (user_id, started_at, duration_s, distance_m, source)
    values (v_consented, now(), 600, 1000, 'app');

  -- (5) service_role / null auth.uid() passes through even for the
  -- unconsented user — the async-importer carve-out.
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);
  insert into public.runs (user_id, started_at, duration_s, distance_m, source)
    values (v_unconsented, now(), 600, 1000, 'strava');
end $$;

select pass('unconsented authenticated caller is rejected inserting a run');
select pass('consented authenticated caller is allowed to insert a run');
select pass('service_role / null-uid write passes through the gate');

-- (4) The consent-stamping path is not locked out: a fresh unstamped
-- user with no profile row can call confirm_age_and_terms (which
-- creates the row + stamp), then write.
do $$
declare
  v_fresh uuid := '77777777-7777-7777-7777-777777777773';
begin
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);
  insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                          instance_id, aud, role)
    values (v_fresh, 'consent-gate-fresh@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;
  delete from public.user_profiles where id = v_fresh;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_fresh::text, true);

  -- Before stamping: a write is rejected.
  begin
    insert into public.runs (user_id, started_at, duration_s, distance_m, source)
      values (v_fresh, now(), 600, 1000, 'app');
    raise exception 'fresh unstamped user must be rejected before consent';
  exception when insufficient_privilege then
    null;
  end;

  -- Stamp via the RPC, then the same write succeeds.
  perform confirm_age_and_terms();
  insert into public.runs (user_id, started_at, duration_s, distance_m, source)
    values (v_fresh, now(), 600, 1000, 'app');
end $$;

select pass(
  'consent-stamping path works: stamp via confirm_age_and_terms then write'
);

select * from finish();
rollback;
