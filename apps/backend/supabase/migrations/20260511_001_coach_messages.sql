-- Coach chat persistence.
--
-- The web /coach surface and the dashboard's "Ask the Coach" promo
-- both render `CoachChat.svelte`, which until now stored the message
-- history in localStorage only — per-device, no cross-device sync,
-- and lost the moment a user signs in on a different browser.
--
-- This table is the per-account home for those threads. Each row is a
-- single message authored by either the runner ('user') or the LLM
-- ('assistant'), scoped to a (user, plan) pair. `plan_id` is nullable
-- so the "no active plan" thread (the runner is asking general
-- questions, not about a specific plan) has its own conversation
-- distinct from the per-plan ones — same shape as the localStorage
-- model that came before, just durable and synced.
--
-- RLS: standard owner-only. SELECT, INSERT, DELETE gated on
-- `auth.uid() = user_id`. No UPDATE policy — messages are immutable
-- once written; "Clear chat" deletes the rows rather than editing them.

create table coach_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  -- Nullable so the "no active plan" thread is distinguishable from
  -- per-plan threads. ON DELETE SET NULL: deleting a plan leaves the
  -- conversation intact under "no plan" so the runner doesn't lose
  -- their chat history when they archive a finished plan.
  plan_id uuid references training_plans(id) on delete set null,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  created_at timestamptz not null default now()
);

-- The hot read path is "give me the chronological thread for this
-- user × plan". Match the index to that exactly so it can satisfy
-- the WHERE + ORDER BY without a sort step.
create index coach_messages_user_plan_created_idx
  on coach_messages (user_id, plan_id, created_at);

alter table coach_messages enable row level security;

create policy coach_messages_owner_select on coach_messages
  for select using (auth.uid() = user_id);

create policy coach_messages_owner_insert on coach_messages
  for insert with check (auth.uid() = user_id);

create policy coach_messages_owner_delete on coach_messages
  for delete using (auth.uid() = user_id);
