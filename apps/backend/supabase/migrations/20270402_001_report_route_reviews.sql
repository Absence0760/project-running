-- Report route reviews — the one user-generated content type on routes
-- with no report affordance today.
--
-- Prior state:
--   * 20260908_001 created reports with CHECK target_kind in
--     ('user','club','route') + the submit_report() RPC.
--   * 20261117_001 added 'comment' (id lives in run_comments).
--   * 20270115_001 added 'club_post' (club_posts) and 'run' (runs).
--
-- This adds 'route_review' (id in route_reviews). Additive: widen the
-- CHECK + the submit_report validation, and add a target-exists branch
-- that also rejects reporting your own review — the review's author
-- column is `user_id` (route_reviews has no `author_id`), mirroring the
-- existing self-user / self-comment / self-post / self-run guards.
-- Bare-body create-or-replace, so the function is the COMPLETE
-- 20270115_001 body plus the one new arm.

alter table reports drop constraint reports_target_kind_check;
alter table reports
  add constraint reports_target_kind_check
  check (target_kind in ('user', 'club', 'route', 'comment', 'club_post', 'run', 'route_review'));

create or replace function submit_report(
  p_target_kind text,
  p_target_id uuid,
  p_reason text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reporter uuid := auth.uid();
  v_target_exists boolean;
  v_report_id uuid;
begin
  if v_reporter is null then
    raise exception 'submit_report: not authorized' using errcode = '42501';
  end if;

  if p_target_kind not in ('user', 'club', 'route', 'comment', 'club_post', 'run', 'route_review') then
    raise exception 'submit_report: invalid target_kind %', p_target_kind
      using errcode = '22023';
  end if;

  if p_reason not in ('spam', 'harassment', 'inappropriate', 'impersonation', 'other') then
    raise exception 'submit_report: invalid reason %', p_reason
      using errcode = '22023';
  end if;

  -- Don't let a user report themselves — most likely a misclick, and
  -- the queue noise isn't worth carrying.
  if p_target_kind = 'user' and p_target_id = v_reporter then
    raise exception 'submit_report: cannot report yourself'
      using errcode = '22023';
  end if;

  -- Validate the target exists. The FROM clauses run as the function owner
  -- (postgres) so RLS doesn't block visibility.
  if p_target_kind = 'user' then
    select exists (select 1 from user_profiles where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'club' then
    select exists (select 1 from clubs where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'route' then
    select exists (select 1 from routes where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'comment' then
    select exists (select 1 from run_comments where id = p_target_id) into v_target_exists;
    -- Reporting your own comment is a misclick; reject like self-user.
    if v_target_exists and exists (
      select 1 from run_comments where id = p_target_id and author_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own comment'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'club_post' then
    select exists (select 1 from club_posts where id = p_target_id) into v_target_exists;
    -- Reporting your own post is a misclick; reject like self-comment.
    if v_target_exists and exists (
      select 1 from club_posts where id = p_target_id and author_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own post'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'run' then
    select exists (select 1 from runs where id = p_target_id) into v_target_exists;
    -- Reporting your own run is a misclick; reject like self-comment.
    if v_target_exists and exists (
      select 1 from runs where id = p_target_id and user_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own run'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'route_review' then
    select exists (select 1 from route_reviews where id = p_target_id) into v_target_exists;
    -- Reporting your own review is a misclick; reject like self-comment.
    -- route_reviews' author column is `user_id` (no `author_id`).
    if v_target_exists and exists (
      select 1 from route_reviews where id = p_target_id and user_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own review'
        using errcode = '22023';
    end if;
  end if;

  if not v_target_exists then
    raise exception 'submit_report: target % % not found', p_target_kind, p_target_id
      using errcode = '02000';
  end if;

  -- Rate-limit: 10 reports per hour per reporter.
  perform enforce_create_rate_limit('create_report', v_reporter, 10, 3600);

  begin
    insert into reports (reporter_id, target_kind, target_id, reason, notes)
    values (v_reporter, p_target_kind, p_target_id, p_reason, p_notes)
    returning id into v_report_id;
  exception when unique_violation then
    raise exception 'submit_report: already reported'
      using errcode = '23505',
            hint = 'You already have a pending report against this target.';
  end;

  return v_report_id;
end;
$$;

revoke execute on function submit_report(text, uuid, text, text) from public;
grant execute on function submit_report(text, uuid, text, text) to authenticated;
