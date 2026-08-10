-- An authenticated client cannot write an `event_results` row at all.
--
-- Verified against the local stack: any INSERT / UPDATE(duration_s,
-- finisher_status) / DELETE on `event_results` by the `authenticated` role
-- aborts with
--
--   42501 permission denied for function recompute_event_ranks
--   CONTEXT: SQL statement "SELECT recompute_event_ranks(new.event_id, new.instance_start)"
--            PL/pgSQL function event_results_rerank_trigger() line 7 at PERFORM
--
-- `recompute_event_ranks` is SECURITY DEFINER (`20260615_001`) but
-- `event_results_rerank_trigger` is not, so the AFTER trigger executes in the
-- writer's own context and needs the writer to hold EXECUTE. `20260711_001`
-- revoked EXECUTE `from public, anon` as a definer-grant-hygiene closure;
-- `authenticated` held it only through `PUBLIC`, so the revoke took it as
-- collateral, and `20261222_001` re-emitted the same revoke. No migration ever
-- granted it back — the ACL is `postgres=X` alone. Every race-result write from
-- web or mobile has been failing since.
--
-- Two ways to close it, and they are not equivalent:
--
--   (a) grant EXECUTE on `recompute_event_ranks` to `authenticated` — the shape
--       `rls_function_hygiene_test.sql` assertion 7 asserts. But the function
--       takes no ownership check: it re-ranks every result row of whatever
--       (event, instance) it is handed and stamps `updated_at`. Granting it
--       publishes a PostgREST RPC any signed-in user can aim at any event —
--       exactly what assertion 6 of the same suite says the revoke exists to
--       prevent. The two assertions were written at different times and
--       contradict each other.
--   (b) make the trigger SECURITY DEFINER, so it runs as the owner and does not
--       consult the writer's grants at all.
--
-- (b) is the fix. It is also the schema's dominant pattern — every other
-- trigger function that mutates a table the writer may not own is definer
-- (`enforce_event_capacity`, `promote_event_waitlist`, `enroll_club_owner`,
-- `clubs_member_count_trigger`, `routes_run_count_trigger`,
-- `gym_sets_maintain_totals`), for this precise reason. The re-rank RPC stays
-- closed to `public`, `anon`, and `authenticated`; assertion 7 is replaced with
-- the behaviour it was standing in for (an authenticated insert succeeds and
-- lands a rank), which is a stronger guard than the grant proxy.
--
-- Bare-body `create or replace` strips prior fixes: this is the COMPLETE live
-- definition (`20260424_001`'s body, unchanged) plus `security definer`. The
-- body performs no work of its own beyond dispatching to the already-definer
-- recompute, so the elevation adds no reachable capability.
--
-- No column changes, so no row-type regeneration is owed.

create or replace function event_results_rerank_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'DELETE') then
    perform recompute_event_ranks(old.event_id, old.instance_start);
    return old;
  else
    perform recompute_event_ranks(new.event_id, new.instance_start);
    return new;
  end if;
end;
$$;

revoke execute on function recompute_event_ranks(uuid, timestamptz)
  from public, anon, authenticated;
