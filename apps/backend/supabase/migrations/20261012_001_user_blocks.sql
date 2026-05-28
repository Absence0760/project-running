-- user_blocks — viewer-controlled hide of another runner's content.
--
-- Persona-hunt Round 3 finding Woman #1. Pre-fix the social layer had
-- *report* (user_reports, migration 20260908_001) but no *block*: a
-- runner harassed via kudos/comments/follow notifications had to wait
-- on operator action while the harasser kept generating events. Block
-- is the runner's own primitive: they hide a specific other account
-- without any moderator in the loop. Reports remain the path for
-- escalation; block is the path for self-defence.
--
-- Symmetry: a block in either direction (viewer blocks target, OR
-- target blocks viewer) suppresses content for both. The viewer's
-- intent is "I don't want to interact with this account at all" —
-- a one-way visibility gate would still let the blocker see the
-- blockee's runs (which then enables harassing engagement from the
-- blockee side, just delayed by report-then-block round-trip).
-- Symmetric matches the Twitter / IG semantic and is what users
-- expect when they say "block".
--
-- Wire surface: run_kudos / run_comments / user_follows policies
-- gate on `is_blocked_either_way(actor, target)`. public_profile_by_id
-- returns empty for a blocked target. Segments leaderboards filter
-- effort rows by the same predicate. Future surfaces follow the same
-- helper — keep additions in one place.

create table user_blocks (
  blocker_id uuid not null references auth.users on delete cascade,
  blocked_id uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  reason text,
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index user_blocks_blocked_id_idx on user_blocks(blocked_id);

alter table user_blocks enable row level security;

-- Owner-only: a blocker can read / insert / delete their own rows.
-- The blocked party never sees the row (so the block is invisible
-- to them — matching the Twitter / IG semantic).
create policy "user_blocks owner read"
  on user_blocks for select
  to authenticated
  using (auth.uid() = blocker_id);

create policy "user_blocks owner insert"
  on user_blocks for insert
  to authenticated
  with check (auth.uid() = blocker_id and auth.uid() <> blocked_id);

create policy "user_blocks owner delete"
  on user_blocks for delete
  to authenticated
  using (auth.uid() = blocker_id);

-- Predicate: are `a` and `b` blocked from interacting in either
-- direction? Used by every downstream surface. SECURITY DEFINER
-- so it can see both sides of the matrix regardless of the caller's
-- RLS-restricted view of user_blocks.
create or replace function is_blocked_either_way(a uuid, b uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from user_blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;

revoke all on function is_blocked_either_way(uuid, uuid) from public;
grant execute on function is_blocked_either_way(uuid, uuid) to authenticated, anon, service_role;

-- Convenience RPCs for the client (avoids exposing the table to
-- direct PostgREST writes — the RLS already protects, but the RPC
-- shape lets us add audit hooks / rate limits cheaply later).

create or replace function block_user(p_target uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'block_user: not authenticated' using errcode = '42501';
  end if;
  if caller = p_target then
    raise exception 'block_user: cannot block self' using errcode = '23514';
  end if;
  insert into user_blocks (blocker_id, blocked_id, reason)
    values (caller, p_target, p_reason)
    on conflict (blocker_id, blocked_id) do update
      set reason = excluded.reason;

  -- One-shot cleanup: drop any existing follow rows in either
  -- direction (the new policy below blocks future follows, but a
  -- pre-existing follow would still surface in feeds until the
  -- blocker manually unfollows. Block subsumes unfollow on both
  -- sides — the symmetric intent.)
  delete from user_follows
    where (follower_id = caller and followee_id = p_target)
       or (follower_id = p_target and followee_id = caller);
end;
$$;

create or replace function unblock_user(p_target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'unblock_user: not authenticated' using errcode = '42501';
  end if;
  delete from user_blocks
    where blocker_id = caller and blocked_id = p_target;
end;
$$;

revoke all on function block_user(uuid, text) from public;
revoke all on function unblock_user(uuid) from public;
grant execute on function block_user(uuid, text) to authenticated;
grant execute on function unblock_user(uuid) to authenticated;

-- ───── Gate the existing social surfaces ─────

-- Block writes to run_kudos / run_comments / user_follows when the
-- other party is blocked in either direction. The READ side stays
-- as-is — the client filters with engagement-summary RPCs that
-- already join on user_id; we add the block predicate there.

-- user_follows: deny INSERT if either side blocks. Existing policy
-- "users follow on their own behalf" (migration 20260521_001) only
-- gates auth.uid() = follower_id. Replace with the block predicate.
drop policy if exists "users follow on their own behalf" on user_follows;
create policy "users follow on their own behalf"
  on user_follows for insert
  with check (
    auth.uid() = follower_id
    and follower_id <> followee_id
    and not is_blocked_either_way(follower_id, followee_id)
  );

-- run_kudos: deny INSERT if the run owner blocks the kudoser or vice
-- versa. The latest authoritative policy lives in migration
-- 20260812_001 (gated on private.is_run_visible_to). Replace it,
-- keeping that visibility check.
drop policy if exists "users give kudos on their own behalf" on run_kudos;
create policy "users give kudos on their own behalf"
  on run_kudos for insert
  with check (
    auth.uid() = user_id
    and private.is_run_visible_to(run_id, auth.uid())
    and not is_blocked_either_way(
      auth.uid(),
      (select r.user_id from runs r where r.id = run_id)
    )
  );

-- run_comments: same gate as run_kudos, on author_id. The latest
-- authoritative policy lives in 20260812_001 — keep the parent-comment
-- top-level rule and add the block predicate.
drop policy if exists "users post comments on their own behalf" on run_comments;
create policy "users post comments on their own behalf"
  on run_comments for insert
  with check (
    auth.uid() = author_id
    and private.is_run_visible_to(run_id, auth.uid())
    and (
      parent_comment_id is null
      or _run_comment_parent_is_top_level(parent_comment_id)
    )
    and not is_blocked_either_way(
      auth.uid(),
      (select r.user_id from runs r where r.id = run_id)
    )
  );

-- ───── public_profile_by_id ─────
-- Return empty for a blocked target so the blockee disappears from
-- the blocker's share-page unfurls. Replaces migration 20261011_001.

create or replace function public_profile_by_id(p_id uuid)
returns table (
  id uuid,
  display_name text,
  avatar_url text
)
language sql
security definer
set search_path = public
stable
as $$
  select u.id, u.display_name, u.avatar_url
  from user_profiles u
  where u.id = p_id
    and (auth.uid() is null
         or not is_blocked_either_way(auth.uid(), u.id));
$$;

revoke all on function public_profile_by_id(uuid) from public;
grant execute on function public_profile_by_id(uuid) to anon, authenticated;
