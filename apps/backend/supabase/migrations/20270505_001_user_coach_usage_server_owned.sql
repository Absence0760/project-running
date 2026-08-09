-- `user_coach_usage` is a server-maintained meter, not user data.
--
-- The only legitimate writers are the auth.uid()-guarded SECURITY DEFINER
-- RPCs (`increment_coach_usage` / `decrement_coach_usage`, latest body in
-- 20261002_001) and the retention cron. But the table shipped (20260430_001)
-- with self-INSERT + self-UPDATE policies, and the grant matrix
-- (20270408_001) hands table-level INSERT/UPDATE to anon + authenticated —
-- so a signed-in caller could reach past the RPCs and rewrite their own
-- counter directly:
--
--   PATCH /rest/v1/user_coach_usage?user_id=eq.<self>&usage_date=eq.<today>
--   {"message_count": 0}
--
-- re-rolling the whole AI-coach allowance after every burst, or
--
--   POST /rest/v1/user_coach_usage
--   {"user_id":"<self>","usage_date":"<tomorrow>","message_count":-1000000}
--
-- which the rolling-24h sum in `increment_coach_usage`
-- (`usage_date >= (now() - interval '24 hours')::date`) adds in, pushing the
-- returned count permanently below every tier limit. Either way the cap that
-- bounds our Anthropic spend stops binding.
--
-- 20260722_001 closed the DELETE half of exactly this ("the daily cap cannot
-- be reset by deleting the counter row"); INSERT and UPDATE were left open.
-- Close them the same way — explicit deny policies so the intent is on disk,
-- plus the grant revoke so the deny does not rest on RLS alone. SELECT stays
-- (the owner reads their own meter; the GDPR export reads it per-user).

drop policy if exists user_coach_usage_own_insert on user_coach_usage;
create policy user_coach_usage_no_insert
  on user_coach_usage for insert
  with check (false);

drop policy if exists user_coach_usage_own_update on user_coach_usage;
create policy user_coach_usage_no_update
  on user_coach_usage for update
  using (false)
  with check (false);

revoke insert, update, delete on public.user_coach_usage from anon, authenticated;
