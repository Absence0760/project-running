-- Social layer: clubs, events, membership, RSVPs, and owner updates.
--
-- Phase 1 MVP:
--   * Clubs with a public/private visibility toggle.
--   * Open-join membership (no request/approval flow yet — Phase 2).
--   * One-off events owned by a club (no recurrence yet — Phase 2).
--   * Event attendees with RSVP status.
--   * Plain-text owner/admin posts on the club feed.

-- ─────────────────────── Clubs ───────────────────────
create table clubs (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid references auth.users not null,
  name          text not null,
  slug          text unique not null,
  description   text,
  avatar_url    text,
  location_label text,
  is_public     boolean default true,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

create index clubs_owner on clubs (owner_id, created_at desc);
create index clubs_public on clubs (is_public, created_at desc) where is_public = true;

-- ─────────────────────── Members ───────────────────────
create table club_members (
  club_id     uuid references clubs on delete cascade not null,
  user_id     uuid references auth.users on delete cascade not null,
  role        text not null default 'member',  -- 'owner' | 'admin' | 'member'
  joined_at   timestamptz default now(),
  primary key (club_id, user_id)
);

create index club_members_user on club_members (user_id);

-- ─────────────────────── Events ───────────────────────
create table events (
  id              uuid primary key default gen_random_uuid(),
  club_id         uuid references clubs on delete cascade not null,
  title           text not null,
  description     text,
  starts_at       timestamptz not null,
  duration_min    integer,
  meet_lat        double precision,
  meet_lng        double precision,
  meet_label      text,
  route_id        uuid references routes on delete set null,
  distance_m      numeric(10, 2),
  pace_target_sec integer,               -- seconds per km
  capacity        integer,
  created_by      uuid references auth.users not null,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

create index events_club_starts_at on events (club_id, starts_at desc);
create index events_starts_at on events (starts_at desc);

-- ─────────────────────── Attendees ───────────────────────
create table event_attendees (
  event_id   uuid references events on delete cascade not null,
  user_id    uuid references auth.users on delete cascade not null,
  status     text not null default 'going', -- 'going' | 'maybe' | 'declined'
  joined_at  timestamptz default now(),
  primary key (event_id, user_id)
);

create index event_attendees_user on event_attendees (user_id);

-- ─────────────────────── Club posts (owner updates) ───────────────────────
create table club_posts (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid references clubs on delete cascade not null,
  event_id    uuid references events on delete cascade,  -- optional: tie a post to a specific event
  author_id   uuid references auth.users not null,
  body        text not null,
  created_at  timestamptz default now()
);

create index club_posts_club on club_posts (club_id, created_at desc);
create index club_posts_event on club_posts (event_id, created_at desc) where event_id is not null;

-- ─────────────────────── Helper: membership + role checks ───────────────────────
-- Encapsulated as SQL functions so RLS policies stay readable and can be
-- tightened later without touching every policy.
create or replace function is_club_member(target_club uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from club_members
    where club_id = target_club and user_id = auth.uid()
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
      and role in ('owner', 'admin')
  );
$$;

-- ─────────────────────── RLS ───────────────────────

-- Clubs: public clubs visible to everyone, private clubs visible to members
-- and the owner. Only authenticated users can create. Only the owner (or an
-- admin via club_members) can update or delete — enforced via is_club_admin.
alter table clubs enable row level security;

create policy "public clubs are readable by anyone"
  on clubs for select using (is_public = true);

create policy "private clubs are readable by members"
  on clubs for select using (
    is_public = false and (
      owner_id = auth.uid() or is_club_member(id)
    )
  );

create policy "authenticated users can create clubs"
  on clubs for insert
  with check (auth.uid() = owner_id);

create policy "club admins can update their club"
  on clubs for update using (is_club_admin(id));

create policy "club owner can delete their club"
  on clubs for delete using (owner_id = auth.uid());

-- Members: a user can see the roster of any club they can see (public or
-- belong to). Users manage their own membership row (open-join: inserts are
-- unrestricted); only club admins can delete other users' rows.
alter table club_members enable row level security;

create policy "members readable with their club"
  on club_members for select using (
    exists (
      select 1 from clubs
      where clubs.id = club_members.club_id
        and (clubs.is_public = true or clubs.owner_id = auth.uid() or is_club_member(clubs.id))
    )
  );

create policy "authenticated users can join clubs"
  on club_members for insert
  with check (auth.uid() = user_id);

create policy "users can leave clubs"
  on club_members for delete using (auth.uid() = user_id);

create policy "admins can manage members"
  on club_members for delete using (is_club_admin(club_id));

create policy "admins can change roles"
  on club_members for update using (is_club_admin(club_id));

-- Events: visibility inherits from the parent club. Only admins can create,
-- update, or delete an event.
alter table events enable row level security;

create policy "events readable with their club"
  on events for select using (
    exists (
      select 1 from clubs
      where clubs.id = events.club_id
        and (clubs.is_public = true or clubs.owner_id = auth.uid() or is_club_member(clubs.id))
    )
  );

create policy "admins can create events"
  on events for insert
  with check (is_club_admin(club_id) and created_by = auth.uid());

create policy "admins can update events"
  on events for update using (is_club_admin(club_id));

create policy "admins can delete events"
  on events for delete using (is_club_admin(club_id));

-- Attendees: anyone who can see the event can see who's RSVP'd. Users manage
-- their own RSVP row.
alter table event_attendees enable row level security;

create policy "attendees readable with their event"
  on event_attendees for select using (
    exists (
      select 1 from events e
      join clubs c on c.id = e.club_id
      where e.id = event_attendees.event_id
        and (c.is_public = true or c.owner_id = auth.uid() or is_club_member(c.id))
    )
  );

create policy "users can RSVP"
  on event_attendees for insert
  with check (auth.uid() = user_id);

create policy "users can update their own RSVP"
  on event_attendees for update using (auth.uid() = user_id);

create policy "users can delete their own RSVP"
  on event_attendees for delete using (auth.uid() = user_id);

-- Club posts: readable by anyone who can see the club. Only admins can post.
-- Only the author can delete their own post.
alter table club_posts enable row level security;

create policy "posts readable with their club"
  on club_posts for select using (
    exists (
      select 1 from clubs
      where clubs.id = club_posts.club_id
        and (clubs.is_public = true or clubs.owner_id = auth.uid() or is_club_member(clubs.id))
    )
  );

create policy "admins can post"
  on club_posts for insert
  with check (is_club_admin(club_id) and author_id = auth.uid());

create policy "authors can delete their posts"
  on club_posts for delete using (author_id = auth.uid());

-- ─────────────────────── Auto-enroll club owner as member ───────────────────────
-- When a club is created, insert the owner as an 'owner' member so
-- is_club_member/is_club_admin work uniformly for them too.
create or replace function enroll_club_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into club_members (club_id, user_id, role)
  values (new.id, new.owner_id, 'owner');
  return new;
end;
$$;

create trigger enroll_club_owner_trigger
  after insert on clubs
  for each row execute function enroll_club_owner();
