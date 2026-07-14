-- Off-route → auto-notify-contact escalation (docs/features/safety.md,
-- persona-woman). The third trigger for the overdue-runner safety net, beside
-- the telemetry-silence scan (20270401_001) and the per-run "not back by X" +
-- SMS legs (20270410_001). Where the scan watches for SILENCE, this fires when
-- a runner on a live-shared run is still moving and still pinging but has left
-- — and stayed off — their planned route.
--
-- Detection is CLIENT-SIDE (only the recording run screen knows the runner's
-- off-route distance vs the planned route; the pure OffRouteAlertDetector
-- debounces a sustained departure). The escalation itself reuses the EXISTING
-- notify path: this RPC enqueues the same safety_email job (+ additive
-- safety_sms) the scan does, with a distinct `off_route` template, and shares
-- the same once-per-run `metadata.safety_escalated_at` stamp so a runner gets
-- ONE alert per run whichever trigger fires first (safety.md decision 4).
--
-- Fail-closed, defence in depth:
--   * owner-only + in-progress-stub-only structural guards,
--   * opt-in pref `safety_off_route_alerts` (default absent/false),
--   * ≥1 confirmed safety contact,
--   * once-per-run (the shared stamp — a concurrent double-tap no-ops),
--   * SMS leg only for a contact with a stored phone AND sms_opt_in (the
--     provider itself stays unconfigured by default — 20270410_001).
-- The client ALSO gates the call on the OFF_ROUTE_ESCALATION_ENABLED deploy
-- flag (default off) + an active live broadcast, so nothing reaches a real
-- contact until owner + CISO + counsel sign-off flips the flag.
--
-- No jobs.kind change (reuses safety_email / safety_sms). No public_runs
-- change (safety_escalated_at is already stripped; no new metadata key).

create or replace function public.escalate_run_off_route(p_run_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_started timestamptz;
  v_last_seen timestamptz;
  v_has_ping boolean;
  v_owner_name text;
begin
  -- Atomic once-per-run stamp gated on every fail-closed condition. A
  -- concurrent double-fire finds safety_escalated_at already set and stamps 0
  -- rows, so the enqueue below can never run twice. Keeps in_progress=true so
  -- the finish/run_completed transition triggers don't see a stub→saved edge.
  update runs r
    set metadata = coalesce(r.metadata, '{}'::jsonb)
                   || jsonb_build_object('safety_escalated_at', now())
  where r.id = p_run_id
    and r.user_id = auth.uid()
    and coalesce(r.metadata->>'in_progress', '') = 'true'
    and r.metadata->>'safety_escalated_at' is null
    and r.started_at > now() - interval '24 hours'
    and exists (
      select 1 from user_settings us
      where us.user_id = r.user_id
        and us.prefs->>'safety_off_route_alerts' = 'true'
    )
    and exists (
      select 1 from safety_contacts sc
      where sc.owner_id = r.user_id and sc.confirmed_at is not null
    )
  returning r.user_id, r.started_at into v_owner, v_started;

  if v_owner is null then
    -- No match: not the owner / not an in-progress stub / already escalated /
    -- opted out / no confirmed contact. Fail-closed: enqueue nothing.
    return false;
  end if;

  -- The runner is still being tracked (a live broadcast is active), so a ping
  -- has almost certainly landed — carry the last-seen time. greatest() floors
  -- to started_at; has_ping distinguishes "no position yet" for the copy.
  select greatest(v_started, coalesce(max(p.at), v_started)),
         max(p.at) is not null
    into v_last_seen, v_has_ping
    from live_run_pings p
    where p.run_id = p_run_id;

  select coalesce(display_name, '') into v_owner_name
    from user_profiles where id = v_owner;

  -- Email: the guaranteed floor — one per confirmed contact, never gated on
  -- the runner's own email_notifications pref (the contact opted in). Times +
  -- the live link only, never coordinates (the /live page privacy-clips).
  insert into public.jobs (kind, payload)
  select
    'safety_email',
    jsonb_strip_nulls(jsonb_build_object(
      'template', 'off_route',
      'contact_user_id', sc.contact_user_id,
      'contact_email', sc.contact_email,
      'owner_name', v_owner_name,
      'run_id', p_run_id::text,
      'started_at', v_started,
      'last_seen_at', case when v_has_ping then v_last_seen end
    ))
  from safety_contacts sc
  where sc.owner_id = v_owner and sc.confirmed_at is not null;

  -- SMS: additive, only for a confirmed contact with a stored phone AND an SMS
  -- opt-in. A disabled/unconfigured SMS leg can never suppress the email.
  insert into public.jobs (kind, payload)
  select
    'safety_sms',
    jsonb_strip_nulls(jsonb_build_object(
      'template', 'off_route',
      'contact_user_id', sc.contact_user_id,
      'contact_phone', sc.contact_phone,
      'owner_name', v_owner_name,
      'run_id', p_run_id::text,
      'started_at', v_started,
      'last_seen_at', case when v_has_ping then v_last_seen end
    ))
  from safety_contacts sc
  where sc.owner_id = v_owner
    and sc.confirmed_at is not null
    and sc.contact_phone is not null
    and sc.sms_opt_in_at is not null;

  return true;
end;
$$;

revoke execute on function public.escalate_run_off_route(uuid) from public, anon;
grant execute on function public.escalate_run_off_route(uuid) to authenticated;
