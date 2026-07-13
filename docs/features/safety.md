# Safety net — auto-live-share on start + overdue-runner escalation

> **STATUS: shipped (2026-07-06).** Built as specced against the
> `reviews/persona-woman.md` CRITICAL finding ("the two safety-contact surfaces
> either fire too late or don't fire at all — no real safety net exists despite
> the UI implying one"): backend scan + worker template (migration
> `20270401_001`, commit c1bc5f9c), settings + the mobile auto-live-share hook
> (31888fcb), surface convergence (209ba17b). ADR §207; parity row in
> parity.md. **Pre-prod checklist item outstanding:** CISO/counsel review of
> the overdue email copy + the consent posture below — the feature is
> fail-closed (both prefs default off) until users opt in, so shipping the
> code exposed no one. The "Open decisions" section records what was chosen
> and why so a future session can revisit deliberately.

## Context / why

The persona's most-wanted feature is *"auto-share a live link when I start,
and alert my partner if I'm not back."* Today:

- `safety_contacts` (migration `20261218_001`, ADR §131) emails confirmed
  contacts **only after a run saves** — a run that ends badly mid-way never
  INSERTs, so the one scenario the feature exists for sends nothing. Silence
  is indistinguishable between "she's fine" and "she never came home."
- The Settings → Account "Safety" card (`trusted_contacts` prefs key) is an
  inert scaffold nothing reads, under copy that implies overdue-run alerts
  exist. Two differently-shaped safety surfaces = conflation risk (the
  persona finding calls this out explicitly).

The safety net closes the loop: the phone starts a live broadcast
automatically on run start (opt-in), and the backend notices a live run that
has gone silent past the runner's chosen window and emails their confirmed
safety contacts a "may be overdue" alert with the live link — once.

## Reuse (don't re-implement)

- **Contacts + channel:** the `safety_contacts` table (double opt-in,
  email-identified, ADR §131) and the `safety_email` job kind (SMTP transport
  + six-locale catalogue in `apps/job_worker/internal/email_i18n.go`). The
  escalation is a third template (`overdue`) beside `confirm` / `finish` —
  same rationale as §131: NOT gated on the runner's `email_notifications`
  pref, recipient may be a non-user.
- **Live broadcast:** `ApiClient.beginLiveBroadcast` (pre-creates the
  `is_public=true` stub run with `metadata.in_progress=true`) +
  `LiveBroadcaster.attach` — the exact block `run_screen._shareLiveLink()`
  already runs manually. `_begin()` already reuses a pre-minted `_runId` when
  the user shared first, so the auto path slots in beside it.
- **Silence signal:** `live_run_pings` (newest `at` per run) with
  `started_at` as the floor for a broadcast that never landed a single ping.
  The 90 s `LIVE_STALE_AFTER_MS` in `live_freshness` is the *spectator*
  staleness bucket; the escalation threshold is minutes-scale and user-chosen
  — don't conflate them.
- **Scheduler:** pg_cron (migration `20260602_001` et seq.) — the
  `enqueue_event_reminders()` / `cleanup_stale_live_run_pings()` pattern: a
  SECURITY DEFINER SQL function scanning + inserting `jobs` rows, scheduled
  every 5 minutes.
- **All-clear:** the existing `finish` safety email (fires on run save
  regardless of `is_public`) is the recovery signal — no new template needed.

## Product decisions (taken 2026-07-06, revisit deliberately)

1. **`safety_contacts` is the single contact list.** The escalation targets
   confirmed `safety_contacts` rows only. The Account-card `trusted_contacts`
   scaffold (name/phone/relationship in a prefs bag, no opt-in, no reader) is
   **removed** and replaced with a link to `/settings/safety`; the settings
   key is marked deprecated in `settings.md`. Phone/SMS is not a channel we
   can deliver (no SMS provider in the stack), so persisting phone numbers
   under a "Safety" heading was liability without capability.
2. **Channel = email** (`safety_email` kind). Native push to contacts is a
   follow-up once `native_push` covers contact-recipients; SMS is out of
   scope (new sub-processor, new cost, Art-9-adjacent data to a new channel).
3. **Trigger = telemetry silence, not expected-duration.** A per-run "I'll be
   back by X" input adds start-flow friction the persona explicitly doesn't
   want (the point is that it's automatic). The runner sets a single
   universal threshold (`safety_overdue_minutes`); a live-broadcast run whose
   last ping (or start, if no ping ever landed) is older than the threshold
   AND that hasn't been saved is overdue. Trade-off: a long no-signal
   stretch (trail canyon) can false-positive — the email copy is calibrated
   for it ("this can also mean loss of phone signal") and the threshold is
   the runner's own choice (15 min minimum, 30/60/120 presets).
4. **Escalate once per run.** The scan stamps
   `runs.metadata.safety_escalated_at` and never re-fires. A rare duplicate
   beats a missed alert (§131's stance), but repeated alerts on the same
   silent run train contacts to ignore them. The saved-run finish email is
   the all-clear; if the run never finishes, one alert stands.
5. **Auto-live-share is a per-device pref, default OFF** (`auto_live_share`,
   D scope — a property of the phone that records, like
   `voice_feedback_enabled`). It makes every run publicly viewable mid-run (the stub is
   `is_public=true` — that's what makes the spectator link work for a
   logged-out partner), so it must be an explicit opt-in. The escalation
   applies to ANY live broadcast (auto or manually shared) — the overdue scan
   doesn't know or care how the broadcast started.
6. **Escalation is opt-in via the threshold** (`safety_overdue_minutes`,
   U scope, null = off). Fail-closed: no threshold → no scan match → no
   email, even with confirmed contacts. Both prefs surface on the safety
   settings screens next to the contacts they depend on.

## Design

### Mobile (auto-live-share on start)

`run_screen._begin()`: after the recorder starts and `_runId` is minted, when
`auto_live_share` is on and the user is signed in, run the same
`beginLiveBroadcast` + `_liveBroadcaster.attach(runId)` block as
`_shareLiveLink()` (minus the share sheet), wrapped in its own try/catch
(L4 — a failed share must never block the recording), and surface a
dismissible "Live sharing on — share link" affordance so the runner can send
the URL to whoever should watch. No web change (web doesn't record).

### Backend (overdue scan)

Migration `20270312_001_safety_overdue_escalation.sql`:

- `enqueue_safety_overdue_emails()` — SECURITY DEFINER, runs every 5 min via
  pg_cron. Matches runs where:
  - `metadata->>'in_progress' = 'true'` (live stub, never saved),
  - `started_at > now() - interval '24 hours'` (bound the scan; ancient
    stubs from crashed clients don't fire when a user sets the pref later),
  - `metadata->>'safety_escalated_at' is null` (once-only),
  - owner's `user_settings.prefs->>'safety_overdue_minutes'` is a number
    ≥ 10,
  - `greatest(started_at, max(live_run_pings.at))` is older than that many
    minutes,
  - owner has ≥ 1 confirmed safety contact.
  For each match: stamp `metadata.safety_escalated_at`, then insert one
  `safety_email` job per confirmed contact with payload
  `{template: 'overdue', run_id, owner_id, contact_email, contact_user_id,
  started_at, last_seen_at}`.
- pgtap: fires for a silent in-progress run past threshold; not for a saved
  run / under threshold / no pref / no confirmed contact / already stamped;
  stamps exactly once.

### Worker (email)

`handler_safety_email.go` grows the `overdue` template: subject "Is
{runner} OK? No movement since {time}", body carries started-at, last-seen
time (or "no position received"), the `/live/{run_id}` link, and the
loss-of-signal caveat. Copy in all six locales in `email_i18n.go`. No
coordinates in the email — the live page already applies privacy-zone
clipping; the email only carries times + the link.

### Settings surfaces

- Web `/settings/safety`: an "Overdue alert" section — enable + threshold
  select (15/30/60/120 min), copy explaining exactly when contacts are
  emailed. Gated visually on having ≥ 1 confirmed contact (the pref persists
  regardless; the scan requires contacts anyway).
- Mobile `settings_safety_screen.dart`: same section (universal pref via
  `SettingsSyncService.updateUniversal`), plus the `auto_live_share` device
  toggle ("Start a live share automatically when I start a run").
- Settings → Account "Safety" card (web) + `trusted_contacts_screen.dart`
  (mobile): replaced by a pointer to the real Safety settings; the
  `trusted_contacts.ts`/`.dart` helpers + tests deleted (nothing else reads
  them), the `trusted_contacts` key marked deprecated in
  [settings.md](../backend/settings.md).

## Consent / privacy posture (Art-9-adjacent)

- Live location of a named person flows to their contacts: **both sides have
  opted in** — the runner by enabling the pref(s), the contact by the
  existing double-opt-in confirm. No new consent surface needed.
- The auto-shared run is public-by-link mid-run (existing manual-share
  semantics, UUID-keyed URL, RLS-gated SELECT, privacy-zone clipping on
  pings both client- and server-side). The pref copy states this plainly.
- The escalation email contains times and a link only, never coordinates.
- Pre-prod deploy checklist (not a code gate): CISO/counsel review of the
  overdue email copy + this posture section. The feature is fail-closed
  (both prefs default off/null) so shipping the code does not expose anyone.

## Failure modes

- **Broadcast fails on start** (offline start): L4 — logged, recording
  unaffected; no stub → no escalation for that run. The runner sees the
  share affordance absent.
- **False positive** (signal loss / long café stop with auto-pause): one
  calibrated email, finish email follows as all-clear when the run saves.
- **Client crashes before save:** stub stays in-progress → escalation fires
  (this is the desired behaviour — it IS the "never came home" case, and
  also covers phone-destroyed scenarios).
- **pg_cron down / worker down:** existing stuck-job alerting
  (`20260731_001`) covers the queue; a missed scan window delays, not
  drops, the alert (the run still matches next tick).

## Commit cadence

1. Backend migration (scan fn + cron + pgtap) + `metadata.md` +
   `email.md` registry rows.
2. Go worker `overdue` template + i18n + test.
3. Settings prefs + web safety page section + `settings.md` rows.
4. Mobile: auto-live-share hook + safety-screen section + iOS twin + tests.
5. Surface convergence: remove the Account-card scaffold (web + mobile),
   delete `trusted_contacts` helpers/tests, deprecate the key.
6. Docs: roadmap, parity, decisions ADR, persona finding status.

## Open decisions (chosen; revisit deliberately)

- Threshold presets 15/30/60/120 min, floor 10 in SQL — arbitrary but sane;
  revisit with field data.
- No per-run expected-return input (friction); could be layered later as an
  optional override without changing the scan.
- No SMS / push channel yet; the payload shape (template + run_id + contact)
  is channel-agnostic so a `native_push` leg can reuse the scan.
- Escalation applies only to live-broadcast runs. A runner who records
  without any live share gets no safety net — the pings ARE the signal. The
  settings copy says this; auto-live-share existing is what makes it a
  reasonable contract. **Softened 2026-07-12 (decisions §235):** a new
  runner who never turned on `auto_live_share` and never shared a link
  used to get *silent* nothing — no prompt that they were recording
  unprotected. The solo-run safety nudge (below) surfaces that gap without
  turning the escalation into a duration-based net.

## Solo-run safety nudge (after-dark, no live share)

> **STATUS: shipped (2026-07-12).** Built against the `reviews/persona-runner-woman.md`
> HIGH finding ("off-route / no-live-share solo runs have no safety net at
> all — the settings copy doesn't make the gap explicit enough"). Decisions §235.

The escalation net above only watches *live-broadcast* runs. The persona's
stated habit is to share a live link for every solo evening run — but a
runner who hasn't enabled `auto_live_share` (default off) and doesn't tap
"Share live link" gets no net and, worse, no signal that they're
unprotected. This closes that gap with a **one-time, throttled, dismissible
contextual nudge** at run start — no start-flow friction, no new blocking
step.

- **Trigger (pure, twinned).** `shouldNudgeSoloSafety` in
  `apps/web/src/lib/safety/safety_nudge.ts` ↔ `apps/mobile_android/lib/safety_nudge.dart`
  (TS↔Dart parity pair, 14 mirror tests each) returns true only when the
  run is genuinely unprotected AND after dark AND not throttled:
  `autoLiveShareOn` off, `isBroadcast` false (no manual share before GO),
  `nudgeDismissed` false, and `isNightWindow(nowLocalMinutes)` true. Night
  is a **fixed 20:00–06:00 local window** (`isNightWindow`), deliberately
  *not* astronomical sunrise/sunset — no new astronomy dependency,
  deterministic, and erring toward nudging slightly early in summer is
  harmless where silently missing a dark run is not. Every guard is
  fail-closed (any suppressor wins), so a covered runner is never prompted.
- **Throttle.** `nudgeThrottled(dismissedAtMs, nowMs)` suppresses the nudge
  for `safetyNudgeThrottleMs` (30 days) after it's surfaced. The device
  pref `safety_nudge_dismissed_at` (D scope, ISO-8601, [settings.md](../backend/settings.md))
  is stamped the moment the banner shows — the banner is transient and
  dismissible, so "surfaced once" is the throttle anchor. A failed
  stamp-write just risks re-surfacing next run (the safe direction).
- **Surface (mobile-only, L4).** `run_screen._maybeShowSafetyNudge()` runs
  inside `_attachRecordingSideEffects` right after the auto-live-share
  block — the complement of that path. It gathers the inputs, and on a
  positive decision shows a top banner ("Running solo after dark? Share a
  live link so someone can follow along.") whose action shares the current
  run's live link (`_shareLiveLink`, one-off — it does NOT flip the
  public-by-default `auto_live_share` pref). The whole method is wrapped in
  its own try/catch + `debugPrint`: a failure computing daylight or reading
  prefs must never touch the recording (L0–L1). Recording is mobile-only,
  so there is no web surface — the decision helper is the twinned canonical
  logic (decisions §24), the banner is the platform-additive surface.
- **Sign-in.** Gated on a settings service being available (so the throttle
  can persist) — without one the nudge would nag every run, which is the
  friction the persona explicitly doesn't want. Fail-closed: no service →
  no nudge.
- **Deferred:** an off-route → auto-notify-contact tie-in stays out of
  scope (no off-route-detection hook exists yet; named in the persona
  finding's Medium bucket). The nudge is the low-friction first step; a
  future off-route signal could reuse the same banner path.
