-- Trusted-contact SMS escalation channel + per-run "not back by X" override
-- (docs/features/safety.md, decisions ADR). Extends the overdue-runner
-- escalation (20270401_001) two ways:
--
--  1. Per-run expected-return override. A runner sets an expected-return time
--     for a specific live-broadcast run (metadata.expected_return_at). The
--     overdue scan now also fires when that time has passed — independent of,
--     and additive to, the universal safety_overdue_minutes silence window
--     (and it works even when that pref is unset). set_run_expected_return()
--     is the owner-only SECURITY DEFINER setter (merges/removes the metadata
--     key atomically so a client can't clobber the rest of the bag).
--
--  2. SMS escalation channel. safety_contacts gains an optional owner-stored
--     E.164 phone plus a contact-side SMS opt-in (sms_opt_in_at). When a
--     confirmed contact has BOTH, the scan enqueues an additional `safety_sms`
--     job beside the email. SMS is ADDITIVE, never a replacement: the email is
--     always enqueued for every confirmed contact, so the alert can never be
--     gated on the SMS provider (which is unconfigured by default — the Go
--     worker fails the SMS leg closed and the email still delivers). Double
--     opt-in mirrors email exactly (owner adds the number, the contact
--     consents), once-per-run via the same safety_escalated_at stamp, and the
--     SMS body carries times + the live link only — never coordinates.
--
-- Off-route → auto-notify-contact remains DEFERRED (no off-route hook at
-- escalation time); see docs/features/safety.md.

-- ─────────────────── 1. safety_contacts: phone + SMS opt-in ───────────────────

alter table public.safety_contacts
  -- Owner-stored destination for the SMS leg. E.164 (+ country code, 7-15
  -- digits, first digit non-zero). NULL = no number on file (email only).
  add column contact_phone text
    constraint safety_contacts_phone_format
      check (contact_phone is null or contact_phone ~ '^\+[1-9][0-9]{6,14}$'),
  -- The contact's explicit consent to be reached by SMS (the second opt-in,
  -- distinct from confirmed_at which covers the relationship/email). NULL =
  -- no SMS. Set only by the SECURITY DEFINER confirm/opt-in RPCs below — an
  -- owner can never self-set it (the force-unconfirmed trigger nulls it on
  -- insert, and there is no owner UPDATE policy).
  add column sms_opt_in_at timestamptz;

comment on column public.safety_contacts.contact_phone is
  'Owner-stored E.164 phone for the SMS escalation leg (decisions ADR). '
  'Optional; SMS only sends when the contact also set sms_opt_in_at.';
comment on column public.safety_contacts.sms_opt_in_at is
  'The contact''s explicit SMS opt-in (second consent beside confirmed_at). '
  'Set only by the SECURITY DEFINER confirm/opt-in RPCs, never by the owner.';

-- ─────────────────── 2. force-unconfirmed guard += sms opt-in ───────────────────

-- Base body is 20261218_001 — this only adds the sms_opt_in_at reset so a
-- client (or a future widened policy) can never preset the SMS consent.
create or replace function safety_contacts_force_unconfirmed()
returns trigger
language plpgsql
as $$
begin
  new.confirmed_at := null;
  new.contact_user_id := null;
  new.sms_opt_in_at := null;
  return new;
end;
$$;

-- ─────────────────── 3. confirm RPCs carry an SMS opt-in ───────────────────

-- Signature change (added a defaulted p_sms_opt_in) needs a drop first;
-- CREATE OR REPLACE can't add a parameter. Existing callers passing only
-- p_id keep working via the default.
drop function if exists confirm_safety_contact(uuid);
create function confirm_safety_contact(p_id uuid, p_sms_opt_in boolean default false)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_count int;
begin
  select email into v_email from auth.users where id = auth.uid();
  if v_email is null then
    return false;
  end if;
  update safety_contacts
    set confirmed_at = now(),
        contact_user_id = auth.uid(),
        -- Only arm SMS when the contact opted in AND the owner stored a number.
        sms_opt_in_at = case
          when p_sms_opt_in and contact_phone is not null then now()
          else null
        end,
        updated_at = now()
  where id = p_id
    and confirmed_at is null
    and lower(contact_email) = lower(v_email)
    and owner_id <> auth.uid();
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function confirm_safety_contact(uuid, boolean) from public;
grant execute on function confirm_safety_contact(uuid, boolean) to authenticated;

drop function if exists confirm_safety_contact_by_token(uuid);
create function confirm_safety_contact_by_token(p_token uuid, p_sms_opt_in boolean default false)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  update safety_contacts
    set confirmed_at = now(),
        sms_opt_in_at = case
          when p_sms_opt_in and contact_phone is not null then now()
          else null
        end,
        updated_at = now()
  where confirm_token = p_token
    and confirmed_at is null;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function confirm_safety_contact_by_token(uuid, boolean) from public;
grant execute on function confirm_safety_contact_by_token(uuid, boolean) to anon, authenticated;

-- Let an already-confirmed linked contact turn SMS on/off later (they own the
-- row via contact_user_id). Opting in requires a stored phone; opting out
-- always clears it.
create or replace function set_safety_sms_opt_in(p_id uuid, p_opt_in boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  update safety_contacts
    set sms_opt_in_at = case
          when p_opt_in and contact_phone is not null then now()
          else null
        end,
        updated_at = now()
  where id = p_id
    and contact_user_id = auth.uid()
    and confirmed_at is not null;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function set_safety_sms_opt_in(uuid, boolean) from public;
grant execute on function set_safety_sms_opt_in(uuid, boolean) to authenticated;

-- ─────────────────── 4. per-run expected-return override ───────────────────

-- The owner sets/clears an expected-return time on their OWN in-progress
-- broadcast run. SECURITY DEFINER (not a raw client UPDATE) so the metadata
-- merge is atomic — a client-side read-modify-write would race/clobber the
-- rest of the jsonb bag. The auth.uid() = user_id + in_progress guards keep
-- it owner-only and stub-only. Passing null clears the override.
create or replace function set_run_expected_return(
  p_run_id uuid,
  p_expected_return_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  update runs r
    set metadata = case
      when p_expected_return_at is null
        then coalesce(r.metadata, '{}'::jsonb) - 'expected_return_at'
      else coalesce(r.metadata, '{}'::jsonb)
           || jsonb_build_object('expected_return_at', p_expected_return_at)
    end
  where r.id = p_run_id
    and r.user_id = auth.uid()
    and coalesce(r.metadata->>'in_progress', '') = 'true';
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function set_run_expected_return(uuid, timestamptz) from public, anon;
grant execute on function set_run_expected_return(uuid, timestamptz) to authenticated;

-- ─────────────────── 5. jobs.kind allowlist += safety_sms ───────────────────

-- Three-file rule: widen the CHECK here + add the Go dispatch case
-- (worker.go) + a handler, all this change set. Full set as of 20270301_001
-- plus the new kind.
alter table public.jobs
  drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (
    kind in (
      'map_match', 'token_refresh', 'strava_event', 'photo_process',
      'notification_email', 'lifecycle_email', 'safety_email', 'web_push',
      'weekly_digest', 'native_push', 'lifecycle_drip', 'route_photo_process',
      'club_photo_process', 'safety_sms'
    )
  );

-- ─────────────────── 6. overdue scan: per-run override + SMS leg ───────────────────

-- Now matches a live-broadcast stub when EITHER:
--   * its per-run expected_return_at has passed (independent of the universal
--     pref — a runner can arm this per-run without ever setting the global
--     threshold), OR
--   * the universal safety_overdue_minutes silence window is exceeded
--     (unchanged 20270401_001 behaviour).
-- Both branches still require ≥1 confirmed contact, an unstamped run, and a
-- start within 24h. The same safety_escalated_at stamp keeps it once-per-run.
-- Enqueues an email per confirmed contact (the guaranteed floor) and,
-- additively, an SMS per confirmed contact who has a phone AND opted into SMS.
create or replace function public.enqueue_safety_overdue_emails()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  with overdue as (
    select
      r.id,
      r.user_id,
      r.started_at,
      greatest(r.started_at, coalesce(max(p.at), r.started_at)) as last_seen_at,
      max(p.at) is not null as has_ping
    from runs r
    -- LEFT join now: the per-run override branch must match even when the
    -- owner has no user_settings row / no universal threshold.
    left join user_settings us on us.user_id = r.user_id
    left join live_run_pings p on p.run_id = r.id
    where coalesce(r.metadata->>'in_progress', '') = 'true'
      and r.metadata->>'safety_escalated_at' is null
      and r.started_at > now() - interval '24 hours'
      and exists (
        select 1 from safety_contacts sc
        where sc.owner_id = r.user_id and sc.confirmed_at is not null
      )
    group by r.id, (us.prefs->>'safety_overdue_minutes')
    having
      (
        -- Per-run "not back by X" override.
        r.metadata->>'expected_return_at' is not null
        and (r.metadata->>'expected_return_at')::timestamptz < now()
      )
      or
      (
        -- Universal telemetry-silence window.
        us.prefs->>'safety_overdue_minutes' ~ '^[0-9]+$'
        and (us.prefs->>'safety_overdue_minutes')::int >= 10
        and greatest(r.started_at, coalesce(max(p.at), r.started_at))
            < now() - make_interval(mins => (us.prefs->>'safety_overdue_minutes')::int)
      )
  ),
  stamped as (
    update runs r
    set metadata = coalesce(r.metadata, '{}'::jsonb)
                   || jsonb_build_object('safety_escalated_at', now())
    from overdue o
    where r.id = o.id
    returning r.id, o.user_id, o.started_at, o.last_seen_at, o.has_ping
  ),
  email_jobs as (
    insert into public.jobs (kind, payload)
    select
      'safety_email',
      jsonb_strip_nulls(jsonb_build_object(
        'template', 'overdue',
        'contact_user_id', sc.contact_user_id,
        'contact_email', sc.contact_email,
        'owner_name', coalesce(pr.display_name, ''),
        'run_id', s.id::text,
        'started_at', s.started_at,
        'last_seen_at', case when s.has_ping then s.last_seen_at end
      ))
    from stamped s
    join safety_contacts sc
      on sc.owner_id = s.user_id and sc.confirmed_at is not null
    left join user_profiles pr on pr.id = s.user_id
    returning 1
  )
  insert into public.jobs (kind, payload)
  select
    'safety_sms',
    jsonb_strip_nulls(jsonb_build_object(
      'template', 'overdue',
      'contact_user_id', sc.contact_user_id,
      'contact_phone', sc.contact_phone,
      'owner_name', coalesce(pr.display_name, ''),
      'run_id', s.id::text,
      'started_at', s.started_at,
      'last_seen_at', case when s.has_ping then s.last_seen_at end
    ))
  from stamped s
  join safety_contacts sc
    on sc.owner_id = s.user_id
   and sc.confirmed_at is not null
   and sc.contact_phone is not null
   and sc.sms_opt_in_at is not null
  left join user_profiles pr on pr.id = s.user_id;
end;
$$;

revoke execute on function public.enqueue_safety_overdue_emails() from public, anon, authenticated;

-- ─────────────────── 7. public_runs strips the override ───────────────────

-- expected_return_at is owner-private safety data — it must never surface on
-- the anon live/public-run read path. Same column list as 20270401_001; only
-- the metadata denylist grows, so CREATE OR REPLACE is safe.
create or replace view public_runs as
select
  r.id,
  r.user_id,
  r.started_at,
  r.duration_s,
  r.distance_m,
  r.elevation_gain_m,
  r.source,
  r.activity_type,
  r.is_dnf,
  r.is_public,
  r.created_at,
  case when is_public_route_by_id(r.route_id) then r.route_id else null end as route_id,
  case when is_public_event_by_id(r.event_id) then r.event_id else null end as event_id,
  r.race_listing_id,
  (r.track_url is not null) as has_track,
  r.fastest_5k_s,
  r.fastest_10k_s,
  r.fastest_half_marathon_s,
  r.fastest_marathon_s,
  coalesce(r.metadata, '{}'::jsonb)
    - 'strava_id'
    - 'garmin_id'
    - 'imported_from'
    - 'imported_at'
    - 'health_connect_type'
    - 'strava_activity_type'
    - 'source_file'
    - 'max_bpm'
    - 'plan_workout_id'
    - 'workout_step_results'
    - 'workout_adherence'
    - 'last_modified_at'
    - 'recovered_from_crash'
    - 'in_progress_saved_at'
    - 'in_progress'
    - 'safety_escalated_at'
    - 'expected_return_at'
    - 'manual_entry'
    - 'indoor_estimated'
    - 'distance_source'
    - 'race_name'
    - 'bib'
    - 'overall_place'
    - 'chip_time'
    - 'gun_time'
    - 'age_group_place'
    - 'age_group'
    - 'perceived_effort'
    - 'run_number'
    as metadata
from runs r
where r.is_public = true;

revoke all on public.public_runs from public, anon, authenticated;
grant select on public_runs to anon, authenticated;
