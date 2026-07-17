-- Owner-callable atomic set/clear of a browser's web-push registration on
-- user_device_settings.prefs (issue #235).
--
-- The web client used to persist a subscription with a read-merge-write of
-- the WHOLE prefs bag (select prefs → merge in JS → upsert prefs), and both
-- halves of that shape failed silently: the upsert result went unchecked
-- (the browser showed push enabled while the server never learned about the
-- subscription), and an errored merge-base read started the merge from `{}`
-- so the upsert replaced the entire bag with just push_subscription —
-- destroying every other per-device pref. PostgREST cannot express a jsonb
-- key-targeted write in a PATCH, so — mirroring the worker-side
-- clear_push_subscription prune — the single-key jsonb_set / minus lives in
-- an RPC. One statement, one key: no merge-base read exists to fail, and a
-- concurrent writer of other prefs cannot be clobbered.
--
-- SECURITY INVOKER: the caller writes only their own row under the existing
-- owner-only RLS policies; auth.uid() scopes the target. The insert arm
-- covers a device row that loadSettings hasn't auto-provisioned yet
-- (platform is NOT NULL, so the client passes its detected platform/label,
-- matching the provision row's shape). A SQL NULL or jsonb 'null'
-- p_subscription clears the key — PostgREST maps a JSON null argument to
-- SQL NULL, but both spellings are accepted so the contract doesn't hinge
-- on that mapping.

create or replace function set_push_subscription(
  p_device_id text,
  p_subscription jsonb,
  p_platform text default 'web',
  p_label text default null
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_clear boolean := p_subscription is null or jsonb_typeof(p_subscription) = 'null';
begin
  insert into user_device_settings (user_id, device_id, platform, label, prefs, updated_at)
  values (
    auth.uid(),
    p_device_id,
    p_platform,
    p_label,
    case when v_clear then '{}'::jsonb
         else jsonb_build_object('push_subscription', p_subscription) end,
    now()
  )
  on conflict (user_id, device_id) do update
    set prefs = case when v_clear
                     then user_device_settings.prefs - 'push_subscription'
                     else jsonb_set(user_device_settings.prefs, '{push_subscription}', p_subscription) end,
        updated_at = now();
end;
$$;

revoke execute on function set_push_subscription(text, jsonb, text, text) from public, anon;
grant execute on function set_push_subscription(text, jsonb, text, text) to authenticated;
