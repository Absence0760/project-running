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
   `voice_feedback_interval_km`). It makes every run publicly viewable mid-run (the stub is
   `is_public=true` — that's what makes the spectator link work for a
   logged-out partner), so it must be an explicit opt-in. The escalation
   applies to ANY live broadcast (auto or manually shared) — the overdue scan
   doesn't know or care how the broadcast started. **The public flip is
   scoped to the live window** (issue #664, decisions §434): on stop the
   saved run follows the runner's default visibility, and keeping it
   public is an explicit post-stop choice — the stop path never silently
   leaves a safety share `is_public=true`.
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
(L4 — a failed share must never block the recording). While any broadcast is
active — auto or manually shared — the recording chrome carries the persistent
**`LiveShareIndicator`** pill (issue #613): a standing "Live" chip in the
top-left, driven by the `_liveShareActive` `ValueNotifier`. Tapping it opens
`showLiveShareSheet` with "Share link again" and "Stop sharing" — stop
concludes the broadcast mid-run (`concludeLiveBroadcast`) without ending the
run, so the share persists until the run finishes. The `concluded_at` stamp is
*owed* until it lands (`_liveConcludeOwed`), not until the broadcaster is torn
down: stopping the share while out of signal detaches the pump anyway, so the
finish path retries the stamp rather than leaving spectators on a frozen live
trace with no conclusion. **On finish** the stop
path resolves the saved run's visibility (`_resolvePostLiveVisibility`,
issue #664): with a not-public default it asks — an `AlertDialog` where
"Keep public" is the explicit act and decline/dismiss fails closed to
`makeRunPrivate`; a share the runner already stopped mid-run reverts
quietly (that also clears the `is_public=true` stub when the cloud save
failed). A `public` privacy default needs no dialog. No web change (web
doesn't record).

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
- **The contact list is owner-scoped by the client, not by RLS** (ADR §720).
  `safety_contacts` carries four permissive policies — the owner pair
  (`owner_id = auth.uid()`) and a linked-contact pair
  (`contact_user_id = auth.uid()`, `20261218_001`) — and permissive policies
  OR, so an unfiltered read returns the union: your contacts plus every
  relationship someone else added you to and you confirmed. Both
  `fetchMySafetyContacts` (web `core/data.ts`, Dart `api_client.dart`) and
  `removeSafetyContact` therefore carry an explicit `owner_id` filter and
  refuse when signed out. Do not remove it, and do not "simplify" it away on
  the grounds that RLS covers it: the delete leg is permissive too, so an
  id-only delete reaches a row you merely appear on and destroys the other
  person's emergency contact. Withdrawing from a relationship you are the
  contact *of* is `declineSafetyRequest` / `decline_safety_contact`. Pinned by
  source guards on both clients plus four assertions in
  `apps/backend/supabase/tests/safety_contacts_test.sql`.
- Settings → Account "Safety" card (web) + `trusted_contacts_screen.dart`
  (mobile): replaced by a pointer to the real Safety settings; the
  `trusted_contacts.ts`/`.dart` helpers + tests deleted (nothing else reads
  them), the `trusted_contacts` key marked deprecated in
  [settings.md](../backend/settings.md).

## Consent / privacy posture (Art-9-adjacent)

- Live location of a named person flows to their contacts: **both sides have
  opted in** — the runner by enabling the pref(s), the contact by the
  existing double-opt-in confirm. No new consent surface needed.
- The auto-shared run is public-by-link mid-run **and only mid-run**
  (existing manual-share semantics, UUID-keyed URL, RLS-gated SELECT,
  privacy-zone clipping on pings both client- and server-side); on stop
  the run returns to the runner's default visibility unless they
  explicitly keep it public (issue #664, decisions §434). The pref copy
  states both plainly.
- The escalation email contains times and a link only, never coordinates.
- Pre-prod deploy checklist (not a code gate): CISO/counsel review of the
  overdue email copy + this posture section. The feature is fail-closed
  (both prefs default off/null) so shipping the code does not expose anyone.

## Failure modes

- **Broadcast fails on start** (offline start): L4 — logged, recording
  unaffected; no stub → no escalation for that run. The runner sees the
  live indicator absent.
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

## SMS escalation + per-run expected-return (feature C, 2026-07-13, ADR §240)

Layered on the email net above; migration `20270410_001`. Reuses the
channel-agnostic scan rather than forking it.

- **Phone + second opt-in.** `safety_contacts.contact_phone` (nullable E.164,
  CHECK `^\+[1-9][0-9]{6,14}$`) is **owner-stored**; `safety_contacts.sms_opt_in_at`
  is a **separate consent the contact controls**. `confirm_safety_contact` /
  `confirm_safety_contact_by_token` gained a defaulted `p_sms_opt_in` that only
  stamps the opt-in when a phone is on file (forced null otherwise, so the anon
  token page can always show the box); `set_safety_sms_opt_in(p_id, p_opt_in)`
  toggles it later.
- **Additive, never suppressive.** The scan enqueues a `safety_sms` job **only**
  for a confirmed contact with `sms_opt_in_at` set. Email stays unconditional —
  a disabled/failed SMS leg can't stop the email.
- **Fail-closed transport.** The Go worker's `smsSender` stays nil unless
  `SMS_PROVIDER=twilio` **and** `TWILIO_ACCOUNT_SID`/`TWILIO_AUTH_TOKEN`/`TWILIO_FROM`
  are all set; the handler no-ops (logs + returns success) when nil. Acquiring
  the Twilio account is a pre-deploy checklist item, not a code gate.
- **Per-run "not back by X".** `set_run_expected_return(p_run_id, p_expected_return_at)`
  writes/clears `runs.metadata.expected_return_at` on an owned in-progress run
  (metadata.md) — an absolute deadline layered over the silence-window pref.
- **Web surfaces.** Optional phone on the `/settings/safety` add form
  (client-validated against the same CHECK) + an "SMS on" badge + the
  contact-side opt-in checkbox on inbound requests; the `/safety/confirm` token
  page now prompts-then-confirms (with the opt-in) rather than auto-confirming;
  an owner-only "Not back by X" control on `/live/[id]` (web can't record, so
  the owner's own live spectator view is the only in-progress-run surface).
- **Mobile surfaces (2026-08-24, ADR §719).** Settings → Safety contacts
  takes the optional number and offers the confirm-time opt-in on an inbound
  request that carries `has_phone`. Two things differ from web deliberately:
  the number is repaired through the shared `e164` parity pair before it is
  graded (a pasted `+44 (0) 7700 900123` is a valid number that is merely
  punctuated — and the parenthesised trunk zero is DELETED, because stripping
  only its brackets yields `+4407700900123`, a different conforming number
  whose alert reaches nobody), and the contact row renders three states
  rather than two: SMS on, **a number on file with no contact opt-in**, or
  nothing. Web shows only the first, so an owner who typed a number the
  contact never consented to sees silence and reads it as working. The
  per-run "not back by X" ladder hangs off the live-share sheet — recording
  is mobile-only, and the RPC needs a server-side in-progress run row, which
  only a live broadcast creates.
- **What the phone cannot disarm — and what that costs.** The deadline is
  written to the run row and read by the cron scan, so killing the app,
  flattening the battery or destroying the handset all leave the alert
  standing. That is the feature. Its cost is the other direction: a run that
  FINISHES out of signal is queued locally, the server row stays
  `in_progress`, and the scan escalates a runner who is already home. This is
  the pre-existing false-positive posture of the whole overdue net (the
  runner's confirmed contacts get one email that says signal loss is a
  possible cause), sharpened by an absolute deadline; the mobile dialog says
  so outright rather than leaving a runner to discover it. A successful save
  upserts the whole metadata bag and takes both `in_progress` and
  `expected_return_at` with it, so an online finish cannot false-fire.
- **Still deferred.** Neither platform can change an SMS consent AFTER
  confirming: `set_safety_sms_opt_in` exists and works, but no surface lists
  the relationships a user is the *contact* of, so nothing can call it. The
  native-push leg still waits on FCM/APNs.

## Open decisions (chosen; revisit deliberately)

- Threshold presets 15/30/60/120 min, floor 10 in SQL — arbitrary but sane;
  revisit with field data.
- ~~No per-run expected-return input~~ — **shipped** as an optional override
  (`set_run_expected_return`, feature C / ADR §240); the scan is unchanged.
- ~~No SMS / push channel yet~~ — **SMS shipped** (feature C / ADR §240, the
  `safety_sms` kind + fail-closed Twilio transport); the payload shape stays
  channel-agnostic so a `native_push` leg can still reuse the scan.
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

- **Trigger (pure, twinned).** `shouldSurfaceSoloSafetyNudge` in
  `apps/web/src/lib/safety/safety_nudge.ts` ↔ `apps/mobile_android/lib/safety_nudge.dart`
  (TS↔Dart parity pair, 30 mirror tests each) returns true only when the
  run is genuinely unprotected AND after dark AND not throttled. It folds
  the throttle composition over `shouldNudgeSoloSafety`'s guards:
  `autoLiveShareOn` off, `isBroadcast` false (no manual share before GO),
  `nudgeThrottled(lastActedAtMs, nowMs)` false, and
  `isDarkOutside(nowLocalMinutes, latitude, dayOfYear)` true. The
  consolidated helper takes an explicit `lastActedAtMs` so a caller can't
  re-introduce the "throttle from shown, not from acted-on" bug by feeding
  a shown-at timestamp (issue #264). "Dark" is the **fixed 20:00–06:00
  local window** (`isNightWindow`, the deterministic floor) **OR** a
  **seasonal sunrise/sunset test** (`isSunDown`) when the runner's latitude
  + day-of-year are known — the latter catches genuinely-dark pre-dawn
  winter runs at higher latitudes (e.g. a 06:30 December run at 60°N,
  sunrise ~09:00), which the old fixed-only window silently missed (issue
  #265). `isSunDown` derives sunrise/sunset from the solar declination +
  latitude, assuming solar noon at local 12:00; it deliberately ignores
  longitude-within-timezone / equation-of-time / DST (~1 h of clock error)
  because it only ever ADDS darkness on top of the fixed floor, so the
  window widens, never narrows, and no run that nudged before stops
  nudging. Polar day → never dark, polar night → always dark. A null
  `latitude`/`dayOfYear` (no GPS fix yet) degrades to exactly the fixed
  window. Still no astronomy dependency (a few lines of trig), and erring
  toward nudging slightly early is harmless where silently missing a dark
  run is not. Every guard is fail-closed (any suppressor wins), so a
  covered runner is never prompted.
- **Throttle.** `nudgeThrottled(actedAtMs, nowMs)` suppresses the nudge
  for `safetyNudgeThrottleMs` (30 days) after the runner **acts on** it.
  The device pref `safety_nudge_dismissed_at` (D scope, ISO-8601,
  [settings.md](../backend/settings.md)) is stamped only when the runner
  shares or dismisses — **not** when the banner merely shows. A nudge a
  runner never engaged with (issue #264: a 6-second banner they missed) is
  therefore never suppressed; it resurfaces next dark solo run. A failed
  stamp-write just risks re-surfacing next run (the safe direction).
- **Surface (mobile-only, L4).** `run_screen._maybeShowSafetyNudge()` runs
  inside `_attachRecordingSideEffects` right after the auto-live-share
  block — the complement of that path. On a positive decision it flips a
  screen-held flag that renders a **persistent, dismissible**
  `SafetyNudgeBanner` (`widgets/safety_nudge_banner.dart`) in the recording
  chrome, a sibling of the off-route / GPS banners — replacing the earlier
  6-second auto-dismissing top banner that was easy to miss (issue #264).
  The banner stays until the runner acts: **Share** shares the current
  run's live link (`_onSafetyNudgeShare` → `_shareLiveLink`, one-off — it
  does NOT flip the public-by-default `auto_live_share` pref); **Not now**
  (`_dismissSafetyNudge`) dismisses it. Both stamp the throttle. The whole
  gather-and-flip method is wrapped in its own try/catch + `debugPrint`: a
  failure computing daylight or reading prefs must never touch the
  recording (L0–L1). Recording is mobile-only, so there is no web
  surface — the decision helper is the twinned canonical logic
  (decisions §24), the banner is the platform-additive surface.
- **Sign-in.** Gated on a settings service being available (so the throttle
  can persist) — without one the nudge would nag every run, which is the
  friction the persona explicitly doesn't want. Fail-closed: no service →
  no nudge.
- ~~**Deferred:** an off-route → auto-notify-contact tie-in stays out of
  scope (no off-route-detection hook exists yet).~~ — **shipped** (feature D,
  below): a debounced off-route detector on the run screen escalates a
  sustained departure to confirmed contacts via the existing notify path,
  gated on a fail-closed deploy flag.

## Stopped-runner readout on the spectator page (2026-08-15, ADR §621)

> **STATUS: shipped web.** The spectator half of the safety story, complementing
> the staleness work in `live_freshness`.

`live_freshness` answers *"can we see them at all"* and `/live/[id]` is
scrupulous about it — a lost-signal runner reads DELAYED, never LIVE. The
complementary question had no answer anywhere on the surface: a runner whose
phone is still pinging every few seconds from the same spot rendered as a
fresh green LIVE dot, and the one derived stat that would have exposed it (the
Recent-pace tile) computes a zero distance delta, returned `null`, and
*disappeared*. Silence about "not moving" and silence about "no data yet"
looked identical — and the more alarming of the two was the one that vanished.
For the canyon-collapse (`ws100-spectator`), night-section (`moab240-spectator`)
and alpine (`utmb-sweep-medical-sar`) cases this is the distinction that
matters most.

- **Decision (pure, web-only).** `motionFor` in
  `apps/web/src/lib/safety/live_motion.ts` grades a window of recent pings into
  `moving` / `stopped` / `unknown`. Constants: `MOTION_MIN_WINDOW_MS` (180 s —
  the minimum observation before any claim, past every ordinary pause a moving
  runner takes), `MOTION_STOPPED_DISTANCE_M` (25 m — enough to absorb an
  accumulating GPS random walk over minutes, not just one fix's error), and
  `MOTION_MAX_GAP_MS` (30 s — the longest hole in the telemetry the window may
  span. No gap length is perfectly safe: at a slow jog a runner clears the
  25 m radius and returns in about twenty seconds, so this is a **proportion,
  not a guarantee** — six missed pings at the ~5 s broadcast cadence absorbs
  ordinary cellular flakiness while keeping any tolerated hole to at most a
  sixth of the shortest claim the helper will make, a ratio a unit test pins).
- **Fail-closed in three directions.** A **stale** fix yields `unknown`: the
  last position being old is exactly the case where "they have not moved" is
  unknowable, and reporting a stationary runner off pre-dropout pings would be
  the same lie in a new place. A **gap** inside the buffer yields `unknown`
  too, for that reason arriving through a different door — a claim about a
  runner staying put is a claim about every moment in between, and an outage is
  precisely where they could have left and come back, so only the contiguous
  run of pings ending at the newest one is evidence and everything before a
  longer gap is discarded rather than vouched for. (Without this, a spectator
  whose runner dropped out in a canyon and re-acquired near the same spot an
  hour later would have been told "not moving for at least 60 min" about an
  hour nobody observed.) And too short a window yields `unknown` — a five-ping
  buffer at a 5 s cadence spans twenty seconds, and every runner alive stands
  still for twenty seconds at a road crossing. A rewound odometer (a re-armed
  recorder) is read as absolute ground covered, so it cannot manufacture a
  stopped verdict either.
- **Neutral, not an alarm.** A runner stopped for six minutes is at an aid
  station; one stopped for ninety is a question for their crew. The chip states
  the fact and the duration in the body text colour and draws no conclusion.
  When the stop fills the whole held buffer the duration is a **floor**
  (`atLeast`) and the copy says "at least N min" rather than stating a figure
  the data does not support.
- **Recent pace under staleness.** The Recent tile kept its confident present-
  tense label on a fix the cut-off card had already refused to project from.
  It now relabels to "When last seen" when `isStale` — the number is a real
  fact about the last sighting and is worth keeping, but not under a label that
  reads as current.
- **Surface.** `/live/[id]` on web, `live_spectator_screen.dart` on mobile. No
  new data reaches an anonymous viewer: the readout is derived from the
  `distance_m` + `at` fields both surfaces already render as the trace and the
  stat strip, and the position itself still comes through the existing
  privacy-zone clipping. Pinned by `apps/web/tests-e2e/live/motion.spec.ts` (4)
  + 18 unit tests web, 18 mirror unit tests + 4 widget tests on mobile.
- **Registered parity pair** (`safety/live_motion.ts` ↔ `live_motion.dart`).
  The mobile buffer is stamped from each ping's own `at` clock, never the
  device's, so a backlog replayed on hydrate cannot land as a burst of "now"
  and collapse an hour of history into a few seconds. The Dart `atMs` is an
  `int` epoch-ms rather than web's `number`, so the non-finite guard covers
  only the odometer on that side — an idiomatic shape difference, not a
  divergence.

## Off-route → auto-notify trusted contact (feature D, 2026-07-13, ADR §241)

> **STATUS: code shipped, prod-gated.** Built against the
> `reviews/persona-runner-woman.md` Medium finding (the off-route leg of the
> "solo-run safety" cluster). The other two legs already shipped: per-run
> "not back by X" (`set_run_expected_return`) + SMS escalation (feature C).
> **Fail-closed and unreachable in prod** until the `OFF_ROUTE_ESCALATION_ENABLED`
> deploy flag flips — the pre-prod checklist item below is the gate.

The overdue net watches for telemetry *silence*; this is the complementary
trigger for a runner who is still moving and still pinging but has left — and
stayed off — their planned route on a live-shared run.

- **Detection (client-side, twinned).** Only the recording run screen knows the
  runner's off-route distance vs the planned route. `OffRouteAlertDetector`
  (`apps/web/src/lib/safety/off_route_alert.ts` ↔
  `apps/mobile_android/lib/off_route_alert.dart`, TS↔Dart parity pair, 10
  mirror tests each) is a pure debounce: it fires ONCE when the runner has been
  continuously > 75 m off route for ≥ 90 s (a single GPS spike or brief
  corner-cut dips under the threshold and resets the clock; larger than the
  40 m off-route *banner* threshold so it's a genuine departure, not a wobble),
  and latches for the run's lifetime (the escalation is once-per-run).
- **Escalation reuses the notify path.** On fire, the run screen calls
  `escalate_run_off_route(p_run_id)` (migration `20270414_001`) — a
  SECURITY DEFINER RPC that enqueues the SAME `safety_email` (+ additive
  `safety_sms`) jobs the overdue scan uses, with a distinct `off_route`
  template, and shares the once-per-run `metadata.safety_escalated_at` stamp
  so a runner gets ONE alert per run whichever trigger fires first. Times +
  the live link only, never coordinates.
- **Fail-closed, defence in depth.** The client only calls the RPC when the
  `OFF_ROUTE_ESCALATION_ENABLED` deploy flag is on (`off_route_flag.ts` /
  `dotenv`, default off), the runner opted into `safety_off_route_alerts` (U
  pref, default off), a route is selected, AND a live broadcast is active (so
  the `/live` link the contact receives works). **All four are checked BEFORE
  the detector is fed**, not after it decides: `OffRouteAlertDetector.update`
  latches once per run at the moment it returns true, so a deliverability
  check downstream of the call would spend the runner's single escalation on
  an episode nobody could be told about — leaving a silently-dead safety net
  for the rest of the run. Practical consequence: the 90 s sustain clock only
  accrues while an escalation is deliverable, so a runner who starts sharing
  mid-departure waits another full window. The RPC re-checks every gate
  server-side: owner-only, in-progress-stub-only, the opt-in pref, ≥1 confirmed
  contact, and the atomic once-per-run stamp (a concurrent double-tap no-ops).
  The SMS leg additionally needs the (default-unset) Twilio provider.
- **Surfaces.** Mobile: a `safety_off_route_alerts` toggle on Settings → Safety
  contacts (hidden until the flag flips) + a run-screen banner on escalation.
  Web: the same opt-in toggle on `/settings/safety` (web can't record, so no
  trigger there). Copy localized across six web locales + all mobile ARBs.
- **Pre-prod deploy checklist (not a code gate):** CISO/counsel review of the
  `off_route` email/SMS copy + this posture, then set
  `OFF_ROUTE_ESCALATION_ENABLED` on the web build + mobile dotenv. The feature
  is fail-closed (flag off, pref off) so shipping the code exposes no one.
