-- Notifications inbox (decisions §38).
--
-- Engagement on the social loop (kudos, comments, replies, follows)
-- previously required visiting each surface to discover. A central
-- notifications table populated by SECURITY DEFINER triggers gives
-- the user one place to see "who did what" + a per-row read marker
-- so unread events surface in a sidebar bell badge.

-- ─────────────────────── notifications table ───────────────────────

create table notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  actor_id    uuid references auth.users(id) on delete set null,
  kind        text not null check (
    kind in ('kudos', 'comment', 'comment_reply', 'follow')
  ),
  -- Source links — only the FK relevant to the kind is populated; the
  -- rest stay null. ON DELETE CASCADE ensures notifications go away
  -- when the source row does (deleted run, deleted comment, etc).
  run_id      uuid references runs(id) on delete cascade,
  comment_id  uuid references run_comments(id) on delete cascade,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index notifications_user
  on notifications (user_id, created_at desc);

-- Partial index for the unread-count badge query — by far the hottest
-- read path. Keeps the index tiny since most notifications go read
-- shortly after they're seen.
create index notifications_user_unread
  on notifications (user_id, created_at desc)
  where read_at is null;

alter table notifications enable row level security;

-- The recipient sees their own notifications. INSERT is closed off to
-- regular users — only the SECURITY DEFINER trigger functions below
-- can write rows.
create policy "users read their own notifications"
  on notifications for select
  using (auth.uid() = user_id);

create policy "users mark their own notifications read"
  on notifications for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "users delete their own notifications"
  on notifications for delete
  using (auth.uid() = user_id);

-- ─────────────────────── trigger functions ───────────────────────

-- Kudos on a run → notify the run owner (skip self-kudos which RLS
-- forbids anyway, but defence in depth).
create or replace function notify_run_kudos()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  run_owner uuid;
begin
  select user_id into run_owner from runs where id = NEW.run_id;
  if run_owner is null or run_owner = NEW.user_id then
    return NEW;
  end if;
  insert into notifications (user_id, actor_id, kind, run_id)
    values (run_owner, NEW.user_id, 'kudos', NEW.run_id);
  return NEW;
end;
$$;

create trigger run_kudos_notify
  after insert on run_kudos
  for each row execute function notify_run_kudos();

-- Comments on a run. Top-level (parent_comment_id IS NULL) notifies
-- the run owner; replies notify the parent comment's author.
create or replace function notify_run_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  run_owner     uuid;
  parent_author uuid;
begin
  if NEW.parent_comment_id is null then
    select user_id into run_owner from runs where id = NEW.run_id;
    if run_owner is null or run_owner = NEW.author_id then
      return NEW;
    end if;
    insert into notifications (user_id, actor_id, kind, run_id, comment_id)
      values (run_owner, NEW.author_id, 'comment', NEW.run_id, NEW.id);
  else
    select author_id into parent_author
      from run_comments where id = NEW.parent_comment_id;
    if parent_author is null or parent_author = NEW.author_id then
      return NEW;
    end if;
    insert into notifications (user_id, actor_id, kind, run_id, comment_id)
      values (parent_author, NEW.author_id, 'comment_reply', NEW.run_id, NEW.id);
  end if;
  return NEW;
end;
$$;

create trigger run_comments_notify
  after insert on run_comments
  for each row execute function notify_run_comment();

-- New followers — notify the followee. The CHECK constraint on
-- user_follows already blocks self-follow, but we guard again.
create or replace function notify_user_follow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.follower_id = NEW.followee_id then
    return NEW;
  end if;
  insert into notifications (user_id, actor_id, kind)
    values (NEW.followee_id, NEW.follower_id, 'follow');
  return NEW;
end;
$$;

create trigger user_follows_notify
  after insert on user_follows
  for each row execute function notify_user_follow();
