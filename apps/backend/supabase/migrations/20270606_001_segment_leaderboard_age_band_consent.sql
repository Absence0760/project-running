-- Age-banded segment leaderboards stop reading the age record without consent.
-- decisions § 718 open item 2; the SQL analogue of § 722's client-side rule.
--
-- `user_profiles.date_of_birth` is two records under one column name (§ 718).
-- It is the **age record**: its consumers are the under-18 exclusions in
-- `search_user_profiles` / `discoverable_runners_near` and the auto-hide report
-- path, a child-protection purpose resting on a lawful basis that is NOT the
-- runner's consent — which is exactly why `20270605_001` stopped
-- `withdraw_health_data_consent()` erasing it (§ 721). But *reading* it to
-- derive an age is an Art 9 health inference, and that belongs behind
-- `health_data_consent_at`.
--
-- Both boards banded on `extract(year from age(up.date_of_birth))` and checked
-- nothing, so a runner who supplied a date and declined the Art 9 checkbox was
-- still placed in an age tier. PR #814 landed the client half of this rule as
-- the `health_consent.ts` ↔ `health_consent.dart` parity pair (`healthUseDob`,
-- § 722); this is the same rule where the derivation actually happens, on the
-- server, for the two surfaces no client gate can reach.
--
-- Gender needs no term of its own and gains none: `gender` is only ever
-- populated under consent, so the gender tier was already correct. Age was the
-- one that leaked.
--
-- ── Two sites per function, and what an unconsented runner sees ──
-- 1. The band MEMBERSHIP filter inside `best_per_athlete`. Gated, so a runner
--    without consent falls out of the age tier ENTIRELY rather than being
--    placed in a wrong one — the same outcome the adjacent
--    `up.date_of_birth is not null` branch already produces for a runner with
--    no date at all, which is the shape this stays consistent with. They are
--    untouched on the UNFILTERED board: dropping them there would spend a
--    privacy gate on a competitive ranking that never needed their age.
-- 2. The caller's own `age` echo in the outer select. Also gated, and null is
--    again what a runner with no date already gets. Withholding the caller's
--    own age from the caller is not protecting them from themselves — the
--    DERIVATION is the processing, and consent is what authorises it. The
--    client twin does exactly this: `healthUseDob` returns null for
--    `consent_withheld` on the runner's own row.
--
-- ── Bare body, and it is 20270524_001's, not the one the follow-up named ──
-- § 718's open item points at `20270424000003` / `20270513_001`, but both
-- bodies were re-emitted later by `20270524_001` (the §206 shadow-hidden
-- definer backstop). A create-or-replace built on the older text would silently
-- revert that fix. Each body below is therefore the COMPLETE live definition as
-- of `20270524_001` — the per-athlete `distinct on` reduction (issue #393), the
-- delegated `private.is_route_visible_to` per-call route check, the
-- shadow-hidden `display_name` / `avatar_url` carve-out, the block filter, the
-- club filter and the own-row demographic masking all carried through
-- unchanged, with the consent term as the only edit. search_path keeps
-- `private`: `is_club_member` moved there in `20261120_001`.
--
-- ── Online safety ──
-- Two `create or replace function` bodies, no table DDL and no constraint, so
-- no lock is taken on any table (docs/backend/migration_locks.md). Signatures,
-- return types, volatility and search_path are unchanged, so no
-- drop-and-recreate and the existing grants stand. No column changes, so no
-- row-type regeneration is owed — verified rather than asserted: both
-- generators (`npm run gen:types`, `dart run scripts/gen_dart_models.dart`)
-- were re-run against this migration and produced a zero diff.

-- ── 1. segment_leaderboard_tiered ──
create or replace function segment_leaderboard_tiered(
  p_segment_id uuid,
  p_gender text default null,
  p_age_band text default null,
  p_limit integer default 50,
  p_club_id uuid default null
)
returns table (
  effort_id uuid,
  user_id uuid,
  run_id uuid,
  time_seconds integer,
  started_at timestamptz,
  display_name text,
  avatar_url text,
  gender text,
  age integer
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
declare
  age_min integer := null;
  age_max integer := null;
  caller uuid := auth.uid();
  v_route_id uuid;
begin
  if caller is null then
    raise exception 'segment_leaderboard_tiered requires an authenticated caller'
      using errcode = '42501';
  end if;

  if p_age_band is not null then
    if p_age_band = '75+' then
      age_min := 75;
      age_max := 200;
    elsif p_age_band ~ '^[0-9]+-[0-9]+$' then
      age_min := split_part(p_age_band, '-', 1)::integer;
      age_max := split_part(p_age_band, '-', 2)::integer;
    else
      raise exception 'segment_leaderboard_tiered: invalid p_age_band %', p_age_band
        using errcode = '22023';
    end if;
  end if;

  -- Every effort on a segment hangs off ONE route, so route visibility is a
  -- per-call question, not a per-row one. A missing segment leaves v_route_id
  -- null and collapses the board, which is also what the dropped
  -- `join segments` used to do.
  select s.route_id into v_route_id
  from public.segments s
  where s.id = p_segment_id;

  if v_route_id is null or not private.is_route_visible_to(v_route_id, caller) then
    return;
  end if;

  -- A club filter only applies when the caller is a member of that club;
  -- otherwise it collapses the board to empty rather than leaking membership.
  if p_club_id is not null and not is_club_member(p_club_id) then
    return;
  end if;

  return query
  with best_per_athlete as (
    -- Each athlete's fastest effort the caller is allowed to see. All
    -- gender/age/club/visibility/block filters live HERE so the reduction
    -- ranks over the visible set — a hidden faster effort can't suppress a
    -- slower visible one for the same athlete.
    select distinct on (se.user_id)
      se.id           as effort_id,
      se.user_id      as user_id,
      se.run_id       as run_id,
      se.time_seconds as time_seconds,
      se.started_at   as started_at
    from public.segment_efforts se
    join public.user_profiles   up on up.id = se.user_id
    where se.segment_id = p_segment_id
      and private.is_run_visible_to(se.run_id, caller)
      and not is_blocked_either_way(caller, se.user_id)
      and (p_gender is null or up.gender = p_gender)
      and (
        p_age_band is null
        or (
          up.date_of_birth is not null
          and up.health_data_consent_at is not null
          and extract(year from age(up.date_of_birth))::integer between age_min and age_max
        )
      )
      and (
        p_club_id is null
        or exists (
          select 1 from public.club_members cm
          where cm.club_id = p_club_id
            and cm.user_id = se.user_id
            and cm.status = 'active'
        )
      )
    order by se.user_id, se.time_seconds asc, se.started_at asc
  )
  select
    b.effort_id,
    b.user_id,
    b.run_id,
    b.time_seconds::integer                                    as time_seconds,
    b.started_at,
    case when up.shadow_hidden = false or up.id = caller
      then up.display_name end                                 as display_name,
    case when up.shadow_hidden = false or up.id = caller
      then up.avatar_url end                                   as avatar_url,
    case when b.user_id = caller then up.gender else null end  as gender,
    case
      when b.user_id = caller
       and up.date_of_birth is not null
       and up.health_data_consent_at is not null
        then extract(year from age(up.date_of_birth))::integer
      else null
    end                                                        as age
  from best_per_athlete b
  join public.user_profiles up on up.id = b.user_id
  order by b.time_seconds asc, b.started_at asc
  limit p_limit;
end;
$$;

-- ── 2. global_segment_leaderboard ──
-- Catalogue segments have no parent route, so no route branch here.
create or replace function global_segment_leaderboard(
  p_segment_id uuid,
  p_gender text default null,
  p_age_band text default null,
  p_limit integer default 50,
  p_club_id uuid default null
)
returns table (
  effort_id uuid,
  user_id uuid,
  run_id uuid,
  time_seconds integer,
  started_at timestamptz,
  display_name text,
  avatar_url text,
  gender text,
  age integer
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
declare
  age_min integer := null;
  age_max integer := null;
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'global_segment_leaderboard requires an authenticated caller'
      using errcode = '42501';
  end if;

  if p_age_band is not null then
    if p_age_band = '75+' then
      age_min := 75;
      age_max := 200;
    elsif p_age_band ~ '^[0-9]+-[0-9]+$' then
      age_min := split_part(p_age_band, '-', 1)::integer;
      age_max := split_part(p_age_band, '-', 2)::integer;
    else
      raise exception 'global_segment_leaderboard: invalid p_age_band %', p_age_band
        using errcode = '22023';
    end if;
  end if;

  -- A club filter only applies when the caller is a member of that club;
  -- otherwise it collapses to empty rather than leaking membership.
  if p_club_id is not null and not is_club_member(p_club_id) then
    return;
  end if;

  return query
  with best_per_athlete as (
    -- Each athlete's fastest effort the caller is allowed to see. All
    -- gender/age/club/visibility/block filters live HERE so the reduction
    -- ranks over the visible set — a hidden faster effort can't suppress a
    -- slower visible one for the same athlete.
    select distinct on (se.user_id)
      se.id           as effort_id,
      se.user_id      as user_id,
      se.run_id       as run_id,
      se.time_seconds as time_seconds,
      se.started_at   as started_at
    from public.global_segment_efforts se
    join public.global_segments      gs on gs.id = se.global_segment_id
    join public.user_profiles        up on up.id = se.user_id
    where se.global_segment_id = p_segment_id
      and gs.is_active = true
      and private.is_run_visible_to(se.run_id, caller)
      -- Block-aware: hide efforts by users the caller has blocked (or who
      -- have blocked the caller). Own effort survives (block of self is false).
      and not is_blocked_either_way(caller, se.user_id)
      and (p_gender is null or up.gender = p_gender)
      and (
        p_age_band is null
        or (
          up.date_of_birth is not null
          and up.health_data_consent_at is not null
          and extract(year from age(up.date_of_birth))::integer between age_min and age_max
        )
      )
      and (
        p_club_id is null
        or exists (
          select 1 from public.club_members cm
          where cm.club_id = p_club_id
            and cm.user_id = se.user_id
            and cm.status = 'active'
        )
      )
    order by se.user_id, se.time_seconds asc, se.started_at asc
  )
  select
    b.effort_id,
    b.user_id,
    b.run_id,
    b.time_seconds::integer                                    as time_seconds,
    b.started_at,
    case when up.shadow_hidden = false or up.id = caller
      then up.display_name end                                 as display_name,
    case when up.shadow_hidden = false or up.id = caller
      then up.avatar_url end                                   as avatar_url,
    case when b.user_id = caller then up.gender else null end  as gender,
    case
      when b.user_id = caller
       and up.date_of_birth is not null
       and up.health_data_consent_at is not null
        then extract(year from age(up.date_of_birth))::integer
      else null
    end                                                        as age
  from best_per_athlete b
  join public.user_profiles up on up.id = b.user_id
  order by b.time_seconds asc, b.started_at asc
  limit p_limit;
end;
$$;
