-- Regression repair: the session_user hardening of
-- lock_subscription_columns in 20261107_001 rewrote the function body
-- from scratch and silently dropped the billing_issue_at guard that
-- 20260729_001 had added (the "bare-body create or replace strips
-- prior fixes" trap — see apps/backend/CLAUDE.md). Net effect: an
-- authenticated user could clear their own billing_issue_at via a
-- self-row UPDATE and suppress the renewal-failure banner — a self-DoS
-- of the dunning surface and the same integrity contract as
-- subscription_tier (RevenueCat is the only legitimate writer).
--
-- Re-emit the COMPLETE body: the 20261107_001 trusted-caller rule
-- (service_role by JWT, or empty-role AND privileged session_user)
-- PLUS all three locked columns. No signature change; pure body
-- restore. Pinned at the pgtap layer by rls_paywall_test.sql (tests
-- 13-14) so a future bare-body rewrite that drops a column fails the
-- backend test-db job before merge, not just the heavier web e2e.

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
  -- Trusted callers (unchanged from 20261107_001):
  --   * REST service role — by JWT role, the only in-band signal inside
  --     a SECURITY DEFINER function (current_user is masked to owner).
  --   * Genuine direct-SQL (migrations + seed) — empty role claim AND a
  --     privileged session_user. PostgREST authenticates every request
  --     as the `authenticator` login role, so an end-user request can
  --     never present session_user=postgres.
  if v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin')) then
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
  if old.billing_issue_at is distinct from new.billing_issue_at then
    raise exception 'billing_issue_at is read-only for non-service-role callers'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
