-- F16 (audit-db-design / audit-db-optimization): four status/policy columns
-- on the social layer were declared as bare `text` with the legal set only in
-- a trailing comment — nothing rejected an out-of-domain write.
--
-- Decision D2 (remediation): standardize on `text` + CHECK as the house style
-- for closed string domains (the Dart generator can't parse `create type ...
-- as enum`, so real enums carry a codegen cost; the three pre-existing real
-- enums — workout_kind, plan_phase, goal_event — are grandfathered). These
-- four columns are the gap the audit found.
--
-- The legal sets are taken from the values the RLS policies, triggers, and
-- client overlays already produce/consume, NOT from the original creation
-- comments (which were stale):
--   * event_attendees.status — 'going' | 'maybe' | 'declined' | 'waitlisted'
--     ('waitlisted' added by 20261018_001's capacity/waitlist flow; the
--     RsvpStatus TS union in apps/web/src/lib/types.ts carries all four).
--   * clubs.join_policy — 'open' | 'request' | 'invite' (JoinPolicy union).
--   * club_members.status — 'active' | 'pending' | 'rejected' ('rejected' is
--     read by the 20260926_001 RLS split; the join-request flow writes
--     'pending'/'active').
--   * events.recurrence_freq — null | 'weekly' | 'biweekly' | 'monthly'
--     (nullable: a one-off event has no recurrence; RecurrenceFreq union).
--
-- integrations.provider is intentionally NOT touched here — it already has a
-- CHECK from 20260505_001.

alter table event_attendees
  add constraint event_attendees_status_check
  check (status in ('going', 'maybe', 'declined', 'waitlisted'));

alter table clubs
  add constraint clubs_join_policy_check
  check (join_policy in ('open', 'request', 'invite'));

alter table club_members
  add constraint club_members_status_check
  check (status in ('active', 'pending', 'rejected'));

alter table events
  add constraint events_recurrence_freq_check
  check (recurrence_freq is null or recurrence_freq in ('weekly', 'biweekly', 'monthly'));
