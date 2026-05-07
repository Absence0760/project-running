-- Fix `lock_subscription_columns` to read the JWT role from BOTH
-- claim formats. The trigger from migration 20260624_001 reads
-- `request.jwt.claim.role` directly — but newer PostgREST (since
-- the per-claim individual-setting deprecation) only populates the
-- JSON blob `request.jwt.claims`. On any stack on the new baseline
-- (including local dev), `current_setting('request.jwt.claim.role',
-- true)` returns NULL → coalesces to '' → trips the
-- "service-role and direct-SQL (empty role)" bypass at the top of
-- the function, and the gate falls through. Net effect: ANY
-- signed-in user can PATCH their own user_profiles row to bump
-- `subscription_tier` to 'pro' and bypass the paywall in 30 seconds
-- with curl. Surfaced by the e2e test in
-- `apps/web/tests-e2e/cross-cutting/db-constraints.spec.ts`.
--
-- Same fix shape as 20260726_001_rate_limit_role_jwt_claims.sql:
-- read the role from BOTH sources via a coalesce so backwards-compat
-- holds on stacks that still set the legacy claim. No signature
-- change; pure function-body update.

create or replace function lock_subscription_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  -- Service-role and direct-SQL (empty role) callers are trusted.
  -- Everything else (authenticated, anon, any future role) gets the
  -- gate applied.
  if v_role = 'service_role' or v_role = '' then
    return new;
  end if;

  if old.subscription_tier is distinct from new.subscription_tier then
    raise exception 'subscription_tier is read-only for non-service-role callers'
      using errcode = '42501';
  end if;
  if old.subscription_at is distinct from new.subscription_at then
    raise exception 'subscription_at is read-only for non-service-role callers'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
