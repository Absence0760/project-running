-- Persona #43 follow-up: let a registered runner claim a bib-only result
-- that an organiser bulk-imported (account-optional event_results landed in
-- 20261028_001). Trust model: organiser approves (decisions.md §95) — the
-- organiser ran the race and imported the sheet, so they're the right party
-- to confirm "bib 102 is this account". An unclaimed/unapproved row sits
-- harmlessly: it stays on the public leaderboard by printed name, exactly
-- as today, just unattached to an account.
--
-- A separate claims table (not a column on event_results) so two people
-- claiming the same bib both surface for the organiser to adjudicate.

create table event_result_claims (
  id uuid primary key default gen_random_uuid(),
  result_id uuid not null references event_results(id) on delete cascade,
  claimant_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  unique (result_id, claimant_id)
);

create index event_result_claims_by_result on event_result_claims(result_id);
create index event_result_claims_pending
  on event_result_claims(result_id) where status = 'pending';

alter table event_result_claims enable row level security;

-- Visibility: a claimant sees their own claims; an event-organiser sees
-- every claim against a result on an event they run.
create policy event_result_claims_select
  on event_result_claims for select
  using (
    claimant_id = auth.uid()
    or exists (
      select 1
      from event_results er
      join events e on e.id = er.event_id
      where er.id = event_result_claims.result_id
        and is_event_organiser(e.club_id)
    )
  );

-- All writes go through the SECURITY DEFINER RPCs below (creating a claim
-- needs cross-row checks RLS can't express; deciding one is organiser-only).
-- No INSERT/UPDATE/DELETE policies → direct client writes are denied.

-- ── Create a claim ──
-- Caller claims a bib-only result. Guards: the row must be bib-only
-- (unclaimed), the caller must be able to see the parent event, and the
-- caller must not already hold a result for that (event, instance) — you
-- can't claim a stranger's time when you already finished it yourself.
create or replace function claim_event_result(p_result_id uuid)
returns event_result_claims language plpgsql security definer set search_path = public as $$
declare
  v_res event_results;
  v_visible boolean;
  v_claim event_result_claims;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_res from event_results where id = p_result_id;
  if v_res.id is null then
    raise exception 'Result not found';
  end if;
  if v_res.user_id is not null then
    raise exception 'This result already belongs to an account';
  end if;

  -- Caller must be able to see the parent event (mirror of the
  -- event_results SELECT visibility chain).
  select exists (
    select 1 from events e
    left join clubs c on c.id = e.club_id
    where e.id = v_res.event_id
      and (c.id is null or c.is_public = true or c.owner_id = auth.uid() or is_club_member(c.id))
  ) into v_visible;
  if not v_visible then
    raise exception 'Not authorised to claim this result';
  end if;

  if exists (
    select 1 from event_results
    where event_id = v_res.event_id
      and instance_start = v_res.instance_start
      and user_id = auth.uid()
  ) then
    raise exception 'You already have a result for this event';
  end if;

  insert into event_result_claims (result_id, claimant_id)
  values (p_result_id, auth.uid())
  on conflict (result_id, claimant_id)
    -- Re-requesting after a rejection re-opens the claim.
    do update set status = 'pending', decided_by = null, decided_at = null,
                  created_at = now()
  returning * into v_claim;
  return v_claim;
end;
$$;

-- ── Decide a claim (organiser only) ──
-- Approving attaches the claimant's account to the bib row and auto-rejects
-- any competing pending claims on the same row. Re-validates that the row is
-- still bib-only and that the claimant hasn't since recorded their own result
-- for the instance, so concurrent activity can't produce a duplicate or a
-- silent steal.
create or replace function decide_event_result_claim(p_claim_id uuid, p_approve boolean)
returns event_result_claims language plpgsql security definer set search_path = public as $$
declare
  v_claim event_result_claims;
  v_res event_results;
  v_club uuid;
begin
  select * into v_claim from event_result_claims where id = p_claim_id;
  if v_claim.id is null then
    raise exception 'Claim not found';
  end if;

  select * into v_res from event_results where id = v_claim.result_id;
  select club_id into v_club from events where id = v_res.event_id;
  if v_club is null or not is_event_organiser(v_club) then
    raise exception 'Not authorised to decide claims for this event';
  end if;

  if v_claim.status <> 'pending' then
    raise exception 'Claim already decided';
  end if;

  if not p_approve then
    update event_result_claims
      set status = 'rejected', decided_by = auth.uid(), decided_at = now()
      where id = p_claim_id
      returning * into v_claim;
    return v_claim;
  end if;

  -- Approval path.
  if v_res.user_id is not null then
    raise exception 'This result has already been claimed by another account';
  end if;
  if exists (
    select 1 from event_results
    where event_id = v_res.event_id
      and instance_start = v_res.instance_start
      and user_id = v_claim.claimant_id
  ) then
    raise exception 'The claimant already has a result for this event';
  end if;

  update event_results
    set user_id = v_claim.claimant_id, updated_at = now()
    where id = v_res.id;

  update event_result_claims
    set status = 'approved', decided_by = auth.uid(), decided_at = now()
    where id = p_claim_id
    returning * into v_claim;

  -- Any other pending claim on the same row is now moot.
  update event_result_claims
    set status = 'rejected', decided_by = auth.uid(), decided_at = now()
    where result_id = v_res.id and id <> p_claim_id and status = 'pending';

  return v_claim;
end;
$$;

revoke execute on function claim_event_result(uuid) from public, anon;
grant execute on function claim_event_result(uuid) to authenticated;
revoke execute on function decide_event_result_claim(uuid, boolean) from public, anon;
grant execute on function decide_event_result_claim(uuid, boolean) to authenticated;

-- Expose the surrogate id on the leaderboard read surface so the client can
-- target a specific row to claim. id is a non-sensitive uuid. Rebuilt from
-- 20261028_001's body (the live view) per the "create or replace strips
-- prior fixes" rule, adding only `id`.
drop view if exists event_results_redacted;

create view event_results_redacted as
select
  id,
  event_id,
  instance_start,
  user_id,
  bib,
  finisher_name,
  duration_s,
  distance_m,
  rank,
  finisher_status,
  case
    when user_id = auth.uid() then age_grade_pct
    else null
  end as age_grade_pct,
  case
    when user_id = auth.uid() then note
    else null
  end as note,
  created_at,
  updated_at,
  organiser_approved,
  case
    when user_id = auth.uid() then run_id
    else null
  end as run_id
from event_results;

alter view event_results_redacted set (security_invoker = on);

grant select on event_results_redacted to anon, authenticated;
