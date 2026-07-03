-- Unblock account deletion: three FKs referencing auth.users would raise on
-- `auth.admin.deleteUser` (the delete-account Edge Function's final step),
-- denying the GDPR / CCPA right-to-erasure the EF exists to satisfy. Same class
-- of regression 20260728_001 fixed for the original eight tables — three later
-- migrations reintroduced it on new tables.
--
-- Chosen semantic for all three: ON DELETE SET NULL, NOT cascade. Each of these
-- columns names the *creator / host* of a shared object (a challenge other
-- runners have joined, a race's aid-station structure the public results depend
-- on, a club event with registered attendees). Cascading would destroy other
-- users' data when the author deletes their account; SET NULL orphans the
-- authored object so it keeps working while the author identity becomes
-- unrecoverable. The delete-account EF does not touch these tables explicitly —
-- it relies on the FK behaviour here.
--
-- 1. challenges.creator_id — self-contradictory today: `not null` AND
--    `on delete set null`. The SET NULL can never fire, so the auth-row delete
--    23502s for any user who created a challenge. The FK was already SET NULL;
--    the bug is the NOT NULL. Drop it so the SET NULL can take effect. RLS
--    (`creator_id = auth.uid()`) and is_challenge_visible tolerate a null
--    creator; a public / club challenge stays visible to its participants.
alter table challenges alter column creator_id drop not null;

-- 2. event_checkpoints.created_by — `not null` with no ON DELETE (defaults to
--    NO ACTION / RESTRICT), so deleting a race director who created any
--    checkpoint 23503s. Make it nullable + SET NULL: the aid-station / cutoff
--    structure survives for the event and its public results, the organiser
--    identity is dropped.
alter table event_checkpoints alter column created_by drop not null;
alter table event_checkpoints
  drop constraint event_checkpoints_created_by_fkey,
  add constraint event_checkpoints_created_by_fkey
    foreign key (created_by) references auth.users (id) on delete set null;

-- 3. events.host_user_id — nullable already, but no ON DELETE (RESTRICT).
--    Dormant today (host defaults to author, whose FK cascades) but blocks
--    deletion for a delegated host once paid-events host delegation ships.
--    SET NULL: the event survives with no payout recipient (correct — the host
--    is gone), attendees and the owning club keep their data.
alter table events
  drop constraint events_host_user_id_fkey,
  add constraint events_host_user_id_fkey
    foreign key (host_user_id) references auth.users (id) on delete set null;
