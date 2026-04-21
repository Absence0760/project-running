-- Finer-grained club roles. Adds `event_organiser` and `race_director`
-- to the existing `owner | admin | member` set.
--
-- Both are strictly weaker than admin — they can manage their specific
-- domain (events / races) but cannot change club settings, remove
-- members, or post as an admin. The role column had no CHECK constraint
-- (only a comment), so we add one now to prevent garbage.
--
-- Also relaxes the feed to let any active member post (not just admins),
-- and opens race_sessions + event_attendee-add to the new roles.

alter table club_members
  add constraint club_members_role_check
  check (role in ('owner', 'admin', 'event_organiser', 'race_director', 'member'));

-- New helper functions, following the pattern of is_club_admin / is_club_member.

create or replace function is_event_organiser(target_club uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from club_members
    where club_id = target_club
      and user_id = auth.uid()
      and status = 'active'
      and role in ('owner', 'admin', 'event_organiser')
  );
$$;

create or replace function is_race_director(target_club uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from club_members
    where club_id = target_club
      and user_id = auth.uid()
      and status = 'active'
      and role in ('owner', 'admin', 'race_director')
  );
$$;

-- ─── Club posts: any active member can post ───

-- Drop the old admin-only INSERT policy and replace it.
drop policy if exists "admins can post" on club_posts;

create policy "members can post"
  on club_posts for insert
  with check (is_club_member(club_id) and author_id = auth.uid());

-- ─── Events: event_organiser can create + edit ───

drop policy if exists "admins can create events" on events;
create policy "organisers can create events"
  on events for insert
  with check (is_event_organiser(club_id) and created_by = auth.uid());

drop policy if exists "admins can edit events" on events;
create policy "organisers can edit events"
  on events for update
  using (is_event_organiser(club_id));

drop policy if exists "admins can delete events" on events;
create policy "organisers can delete events"
  on events for delete
  using (is_event_organiser(club_id));

-- ─── Event attendees: organiser can add others ───

-- The existing "anyone RSVPs themselves" policy stays. Add one that
-- lets event_organiser + admin add someone else (e.g. "register a
-- walk-up participant who doesn't have the app").
create policy "organisers can add attendees"
  on event_attendees for insert
  with check (
    auth.uid() = user_id   -- self-RSVP (existing path)
    or exists (
      select 1 from events e
      where e.id = event_attendees.event_id
        and is_event_organiser(e.club_id)
    )
  );

-- Drop the narrower self-only INSERT if it existed separately. The
-- combined policy above handles both cases, so we don't want both
-- firing. The policy name varies between migrations; catch both.
drop policy if exists "users can rsvp" on event_attendees;
drop policy if exists "attendees can rsvp" on event_attendees;

-- ─── Race sessions: race_director can arm / start / end ───

drop policy if exists race_sessions_admin_insert on race_sessions;
create policy race_sessions_director_insert
  on race_sessions for insert
  with check (
    exists (
      select 1 from events e
      where e.id = race_sessions.event_id
        and is_race_director(e.club_id)
    )
  );

drop policy if exists race_sessions_admin_update on race_sessions;
create policy race_sessions_director_update
  on race_sessions for update
  using (
    exists (
      select 1 from events e
      where e.id = race_sessions.event_id
        and is_race_director(e.club_id)
    )
  );

drop policy if exists race_sessions_admin_delete on race_sessions;
create policy race_sessions_director_delete
  on race_sessions for delete
  using (
    exists (
      select 1 from events e
      where e.id = race_sessions.event_id
        and is_race_director(e.club_id)
    )
  );

-- ─── Event results: race_director can approve ───

-- The approve_event_result RPC was admin-only. Replace it so
-- race_director can too.
create or replace function approve_event_result(
  p_event_id uuid,
  p_instance_start timestamptz,
  p_user_id uuid,
  p_approve boolean
) returns event_results language plpgsql security definer set search_path = public as $$
declare
  v_row event_results;
  v_club uuid;
begin
  select club_id into v_club from events where id = p_event_id;
  if v_club is null or not is_race_director(v_club) then
    raise exception 'Not authorised to approve results for this event';
  end if;
  update event_results
    set organiser_approved = p_approve,
        organiser_approved_by = auth.uid(),
        organiser_approved_at = now(),
        updated_at = now()
    where event_id = p_event_id
      and instance_start = p_instance_start
      and user_id = p_user_id
    returning * into v_row;
  return v_row;
end;
$$;

-- ─── Event results: race_director can edit / delete ───

drop policy if exists event_results_update_self_or_admin on event_results;
create policy event_results_update_self_or_director
  on event_results for update
  using (
    auth.uid() = user_id
    or exists (
      select 1 from events e
      where e.id = event_results.event_id
        and is_race_director(e.club_id)
    )
  )
  with check (
    auth.uid() = user_id
    or exists (
      select 1 from events e
      where e.id = event_results.event_id
        and is_race_director(e.club_id)
    )
  );

drop policy if exists event_results_delete_self_or_admin on event_results;
create policy event_results_delete_self_or_director
  on event_results for delete
  using (
    auth.uid() = user_id
    or exists (
      select 1 from events e
      where e.id = event_results.event_id
        and is_race_director(e.club_id)
    )
  );
