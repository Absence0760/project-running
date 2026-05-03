-- RLS audit cleanup batch — close low-severity findings.
--
-- The findings closed here:
--
-- (a) `fitness_snapshots_self_insert` accepts any `source` value
--     (column CHECK is `('server', 'client')`). The trend chart
--     uses `source` to label rows; a malicious client can
--     INSERT a row with `source = 'server'` and pretend their
--     fabricated VDOT / VO2 row is the authoritative server
--     recompute, polluting their own chart and any future
--     leaderboard / advisor that trusts server-source rows.
--     Tighten the policy to require `source = 'client'` so the
--     server label is reachable only via the recompute job
--     (which writes as service_role and bypasses RLS).
--
-- (b) `personal_records`, `monthly_funding`, `fitness_snapshots`
--     have only the SELECT policies they need; INSERT / UPDATE
--     / DELETE for `personal_records` and `monthly_funding`
--     are denied implicitly because no policy matches under
--     RLS. Supabase's defaults grant the underlying table
--     privileges to `anon` / `authenticated` regardless, so a
--     future "drop RLS to debug" or a missed `enable rls` on a
--     migration restore would silently widen the gate.
--     Explicitly revoke writes here so the GRANT layer
--     mirrors the policy intent. Defence-in-depth, not a
--     fix — RLS is still the primary gate.
--
-- The trigger that maintains `personal_records` is
-- SECURITY DEFINER and runs as the function owner, so the
-- revokes don't affect counter maintenance. Service-role
-- writes (recompute job, RevenueCat webhook for funding-
-- adjacent flows) bypass GRANTs by design.

-- (a) Tighten fitness_snapshots self-INSERT to client-source only.
drop policy fitness_snapshots_self_insert on fitness_snapshots;

create policy fitness_snapshots_self_insert on fitness_snapshots
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and source = 'client'
  );

-- (b) Explicit write revokes on tables that should be read-only
-- to clients. RLS already denies these, but mirror the intent
-- at the GRANT layer.
revoke insert, update, delete on personal_records from anon, authenticated;
revoke insert, update, delete on monthly_funding from anon, authenticated;
