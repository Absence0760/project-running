-- Coach-athlete relationship (persona #46 MVP: invite/accept + roster).
--
-- A coach generates a shareable invite token; the athlete redeems it to form an
-- active link. Either party can end the link. This is the relationship spine that
-- consent-gated coach run visibility (#47) and coach-owned training plans build on
-- later -- this migration ships only the link model + the redeem RPC.
--
-- athlete_id is null while an invite token is unredeemed, so a coach can have many
-- open invites. On redemption the row gains the athlete and flips to 'active'.
-- The status CHECK is a table-level constraint (not a trailing add-constraint) so
-- the Dart row generator's paren-aware body splitter parses it cleanly.

create table coach_athletes (
  id           uuid primary key default gen_random_uuid(),
  coach_id     uuid references auth.users on delete cascade not null,
  athlete_id   uuid references auth.users on delete cascade,
  status       text not null default 'pending',
  invite_token text not null,
  note         text,
  created_at   timestamptz not null default now(),
  accepted_at  timestamptz,
  ended_at     timestamptz,
  constraint coach_athletes_status_check check (status in ('pending', 'active', 'ended'))
);

create unique index coach_athletes_invite_token_key on coach_athletes (invite_token);

-- At most one live link per (coach, athlete). Unredeemed invites have a null
-- athlete_id and are excluded (nulls are distinct), so many open invites are fine.
create unique index coach_athletes_live_pair_key
  on coach_athletes (coach_id, athlete_id)
  where athlete_id is not null and status in ('pending', 'active');

create index coach_athletes_coach_active_idx on coach_athletes (coach_id) where status = 'active';

create index coach_athletes_athlete_active_idx on coach_athletes (athlete_id) where status = 'active';

alter table coach_athletes enable row level security;

-- redeem_coach_invite below is SECURITY DEFINER and owned by `postgres`. New
-- public tables are auto-granted only to anon/authenticated/service_role, so
-- without this the definer body hits "permission denied for table
-- coach_athletes". Matches the privileges older tables (e.g. club_members)
-- already carry for their definer RPCs.
grant select, insert, update, delete on coach_athletes to postgres;

-- Either party can read links they're part of.
create policy "coach or athlete reads own links"
  on coach_athletes for select
  using (coach_id = auth.uid() or athlete_id = auth.uid());

-- A coach creates only their own unredeemed pending invites. Redemption sets the
-- athlete via the SECURITY DEFINER RPC below, never a direct insert.
create policy "coach creates own pending invite"
  on coach_athletes for insert
  with check (coach_id = auth.uid() and athlete_id is null and status = 'pending');

-- Either party can mutate a link they're part of (the only client mutation today
-- is ending it). The redeem path runs as definer and bypasses this.
create policy "party updates own link"
  on coach_athletes for update
  using (coach_id = auth.uid() or athlete_id = auth.uid())
  with check (coach_id = auth.uid() or athlete_id = auth.uid());

-- A coach can revoke (delete) an invite they created that nobody redeemed yet.
create policy "coach deletes own unredeemed invite"
  on coach_athletes for delete
  using (coach_id = auth.uid() and athlete_id is null and status = 'pending');

-- Redeem an invite token: the caller becomes the athlete on a pending invite.
-- Runs as definer because the athlete has no RLS write path to a row that isn't
-- theirs yet (athlete_id is still null at redemption time).
create or replace function redeem_coach_invite(token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  inv coach_athletes%rowtype;
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  select * into inv from coach_athletes
    where invite_token = token and status = 'pending' and athlete_id is null
    for update;

  if not found then
    raise exception 'invite not found or already redeemed';
  end if;

  if inv.coach_id = uid then
    raise exception 'cannot coach yourself';
  end if;

  if exists (
    select 1 from coach_athletes
    where coach_id = inv.coach_id
      and athlete_id = uid
      and status in ('pending', 'active')
  ) then
    raise exception 'already linked to this coach';
  end if;

  update coach_athletes
    set athlete_id = uid, status = 'active', accepted_at = now()
    where id = inv.id;

  return inv.coach_id;
end;
$$;

grant execute on function redeem_coach_invite(text) to authenticated;
