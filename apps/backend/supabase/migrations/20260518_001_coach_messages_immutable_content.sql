-- Restrict coach_messages UPDATE to (archived_at, reaction) only.
--
-- The owner-update policy added in 20260512 gates on `auth.uid() =
-- user_id` but allows any column to change. A user could overwrite
-- their own assistant messages' content or flip role from assistant
-- to user — no cross-user exposure, but breaks the auditability of
-- the conversation log (and would corrupt any future model-quality
-- signal that reads from it).
--
-- The only mutations the client ever issues are:
--   - archive: set archived_at = now() (CoachChat.archiveCurrentThread)
--   - react:   set reaction = 'up' | 'down' | null (CoachChat.reactTo)
-- Both of those need only those two columns. Column-level GRANT is a
-- cleaner enforcement than a trigger or a WITH CHECK self-subquery —
-- PostgREST honours per-column UPDATE grants and rejects mutations
-- that touch other columns at the gateway.
--
-- RLS still scopes which rows a user can touch; this migration scopes
-- which columns within those rows.

revoke update on coach_messages from authenticated;
grant update (archived_at, reaction) on coach_messages to authenticated;
