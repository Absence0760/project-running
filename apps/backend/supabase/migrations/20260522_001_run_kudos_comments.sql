-- Kudos + comments on runs (decisions.md § 32).
--
-- The activity feed (§31) ships without an engagement loop. Strava's
-- one-tap kudos + free-form comments with one level of threading is
-- the canonical answer; we copy the shape and let visibility track
-- the parent run's RLS via EXISTS subqueries — the same pattern
-- club_posts uses to inherit clubs visibility.

-- ─────────────────────── run_kudos ───────────────────────

create table run_kudos (
  user_id   uuid references auth.users(id) on delete cascade not null,
  run_id    uuid references runs(id) on delete cascade not null,
  given_at  timestamptz not null default now(),
  primary key (user_id, run_id)
);

create index run_kudos_run_id on run_kudos (run_id, given_at desc);
create index run_kudos_user_id on run_kudos (user_id, given_at desc);

alter table run_kudos enable row level security;

-- Visibility tracks the parent run. The runs RLS policies
-- (`auth.uid() = user_id` and `is_public = true`) are themselves
-- applied to this subquery, so kudos on a private run are invisible
-- to everyone but the owner.
create policy "kudos readable when run is readable"
  on run_kudos for select
  using (exists (select 1 from runs where runs.id = run_kudos.run_id));

-- A user gives kudos on their own behalf, and only on a run they
-- can SELECT (otherwise they could enumerate run UUIDs).
create policy "users give kudos on their own behalf"
  on run_kudos for insert
  with check (
    auth.uid() = user_id
    and exists (select 1 from runs where runs.id = run_kudos.run_id)
  );

-- Only the giver can rescind.
create policy "users rescind their own kudos"
  on run_kudos for delete
  using (auth.uid() = user_id);

-- ─────────────────────── run_comments ───────────────────────

create table run_comments (
  id                 uuid primary key default gen_random_uuid(),
  run_id             uuid references runs(id) on delete cascade not null,
  author_id          uuid references auth.users(id) on delete cascade not null,
  parent_comment_id  uuid references run_comments(id) on delete cascade,
  body               text not null check (length(body) between 1 and 2000),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index run_comments_run_id on run_comments (run_id, created_at desc);
create index run_comments_author on run_comments (author_id, created_at desc);
create index run_comments_parent on run_comments (parent_comment_id) where parent_comment_id is not null;

alter table run_comments enable row level security;

create policy "comments readable when run is readable"
  on run_comments for select
  using (exists (select 1 from runs where runs.id = run_comments.run_id));

-- Authenticated users post on their own behalf, on runs they can
-- SELECT, and replies are limited to one level of nesting (the
-- parent must itself be a top-level comment).
create policy "users post comments on their own behalf"
  on run_comments for insert
  with check (
    auth.uid() = author_id
    and exists (select 1 from runs where runs.id = run_comments.run_id)
    and (
      parent_comment_id is null
      or exists (
        select 1 from run_comments parent
        where parent.id = run_comments.parent_comment_id
          and parent.parent_comment_id is null
      )
    )
  );

-- Author can edit their own comment.
create policy "users edit their own comments"
  on run_comments for update
  using (auth.uid() = author_id)
  with check (auth.uid() = author_id);

-- Author can delete their own comment.
create policy "users delete their own comments"
  on run_comments for delete
  using (auth.uid() = author_id);

-- Run owner can delete any comment on their run (moderation).
create policy "run owner deletes comments on their run"
  on run_comments for delete
  using (
    exists (
      select 1 from runs
      where runs.id = run_comments.run_id
        and runs.user_id = auth.uid()
    )
  );

-- updated_at trigger so edits are visible to consumers.
create or replace function run_comments_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger run_comments_updated_at_trigger
  before update on run_comments
  for each row execute function run_comments_set_updated_at();
