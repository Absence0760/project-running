-- Explicit DELETE deny on `user_coach_usage`.
--
-- Audit pass 3 finding: the table from `20260430_001` has SELECT,
-- INSERT, UPDATE policies but no DELETE policy. PostgreSQL deny-by-
-- default means a missing policy currently rejects all DELETEs from
-- non-service-role callers, but the absence of an explicit policy
-- creates two risks:
--   1. A future PR adding a "reset usage" convenience would assume
--      the gap was unintentional and might add a permissive
--      `DELETE USING (true)` that bypasses the daily cap.
--   2. The intent is undocumented — "no DELETE allowed" is the
--      design contract but reading the migration source can't tell
--      you that.
--
-- This migration adds an explicit `using (false)` policy so the
-- intent is on disk. Service role still bypasses RLS as it does for
-- every table; this policy applies only to PostgREST-routed
-- authenticated / anon callers.

create policy user_coach_usage_no_delete
  on user_coach_usage for delete
  using (false);
