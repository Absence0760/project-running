-- Challenges & competitions (challenges.md): time-boxed competitions computed
-- at read time from the `activities` view. Three social shapes — individual,
-- club_vs_club, group_goal. Greenfield on top of the social layer; reuses the
-- activity log + clubs + follow graph rather than a parallel data world.
--
-- v1 scopes the metric set to distance / duration / activity_count / streak_days
-- (runs only). `vert` is intentionally NOT in the CHECK: total elevation gain
-- has no first-class `runs` column — it lives only in `runs.metadata.elevation_m`,
-- populated for some imports and absent for app-recorded runs — so a `vert`
-- board would silently undercount. It ships in a later slice once elevation is
-- first-classed (challenges.md Open Question 1).

create table challenges (
  id            uuid primary key default gen_random_uuid(),
  creator_id    uuid references auth.users(id) on delete set null not null,
  club_id       uuid references clubs(id) on delete cascade,
  title         text not null check (char_length(title) between 1 and 120),
  description   text check (char_length(description) <= 2000),
  metric        text not null,
  scope         text not null,
  goal_value    numeric,
  activity_type text,
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  is_public     boolean not null default true,
  created_at    timestamptz not null default now(),
  constraint challenges_window_ck check (ends_at > starts_at),
  constraint challenges_metric_ck check (
    metric in ('distance', 'duration', 'activity_count', 'streak_days')),
  constraint challenges_scope_ck check (
    scope in ('individual', 'club_vs_club', 'group_goal')),
  constraint challenges_activity_type_ck check (
    activity_type is null or activity_type in ('run', 'walk', 'hike', 'cycle', 'stroller')),
  -- club_vs_club aggregates across many clubs, so it never anchors to a single
  -- club_id; the team a participant pools into is on the participant row.
  constraint challenges_scope_club_ck check (
    scope <> 'club_vs_club' or club_id is null)
);

create index challenges_window on challenges (starts_at, ends_at);
create index challenges_club on challenges (club_id) where club_id is not null;

create table challenge_participants (
  challenge_id  uuid references challenges(id) on delete cascade not null,
  user_id       uuid references auth.users(id) on delete cascade not null,
  team_club_id  uuid references clubs(id) on delete set null,
  joined_at     timestamptz not null default now(),
  completed_at  timestamptz,
  primary key (challenge_id, user_id)
);

create index challenge_participants_user on challenge_participants (user_id);
create index challenge_participants_team on challenge_participants (challenge_id, team_club_id);

-- Durable completion record (the badge hook). One per (user, challenge); the
-- insert is the completion side effect, written only by the SECURITY DEFINER
-- completion RPC.
create table challenge_badges (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users(id) on delete cascade not null,
  challenge_id  uuid references challenges(id) on delete cascade not null,
  metric        text not null,
  final_value   numeric not null,
  awarded_at    timestamptz not null default now(),
  unique (user_id, challenge_id)
);

create index challenge_badges_user on challenge_badges (user_id, awarded_at desc);

-- ─────────────────────── helper: visibility ───────────────────────
-- A challenge is visible to the caller when it's public, they created it,
-- they're a participant, or it's club-anchored and they're a member of that
-- club. Encapsulated so the participant + badge policies can reuse it without
-- duplicating the subquery (mirrors is_club_member's role).
create or replace function is_challenge_visible(target_challenge uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from challenges c
    where c.id = target_challenge
      and (
        c.is_public = true
        or c.creator_id = auth.uid()
        or exists (
          select 1 from challenge_participants p
          where p.challenge_id = c.id and p.user_id = auth.uid()
        )
        or (
          c.club_id is not null and exists (
            select 1 from club_members m
            where m.club_id = c.club_id and m.user_id = auth.uid()
          )
        )
      )
  );
$$;

-- ─────────────────────── RLS ───────────────────────
alter table challenges enable row level security;

create policy "challenges visible to members or public"
  on challenges for select using (
    is_public = true
    or creator_id = auth.uid()
    or exists (
      select 1 from challenge_participants p
      where p.challenge_id = challenges.id and p.user_id = auth.uid()
    )
    or (
      club_id is not null and exists (
        select 1 from club_members m
        where m.club_id = challenges.club_id and m.user_id = auth.uid()
      )
    )
  );

-- Anyone authenticated may create an OPEN challenge; a club-anchored one
-- requires admin on that club. Fail-closed: club_id set without admin is
-- rejected (challenges.md Open Question 2).
create policy "users create open challenges or admins create club ones"
  on challenges for insert
  with check (
    auth.uid() = creator_id
    and (club_id is null or private.is_club_admin(club_id))
  );

create policy "creator or club admin can update"
  on challenges for update using (
    creator_id = auth.uid()
    or (club_id is not null and private.is_club_admin(club_id))
  );

create policy "creator or club admin can delete"
  on challenges for delete using (
    creator_id = auth.uid()
    or (club_id is not null and private.is_club_admin(club_id))
  );

alter table challenge_participants enable row level security;

create policy "participants readable with their challenge"
  on challenge_participants for select using (
    is_challenge_visible(challenge_id)
  );

-- Join: the caller joins themselves, the challenge must be visible, and for a
-- team-pooled join the caller must be an active member of team_club_id.
create policy "users join visible challenges"
  on challenge_participants for insert
  with check (
    auth.uid() = user_id
    and is_challenge_visible(challenge_id)
    and (
      team_club_id is null
      or exists (
        select 1 from club_members m
        where m.club_id = team_club_id and m.user_id = auth.uid()
      )
    )
  );

create policy "users leave their own challenge"
  on challenge_participants for delete using (auth.uid() = user_id);

-- A participant may edit their own row but NOT completed_at — that is written
-- only by the completion RPC. The column-grant lockdown below enforces it; the
-- self-only USING/WITH CHECK keeps the row owner-scoped.
create policy "users update their own participant row"
  on challenge_participants for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Lock completed_at against direct client writes: drop the table-level UPDATE
-- grant and re-grant only team_club_id per-column (the one field a participant
-- may legitimately change). completed_at + joined_at are deliberately omitted;
-- the SECURITY DEFINER RPC runs as table owner and is unaffected.
revoke update on challenge_participants from authenticated, anon;
grant update (team_club_id) on challenge_participants to authenticated;

alter table challenge_badges enable row level security;

-- Badges readable by the owner, or by anyone when the challenge is public (so a
-- profile can show earned badges). No client INSERT/UPDATE/DELETE — the
-- completion RPC is the sole writer.
create policy "badges readable by owner or when challenge public"
  on challenge_badges for select using (
    auth.uid() = user_id
    or exists (
      select 1 from challenges c
      where c.id = challenge_badges.challenge_id and c.is_public = true
    )
  );
