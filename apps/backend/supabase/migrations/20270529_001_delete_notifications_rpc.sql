-- Dismissing a notification group is ONE transaction again.
--
-- The client used to hand the whole id list to a single PostgREST `in` filter.
-- That filter is serialised into the request URL, which puts a bulk dismiss at
-- the mercy of whatever request-line budget the gateway in front of PostgREST
-- happens to enforce: measured against the local stack the request is REFUSED
-- with a 414 past roughly 200 ids, while decisions § 653 records a gateway that
-- answered 200 with an empty match instead. Either way the rows survive a large
-- dismiss, and which of the two you get is a property of the deployment rather
-- than of the code. The fix chunked the list, which bought a third failure:
-- chunk 3 of 5 can fail and leave the inbox half-dismissed, with the undo offer
-- already spent.
--
-- Neither shape is right, because the client was choosing between them at all.
-- An array argument travels in the RPC's POST body, which carries no such
-- bound, and one function call is one statement in one transaction: every id
-- goes, or none does.
--
-- SECURITY INVOKER, and the RLS policy is the whole authorisation story. The
-- "users delete their own notifications" policy (20260528000001) already reads
-- `auth.uid() = user_id`, so a caller naming a stranger's id deletes zero rows
-- and is told so by the returned count. A DEFINER variant would have to
-- re-derive that same predicate by hand, with nothing left to catch it if the
-- two ever drifted.
--
-- The cap is explicit on purpose. An unbounded array is not free — it is row
-- locks held for the length of one statement — but silently truncating it
-- would re-open, in a new place, exactly the bug this migration closes. Past
-- the cap the call RAISES; it never deletes a prefix. Both inboxes page at 100
-- rows, so 1000 is far above any dismiss a surface can actually assemble.
--
-- Lock impact (migration_locks.md): one function body. No table DDL, no
-- constraint, no backfill — CREATE FUNCTION locks the pg_proc entry only.

create or replace function delete_notifications(p_ids uuid[])
returns integer
language plpgsql
volatile
security invoker
set search_path = public
as $$
declare
  v_ids   uuid[]  := coalesce(p_ids, '{}'::uuid[]);
  v_count integer := coalesce(array_length(v_ids, 1), 0);
begin
  if v_count = 0 then
    return 0;
  end if;

  if v_count > 1000 then
    raise exception 'delete_notifications: % ids exceeds the 1000-id limit', v_count
      using errcode = '22023';
  end if;

  delete from notifications where id = any (v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Supabase's default privileges hand every new public function to anon as well,
-- so the revoke names it: a mutation has no business being reachable without a
-- session, even though RLS would already match zero rows for one.
revoke execute on function delete_notifications(uuid[]) from public, anon;
grant  execute on function delete_notifications(uuid[]) to authenticated;
