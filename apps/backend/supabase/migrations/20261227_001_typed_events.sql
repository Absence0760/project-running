-- Typed club events (slice E of docs/features/club_events.md).
--
-- Clubs are generic containers; an event now carries a `category` that drives
-- which fields + features apply:
--   run / cycle -> distance-based athletic events (route, pace, race mode,
--                  results leaderboard, finisher certificate)
--   class       -> instructor-led session (yoga / pilates / spin / strength);
--                  no route / pace / results. The specific style is the
--                  free-text `discipline` label, NOT an enum.
--   social      -> a meetup (title / time / place / capacity only)
-- Names track the existing ActivityType union ('cycle', not 'ride') so the app
-- keeps one type vocabulary (see club_events.md § Category -> modality mapping).
--
-- `host_user_id` names the payout recipient for a later paid-events slice and
-- defaults to the creator (money follows the instructor, not the club).
-- `gym_template` is the optional class->gym seam hint (reserved; the
-- attendee-side write ships later).
--
-- Defense in depth: a non-athletic event must be un-race-able and
-- un-result-able at the DATA layer, not just hidden in the UI. Triggers reject
-- race_sessions / event_results inserts whose parent event is not run / cycle.

-- 1. Columns ---------------------------------------------------------------

-- The CHECK is a separate `add constraint` (not inline) so the Dart row
-- generator's add-column parser stays happy and the constraint matches the
-- narrow-union pattern (20260505_001) the parity guard expects.
alter table events add column category text not null default 'run';
alter table events add constraint events_category_check
  check (category in ('run', 'cycle', 'class', 'social'));

alter table events add column discipline text;
alter table events add column host_user_id uuid references auth.users;
alter table events add column gym_template jsonb;

-- Existing events predate the column and are all run-shaped; the NOT NULL
-- DEFAULT already stamps them 'run'. Backfill the host to the creator
-- (events.author_id is the creator since the f17 rename, 20261217_001).
update events set host_user_id = author_id where host_user_id is null;

-- Always populate the payout recipient: default it to the creator when the
-- client omits it. Clubs stay generic; money follows the event's host.
create or replace function events_default_host()
returns trigger
language plpgsql
as $$
begin
  if new.host_user_id is null then
    new.host_user_id := new.author_id;
  end if;
  return new;
end;
$$;

create trigger events_set_default_host
  before insert on events
  for each row execute function events_default_host();

-- 2. Data-layer guards: only athletic events can be raced / have results -----

-- SECURITY DEFINER + pinned search_path (the is_club_admin pattern) so the
-- category read is reliable regardless of the caller's RLS visibility.
create or replace function event_is_athletic(target_event uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from events e
    where e.id = target_event
      and e.category in ('run', 'cycle')
  );
$$;

create or replace function reject_nonathletic_race()
returns trigger
language plpgsql
as $$
begin
  if not event_is_athletic(new.event_id) then
    raise exception 'race sessions are only allowed on run/cycle events (event % is not athletic)', new.event_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger race_sessions_require_athletic
  before insert on race_sessions
  for each row execute function reject_nonathletic_race();

create or replace function reject_nonathletic_result()
returns trigger
language plpgsql
as $$
begin
  if not event_is_athletic(new.event_id) then
    raise exception 'event results are only allowed on run/cycle events (event % is not athletic)', new.event_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger event_results_require_athletic
  before insert on event_results
  for each row execute function reject_nonathletic_result();
