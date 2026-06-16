-- Fix: the block gate on run_kudos / run_comments INSERT never denied.
--
-- The policies added in 20261012_001 gated the write with
--   not is_blocked_either_way(auth.uid(),
--     (select r.user_id from runs r where r.id = run_id))
-- The owner subquery runs under the INSERTing user's RLS on `runs`.
-- Since 20260701_001 dropped the public-runs SELECT policy on the base
-- table (public reads go through the `public_runs` view), a kudoser /
-- commenter can only SELECT their OWN runs (or an athlete's runs as a
-- coach). For anyone else's run — which is the only run you kudos or
-- comment on — the subquery returns NULL, so
--   not is_blocked_either_way(actor, NULL)  ->  not false  ->  true
-- and the block predicate is satisfied for every cross-user write. The
-- self-defence primitive (a harassed runner blocking their harasser to
-- stop kudos/comment notifications — the very persona-hunt finding that
-- motivated 20261012_001) was dead on arrival for the engagement-write
-- path.
--
-- Fix mirrors how 20260812_001 already solved "the actor can't see the
-- run row under RLS": resolve the owner inside a SECURITY DEFINER
-- predicate (private schema), so the block check sees the real owner
-- regardless of the caller's RLS-restricted view of `runs`.
--
-- The other is_blocked_either_way call sites are unaffected: user_follows
-- (follower_id/followee_id are columns on the inserted row), direct_messages
-- (sender_id/recipient_id on the row), search_segment_leaderboard (se.user_id
-- inside a SECURITY DEFINER RPC), and public_profile_by_id (SECURITY DEFINER)
-- all evaluate the block against a value already in hand, never via an
-- RLS-visible subquery.

create or replace function private.is_blocked_for_run(p_actor uuid, p_run_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from runs r
    join user_blocks ub
      on (ub.blocker_id = p_actor and ub.blocked_id = r.user_id)
      or (ub.blocker_id = r.user_id and ub.blocked_id = p_actor)
    where r.id = p_run_id
  );
$$;

revoke execute on function private.is_blocked_for_run(uuid, uuid) from public;
grant execute on function private.is_blocked_for_run(uuid, uuid)
  to anon, authenticated, service_role;

-- run_kudos: same gate, owner now resolved in DEFINER context.
drop policy if exists "users give kudos on their own behalf" on run_kudos;
create policy "users give kudos on their own behalf"
  on run_kudos for insert
  with check (
    auth.uid() = user_id
    and private.is_run_visible_to(run_id, auth.uid())
    and not private.is_blocked_for_run(auth.uid(), run_id)
  );

-- run_comments: same gate, keeping the top-level-parent rule.
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
    and not private.is_blocked_for_run(auth.uid(), run_id)
  );
