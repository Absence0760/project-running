-- Reactions on coach messages.
--
-- Thumbs-up / thumbs-down on assistant replies, surfaced inline in the
-- bubble actions. Useful both for the runner ("save this answer was
-- great") and as a future signal if we ever want to fine-tune or
-- A/B test prompt changes.
--
-- A `reaction` lives on the message itself rather than a separate table
-- because there's exactly one runner per (user × message): the owner.
-- No multi-user voting model — this is a personal chat.

alter table coach_messages
  add column reaction text check (reaction in ('up', 'down'));
