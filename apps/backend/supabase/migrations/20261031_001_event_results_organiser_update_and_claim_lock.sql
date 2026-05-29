-- Two correctness fixes for the persona #43 import + claim flow, found in
-- adversarial review.
--
-- 1. Organiser UPDATE policy for re-import.
--    20261028_001 added event_results_insert_organiser so an event-organiser
--    can bulk-import, but a re-import upserts via ON CONFLICT DO UPDATE, and
--    Postgres evaluates the UPDATE RLS path for the conflict branch. The only
--    UPDATE policy (event_results_update_self_or_admin, 20260424_001) allows
--    `auth.uid() = user_id` (false for bib-only rows) OR is_club_admin (false
--    for the event_organiser role). So a non-owner/admin organiser can do the
--    first import but hits a permission error on every re-import. Add an
--    UPDATE policy scoped to bib-only rows (user_id is null) on events they
--    organise. The `user_id is null` guard in USING + WITH CHECK keeps an
--    event_organiser from mutating an account-owned result (or assigning
--    ownership) through the import path — owner/admin edits still flow through
--    the existing self-or-admin policy.
create policy event_results_update_organiser_bib
  on event_results for update
  using (
    user_id is null
    and exists (
      select 1 from events e
      where e.id = event_results.event_id
        and is_event_organiser(e.club_id)
    )
  )
  with check (
    user_id is null
    and exists (
      select 1 from events e
      where e.id = event_results.event_id
        and is_event_organiser(e.club_id)
    )
  );

-- 2. Serialize concurrent claim approvals.
--    decide_event_result_claim read the result row without a lock, so two
--    organisers approving different claims on the same bib row could both see
--    user_id = NULL, both pass the guard, and both UPDATE user_id — last write
--    wins on the row while both claims are marked approved (one then points at
--    a result owned by someone else). Re-created here verbatim from
--    20261030_001 (the live body) with a `for update` lock taken on the result
--    row at the top of the approval path so the second transaction blocks until
--    the first commits and then fails the `user_id is not null` re-check.
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

  -- Approval path. Lock the result row so concurrent approvals of competing
  -- claims serialize — the second transaction re-reads user_id after the
  -- first commits and fails the not-null guard below instead of clobbering it.
  select * into v_res from event_results where id = v_claim.result_id for update;
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

  update event_result_claims
    set status = 'rejected', decided_by = auth.uid(), decided_at = now()
    where result_id = v_res.id and id <> p_claim_id and status = 'pending';

  return v_claim;
end;
$$;

revoke execute on function decide_event_result_claim(uuid, boolean) from public, anon;
grant execute on function decide_event_result_claim(uuid, boolean) to authenticated;
