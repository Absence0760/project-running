-- Challenge discovery: rank popular challenges over throwaway ones.
--
-- The Browse section on /challenges used to `select * ... order by ends_at` and
-- enrich participant counts client-side — every public challenge, unranked,
-- unbounded. As open creation is ungated (anyone can make a public challenge),
-- that surface degrades to noise as volume grows. This migration adds:
--
--   1. challenges.participant_count — a trigger-maintained denormalised cache
--      (the derived_state.md cache=authoritative-query contract) so ranking +
--      pagination never aggregate over challenge_participants at read time.
--   2. browse_public_challenges(p_search, p_limit, p_offset) — a ranked,
--      paginated, searchable discovery RPC. Score = total size + recent join
--      velocity, so a challenge with momentum outranks a stale big one and a
--      dead board sinks. Throwaway suppression hides participant-less boards
--      past a grace window.
--   3. a create-challenge rate-limit trigger — the spam backstop challenges.md
--      Open Question 2 pointed at, so a script can't flood Browse.

-- ─────────────────────── 1. participant_count cache ───────────────────────
alter table challenges add column participant_count integer not null default 0;

update challenges c
  set participant_count = (
    select count(*) from challenge_participants p where p.challenge_id = c.id
  );

-- Recompute from source on every join/leave. SECURITY DEFINER because a runner
-- joining a challenge they don't own has no UPDATE grant on the challenges row
-- (the update RLS policy is creator/club-admin only); the recompute must bypass
-- it. Recompute-from-count (not ±1) is self-healing — the cache can never drift
-- from count(*).
create or replace function sync_challenge_participant_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_challenge uuid := coalesce(new.challenge_id, old.challenge_id);
begin
  update challenges
    set participant_count = (
      select count(*) from challenge_participants p where p.challenge_id = v_challenge
    )
  where id = v_challenge;
  return coalesce(new, old);
end;
$$;

create trigger challenge_participants_count_sync
  after insert or delete on challenge_participants
  for each row execute function sync_challenge_participant_count();

-- Velocity index: the browse score reads joins in the trailing 7 days.
create index challenge_participants_challenge_joined
  on challenge_participants (challenge_id, joined_at);

-- ─────────────────────── 2. ranked discovery RPC ───────────────────────
-- SECURITY DEFINER (like the other discovery RPCs): the velocity term counts
-- ALL recent joins, which a non-participant caller's RLS on challenge_participants
-- would hide and undercount. The function returns ONLY public challenges and only
-- aggregate counts — no per-user rows, no PII — so definer leaks nothing the
-- caller couldn't already see. auth.uid() still resolves to the caller under
-- definer (it reads the request JWT, not the function owner).
create or replace function browse_public_challenges(
  p_search text default null,
  p_limit integer default 24,
  p_offset integer default 0
)
returns table (
  id uuid,
  creator_id uuid,
  club_id uuid,
  title text,
  description text,
  metric text,
  scope text,
  goal_value numeric,
  activity_type text,
  starts_at timestamptz,
  ends_at timestamptz,
  is_public boolean,
  created_at timestamptz,
  participant_count integer
)
language sql
stable
security definer
set search_path = public
as $$
  with eligible as (
    select
      c.*,
      (
        select count(*) from challenge_participants p
        where p.challenge_id = c.id
          and p.joined_at >= now() - interval '7 days'
      ) as joins_7d
    from challenges c
    where c.is_public = true
      -- still open to join
      and c.ends_at > now()
      -- not one the caller already joined (those live in My challenges)
      and not exists (
        select 1 from challenge_participants pj
        where pj.challenge_id = c.id and pj.user_id = auth.uid()
      )
      -- throwaway suppression: hide dead boards (no participants past a 7-day
      -- grace window) unless the caller created them, so a new challenge still
      -- gets a fair shot at gaining traction.
      and (
        c.participant_count > 0
        or c.created_at >= now() - interval '7 days'
        or c.creator_id = auth.uid()
      )
      and (
        p_search is null
        or btrim(p_search) = ''
        or c.title ilike '%' || btrim(p_search) || '%'
        or c.description ilike '%' || btrim(p_search) || '%'
      )
  )
  select
    id, creator_id, club_id, title, description, metric, scope, goal_value,
    activity_type, starts_at, ends_at, is_public, created_at, participant_count
  from eligible
  order by (participant_count + joins_7d * 2) desc, ends_at asc, created_at desc, id
  limit greatest(0, least(coalesce(p_limit, 24), 100))
  offset greatest(0, coalesce(p_offset, 0));
$$;

grant execute on function browse_public_challenges(text, integer, integer) to authenticated, anon;

-- ─────────────────────── 3. create-challenge rate limit ───────────────────────
-- Spam backstop (Open Question 2). A throttle on creation so a script can't
-- flood Browse with throwaway boards. Generous (30/hour) — far above any real
-- or test usage. Guarded two ways so it can never block a legitimate path:
--   * auth.uid() is null (seed / migration / service-role / superuser inserts)
--     pass straight through — only authenticated client inserts are throttled.
--   * any unexpected error from the rate-limit RPC fails OPEN (returns the row),
--     mirroring the helper's own fail-open philosophy — a rate-limit hiccup must
--     never take down challenge creation.
create or replace function enforce_challenge_create_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allowed boolean;
begin
  if auth.uid() is null then
    return new;
  end if;
  begin
    select allowed into v_allowed
    from check_rate_limit(auth.uid(), 'create_challenge', 30, 3600);
  exception when others then
    return new;
  end;
  if v_allowed is false then
    raise exception 'challenge_create_rate_limited'
      using hint = 'Too many challenges created recently. Try again later.';
  end if;
  return new;
end;
$$;

create trigger challenges_create_rate_limit
  before insert on challenges
  for each row execute function enforce_challenge_create_rate_limit();
