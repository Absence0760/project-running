-- Fix: a club owner could not delete their account (GDPR Art-17 erasure
-- failure).
--
-- clubs_member_count_trigger() ran SECURITY INVOKER — unlike every sibling
-- derived-count trigger (routes_run_count_trigger,
-- refresh_personal_records_for_user are both SECURITY DEFINER). When a club
-- owner's account is deleted, GoTrue's admin.deleteUser runs the auth.users
-- delete as the `supabase_auth_admin` role. The ON DELETE CASCADE strips the
-- owner's club_members row, firing this AFTER DELETE trigger, whose
-- `update clubs set member_count = ...` then executes as supabase_auth_admin —
-- which has NO UPDATE privilege on public.clubs. The UPDATE raises
-- permission-denied; GoTrue surfaces the generic "Database error deleting
-- user"; the delete-account Edge Function returns 500. Net effect: ANY club
-- owner is undeletable.
--
-- It hid from schema-level checks because a superuser `delete from auth.users`
-- (e.g. `supabase db reset`, raw psql) cascades fine — the privilege gap only
-- bites under the auth_admin role GoTrue actually uses — and from the e2e saga
-- fixture, which pre-deletes owned clubs (OWNER_TABLES) before the auth delete.
--
-- Fix: SECURITY DEFINER + a pinned search_path, matching every sibling count
-- trigger, so the cascade UPDATE runs as the function owner regardless of which
-- role drives the delete. Full body re-emitted per the "bare-body create or
-- replace strips prior fixes" rule.
create or replace function clubs_member_count_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'active' then
      update clubs set member_count = member_count + 1 where id = new.club_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.status = 'active' then
      update clubs set member_count = greatest(member_count - 1, 0) where id = old.club_id;
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    if old.status is distinct from new.status then
      if old.status = 'active' then
        update clubs set member_count = greatest(member_count - 1, 0) where id = old.club_id;
      end if;
      if new.status = 'active' then
        update clubs set member_count = member_count + 1 where id = new.club_id;
      end if;
    end if;
    if old.club_id is distinct from new.club_id then
      if old.status = 'active' then
        update clubs set member_count = greatest(member_count - 1, 0) where id = old.club_id;
      end if;
      if new.status = 'active' then
        update clubs set member_count = member_count + 1 where id = new.club_id;
      end if;
    end if;
    return new;
  end if;
  return null;
end;
$$;
