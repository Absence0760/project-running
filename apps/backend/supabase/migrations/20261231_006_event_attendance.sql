-- M6 (instructor_business.md): attendance as a concept distinct from RSVP.
--
-- A paid/RSVP'd seat is not the same as a body in the room. The host of a
-- `class` event needs to record who actually showed up — paid != attended —
-- without that signal being conflated with the attendee's own RSVP status.
--
-- Design (instructor_business.md risk #5 — LEAN ENUM, not a check-in
-- timestamp): a single nullable `attendance` column on event_attendees.
-- NULL = not yet marked; 'attended'/'no_show' = the host's call. The RSVP
-- `status` column is left untouched and stays orthogonal — a 'going' RSVP
-- with attendance NULL is the normal pre-class state.
--
-- The CHECK is written as a bare `attendance in (...)` (not
-- `attendance is null or ...`) deliberately: a CHECK passes when its
-- expression is NULL under SQL three-valued logic, so this already permits
-- NULL while staying parseable by check_constraint_unions.mjs (which keys
-- the EventAttendance TS union to this constraint).

alter table event_attendees
  add column attendance text;

alter table event_attendees
  add constraint event_attendees_attendance_check
  check (attendance in ('attended', 'no_show'));

-- Who may write attendance: only the event's organiser, and ONLY this column.
--
-- We do NOT loosen the existing self-only UPDATE policy ("users can update
-- their own RSVP" from 20260416_001) — that would let a host rewrite an
-- attendee's RSVP status, or an attendee write their own attendance. Instead
-- attendance flows through a SECURITY DEFINER RPC that checks
-- is_event_organiser and touches the attendance column alone (least
-- privilege). Reads are already covered by the existing attendee SELECT
-- policy (anyone who can see the event sees the attendee rows), so attendance
-- is host-written, attendee-readable with no new SELECT policy.
--
-- `private.is_event_organiser` (moved out of public in 20261120_001) is
-- reachable from this definer body because search_path includes `private`.
create or replace function mark_attendance(
  p_event_id uuid,
  p_user_id uuid,
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
    and user_id = p_user_id;

  if not found then
    raise exception 'attendee not found' using errcode = 'no_data_found';
  end if;
end;
$$;

revoke execute on function mark_attendance(uuid, uuid, text) from public;
grant execute on function mark_attendance(uuid, uuid, text) to authenticated;

-- Lock the `attendance` column against direct writes so the RPC is the ONLY
-- write path. The self-only RSVP UPDATE policy from 20260416_001 stays intact
-- (an attendee can still change their own `status`), but column grants
-- compose with RLS: an UPDATE touching `attendance` needs the column
-- privilege too, and authenticated/anon no longer hold it. The SECURITY
-- DEFINER RPC runs as the table owner so it is unaffected — host-written,
-- attendee-readable.
--
-- A single-column `revoke update (attendance)` would be a no-op while a
-- TABLE-level UPDATE grant exists (the table grant implies every column).
-- So we drop the table-level UPDATE and re-grant it per-column on exactly the
-- columns the existing client write paths touch — the RSVP upsert
-- (event_id/user_id/status/instance_start) and walk-up org-add. `order_id`
-- stays service-role-only (paid path); `joined_at` keeps its default;
-- `attendance` is deliberately omitted.
revoke update on event_attendees from authenticated, anon;
grant update (event_id, user_id, status, instance_start)
  on event_attendees to authenticated;
