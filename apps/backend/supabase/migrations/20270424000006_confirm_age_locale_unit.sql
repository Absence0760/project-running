-- confirm_age_and_terms(): seed the region unit default at account creation.
--
-- The function is the FIRST writer of a brand-new user's user_profiles
-- row on the web email-signup + OAuth-callback paths (it runs before the
-- client auth-store bootstrap). It hard-coded `preferred_unit = 'km'` on
-- that insert, so a US/GB/LR/MM visitor's account was always minted metric
-- regardless of locale — defeating the `defaultUnitForLocale` mechanism
-- that only the client can evaluate (the server has no browser locale at
-- insert time). The onboarding units step then prefilled that 'km' and the
-- skip path never re-defaulted, so region units effectively never applied
-- (issue #488).
--
-- Fix: accept the client's locale-derived default and apply it ONLY on the
-- brand-new-row insert. The `on conflict do update` branch still never
-- touches preferred_unit, so a RETURNING user's explicit choice is
-- untouched — the region default reaches new accounts only. Callers that
-- don't pass a unit (mobile ApiClient.signUp, the /auth/confirm-age
-- fallback) keep the prior 'km' default, so this is backward-compatible.
--
-- Full body rewrite per the backend "create or replace strips prior fixes"
-- rule — this preserves the auth guard + the idempotent consent-timestamp
-- coalesce from 20260929_001 unchanged. Signature changes (a new param),
-- so drop-then-create rather than replace; the defaulted param keeps the
-- zero-arg call site resolving.

drop function if exists confirm_age_and_terms();

create function confirm_age_and_terms(p_preferred_unit text default 'km')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  -- Normalise to the two valid values, mirroring the client `setUnit`
  -- ('mi' or 'km'); anything unexpected falls back to the metric default.
  unit text := case when p_preferred_unit = 'mi' then 'mi' else 'km' end;
begin
  if caller is null then
    raise exception 'confirm_age_and_terms: not authenticated'
      using errcode = '42501';
  end if;

  -- Upsert: a brand-new user (no user_profiles row yet) lands here when
  -- the client calls this immediately after auth.signUp. An existing user
  -- (returning after an OAuth callback that dropped the sessionStorage
  -- tick) updates only the null consent columns so the original consent
  -- timestamps AND the user's existing unit choice are preserved.
  insert into user_profiles (id, age_confirmed_at, terms_accepted_at, preferred_unit, subscription_tier)
    values (caller, now(), now(), unit, 'free')
    on conflict (id) do update
    set age_confirmed_at = coalesce(user_profiles.age_confirmed_at, excluded.age_confirmed_at),
        terms_accepted_at = coalesce(user_profiles.terms_accepted_at, excluded.terms_accepted_at);
end;
$$;

revoke execute on function confirm_age_and_terms(text) from public, anon;
grant execute on function confirm_age_and_terms(text) to authenticated;

comment on function confirm_age_and_terms(text) is
  'GDPR Art 8 + ToS acceptance capture — stamps age_confirmed_at + '
  'terms_accepted_at on the caller''s user_profiles row. Idempotent: '
  'existing timestamps are preserved (first-stamp wins). `p_preferred_unit` '
  '(''mi''|''km'', default ''km'') seeds the region unit default on the '
  'brand-new-row insert only — a returning user''s existing choice is never '
  'overwritten (issue #488). Called from web /login (email-password) + '
  '/auth/callback (OAuth) and from mobile sign_up_screen.dart.';
