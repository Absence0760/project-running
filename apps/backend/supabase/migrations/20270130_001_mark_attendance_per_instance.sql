-- mark_attendance ignored the occurrence: its UPDATE matched only
-- (event_id, user_id), but event_attendees is keyed
-- (event_id, user_id, instance_start) — one row per occurrence of a recurring
-- event. So a host marking a single class (e.g. this week's Vinyasa) stamped the
-- same attendance on EVERY occurrence the attendee had RSVP'd to, making the
-- column meaningless for any recurring class (instructor_business.md M6).
--
-- Re-create the RPC with a p_instance_start parameter and scope the UPDATE to
-- that one occurrence. The 3-arg form is dropped so no caller can keep writing
-- across instances. Full body re-stated (signature change), preserving the
-- value guard + organiser check + sole-writer model from 20270102_001.

drop function if exists mark_attendance(uuid, uuid, text);

create function mark_attendance(
  p_event_id uuid,
  p_user_id uuid,
  p_instance_start timestamptz,
  p_attendance text
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_club uuid;
begin
  if p_attendance is not null and p_attendance not in ('attended', 'no_show') then
    raise exception 'invalid attendance value: %', p_attendance
      using errcode = 'check_violation';
  end if;

  select e.club_id into v_club
  from events e
  where e.id = p_event_id;

  if v_club is null then
    raise exception 'event not found' using errcode = 'no_data_found';
  end if;

  if not is_event_organiser(v_club) then
    raise exception 'only the event organiser can mark attendance'
      using errcode = 'insufficient_privilege';
  end if;

  update event_attendees
  set attendance = p_attendance
  where event_id = p_event_id
    and user_id = p_user_id
    and instance_start = p_instance_start;

  if not found then
    raise exception 'attendee not found' using errcode = 'no_data_found';
  end if;
end;
$$;

revoke execute on function mark_attendance(uuid, uuid, timestamptz, text) from public;
grant execute on function mark_attendance(uuid, uuid, timestamptz, text) to authenticated;
