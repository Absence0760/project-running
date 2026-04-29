-- Following graph + public-by-default user profiles (decisions.md § 31).
--
-- Two coordinated changes:
--   1. user_follows — asymmetric follow relationship between two users.
--      Composite-PK join table; CHECK blocks self-follow; cascading
--      deletes on both sides so a user disappearing tears down the
--      graph cleanly.
--
--   2. user_profiles gains a public-read policy. Until now the only
--      policy on user_profiles was `auth.uid() = id`, which silently
--      broke cross-user enrichment (every fetchClubMembers /
--      enrichPosts call returned empty display_name for other users).
--      The follow feature requires cross-user reads, and the bug
--      fix is the same line of SQL — so we ship them together.
--      `subscription_tier` and `parkrun_number` are now world-readable
--      to authenticated users; we accept that trade-off (decisions § 31).

-- ─────────────────────── user_follows ───────────────────────

create table user_follows (
  follower_id  uuid references auth.users(id) on delete cascade not null,
  followee_id  uuid references auth.users(id) on delete cascade not null,
  followed_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  constraint user_follows_no_self_follow check (follower_id <> followee_id)
);

create index user_follows_follower
  on user_follows (follower_id, followed_at desc);

create index user_follows_followee
  on user_follows (followee_id, followed_at desc);

alter table user_follows enable row level security;

-- The follow graph is public — anyone authenticated can SELECT to power
-- profile-page follower/following counts and the "Follows X people you
-- know" affordance. We deliberately don't hide either side; if a user
-- doesn't want to be followed, that's a future private-profile toggle.
create policy "follows are readable by anyone authenticated"
  on user_follows for select
  using (auth.role() = 'authenticated');

-- A user follows on their own behalf.
create policy "users follow on their own behalf"
  on user_follows for insert
  with check (auth.uid() = follower_id);

-- Only the follower can unfollow.
create policy "users unfollow on their own behalf"
  on user_follows for delete
  using (auth.uid() = follower_id);

-- ─────────────────────── user_profiles public read ───────────────────────

-- Add a public-read policy. The existing `auth.uid() = id` policy is
-- `for all` so it stays in place for INSERT/UPDATE/DELETE; the new
-- policy is SELECT-only and additive — Postgres OR-combines policies
-- of the same command, so callers see the row if EITHER policy
-- matches.
create policy "profiles are readable by anyone authenticated"
  on user_profiles for select
  using (auth.role() = 'authenticated');
