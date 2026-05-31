-- audit-findings 2026-05-30 Medium [security/rls] — `lock_subscription_columns`
-- treats an empty JWT role (`v_role = ''`) as a trusted bypass. The
-- intent was to let direct-SQL callers (migrations + seed, which run
-- with no JWT context) write the privileged subscription columns. But
-- "empty role claim" is a property of the *request*, not the caller's
-- actual database privilege — any path that lands in the trigger with
-- an unset/blank role claim sails straight through the paywall gate.
--
-- Anchor the bypass on signals the REST surface cannot forge instead:
--   * `v_role = 'service_role'` — the only in-band signal available
--     inside a SECURITY DEFINER function (where current_user is masked
--     to the owner) for a legitimate service-role REST call.
--   * `session_user in ('postgres', 'supabase_admin')` — genuine
--     privileged DB connections used by migrations + seed. PostgREST
--     authenticates every request as the `authenticator` login role and
--     only `set role`s to authenticated/anon/service_role, so an
--     end-user request can never present session_user = postgres.
--
-- Net: migrations + seed still write the columns; a real service-role
-- caller still bypasses; an authenticated (or role-claim-stripped)
-- end-user is gated. No signature change; pure function-body update.
-- Pinned by the existing e2e in
-- apps/web/tests-e2e/cross-cutting/db-constraints.spec.ts (drives the
-- real PostgREST path, where session_user = authenticator).

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
  -- Trusted: the REST service role (by JWT role) and genuine
  -- privileged DB connections (by session_user, which PostgREST cannot
  -- forge). Everything else — authenticated, anon, any caller whose
  -- role claim parsed empty over REST — gets the gate.
  if v_role = 'service_role'
     or session_user in ('postgres', 'supabase_admin') then
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
