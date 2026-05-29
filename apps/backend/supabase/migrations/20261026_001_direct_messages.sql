-- Direct messages — 1:1 threads (very-social persona #55).
--
-- There was no private-message surface anywhere. This adds a flat
-- direct_messages table (a "thread" is just the unordered pair of
-- participants) with RLS that:
--   * lets each participant read their own threads;
--   * gates INSERT on (a) no block in either direction and (b) an
--     existing follow relationship in either direction — so cold
--     strangers can't DM you, only people in your follow graph. This is
--     the conservative anti-spam default; a "message requests" inbox for
--     non-followers can relax it later.
--   * lets the recipient mark messages read.
-- A 'message' notification fires to the recipient on the first unread
-- message of a burst (not per message) so an active back-and-forth
-- doesn't flood the bell.

create table direct_messages (
  id            uuid primary key default gen_random_uuid(),
  sender_id     uuid references auth.users(id) on delete cascade not null,
  recipient_id  uuid references auth.users(id) on delete cascade not null,
  body          text not null check (length(btrim(body)) between 1 and 4000),
  created_at    timestamptz not null default now(),
  read_at       timestamptz,
  check (sender_id <> recipient_id)
);

-- Thread read path: messages between a pair, newest first. The
-- least/greatest keys make the index symmetric (A→B and B→A share it).
create index direct_messages_thread
  on direct_messages (least(sender_id, recipient_id), greatest(sender_id, recipient_id), created_at desc);

-- Unread-badge path.
create index direct_messages_recipient_unread
  on direct_messages (recipient_id, created_at desc)
  where read_at is null;

alter table direct_messages enable row level security;

create policy "participants read their own messages"
  on direct_messages for select
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

create policy "send when not blocked and within follow graph"
  on direct_messages for insert
  with check (
    sender_id = auth.uid()
    -- SECURITY DEFINER helper: a plain subquery on user_blocks would be
    -- subject to user_blocks RLS (owner-read only), so the sender could
    -- never see a block the RECIPIENT placed on them — the gate would
    -- leak. is_blocked_either_way bypasses that and sees both directions.
    and not is_blocked_either_way(sender_id, recipient_id)
    and exists (
      select 1 from user_follows f
      where (f.follower_id = sender_id and f.followee_id = recipient_id)
         or (f.follower_id = recipient_id and f.followee_id = sender_id)
    )
  );

-- Only the recipient can mark messages read (toggling read_at). The
-- WITH CHECK keeps the recipient from reassigning the row to someone
-- else; body edits aren't offered.
create policy "recipient marks read"
  on direct_messages for update
  using (auth.uid() = recipient_id)
  with check (auth.uid() = recipient_id);

-- Either participant can delete a message (sender unsends, recipient
-- removes from their view — a hard delete for MVP).
create policy "participants delete their messages"
  on direct_messages for delete
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

-- 'message' notification kind.
alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message'
    )
  );

create or replace function notify_direct_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only notify on the first unread message of a burst — if the
  -- recipient already has an unread message from this sender, the bell
  -- is already lit, so don't stack another row.
  if exists (
    select 1 from direct_messages m
    where m.sender_id = new.sender_id
      and m.recipient_id = new.recipient_id
      and m.read_at is null
      and m.id <> new.id
  ) then
    return new;
  end if;
  insert into notifications (user_id, actor_id, kind)
    values (new.recipient_id, new.sender_id, 'message');
  return new;
end;
$$;

create trigger trg_notify_direct_message
  after insert on direct_messages
  for each row execute function notify_direct_message();
