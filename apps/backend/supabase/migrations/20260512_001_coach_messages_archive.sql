-- Archive support for coach chat threads.
--
-- Before this migration, "Clear chat" deleted every row for a (user,
-- plan) — there was no way to keep a thread for later. Runners hitting
-- the Clear button after a useful conversation lost the only copy.
--
-- The model: `archived_at` is null for messages in the active thread;
-- "Start new conversation" updates every active row in a (user, plan)
-- to the same `now()`, grouping them into one archived conversation.
-- All rows sharing an `archived_at` value (within the same user × plan)
-- form one historical thread. The history list is `select distinct
-- archived_at ... where archived_at is not null`.
--
-- Per-archive delete is still available if a user wants a specific
-- thread gone — `delete ... where archived_at = $T` is RLS-scoped.

alter table coach_messages
  add column archived_at timestamptz;

-- Hot read shapes after this change:
--   1. Active thread: where user_id=X and plan_id=Y and archived_at is null order by created_at
--   2. Per-archive thread: where user_id=X and plan_id=Y and archived_at=$T order by created_at
--   3. Archive list: select distinct archived_at where user_id=X and plan_id=Y and archived_at is not null
-- A composite index on (user_id, plan_id, archived_at, created_at)
-- satisfies all three without a sort step. The previous index was a
-- strict prefix of this one, so we drop it.
drop index coach_messages_user_plan_created_idx;
create index coach_messages_user_plan_archive_created_idx
  on coach_messages (user_id, plan_id, archived_at, created_at);

-- The original migration deliberately left out an UPDATE policy
-- ("messages are immutable"). Archiving needs to flip `archived_at` on
-- existing rows, so the policy lands here. RLS still scopes writes to
-- the owner; content / role flips aren't enforced at the DB level —
-- the client just doesn't issue them.
create policy coach_messages_owner_update on coach_messages
  for update using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
