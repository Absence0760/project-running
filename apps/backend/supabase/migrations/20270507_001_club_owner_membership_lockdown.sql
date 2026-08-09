-- A club admin cannot demote, remove, or impersonate the club OWNER.
--
-- `20260416_001` gave admins two blanket policies over `club_members`:
--
--   create policy "admins can manage members" ... for delete using (is_club_admin(club_id));
--   create policy "admins can change roles"   ... for update using (is_club_admin(club_id));
--
-- Neither inspects the TARGET row, and `private.is_club_admin` treats 'owner'
-- and 'admin' identically — so an admin the owner delegated moderation to can
-- turn on the owner with one REST call:
--
--   PATCH  /rest/v1/club_members?club_id=eq.<c>&user_id=eq.<owner>  {"role":"member"}
--   DELETE /rest/v1/club_members?club_id=eq.<c>&user_id=eq.<owner>
--
-- Either one strips the real owner of `private.is_club_admin`, which is what
-- gates "club admins can update their club", event + organiser management, and
-- the join-request queue — while the attacker keeps full admin. The owner is
-- left with only the `clubs.owner_id`-gated delete-the-whole-club escape.
-- The same missing target check lets an admin PATCH their OWN row to
-- `role = 'owner'` and wear the owner badge every other member sees.
--
-- The product already knew the rule: the web Members tab renders the role
-- selector and the remove button only under
-- `{#if isAdmin && m.role !== 'owner' && m.user_id !== club?.owner_id}`
-- (apps/web/src/routes/clubs/[slug]/+page.svelte), and `removeMember`'s comment
-- in data.ts claims "the trigger rejecting an owner-row delete will block a
-- misuse" — there is no such trigger. The gate was UI-only. Push it into RLS,
-- the same way `20260702_001` pinned `role = 'member'` on the self-join INSERT
-- so a joiner could not claim 'admin'/'owner'.
--
-- The owner's own row is untouched by these policies afterwards; the separate
-- permissive "users can leave clubs" policy (auth.uid() = user_id) still lets
-- the owner delete their own membership, so account deletion is unaffected.

-- Owner lookup that bypasses `clubs` RLS, mirroring `private.route_owner_id`
-- (20270428_001): a plain sub-select on `clubs` inside a policy is itself
-- RLS-gated and can read NULL in a nested context, which would silently
-- re-open the branch it is meant to close.
create or replace function private.club_owner_id(p_club_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$ select owner_id from clubs where id = p_club_id $$;

revoke execute on function private.club_owner_id(uuid) from public;
grant execute on function private.club_owner_id(uuid)
  to anon, authenticated, service_role;

drop policy if exists "admins can change roles" on club_members;
create policy "admins can change roles"
  on club_members for update
  to authenticated
  using (
    private.is_club_admin(club_members.club_id)
    and club_members.user_id is distinct from private.club_owner_id(club_members.club_id)
  )
  with check (
    private.is_club_admin(club_members.club_id)
    and club_members.user_id is distinct from private.club_owner_id(club_members.club_id)
    and club_members.role <> 'owner'
  );

drop policy if exists "admins can manage members" on club_members;
create policy "admins can manage members"
  on club_members for delete
  to authenticated
  using (
    private.is_club_admin(club_members.club_id)
    and club_members.user_id is distinct from private.club_owner_id(club_members.club_id)
  );
