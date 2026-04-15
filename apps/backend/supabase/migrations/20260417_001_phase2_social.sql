-- Phase 2 of the social layer:
--   * Event recurrence: enum freq + byday + until_date, with RSVPs pinned to
--     a specific instance rather than the whole series.
--   * Club join policies: 'open' (default) | 'request' | 'invite'.
--   * Shareable invite tokens on private / invite-only clubs.
--   * Threaded replies on club posts.
--
-- Decisions (see docs/decisions.md #10):
--   - One row per event series. Instance timestamps are computed on the
--     client from (starts_at, recurrence_freq, recurrence_byday, until).
--     `event_attendees` carries an `instance_start` column so RSVPs are
--     per-instance, not per-series.
--   - Invite token is a single opaque text column on clubs, not a separate
--     table. Rotating the token invalidates old links — good enough for v1.
--   - Threaded replies are one level deep. Nested threads of threads are
--     out of scope; `parent_post_id` is top-level-or-reply, not a tree.

-- ─────────────────────── Recurrence ───────────────────────
alter table events add column recurrence_freq text;             -- 'weekly' | 'biweekly' | 'monthly'
alter table events add column recurrence_byday text[];          -- ISO codes: 'MO','TU','WE','TH','FR','SA','SU'
alter table events add column recurrence_until timestamptz;
alter table events add column recurrence_count integer;         -- optional cap; null = no cap besides until

-- Per-instance RSVPs. Drop the old pkey and add a new composite that includes
-- the instance start. Default existing rows to the series' starts_at so the
-- Phase 1 data keeps working.
alter table event_attendees add column instance_start timestamptz;

update event_attendees ea
set instance_start = (select e.starts_at from events e where e.id = ea.event_id)
where instance_start is null;

alter table event_attendees alter column instance_start set not null;

alter table event_attendees drop constraint event_attendees_pkey;
alter table event_attendees add primary key (event_id, user_id, instance_start);

create index event_attendees_event_instance
  on event_attendees (event_id, instance_start);

-- Same story for event-tagged posts: a post can pin to a specific instance.
alter table club_posts add column event_instance_start timestamptz;

-- ─────────────────────── Club join policies + invites ───────────────────────
alter table clubs add column join_policy text not null default 'open';  -- 'open' | 'request' | 'invite'
alter table clubs add column invite_token text unique;

alter table club_members add column status text not null default 'active'; -- 'active' | 'pending'

-- Tighten is_club_member: only 'active' members count for visibility checks.
-- Pending requests must not grant read access to private-club content.
create or replace function is_club_member(target_club uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from club_members
    where club_id = target_club
      and user_id = auth.uid()
      and status = 'active'
  );
$$;

create or replace function is_club_admin(target_club uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from club_members
    where club_id = target_club
      and user_id = auth.uid()
      and status = 'active'
      and role in ('owner', 'admin')
  );
$$;

-- A user can always see their own membership row, even when it's pending,
-- so the UI can show "Request pending" without relying on the readable-
-- with-club policy (which requires active status).
create policy "users can see their own membership"
  on club_members for select using (auth.uid() = user_id);

-- Invite-token join helper. Validates the token, inserts an active
-- membership, and returns the club id. Runs as security definer so it can
-- bypass the normal INSERT policy (which doesn't know anything about tokens).
create or replace function join_club_by_token(token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_club uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select id into target_club from clubs where invite_token = token;
  if target_club is null then
    raise exception 'invalid invite token';
  end if;

  insert into club_members (club_id, user_id, role, status)
  values (target_club, auth.uid(), 'member', 'active')
  on conflict (club_id, user_id) do update
    set status = 'active';

  return target_club;
end;
$$;

grant execute on function join_club_by_token(text) to authenticated;

-- ─────────────────────── Threaded replies ───────────────────────
-- One level deep: parent_post_id is null for top-level posts; non-null for
-- replies. A reply cannot itself be replied to (enforced client-side for v1,
-- not at the schema level — upgrade path is free if we ever want deeper
-- threads).
alter table club_posts add column parent_post_id uuid references club_posts on delete cascade;
create index club_posts_parent on club_posts (parent_post_id, created_at) where parent_post_id is not null;

-- Members (not just admins) may reply to posts. Top-level posts stay admin-
-- only. Two separate insert policies: one for top-level (admins), one for
-- replies (any active member).
drop policy if exists "admins can post" on club_posts;

create policy "admins can post top-level"
  on club_posts for insert
  with check (
    parent_post_id is null
    and is_club_admin(club_id)
    and author_id = auth.uid()
  );

create policy "active members can reply"
  on club_posts for insert
  with check (
    parent_post_id is not null
    and is_club_member(club_id)
    and author_id = auth.uid()
  );
