-- Safety-contact finish alerts (persona round-5 family-club, followups.md).
--
-- The run_completed notification (20261101_001) fans a *public* run out to
-- the runner's *followers*. The family-club persona wanted a partner to be
-- alerted that the runner finished even on a *private* run — a safety use
-- case. Removing the is_public gate there would broadcast every private run
-- to all followers, a privacy regression, so this is a distinct, explicit,
-- double-opt-in feature: one designated contact, alerted on every finish
-- regardless of is_public.
--
-- Shape:
--   * safety_contacts: owner -> contact. The contact is identified by an
--     EMAIL (always) and OPTIONALLY linked to an app user (contact_user_id)
--     once they confirm in-app. Storing only the email at add time avoids an
--     account-enumeration leak — the owner cannot probe whether an arbitrary
--     address belongs to a registered user. confirmed_at is the contact's
--     opt-in; the owner's opt-in is implicit in creating the row, so a row
--     that exists AND has confirmed_at set === both sides opted in.
--   * confirm_token backs an unauthenticated email-link confirm for external
--     (non-app-user) contacts; app users can instead confirm in-app via
--     my_pending_safety_requests() + confirm_safety_contact().
--   * A runs AFTER INSERT trigger enqueues a safety_email 'finish' job for
--     every CONFIRMED contact of the runner, regardless of is_public, with
--     the same 24h recency guard run_completed uses so a bulk history import
--     can't blast a contact with years of old finishes.
--   * A safety_contacts AFTER INSERT trigger enqueues a safety_email
--     'confirm' job so the contact receives the opt-in request by email.
--
-- The email leg rides a NEW safety_email job kind on the Go worker
-- (handler_safety_email.go). It is deliberately neither channel:
--   - not notification_email — there is no notifications inbox row, and it
--     must NOT be gated on the runner's email_notifications preference (a
--     safety contact explicitly opted in and must not be silenced by the
--     runner's social-email setting);
--   - not lifecycle_email — the recipient may be a non-user identified only
--     by an email, and the copy carries per-finish context (distance, time).
-- decisions §123.

-- ─────────────────────── table ───────────────────────

create table public.safety_contacts (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users(id) on delete cascade,
  -- Set only after an app-user contact confirms in-app, linking their
  -- account so a later account deletion cascades this row away and the
  -- alert can localize to their language. NULL for a pending or external
  -- (email-only) contact.
  contact_user_id uuid references auth.users(id) on delete cascade,
  contact_email   text not null,
  -- The contact's opt-in. NULL = pending (no alerts sent yet).
  confirmed_at    timestamptz,
  -- Capability token for the unauthenticated email-link confirm path.
  confirm_token   uuid not null default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint safety_contacts_email_format
    check (contact_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  -- A linked contact can't be the owner themselves.
  constraint safety_contacts_not_self
    check (contact_user_id is null or contact_user_id <> owner_id)
);

comment on table public.safety_contacts is
  'Opt-in safety contacts alerted by email when their owner finishes a run, '
  'regardless of is_public (decisions §123). Email-identified; contact_user_id '
  'links an app user after they confirm. Owner-scoped RLS, cascade-delete from '
  'auth.users on both legs.';

-- One contact address per owner (case-insensitive); re-adding the same
-- address is a no-op the client surfaces, not a duplicate row.
create unique index safety_contacts_owner_email_uniq
  on public.safety_contacts (owner_id, lower(contact_email));
create index safety_contacts_contact_user
  on public.safety_contacts (contact_user_id) where contact_user_id is not null;
create index safety_contacts_confirm_token
  on public.safety_contacts (confirm_token);

-- ─────────────────────── RLS ───────────────────────

alter table public.safety_contacts enable row level security;

-- Owner: read / add / remove their own list. Deliberately NO owner UPDATE
-- policy — confirmed_at + contact_user_id are set only by the SECURITY
-- DEFINER confirm functions below, so an owner can never self-confirm a
-- contact (which would email an address that never agreed). The owner edits
-- by delete + re-add.
create policy "safety_contacts owner read"
  on public.safety_contacts for select
  using (owner_id = auth.uid());
create policy "safety_contacts owner insert"
  on public.safety_contacts for insert
  with check (owner_id = auth.uid());
create policy "safety_contacts owner delete"
  on public.safety_contacts for delete
  using (owner_id = auth.uid());

-- Linked contact: see + withdraw from rows naming them. A *pending* contact
-- (not yet linked) is reached via the definer RPCs below (the email->row
-- match needs an auth.users read), not RLS.
create policy "safety_contacts linked contact read"
  on public.safety_contacts for select
  using (contact_user_id = auth.uid());
create policy "safety_contacts linked contact delete"
  on public.safety_contacts for delete
  using (contact_user_id = auth.uid());

-- Defense in depth: even though there's no owner UPDATE policy, force every
-- INSERT to the unconfirmed state so neither a client nor a future widened
-- policy can preset the contact's opt-in.
create or replace function safety_contacts_force_unconfirmed()
returns trigger
language plpgsql
as $$
begin
  new.confirmed_at := null;
  new.contact_user_id := null;
  return new;
end;
$$;

create trigger safety_contacts_unconfirmed_on_insert
  before insert on public.safety_contacts
  for each row execute function safety_contacts_force_unconfirmed();

-- ─────────────────────── confirm RPCs ───────────────────────

-- Pending safety requests addressed to the calling user's account email.
-- SECURITY DEFINER so it can match auth.users.email (PostgREST can't read
-- it) — but it only ever returns rows whose contact_email equals the
-- caller's own email, so it leaks nothing about other users.
create or replace function my_pending_safety_requests()
returns table (id uuid, owner_name text, created_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select sc.id,
         coalesce(p.display_name, ''),
         sc.created_at
  from safety_contacts sc
  join auth.users me on me.id = auth.uid()
  left join user_profiles p on p.id = sc.owner_id
  where sc.confirmed_at is null
    and lower(sc.contact_email) = lower(me.email);
$$;

revoke execute on function my_pending_safety_requests() from public;
grant execute on function my_pending_safety_requests() to authenticated;

-- An app user confirms a pending request addressed to their email, linking
-- their account. Returns true iff a row was confirmed.
create or replace function confirm_safety_contact(p_id uuid)
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
        updated_at = now()
  where id = p_id
    and confirmed_at is null
    and lower(contact_email) = lower(v_email)
    and owner_id <> auth.uid();
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function confirm_safety_contact(uuid) from public;
grant execute on function confirm_safety_contact(uuid) to authenticated;

-- Decline a pending request OR withdraw from a confirmed relationship —
-- removes any row addressed to the caller's email. Covers the pending case
-- the linked-contact DELETE policy can't (no contact_user_id yet).
create or replace function decline_safety_contact(p_id uuid)
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
  delete from safety_contacts
  where id = p_id
    and lower(contact_email) = lower(v_email);
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function decline_safety_contact(uuid) from public;
grant execute on function decline_safety_contact(uuid) to authenticated;

-- Email-link confirm for an external (non-app-user) contact. The unguessable
-- v4 token is the capability, so anon may call it; contact_user_id stays null
-- (no account to link). Returns true iff a pending row was confirmed.
create or replace function confirm_safety_contact_by_token(p_token uuid)
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
        updated_at = now()
  where confirm_token = p_token
    and confirmed_at is null;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function confirm_safety_contact_by_token(uuid) from public;
grant execute on function confirm_safety_contact_by_token(uuid) to anon, authenticated;

-- ─────────────────────── jobs.kind allowlist += safety_email ───────────────────────

-- Three-file rule (apps/job_worker/CLAUDE.md): widen the CHECK here + add the
-- Go dispatch case (worker.go) + extend the pgtap test, all this commit.
-- Re-list every existing kind (full set as of 20261211_001) plus the new one.
alter table public.jobs
  drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (kind in ('map_match', 'token_refresh', 'strava_event', 'photo_process', 'notification_email', 'lifecycle_email', 'safety_email'));

-- ─────────────────────── confirm-email enqueue trigger ───────────────────────

-- New safety_contacts row → email the contact an opt-in request. SECURITY
-- DEFINER so it can write public.jobs (RLS-denied to all but service_role).
create or replace function enqueue_safety_confirm_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  select coalesce(display_name, '') into v_name
  from user_profiles where id = new.owner_id;

  insert into public.jobs (kind, payload)
  values (
    'safety_email',
    jsonb_build_object(
      'template', 'confirm',
      'contact_email', new.contact_email,
      'owner_name', v_name,
      'confirm_token', new.confirm_token::text
    )
  );
  return new;
end;
$$;

revoke execute on function enqueue_safety_confirm_email() from public;

create trigger safety_contacts_enqueue_confirm
  after insert on public.safety_contacts
  for each row execute function enqueue_safety_confirm_email();

-- ─────────────────────── finish-alert enqueue trigger ───────────────────────

-- New run → email every CONFIRMED safety contact of the runner that they
-- finished. NO is_public gate (the whole point is to alert on private runs).
-- The 24h recency guard mirrors notify_run_completed (20261101_001): a bulk
-- history import (Strava/Garmin ZIP, parkrun backfill, CSV restore) must not
-- blast a contact with years of old finishes — only a run that actually
-- finished in the last day alerts. The window covers an ultra-length single
-- session (decisions §96). One job per (confirmed contact, run).
create or replace function enqueue_safety_finish_emails()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.started_at < now() - interval '24 hours' then
    return new;
  end if;

  insert into public.jobs (kind, payload)
  select
    'safety_email',
    jsonb_build_object(
      'template', 'finish',
      'contact_user_id', sc.contact_user_id,
      'contact_email', sc.contact_email,
      'owner_name', coalesce(p.display_name, ''),
      'run_id', new.id::text,
      'distance_m', new.distance_m,
      'duration_s', new.duration_s
    )
  from safety_contacts sc
  left join user_profiles p on p.id = new.user_id
  where sc.owner_id = new.user_id
    and sc.confirmed_at is not null;

  return new;
end;
$$;

revoke execute on function enqueue_safety_finish_emails() from public;

create trigger runs_enqueue_safety_finish
  after insert on runs
  for each row execute function enqueue_safety_finish_emails();
