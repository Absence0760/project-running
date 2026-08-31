-- `enforce_create_rate_limit`'s service-role skip has never fired.
--
-- 20260726_001 brought `check_rate_limit` / `check_rate_limit_tiered` onto the
-- claim shape PostgREST actually sets: newer PostgREST populates only the JSON
-- blob `request.jwt.claims`, and the per-claim settings it deprecated
-- (`request.jwt.claim.role`, `…sub`) are never written. Its header records what
-- reading only the legacy setting cost — every fail-closed Edge Function
-- rejected its own service-role-keyed admin call, surfacing as a blanket 503.
--
-- 20260907_001 wrote `enforce_create_rate_limit` six weeks later and reached
-- for the legacy setting alone. So `v_role` is the empty string on every
-- deployment on the current PostgREST baseline, `v_role = 'service_role'` is
-- never true, and skip 1 is dead code. Measured against the live catalogue,
-- this is the ONLY function left in `public` or `private` that reads the
-- legacy claim without the JSON fallback; every other role-reading body — the
-- two rate-limit RPCs, `lock_event_order_status`, `lock_donation_status`, the
-- subscription-column locks — carries the coalesce.
--
-- Nothing is broken TODAY only because skip 2 covers the same callers by
-- accident: a service-role JWT carries no `sub`, so `auth.uid()` is null and
-- the next line returns. The moment a service-role caller carries a `sub` —
-- admin tooling acting for a named user, which is exactly what skip 1's own
-- comment describes — it is throttled against that user's queue instead of
-- being skipped, and the eleven buckets riding this helper (clubs, routes,
-- challenges, reports, the four clone RPCs, the template publish and both
-- direct-message windows) all inherit that.
--
-- Bare-body `create or replace` over 20260907_001, which is the only
-- definition this function has ever had (verified against the full migration
-- set, not the one file). The single edit is `v_role`; the skips, their order,
-- the raise, the errcode and the hint are unchanged, so no bucket's behaviour
-- moves for any caller the skip did not already reach.
--
-- Online-safety: CREATE OR REPLACE FUNCTION takes no lock on any relation, so
-- none of docs/backend/migration_locks.md applies. Signature, return type,
-- volatility and search_path are unchanged, so neither row-type generator
-- moves.

create or replace function enforce_create_rate_limit(
  p_bucket text,
  p_user_id uuid,
  p_max integer,
  p_window_seconds integer
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Both sources, the same shape check_rate_limit uses since 20260726_001:
  -- the legacy per-claim setting where a deployment still writes it, else the
  -- JSON blob every current PostgREST writes.
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
  v_allowed boolean;
  v_retry integer;
begin
  -- Three skip cases:
  --   1. service_role — admin tooling / Edge Functions writing on a
  --      user's behalf shouldn't get throttled by their own queue.
  --   2. No auth context at all (auth.uid() IS NULL) — direct SQL,
  --      migrations, seed.sql. These are trusted by definition; if
  --      they weren't, the underlying row-level grants would already
  --      have rejected the INSERT before this trigger fired.
  --   3. Caller is not the row owner (auth.uid() <> p_user_id) — a
  --      forged INSERT under another user_id. We MUST NOT raise our
  --      own P0001 here; the existing RLS WITH CHECK policy rejects
  --      forges with 42501, and the rls_clubs / rls_routes pgtap
  --      suites assert that errcode. Beating RLS to the punch with
  --      a different error mis-classifies the attack and breaks
  --      those guards.
  --
  -- The existing check_rate_limit guard on auth.uid() <> p_user_id
  -- raises 'not authorized' under both (1) and (2) without these
  -- short-circuits, which is what broke seed.sql on first land.
  if v_role = 'service_role' then return; end if;
  if auth.uid() is null then return; end if;
  if auth.uid() is distinct from p_user_id then return; end if;

  select allowed, retry_after_seconds
    into v_allowed, v_retry
  from check_rate_limit(p_user_id, p_bucket, p_max, p_window_seconds);

  if not v_allowed then
    raise exception 'rate limit exceeded for %, retry in %s', p_bucket, v_retry
      using errcode = 'P0001',
            hint = 'You are creating these too quickly. Please wait and try again.';
  end if;
end;
$$;

-- CREATE OR REPLACE preserves the existing ACL, so this restates rather than
-- restores 20270626000001's sweep. Kept so the withheld set survives a future
-- drop-and-create, which is what re-issues the image default (decisions § 799),
-- and named on all three grantees exactly as the sweep names them.
revoke execute on function enforce_create_rate_limit(text, uuid, integer, integer)
  from public, anon, authenticated;
