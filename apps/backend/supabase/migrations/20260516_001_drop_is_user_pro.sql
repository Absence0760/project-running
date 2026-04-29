-- Drop is_user_pro(uuid). It's `security definer` and granted to
-- authenticated, with no caller-identity guard — any logged-in user
-- could call rpc('is_user_pro', { p_user_id: <victim> }) to learn
-- another user's subscription tier directly. Same footgun pattern
-- closed in 20260503 for the coach-usage RPCs and 20260515 for the
-- personal-records refresher.
--
-- The no-arg `is_pro()` function (defined in the same migration as
-- the original is_user_pro) covers every legitimate use case — it
-- already gates internally on `auth.uid()` so it can't be coerced
-- into reading another user's tier. Both call sites in the web app
-- (`CoachChat.svelte`, `api/coach/+server.ts`) only ever pass the
-- session user's own id, so they swap cleanly.
--
-- Drop rather than guard: keeping a guarded `is_user_pro(uuid)`
-- around adds a footgun for future code without delivering anything
-- `is_pro()` doesn't already provide.

drop function if exists is_user_pro(uuid);
