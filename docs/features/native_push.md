# Native push (FCM / APNs) — implementation plan

> **Status:** Planned — specced 2026-06-15, not yet built. This is an implementation handoff plan, not a description of shipped behaviour. Tracked in [roadmap.md § Planned features](../product/roadmap.md#planned-features--specced-2026-06-15).

## Goal & user value
Deliver the last device-delivery leg: a push notification to a **locked phone**
(not just the browser, not just email). Build the FCM/APNs sender as a **second
consumer of the existing `notifications` rows** — exactly the sibling-consumer
pattern the shipped `web_push` kind already demonstrates — plus the client-side
device-token registration on sign-in that the `device_tokens` table was created
for but never got a write path. Going *live* is blocked only on operator-
supplied Firebase/APNs credentials; **all credential-independent code ships
now, fail-closed** (nil sender → jobs finish without sending, rows stay
pending), so a later credentialed deploy delivers the backlog.

## What already exists to build on (verified)
- **`notifications` table** is the single source of truth read by the in-app
  bell, the `notification_email` kind, and the `web_push` kind. Each consumer
  has its own `*_sent_at` idempotency column and its own preference gate.
- **`device_tokens` table** — `apps/backend/supabase/migrations/20260506_001_device_tokens.sql`.
  Columns: `id, user_id, platform (check in ('ios','android','web')), token,
  app_version, locale, notifications_enabled bool default true, last_seen_at,
  created_at, updated_at, unique (user_id, token)`. The DDL comment already
  describes the fan-out: "Fan-out sender queries by (user_id,
  notifications_enabled=true)" and the device-changed-hands semantics. **It has
  NO client write path today** (grep: only the generated `db_rows.dart`
  references it). Renamed/touched again in `20261217_001_f17_naming_uniformity.sql`;
  purge logic in `20260922_001_data_retention_purge_jobs.sql` (verify it already
  purges stale `device_tokens`).
- **The `web_push` kind — the exact pattern to copy:**
  - Migration `apps/backend/supabase/migrations/20261219_001_web_push_channel.sql`:
    adds `notifications.web_push_sent_at`, extends the `jobs_kind_chk` CHECK
    allowlist, the `enqueue_notification_web_push_job()` AFTER-INSERT trigger
    (one job per recipient **gated on subscription presence** to avoid no-op
    jobs), and the `clear_push_subscription` SECURITY DEFINER prune RPC.
  - Worker handler `apps/job_worker/internal/handler_web_push.go` — load the
    notification, gate on the `push_notifications` pref, load subscriptions,
    send, prune dead endpoints (404/410), defer on 429/5xx, stamp the
    `*_sent_at` guard on every terminal path EXCEPT "sender not configured"
    (leaves the row pending so a later credentialed deploy sends it).
  - Sender package `apps/job_worker/internal/webpush/` (RFC 8291/8292, stdlib +
    `golang-jwt`).
  - Worker plumbing: `apps/job_worker/internal/worker.go` — `WebPushSender`
    interface field (`WebPush`, nil disables), and the `dispatch()` switch
    (`case "web_push"` at worker.go:312).
  - Payload + sent-state types in `apps/job_worker/internal/types.go`
    (`WebPushPayload`, `WebPushSentAt`).
- **Preference:** `user_settings.prefs.push_notifications` (`all|important|off`,
  same shape as `email_notifications`, independent channel) — already the gate
  used by `web_push`; native push reuses the **same** pref (one "push" channel
  covers browser + native, per the docs). Toggle already exists on web
  `/settings/preferences` + mobile `settings_preferences_screen.dart`.
- **Docs:** `docs/features/email.md` — the "Native push (FCM / APNs)" bullet
  under "Planned / not built" explicitly states the design ("Same notifications
  source of truth + sibling-consumer pattern the web_push kind now demonstrates;
  an FCM/APNs sender is another sibling. Blocked on operator-supplied
  Firebase/APNs credentials + mobile firebase_messaging token registration.
  roadmap Phase 4b").
- **Mobile:** no `firebase_messaging` dependency in
  `apps/mobile_android/pubspec.yaml` yet; `packages/api_client` is the only
  Supabase entry point (no `device_tokens` method yet).

## Data model / migrations
One migration, mirroring `20261219_001` (use the next free `YYYYMMDD_NNN`, e.g.
`2027MMDD_001`; latest seen is `20270109_001`):

```sql
-- apps/backend/supabase/migrations/2027MMDD_001_native_push_channel.sql

-- 1. per-row send-state guard, sibling of web_push_sent_at / email_sent_at
alter table notifications add column native_push_sent_at timestamptz;

-- 2. extend the jobs.kind allowlist — FULL RESTATE of the legal set (dropping a
--    kind breaks an existing enqueue trigger insert: 23514 at INSERT time)
alter table public.jobs drop constraint jobs_kind_chk;
alter table public.jobs add constraint jobs_kind_chk check (
  kind in (
    'map_match','token_refresh','strava_event','photo_process',
    'notification_email','lifecycle_email','safety_email','web_push',
    'weekly_digest','native_push'
  )
);
-- (verify the live allowlist at write time — include EVERY kind currently in
--  worker.go dispatch + any migration since this plan was written.)

-- 3. enqueue trigger: notification → native_push job, gated on the recipient
--    having at least one device_tokens row (notifications_enabled = true).
--    Mirror enqueue_notification_web_push_job() exactly. Gating on token
--    presence avoids a no-op job per notification for the push-less majority.
create or replace function enqueue_notification_native_push_job()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (
    select 1 from device_tokens d
    where d.user_id = new.user_id and d.notifications_enabled = true
  ) then
    insert into jobs (kind, payload)
    values ('native_push', jsonb_build_object('notification_id', new.id));
  end if;
  return new;
end $$;
create trigger trg_notification_native_push
  after insert on notifications
  for each row execute function enqueue_notification_native_push_job();

-- 4. prune-dead-token RPC, sibling of clear_push_subscription. The FCM/APNs
--    "unregistered"/410 response means the token is dead — delete that row.
create or replace function clear_device_token(p_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from device_tokens where token = p_token;
end $$;
```

**RLS for the client write path:** `device_tokens` must allow a signed-in user
to upsert/select/delete **their own** rows. Verify whether the original
`20260506_001` already enabled RLS + owner policies; if not, add:

```sql
alter table device_tokens enable row level security;
create policy device_tokens_owner on device_tokens
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

**Codegen (two-regeneration rule, same commit as the migration):**
- `npm run gen:types --workspace=apps/backend` → `apps/web/src/lib/database.types.ts`
- `dart run scripts/gen_dart_models.dart` → `packages/core_models/lib/src/generated/db_rows.dart`
Both committed; CI `parity-types` enforces. `platform` is already a CHECK union;
the `IntegrationProvider`-style narrow-union TS overlay is optional here (clients
write `'ios'/'android'`, no client enum needed — note it, don't force it).

## Web implementation (canonical)
Native push is a **device-only capability** (physical-exception list, §24): a
browser cannot register an FCM/APNs token. So the **client** leg is mobile-only.
The **server** leg (worker) is shared infra, not a web UI. Web work is minimal:
- No new web UI — the `push_notifications` pref toggle already exists on
  `/settings/preferences`. (Confirm copy still reads as a single "Push" channel
  covering browser + phone; tweak `settings.*` i18n if it implied browser-only.)
- `docs/backend/settings.md` registry note: `push_notifications` now gates
  native push too (no new key).

## Worker implementation (Go — the credential-independent core)
Copy the `web_push` trio:
- **`apps/job_worker/internal/handler_native_push.go`** — `handleNativePush`:
  nil-`NativePush`-sender → log + return nil **without stamping** (rows stay
  pending for a later credentialed deploy); else load the notification
  (`FetchNotificationForNativePush`, add to the backend like
  `FetchNotificationForWebPush`), short-circuit if `native_push_sent_at` set,
  gate on `push_notifications` pref (reuse the same pref-resolution helper the
  web_push handler uses), load `device_tokens` for the user where
  `notifications_enabled = true`, send to each, prune dead tokens via
  `clear_device_token` (FCM `UNREGISTERED` / APNs 410), defer (return err) on
  transient 429/5xx, stamp `native_push_sent_at` on every terminal path except
  the nil-sender branch. Title/body come from the shared notification catalogue
  (same source `web_push`'s `push_render.go` uses — reuse it).
- **`apps/job_worker/internal/nativepush/`** — the sender package. Two
  transports behind one `NativePushSender` interface:
  - FCM HTTP v1 (`POST https://fcm.googleapis.com/v1/projects/<id>/messages:send`,
    OAuth2 bearer from the service-account JSON — reuse the existing
    `golang-jwt` like `webpush/` does, no heavy third-party Firebase Admin SDK
    unless the team prefers it; note the trade-off).
  - APNs HTTP/2 (`POST https://api.push.apple.com/3/device/<token>`, JWT `:path`
    auth with the `.p8` key). Android tokens → FCM; iOS tokens → APNs (route on
    `device_tokens.platform`). Decide: route iOS through FCM too (simpler, one
    transport) vs. direct APNs (no Google dependency for Apple) — open question.
- **`apps/job_worker/internal/worker.go`** — add a `NativePush NativePushSender`
  field (nil disables, mirroring `WebPush`), add `case "native_push":
  return w.handleNativePush(ctx, job)` to `dispatch()`.
- **`apps/job_worker/internal/types.go`** — `NativePushPayload {NotificationID}`
  + `NativePushSentAt` on the notification type.
- **Config gating (fail-closed):** the sender is constructed only when the
  operator sets the credentials (e.g. `FCM_SERVICE_ACCOUNT_JSON` / `FCM_PROJECT_ID`
  and/or `APNS_KEY_P8` / `APNS_KEY_ID` / `APNS_TEAM_ID` / `APNS_TOPIC`). Unset →
  `w.NativePush == nil` → jobs finish done, notification rows stay pending.
  Same posture as `web_push` (VAPID unset) and the email handler (SMTP unset).

## Mobile implementation (Android + iOS twin)
The device-led leg — token registration + foreground/background display:
- **Dependency:** add `firebase_messaging` (+ `firebase_core`) to
  `apps/mobile_android/pubspec.yaml` AND `apps/mobile_ios/pubspec.yaml`
  (twin: pubspecs differ only in `name`/`description` — every dep stays in
  lockstep). Android needs `google-services.json`, iOS needs
  `GoogleService-Info.plist` + the APNs entitlement — **these are operator
  artifacts; the code compiles without live values but won't deliver** (the
  credential gate; document as a deploy checklist item, do not stub the code).
- **`packages/api_client`** — add `registerDeviceToken({platform, token,
  appVersion, locale})` (upsert on `(user_id, token)`) +
  `setDeviceNotificationsEnabled(token, enabled)` + `removeDeviceToken(token)`.
  Route through api_client, not raw `Supabase.instance.client.from(...)`.
- **`apps/mobile_android/lib/push_messaging_bridge.dart`** (new top-level
  service, sibling of `wear_auth_bridge.dart` / `run_notification_bridge.dart`):
  - On sign-in (hook the same auth-state path `wear_auth_bridge` uses, wired in
    `main.dart`): request notification permission (Android 13+ runtime
    `POST_NOTIFICATIONS`, iOS APNs prompt), fetch the FCM token
    (`FirebaseMessaging.instance.getToken()`), call
    `ApiClient.registerDeviceToken(...)` with `platform = Platform.isIOS ? 'ios'
    : 'android'`. Listen to `onTokenRefresh` → re-register.
  - On sign-out: `removeDeviceToken` for the current token (so the next user on
    the device doesn't inherit pushes — matches the device-changed-hands DDL
    comment) and unsubscribe.
  - Foreground display + tap-to-deep-link (`onMessage` / `onMessageOpenedApp` →
    route to the notification's target, reusing the existing in-app
    notification-target routing; `/feed` deep links already exist per
    `apps/web/CLAUDE.md`). Wrap every platform-channel call in its own
    try/catch + `debugPrint` (L4 auxiliary-effect resilience — a push-init
    failure must never break sign-in or any core flow).
  - Gate the whole bridge on `firebase_messaging` being initialisable; if
    Firebase isn't configured (no `google-services.json`), `attach()` is a
    best-effort no-op (compiles + runs in dev without credentials).
  - Mirror byte-identical to `apps/mobile_ios/lib/push_messaging_bridge.dart`
    in the same commit; `Platform.isIOS`/`isAndroid` for any platform delta.
- **Native glue:** Android `FirebaseMessagingService` registration in the
  manifest + iOS `AppDelegate` APNs registration. These live outside `lib/`
  (`android/`, `ios/`) so they are *not* twin-shared — each app owns its native
  side. Operator supplies the Firebase config files.
- **Settings:** the `push_notifications` toggle already exists in
  `settings_preferences_screen.dart`; ensure it also drives
  `setDeviceNotificationsEnabled` on the local token (so the per-device DDL flag
  tracks the pref) — keep the universal `push_notifications` pref as the channel
  gate (worker-side) and `device_tokens.notifications_enabled` as the per-device
  fan-out filter.
- **Nav:** none — no new screen, no new tab (5-slot ceiling unaffected).

## TS↔Dart parity helpers
**None.** The push delivery is server-side Go + native platform SDKs; there is
no pure cross-platform logic to share as a TS↔Dart pair. The pref-resolution
logic lives in the worker (Go) and is exercised by `web_push` already. State
this explicitly so the implementer doesn't manufacture a pair.

## Tests (ship in the same commit as each piece)
- **pgtap (backend):** `apps/backend/supabase/tests/native_push_enqueue_test.sql`
  — inserting a `notifications` row enqueues a `native_push` job **only** when
  the recipient has an enabled `device_tokens` row; no token → no job (mirror
  the web_push enqueue test). Plus `device_tokens_rls_test.sql` — owner CRUD,
  non-owner denied, `clear_device_token` deletes by token.
- **Go (worker):** `apps/job_worker/internal/handler_native_push_test.go` —
  mirror `handler_web_push_test.go` / `handler_notification_email_test.go`:
  nil-sender leaves row pending (unstamped); opted-out stamps without sending;
  dead-token (410/UNREGISTERED) prunes + treated as handled; transient 5xx
  returns an error (retry); successful send stamps `native_push_sent_at`. Use a
  fake `NativePushSender` so no real FCM/APNs call is made.
- **Flutter (mobile, + iOS twin):** `apps/mobile_android/test/push_messaging_bridge_test.dart`
  — with a fake messaging seam: registers token on sign-in, re-registers on
  refresh, removes on sign-out, no-ops gracefully when Firebase is
  unconfigured. Mirror to `apps/mobile_ios/test/`.
- **No web e2e** — there is no web UI change beyond an existing toggle; mobile
  has no e2e by design (`docs/testing/testing.md § What's not covered`).

## i18n keys to add (all six web locales + all mobile ARBs)
- Push **titles/bodies are NOT new i18n** — they reuse the shared notification
  catalogue the bell + web_push already render (verify; reuse `push_render.go`).
- Mobile permission-rationale copy may need new ARB keys:
  `pushPermissionRationale`, `pushPermissionDenied` (a non-blocking explainer if
  the user declines). Add to all six ARBs, `flutter gen-l10n`, mirror gen to iOS
  twin.
- If the web `settings.pushNotifications*` strings imply browser-only, update
  copy across `apps/web/src/lib/i18n/locales/{en,de,fr,es,ja,pt-BR}.ts`.

## Docs to update
- `docs/features/email.md` — flip the "Native push (FCM/APNs)" bullet from
  `[ ]` to `[~]` (backend + client built, send gated on credentials); add the
  `native_push` kind to the architecture sibling list + the "Where the code
  lives" + "Production ops" sections (the new env vars).
- `docs/product/roadmap.md` — tick the Phase 4b push bullet to "built, gated".
- `docs/product/parity.md` — push row for android/ios.
- `docs/backend/settings.md` — note `push_notifications` covers native too.
- `docs/architecture/decisions.md` — one entry: "Native push is a third
  notifications-row consumer (`native_push` kind), fail-closed on operator
  FCM/APNs credentials, device_tokens fan-out gated on a per-device enabled
  flag" — sibling to the web_push ADR (§133).
- `apps/mobile_android/CLAUDE.md` + `apps/mobile_ios/CLAUDE.md` — add the new
  `push_messaging_bridge.dart` to the top-level `lib/` file list.

## Gating / compliance
- **Fail-closed on operator credentials.** All credential-independent code ships
  on `main`. The worker sender is nil until FCM service-account / APNs `.p8` env
  vars are set → jobs finish done, rows stay pending → a later credentialed
  deploy delivers the backlog. The mobile client compiles + runs without
  `google-services.json` / `GoogleService-Info.plist` (the bridge no-ops). This
  is the §150 pattern (genuine external-credential blocker for *going live*,
  write everything that doesn't need the secret now). **Not a paywall, not a
  CISO/counsel gate** — push of an already-consented notification is not
  privacy-sensitive new processing; the `push_notifications` pref + per-device
  flag are the user controls. Record the credential provisioning + APNs
  entitlement as a deploy-time checklist item in `email.md`'s "Production ops".

## Commit plan (ordered, path-scoped per-piece)
1. Migration + codegen + pgtap:
   `git commit -- apps/backend/supabase/migrations/2027MMDD_001_native_push_channel.sql apps/backend/supabase/tests/native_push_enqueue_test.sql apps/backend/supabase/tests/device_tokens_rls_test.sql apps/web/src/lib/database.types.ts packages/core_models/lib/src/generated/db_rows.dart`
2. Worker sender + handler + dispatch + Go tests:
   `git commit -- apps/job_worker/internal/handler_native_push.go apps/job_worker/internal/handler_native_push_test.go apps/job_worker/internal/nativepush/ apps/job_worker/internal/worker.go apps/job_worker/internal/types.go`
3. api_client device-token methods:
   `git commit -- packages/api_client/lib/...`
4. Mobile bridge + pubspec dep + tests + ARBs + gen (Android + iOS twin):
   `git commit -- apps/mobile_android/lib/push_messaging_bridge.dart apps/mobile_ios/lib/push_messaging_bridge.dart apps/mobile_android/lib/main.dart apps/mobile_ios/lib/main.dart apps/mobile_android/pubspec.yaml apps/mobile_ios/pubspec.yaml apps/mobile_android/lib/l10n/ apps/mobile_ios/lib/l10n/ apps/mobile_android/test/push_messaging_bridge_test.dart apps/mobile_ios/test/push_messaging_bridge_test.dart`
   (native `android/` + `ios/` glue can be a separate commit per app if it grows.)
5. Docs sweep:
   `git commit -- docs/features/email.md docs/product/roadmap.md docs/product/parity.md docs/backend/settings.md docs/architecture/decisions.md apps/mobile_android/CLAUDE.md apps/mobile_ios/CLAUDE.md`

## Open questions / decisions owed by the user
1. **Route iOS through FCM (one transport, depends on Firebase for Apple too) or
   direct APNs HTTP/2 (`.p8`, no Google dependency for Apple)?** Plan keeps both
   transports behind one interface; pick one to wire first.
2. **Firebase Admin Go SDK vs. hand-rolled FCM HTTP v1 + `golang-jwt`?** The
   web_push package chose stdlib + `golang-jwt` (no third-party). Recommend the
   same for consistency + smaller dep surface; confirm.
3. **One "Push" channel for browser + native (reuse `push_notifications`,
   recommended) vs. a separate `native_push_notifications` pref?** Plan reuses
   the existing pref. Confirm.
4. **Credentials** — who provisions the Firebase project + APNs key, and on what
   timeline? (This is the only thing blocking go-live.)

## Sequencing for the implementer
1. Write the migration mirroring `20261219_001` (verify the live `jobs_kind_chk`
   allowlist first), apply locally (`cd apps/backend && supabase migration up`),
   run **both** codegen commands, write the pgtap tests (commit 1).
2. Copy `handler_web_push.go` → `handler_native_push.go`; build
   `internal/nativepush/` (start with FCM HTTP v1); wire `worker.go` +
   `types.go`; write the Go handler test with a fake sender (commit 2).
3. Add the `device_tokens` CRUD methods to `packages/api_client` (commit 3).
4. Add `firebase_messaging` to both pubspecs; build `push_messaging_bridge.dart`
   (token register on sign-in, refresh, remove on sign-out, foreground display,
   L4-wrapped), wire into `main.dart`; mirror to iOS twin; ARBs + gen-l10n;
   Flutter test (commit 4). Operator adds the Firebase config files separately.
5. Docs sweep (commit 5). Run `/check` before each commit; run the
   `audit:twin-parity` + `audit:schema-drift` skills before declaring done.
