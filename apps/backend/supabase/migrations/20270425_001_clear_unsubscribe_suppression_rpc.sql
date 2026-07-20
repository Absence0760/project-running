-- Re-opt-in escape hatch for a user-initiated unsubscribe suppression.
--
-- The one-click unsubscribe endpoint (worker internal/unsubscribe) both flips
-- the per-stream opt-in pref off AND inserts an email_suppressions row keyed by
-- the user's address (reason 'unsubscribe'). email_suppressions has fail-closed
-- RLS (no policy → anon/authenticated denied entirely; service_role only), and
-- nothing cleared an 'unsubscribe' row — so a user who unsubscribed once then
-- re-enabled the stream via Settings had the pref show 'on' while the
-- address-keyed hard-block silently dropped every future send (issue #392).
--
-- This RPC is the missing clear path: when a user re-opts into an engagement
-- stream (a pref flips off→on in Settings), the web client calls it to lift the
-- user-initiated block so the per-stream pref becomes the authoritative gate
-- again. It is deliberately narrow:
--   * SECURITY DEFINER (authenticated cannot touch the fail-closed table
--     directly), with search_path pinned as the hijack defence.
--   * The address is resolved from the caller's own auth.users row via
--     auth.uid() — never a parameter — so a user can only ever clear their OWN
--     suppression. This matches the exact address the worker keys the row on
--     (auth.users.email via the GoTrue admin API).
--   * reason = 'unsubscribe' ONLY. A 'bounce' / 'complaint' / 'manual'
--     suppression is a deliverability / abuse signal, NOT reversible by the
--     recipient toggling a pref, and is left untouched.

create or replace function public.clear_my_unsubscribe_suppression()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_cleared integer;
begin
  select email into v_email from auth.users where id = auth.uid();
  if v_email is null or v_email = '' then
    return 0;
  end if;

  delete from public.email_suppressions
   where email = v_email
     and reason = 'unsubscribe';
  get diagnostics v_cleared = row_count;
  return v_cleared;
end;
$$;

revoke execute on function public.clear_my_unsubscribe_suppression() from public, anon;
grant execute on function public.clear_my_unsubscribe_suppression() to authenticated;
