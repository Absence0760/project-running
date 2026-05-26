-- Pins migration 20260929_001 — server-side age + ToS confirmation.
--
-- Behaviour pinned:
--
--   1. user_profiles.age_confirmed_at + terms_accepted_at columns
--      exist with the right type (nullable timestamptz). NULL is the
--      "not yet stamped" sentinel.
--   2. confirm_age_and_terms() RPC stamps both columns for an
--      authenticated caller; raises 42501 when unauthenticated.
--   3. Idempotent: re-calling the RPC preserves the original timestamp
--      (first-stamp wins). Required because the OAuth callback may
--      replay the RPC on every login, and consent is a once-per-
--      account act.
--   4. EXECUTE grants are narrow: authenticated only.

begin;
select plan(11);

-- ─── columns ───────────────────────────────────────────────────────
select has_column(
  'public', 'user_profiles', 'age_confirmed_at',
  'user_profiles.age_confirmed_at column must exist'
);
select col_type_is(
  'public', 'user_profiles', 'age_confirmed_at', 'timestamp with time zone',
  'age_confirmed_at must be timestamptz'
);
select col_is_null(
  'public', 'user_profiles', 'age_confirmed_at',
  'age_confirmed_at must be nullable so a missing stamp is detectable'
);

select has_column(
  'public', 'user_profiles', 'terms_accepted_at',
  'user_profiles.terms_accepted_at column must exist'
);
select col_type_is(
  'public', 'user_profiles', 'terms_accepted_at', 'timestamp with time zone',
  'terms_accepted_at must be timestamptz'
);

-- ─── function + grants ─────────────────────────────────────────────
select has_function(
  'public', 'confirm_age_and_terms', ARRAY[]::text[],
  'confirm_age_and_terms() must exist'
);

select function_privs_are(
  'public', 'confirm_age_and_terms', ARRAY[]::text[],
  'authenticated', ARRAY['EXECUTE'],
  'authenticated role must have EXECUTE on confirm_age_and_terms'
);

select function_privs_are(
  'public', 'confirm_age_and_terms', ARRAY[]::text[],
  'anon', ARRAY[]::text[],
  'anon role must NOT have EXECUTE on confirm_age_and_terms'
);

-- ─── behaviour ─────────────────────────────────────────────────────
-- A fresh synthetic user starts unstamped. After confirm_age_and_terms
-- the columns are populated. A second call preserves the original
-- timestamp.

do $$
declare
  v_user uuid := '88888888-8888-8888-8888-888888888888';
  v_first_age timestamptz;
  v_second_age timestamptz;
begin
  perform set_config('request.jwt.claim.role', 'service_role', true);
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'age-gate-test@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
  -- Ensure no profile exists yet for the first-stamp branch.
  delete from public.user_profiles where id = v_user;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_user::text, true);

  perform confirm_age_and_terms();
  select age_confirmed_at into v_first_age
    from public.user_profiles where id = v_user;
  if v_first_age is null then
    raise exception 'first stamp must populate age_confirmed_at';
  end if;

  -- Sleep a hair so a NEW now() is observably different from the
  -- first stamp — if the RPC overwrites, the test catches it.
  perform pg_sleep(0.05);
  perform confirm_age_and_terms();
  select age_confirmed_at into v_second_age
    from public.user_profiles where id = v_user;
  if v_second_age <> v_first_age then
    raise exception 'second call must preserve first stamp (got % vs %)',
      v_second_age, v_first_age;
  end if;

  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);
  delete from auth.users where id = v_user;
end $$;

select pass(
  'confirm_age_and_terms stamps + is idempotent (first-stamp wins)'
);

-- Unauthenticated caller must be rejected with 42501 — not silently
-- create a row for the null user.
do $$
begin
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform confirm_age_and_terms();
    raise exception 'confirm_age_and_terms must reject an unauthenticated caller';
  exception when insufficient_privilege then
    -- expected
    null;
  end;
end $$;

select pass(
  'confirm_age_and_terms rejects an unauthenticated caller with 42501'
);

-- Backfill: existing seeded users (runner@test.com, etc.) must have
-- both columns populated by the migration's backfill step. The seed
-- user predates the gate.
select isnt_empty(
  $$select 1 from public.user_profiles
      where id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
        and age_confirmed_at is not null
        and terms_accepted_at is not null$$,
  'seed runner@test.com must be backfilled with both consent timestamps'
);

select * from finish();
rollback;
