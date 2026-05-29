-- Activity-risk acknowledgement at club join (parkrun persona #45). The app's
-- Terms cover the software, not the physical risk of group runs. A club can
-- now require members to acknowledge that risk when joining, and the
-- acknowledgement timestamp is recorded on the membership for the organiser's
-- audit trail.
--
-- Two plain column adds (the Dart generator understands `add column`):
--   clubs.requires_activity_waiver  — admin opt-in per club.
--   club_members.activity_waiver_ack_at — when the member acknowledged.

alter table clubs
  add column requires_activity_waiver boolean not null default false;

alter table club_members
  add column activity_waiver_ack_at timestamptz;
