-- Route the challenge-create throttle through the shared
-- `enforce_create_rate_limit` helper (20260907_001), so its refusal carries
-- the bucket name and the retry figure every other bucket's refusal carries.
--
-- 20270308_001 gave `challenges` its own trigger body calling
-- `check_rate_limit` directly and raising the bare string
-- `challenge_create_rate_limited`. The client parsers
-- (`apps/web/src/lib/util/rate_limit_errors.ts` + `rate_limit_errors.dart`)
-- match `rate limit exceeded for <bucket>, retry in Ns`, so that shape
-- reached no reader: web's ChallengeEditor fell through to its generic
-- "Couldn't create the challenge." toast, which names neither the cause nor
-- the wait. Replacing the FUNCTION rather than the trigger is enough — the
-- trigger keeps pointing at the same name — so this takes no lock on
-- `challenges` at all.
--
-- Three behaviours change with the helper, all of them deliberate:
--
--   * The bucket is keyed on `new.creator_id` rather than `auth.uid()`. On
--     any insert the WITH CHECK policy admits those are the same user; the
--     difference is the forged one, where the helper skips outright so the
--     policy raises 42501 instead of this trigger raising P0001 out of the
--     forger's own bucket and mis-classifying the attack. That is exactly
--     why 20260907_001 carries the skip.
--   * `service_role` is skipped explicitly, matching every other bucket.
--     Previously an Edge Function writing on a user's behalf under a JWT
--     carrying a `sub` was throttled by that user's own queue.
--   * The `exception when others then return new` fail-open wrapper is
--     gone. 20270308_001 justified it as "mirroring the helper's own
--     fail-open philosophy"; the helper has never had one, and behind its
--     guards both errors `check_rate_limit` can raise — a foreign
--     `p_user_id` and a non-positive max/window — are unreachable here.
--
-- Cap unchanged: 30 challenge creates per user per fixed hour.

create or replace function enforce_challenge_create_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform enforce_create_rate_limit('create_challenge', new.creator_id, 30, 3600);
  return new;
end;
$$;
