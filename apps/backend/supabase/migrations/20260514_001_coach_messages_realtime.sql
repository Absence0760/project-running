-- Add coach_messages to the supabase_realtime publication so a client
-- that reloads mid-stream can pick the assistant reply up via Realtime
-- when it eventually lands. Without this, a runner who refreshes the
-- /coach page while a request is in flight loses the typing indicator
-- and never sees the assistant reply land in the live thread (until
-- they reload again).
--
-- RLS still applies to realtime payloads — the runner only sees inserts
-- on rows where they're the owner.

alter publication supabase_realtime add table coach_messages;
