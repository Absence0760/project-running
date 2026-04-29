-- Fix infinite-recursion error on INSERT into run_comments.
--
-- The original INSERT policy in 20260522_001 referenced run_comments
-- inside its own WITH CHECK (the EXISTS clause that limits replies to
-- one level of nesting). PostgreSQL's RLS planner flags any policy
-- that selects from its own table as recursive, even when the runtime
-- path is acyclic. The result: every authenticated comment INSERT
-- failed with `infinite recursion detected in policy for relation
-- "run_comments"` and PostgREST returned 500.
--
-- Fix: lift the depth check into a SECURITY DEFINER helper. The
-- helper runs as the function owner with RLS bypassed for its single
-- internal query, so the policy graph no longer contains a self-loop.

create or replace function _run_comment_parent_is_top_level(parent_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from run_comments
    where id = parent_id
      and parent_comment_id is null
  );
$$;

revoke all on function _run_comment_parent_is_top_level(uuid) from public;
grant execute on function _run_comment_parent_is_top_level(uuid) to authenticated;

drop policy "users post comments on their own behalf" on run_comments;

create policy "users post comments on their own behalf"
  on run_comments for insert
  with check (
    auth.uid() = author_id
    and exists (select 1 from runs where runs.id = run_comments.run_id)
    and (
      parent_comment_id is null
      or _run_comment_parent_is_top_level(parent_comment_id)
    )
  );
