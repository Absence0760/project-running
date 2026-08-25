-- Issue #789 (decisions § 718 open item 1 / § 721). Withdrawing health-data
-- consent must stop erasing `user_profiles.date_of_birth`.
--
-- The column carries two purposes on two lawful bases, and only one of them
-- is the consent being withdrawn:
--
--   * `user_profiles.date_of_birth` is the AGE RECORD. Its consumers are the
--     under-18 exclusions inside `search_user_profiles` (20261017_001 /
--     20261104_001), `discoverable_runners_near` (20270424000005) and the
--     auto-hide report path (20270218_001) — a child-protection purpose that
--     never rested on the runner's Art 9 consent and must not be defeated by
--     withdrawing it. Erasing it here made a declared minor name-searchable
--     and locatable again the moment they exercised an unrelated right.
--   * `user_settings.prefs.date_of_birth` is the Art 9 HEALTH-USE MIRROR
--     (coach context, HR-max derivation). That copy follows consent in both
--     directions and every client clears it on withdrawal; nothing in this
--     RPC touches it.
--
-- Withdrawal is not erasure. GDPR Art 7(3) ends the processing that the
-- consent authorised; Art 17 erasure is a separate right with its own path
-- (`delete-account`, which drops the auth.users row and cascades
-- user_profiles away entirely — `user_profiles_id_fkey` on delete cascade,
-- 20260728_001). So the age record survives a withdrawal and does not
-- survive a deletion, which is exactly the split the two rights describe.
--
-- Until this landed every client compensated by re-asserting the age record
-- immediately after calling the RPC (§ 718). A client that crashed between
-- the two calls left the minor discoverable until their next save. This is a
-- bare-body `create or replace` on top of 20270418_001 — no signature
-- change, no type regeneration, and the client compensation is removed in
-- the same change.
--
-- height_cm, gender and the body_metrics weight series are untouched by this
-- migration: they are Art 9 through and through, they have no child-safety
-- consumer, and they still go in the same transaction.

create or replace function withdraw_health_data_consent()
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
  -- Insert-or-update so the withdrawal ALWAYS lands a row carrying the
  -- withdrawn state — a 0-row silent no-op here means special-category
  -- data lives on while the user believes it erased.
  --
  -- `date_of_birth` is deliberately absent: it is the child-safety age
  -- record, not an Art 9 column (§ 721).
  insert into user_profiles (id)
  values (v_uid)
  on conflict (id) do update
    set health_data_consent_at = null,
        height_cm = null,
        gender = null;
  -- Art 7(3): the special-category weight series goes in the same
  -- transaction — no partial-failure window between two client calls.
  delete from body_metrics where user_id = v_uid;
end;
$$;

revoke all on function withdraw_health_data_consent() from public, anon;
grant execute on function withdraw_health_data_consent() to authenticated, service_role;
