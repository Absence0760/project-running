-- Conversation-list RPC for the DM inbox (perf + correctness).
--
-- fetchDmThreads pulled the viewer's most-recent 500 messages (select('*'),
-- both directions) and folded them into latest-per-partner + unread counts in
-- JS. Two problems: it shipped every full message body just to render one
-- preview line per partner, and — worse — the 500-row window is the newest
-- 500 across ALL partners, so an active messager whose newest conversations
-- exceed 500 total messages silently lost older partners from the list.
--
-- dm_threads() does the latest-per-partner + unread aggregation server-side
-- over the viewer's ENTIRE message set (no window → no truncation), returning
-- one row per conversation with only the preview body. SECURITY INVOKER keeps
-- the caller's RLS ("participants read their own messages"), so the scan sees
-- exactly the viewer's messages. Profile (name/avatar) join stays a client
-- .in() lookup, unchanged.

-- Per-direction indexes so the one-participant scan is index-served (BitmapOr
-- of the two) instead of a seq scan. The existing (least,greatest) thread
-- index is symmetric for a two-party history but useless for "all of my
-- messages"; the recipient_unread partial index only covers unread rows.
create index if not exists direct_messages_sender_created
  on direct_messages (sender_id, created_at desc);
create index if not exists direct_messages_recipient_created
  on direct_messages (recipient_id, created_at desc);

create or replace function dm_threads()
returns table (
  partner_id uuid,
  last_body text,
  last_at timestamptz,
  last_from_me boolean,
  unread bigint
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with my_msgs as (
    select
      case when sender_id = auth.uid() then recipient_id else sender_id end as partner_id,
      sender_id,
      recipient_id,
      body,
      created_at,
      read_at
    from direct_messages
    where sender_id = auth.uid() or recipient_id = auth.uid()
  ),
  latest as (
    select distinct on (partner_id)
      partner_id,
      body as last_body,
      created_at as last_at,
      (sender_id = auth.uid()) as last_from_me
    from my_msgs
    order by partner_id, created_at desc
  ),
  unread as (
    select partner_id, count(*) as cnt
    from my_msgs
    where recipient_id = auth.uid() and read_at is null
    group by partner_id
  )
  select
    l.partner_id,
    l.last_body,
    l.last_at,
    l.last_from_me,
    coalesce(u.cnt, 0) as unread
  from latest l
  left join unread u using (partner_id)
  order by l.last_at desc;
$$;

grant execute on function dm_threads() to authenticated;
