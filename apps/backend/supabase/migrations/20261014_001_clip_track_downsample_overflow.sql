-- clip_track_for_user: downsample inputs above the 50k cap instead of
-- rejecting them outright.
--
-- Persona-hunt Round 3 finding Ultra #5. Pre-fix, the original RPC
-- (migration 20260523_001) raised an exception on any input > 50000
-- points. A 5-hour run at 1Hz GPS is ~18k points (well under the cap),
-- but a 100-mile / 200-mile / multi-stage ultra at 1Hz GPS can hit
-- 100k–400k points (the ultra persona's primary use case is exactly
-- a track that long). The hard error meant spectators of an ultra
-- saw an empty trace on /share/run/[id] and /live/[id] for the entire
-- back half of the event.
--
-- Fix: when the input exceeds the cap, walk it with an even stride
-- (keep every Nth point so the output stays ≤ kept_max), explicitly
-- preserving the first and last samples so endpoints don't drift.
-- Then run the existing zone-clipping pass over the downsampled
-- array. The clipper's privacy contract is unchanged — zones never
-- leave the database — and the residual probe-attack bound from the
-- original ADR still holds because the walk is bounded by the cap.
--
-- Why even-stride instead of true RDP:
--   - Same primary goal (bound payload size).
--   - Endpoints preserved (the persona's stated correctness criterion).
--   - Deterministic O(n) — RDP in plpgsql is O(n log n) average +
--     ~50 lines of code for a value the spectator view doesn't need.
--   - The clipped output is for a privacy-zone-aware preview, not
--     route reconstruction; shape fidelity above 50k samples is below
--     the perceptual floor of a 1200×600 map render.
--
-- Result: a 360k-point ultra track downsampled at stride 8 yields
-- ~45k points; the existing zone-clip pass then drops in-zone
-- leading + trailing samples as before. Spectator sees a complete
-- (privacy-clipped) trace instead of a hard error.

-- Helper: even-stride downsample of a jsonb array.
-- Always emits the first and last elements (modulo array bounds);
-- intermediate elements are picked at stride = ceil(len / max_out).
-- Output length is ≤ max_out + 1; the +1 absorbs the explicit final
-- element when the stride doesn't land on (len - 1).
--
-- IMPLEMENTATION NOTE: the per-element `result := result ||
-- jsonb_build_array(...)` accumulation pattern is O(n²) in jsonb
-- (each `||` rebuilds the entire array). For n=50k that's ~1.25B
-- byte copies — minutes of wall time. We use `jsonb_agg` over
-- `generate_series` indices instead: a single aggregate over n
-- rows is O(n).
create or replace function _privacy_downsample(arr jsonb, max_out int)
returns jsonb
language plpgsql
immutable
parallel safe
as $$
declare
  arr_len int;
  stride int;
  out_arr jsonb;
  last_elem jsonb;
begin
  if arr is null or jsonb_typeof(arr) <> 'array' then
    return '[]'::jsonb;
  end if;
  arr_len := jsonb_array_length(arr);
  if arr_len <= max_out then return arr; end if;
  -- ceil(arr_len / max_out) — Postgres integer division truncates.
  stride := (arr_len + max_out - 1) / max_out;
  -- Single-pass aggregate over the stride indices. Alias `idx`
  -- (not `i`) so it can't collide with any plpgsql variable a
  -- caller might have shadowed.
  out_arr := (
    select coalesce(jsonb_agg(arr -> idx order by idx), '[]'::jsonb)
    from generate_series(0, arr_len - 1, stride) as g(idx)
  );
  -- Pin the last element explicitly so endpoints don't drift when
  -- the stride doesn't land cleanly on arr_len - 1.
  last_elem := arr -> (arr_len - 1);
  if jsonb_array_length(out_arr) = 0
     or (out_arr -> (jsonb_array_length(out_arr) - 1)) is distinct from last_elem then
    out_arr := out_arr || jsonb_build_array(last_elem);
  end if;
  return out_arr;
end;
$$;

revoke all on function _privacy_downsample(jsonb, int) from public;
-- No external grants — this is an internal helper.

create or replace function clip_track_for_user(target_user_id uuid, points jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  zones jsonb;
  working jsonb;
  arr_len int;
  start_idx int;
  end_idx int;
  i int;
  pt jsonb;
  result jsonb := '[]'::jsonb;
begin
  if points is null or jsonb_typeof(points) <> 'array' then
    return '[]'::jsonb;
  end if;

  arr_len := jsonb_array_length(points);
  if arr_len = 0 then return '[]'::jsonb; end if;

  -- Persona-hunt Round 3 finding Ultra #5. Downsample-on-overflow
  -- instead of hard error. The cap (50k) bounds the residual zone-
  -- probe attack just as before; the stride pass simply means we
  -- ship a thinner trace instead of nothing.
  if arr_len > 50000 then
    working := _privacy_downsample(points, 50000);
    arr_len := jsonb_array_length(working);
  else
    working := points;
  end if;

  select prefs->'privacy_zones' into zones
    from user_settings where user_id = target_user_id;

  -- No zones configured → return downsampled (or original) input.
  if zones is null or jsonb_typeof(zones) <> 'array' or jsonb_array_length(zones) = 0 then
    return working;
  end if;

  -- Walk forward dropping in-zone leading points.
  start_idx := 0;
  while start_idx < arr_len loop
    pt := working -> start_idx;
    exit when not privacy_in_any_zone(
      (pt->>'lat')::float,
      (pt->>'lng')::float,
      zones
    );
    start_idx := start_idx + 1;
  end loop;

  if start_idx >= arr_len then return '[]'::jsonb; end if;

  -- Walk backward dropping in-zone trailing points.
  end_idx := arr_len - 1;
  while end_idx > start_idx loop
    pt := working -> end_idx;
    exit when not privacy_in_any_zone(
      (pt->>'lat')::float,
      (pt->>'lng')::float,
      zones
    );
    end_idx := end_idx - 1;
  end loop;

  -- Single-pass aggregate over the kept indices instead of the
  -- O(n²) `result := result || jsonb_build_array(...)` accumulator
  -- the original RPC used. For n=50k that's the difference between
  -- ~minutes and ~tens of ms. Alias `idx` (not `i`) so it can't
  -- collide with the function's `i` declaration above.
  result := (
    select coalesce(jsonb_agg(working -> idx order by idx), '[]'::jsonb)
    from generate_series(start_idx, end_idx) as g(idx)
  );
  return result;
end;
$$;

-- Grants must match the latest audit state (migration
-- 20260915_001 revoked anon access — anon callers go through the
-- clip-public-track Edge Function which uses service_role).
revoke execute on function clip_track_for_user(uuid, jsonb) from public;
revoke execute on function clip_track_for_user(uuid, jsonb) from anon;
grant execute on function clip_track_for_user(uuid, jsonb) to authenticated, service_role;
