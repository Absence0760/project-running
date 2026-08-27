-- Make the column-level WRITE lockdowns actually lock, and make anon never
-- wider than authenticated.
--
-- Four tables re-grant INSERT and/or UPDATE column by column for the app roles
-- (achievements 20270506_001, challenge_participants 20270209_001,
-- coach_messages 20260518_001, event_attendees 20270102_001 + 20270520_001).
-- Three defects, each measured against the local stack before this migration
-- was written:
--
-- (1) challenge_participants still carried a TABLE-level INSERT beside its
--     column-scoped UPDATE — the exact asymmetry decisions.md 584 found on
--     event_attendees and 20270520_001 closed there. INSERT and DELETE are both
--     own-row verbs here ("users join visible challenges" / "users leave their
--     own challenge"), so the completed_at lockdown the 20270209_001 header
--     describes, and that challenge_participants_completed_lockdown_test pins
--     against a direct UPDATE, was reachable in two statements:
--
--       delete from challenge_participants where challenge_id = <mine>;
--       insert into challenge_participants (challenge_id, user_id, completed_at)
--         values (<mine>, auth.uid(), now());
--
--     Verified under the participant's own JWT: the UPDATE raises 42501 and the
--     round trip writes completed_at unchallenged. joined_at, deliberately
--     omitted from the UPDATE grant by the same header, was backdatable the
--     same way. The re-grant below is exactly the three columns both clients
--     send (joinChallenge in apps/web/src/lib/core/data.ts and
--     apps/mobile_android/lib/social_service.dart both insert
--     {challenge_id, user_id, team_club_id} and nothing else), so leaving and
--     rejoining now resets completed_at to null and joined_at to now() —
--     which is what leaving and rejoining means.
--
-- (2) coach_messages was the ONE place in the whole public schema where anon
--     held a privilege authenticated does not: a table-level UPDATE, against
--     authenticated's column-scoped (archived_at, reaction). 20260518_001
--     revoked the table grant from `authenticated` only, and 20270408_001 —
--     generated from the drifted prod schema — version-controlled the leftover.
--     It is inert today because coach_messages_owner_update reads
--     `auth.uid() = user_id` and anon's auth.uid() is null, but that is RLS
--     covering for a grant, not a decision. decisions.md 759 made the same
--     argument for SELECT: a divergence is a leak on the wider side, not a
--     variant worth carrying silently.
--
-- (3) coach_messages' INSERT was table-wide, so a client could choose its own
--     `id` and backdate `created_at` — against a lockdown whose stated purpose
--     is "the auditability of the conversation log". role='assistant' forgery
--     was already blocked by coach_messages_owner_insert's WITH CHECK, and
--     stays blocked. The four columns re-granted are exactly what the only
--     client insert site sends (CoachChat.svelte's legacy-thread migration);
--     the assistant turn is written by the secret-key client in
--     apps/web/src/lib/coach/handler.ts, which is service_role and unaffected.
--
-- achievements needs no INSERT carve-out because it needs no client INSERT at
-- all: awards come only from award_achievements_for_user (SECURITY DEFINER),
-- and the table has no permissive INSERT or DELETE policy, so both grants are
-- already dead — measured, an insert as the owner raises 42501 "new row
-- violates row-level security policy". Revoking them is therefore a statement
-- of intent rather than a behaviour change, in the same spirit as
-- decisions.md 584's third change: stating an invariant at the privilege layer
-- is cheaper than re-deriving that RLS happens to cover for it. It also keeps
-- the class invariant uniform — after this migration no table in the write
-- registry grants a client an INSERT surface it has not thought about.
--
-- Online safety: GRANT and REVOKE take NO lock on the target relation. Measured
-- on this Postgres — a `revoke insert on public.achievements from anon` inside
-- an open transaction holds only AccessShareLock on pg_class and its indexes,
-- never anything on `achievements`. There is no table scan and no rewrite, so
-- none of docs/backend/migration_locks.md's online-DDL machinery applies.

-- (1) challenge_participants: mirror 20270520_001's event_attendees fix. A
-- single-column `revoke insert (completed_at)` would be a no-op while a
-- table-level INSERT grant exists, so drop the table grant and re-grant
-- per-column.
revoke insert on public.challenge_participants from anon, authenticated;
grant insert (challenge_id, user_id, team_club_id)
  on public.challenge_participants to authenticated;

-- (2) + (3) coach_messages.
revoke update on public.coach_messages from anon;
revoke insert on public.coach_messages from anon, authenticated;
grant insert (user_id, plan_id, role, content)
  on public.coach_messages to authenticated;

-- (4) achievements: no client write path exists at all beyond the is_public
-- toggle 20270506_001 kept.
revoke insert, delete on public.achievements from anon, authenticated;
