-- audit-gdpr #11 (GDPR Art 7(3)): consent must be as easy to withdraw as it
-- is to give. AI-coach consent is stamped by record_coach_consent()
-- (first-stamp-wins) and the lock_consent_columns trigger (20261110_001)
-- blocks any direct write to coach_consent_at — so the documented withdrawal
-- path was "just stop using it", which is not a meaningful withdrawal
-- mechanism. This adds the sanctioned inverse: a SECURITY DEFINER RPC that
-- clears the stamp for the caller. Once cleared, the coach request handler's
-- existing 403 gate (apps/web/src/lib/coach/handler.ts — coach_consent_at
-- null → refuse) re-blocks the Coach until the user re-consents through
-- record_coach_consent(). Same trust model as record_coach_consent(): raise
-- the transaction-local app.consent_write flag just before the write so the
-- lock trigger lets this one through; a client can't prepend a set_config to
-- a single PostgREST UPDATE, so only this function can raise it.

create or replace function withdraw_coach_consent()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  perform set_config('app.consent_write', 'on', true);
  update user_profiles
    set coach_consent_at = null
    where id = v_uid;
end;
$$;

revoke all on function withdraw_coach_consent() from public, anon;
grant execute on function withdraw_coach_consent() to authenticated, service_role;
