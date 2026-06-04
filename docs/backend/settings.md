# Settings registry

Two jsonb bags drive every user preference in the app:

- **`user_settings.prefs`** — one row per user. Universal settings that should
  follow the user across every device they sign into. Edited from the web and
  mobile settings screens.
- **`user_device_settings.prefs`** — one row per (user, device). Per-device
  overrides of universal settings, plus settings that only make sense on one
  device. Edited from the per-device settings screen.

**Effective value lookup**: device override → universal → client default.
Absent keys fall through; explicit `null` is treated as "unset" and also
falls through. Clients that want "device explicitly opts out of the
universal value" must use a sentinel like `"off"` rather than `null`.

The DB stores an opaque jsonb bag. This file is the registry of known
keys. Adding a new key is a client change + an entry below — no migration.

## Placement rule — bag vs column (F4)

When you add a **user preference**, decide where it lives before reaching for
this registry:

1. **A `prefs` bag key (here)** — the default for a preference. Use it when the
   value is read by *clients* to shape the UI / behaviour and is **never
   filtered, joined, or aggregated in SQL**. No migration, no type regen — just
   a row in the table below and a client default. Almost every preference is
   this.
2. **A real column on a domain table** (`user_profiles`, `runs`, …) — only when
   the value must be queried server-side: a `WHERE` / `ORDER BY` / `GROUP BY`,
   a `CHECK`, an index, or a read by a view / RPC / trigger / RLS policy. This
   is the same bar the [activity-table column checklist](../architecture/conventions.md#activity-table-column-checklist--column-vs-jsonb-bag-f6--decision-d4)
   applies to activity attributes. A column costs a migration + both type
   regens, so only pay it when SQL genuinely needs the value. (`preferred_unit`
   is the live example of the migrate-away-from-a-column direction — it began
   as `profiles.preferred_unit`, is dual-read today, and the column is slated to
   drop once every client prefers the bag.)

Then, **within the bag**, pick the scope (U / D / UD below): default to `UD`,
but ask whether a per-device override is actually meaningful — if it isn't,
make it `U`. A pref that only makes sense on one physical device is `D`.

## Scope shorthand

| Symbol | Meaning |
|---|---|
| U | Universal-only. Stored on `user_settings`; per-device overrides ignored. |
| D | Device-only. Stored on `user_device_settings`; never overlaid from universal. |
| UD | Overridable. Written to `user_settings` by default; a device may override. |

## Keys

| Key | Type | Scope | Default | Description |
|---|---|---|---|---|
| `preferred_unit` | `'km' \| 'mi'` | UD | `km` | Distance unit for all displays. Mirrors `profiles.preferred_unit` today; migrate away from the column in a follow-up. |
| `default_activity_type` | `'run' \| 'walk' \| 'hike' \| 'cycle'` | UD | `run` | Pre-selected activity on the watch/phone start screen. |
| `hr_zones` | `{ z1: int, z2: int, z3: int, z4: int, z5: int }` | U | — | HR zone upper bounds in bpm. Used by training plan pace derivation + post-run zone split. |
| `resting_hr_bpm` | `int` | U | — | Resting heart rate. Feeds VDOT estimate if a recent race isn't available. |
| `max_hr_bpm` | `int` | U | — | Max heart rate override. If absent, we fall back to Tanaka `208 − 0.7 × age` (from `date_of_birth`), then a 190-bpm default. See `apps/web/src/lib/training/hr_zones.ts` / `apps/mobile_android/lib/hr_zones.dart`. |
| `date_of_birth` | `YYYY-MM-DD` | U | — | Used for age-based HR max + age-grade calculation. Also gates name-search discoverability: a declared minor (under 18) is hard-excluded from `search_user_profiles` regardless of `discoverable_in_search` (migration `20261017_001`, reading the canonical `user_profiles.date_of_birth` column per `20261104_001`). The discoverability floor only fires when a DOB exists, so the canonical column write must NOT be Art 9-consent-gated — `/onboarding` writes `user_profiles.date_of_birth` whenever the user supplies it (consent gates only the prefs-bag mirror + the leaderboard/HR *use*), per persona round-5 family-club. **Carry-over:** `/settings/preferences` still null-writes the column without consent, so a minor who only ever set DOB there + declined consent stays NULL-DOB → discoverable; align that surface with onboarding when next touched. |
| `privacy_default` | `'public' \| 'followers' \| 'private'` | U | `followers` (unset fallback) / `private` (wizard pre-selection) | Default visibility of new runs; per-run override still wins. The onboarding wizard pre-selects `private`; honoured on every run-creation + import path, failing closed to private. Full behaviour in [§ privacy_default detail](#privacy_default-detail). |
| `strava_auto_share` | `bool` | U | `false` | Auto-push every new run to Strava (requires connected integration). |
| `email_notifications` | `'all' \| 'important' \| 'off'` | U | `important` | Which notification kinds are delivered by email. `important` (default) emails event reminders/cancellations, coach plan updates, and direct messages; `all` adds the social loop (kudos, comments, follows, club posts, run-completed); `off` suppresses every email. The in-app bell is unaffected — this gates only the email channel. Read server-side by the Go worker's `notification_email` handler (migration `20261130_001`); the `List-Unsubscribe` header + email footer both link to `/settings/preferences`. Unknown/non-string values fall back to `important` (fail toward the smaller set). Editable in web Settings → Preferences (`/settings/preferences`, "Notifications" card) and mobile Settings → Preferences ("Notifications" section), both i18n'd across all six locales. |
| `locale` | BCP-47 tag (`en` \| `de` \| `fr` \| `es` \| `ja` \| `pt-BR`) | U | — (clients write the active UI locale) | The user's preferred language for **server-sent communications** (email). Web + mobile write the active UI locale into the universal bag so the Go worker can localize emails — see `decisions.md § 120`. **Distinct** from the per-device UI locale that governs what the app shows on a given device (mobile `Preferences.locale`; web client-side detection — `decisions.md § 113`); this key exists only because the server can't read those. The email renderer normalizes unknown/region tags to the six supported locales and falls back to English. Not a per-control toggle — it's written as a side effect of the existing language picker. |
| `discoverable_in_search` | `bool` | U | `true` | When `false`, this user is excluded from People-tab name search (`search_user_profiles` RPC — migration `20261015_001`). The user remains reachable by direct profile URL and via share-page unfurls; this only gates name-string discovery. Persona-hunt Round 3 finding Woman #2. A declared minor (`date_of_birth` under 18) is excluded regardless of this pref — migration `20261017_001`, Round 4 finding family-club #1. |
| `trusted_contacts` | `TrustedContact[]` | U | `[]` | Array of `{ name, phone?, email?, relationship? }` rows (max 5). Scaffold for the planned overdue-run / panic-button surface — no delivery logic ships with this key. Pure shape lives in `apps/web/src/lib/social/trusted_contacts.ts` ↔ `apps/mobile_android/lib/trusted_contacts.dart`. Persona-hunt Round 3 finding Woman #4. |
| `primary_goal` | `'general_fitness' \| 'weight_loss' \| '5k' \| '10k' \| 'half_marathon' \| 'marathon'` | U | — | Set by the post-signup `/onboarding` wizard (step 3). Drives the planned post-onboarding plan suggestion ("create a 10K plan?"). Distance values map 1:1 to `training.ts#GoalEvent`. See `docs/architecture/decisions.md § 78`. |
| `coach_personality` | `'supportive' \| 'drill_sergeant' \| 'analytical'` | U | `supportive` | Tone preset for the Claude coach chat. |
| `multi_modal_nav` | `bool` | U | `false` | Phase 4 multi-modal feature flag (decisions §63, [multi_modal.md](../features/multi_modal.md)). When `true`, the web surfaces light up their gym slices (gym routes stay reachable by URL regardless — the flag gates the affordances, not the data, so a pure runner's app is unchanged): the **Gym** sidebar item (`+layout.svelte`); the self-hiding Today's-lift + Recent-lifts cards AND the lift→load contribution to the fitness/fatigue/form curve on `/dashboard`; and the All/Runs/Lifts/Meals kind chips + unified `activities` timeline on `/runs`. Each is *also* gated on data presence, so a flagged-but-empty user still sees no clutter. Read in each surface via `effective<boolean>(…, 'multi_modal_nav', false)`. Mobile nav reshape (Run → Log action) keys off the same flag when it lands. No UI toggle ships yet (set it directly in the prefs bag); a Settings switch is still pending. |
| `voice_feedback_enabled` | `bool` | D | `false` | Speak pace/distance callouts during a run. Device-scoped because mic/speaker availability differs. |
| `voice_feedback_verbosity` | `string` | U | `full` | `full` speaks every cue; `minimal` suppresses the chatty in-rep progress + pace-drift nudges. Universal so the choice roams across devices. |
| `voice_feedback_interval_km` | `double` | D | `1.0` | Interval in km between spoken callouts. |
| `haptic_feedback_enabled` | `bool` | D | `true` | Vibration on lap + pace-zone changes. Watches only. |
| `keep_screen_on` | `bool` | D | `true` | Disable OS auto-dim while the running screen is visible. Phones only; watches use ambient mode. |
| `map_style` | `'streets' \| 'satellite' \| 'outdoors' \| 'dark'` | UD | `streets` | MapLibre style for the map view. |
| `units_pace_format` | `'min_per_km' \| 'min_per_mi' \| 'kph' \| 'mph'` | UD | `min_per_km` | Display format for pace. Independent of `preferred_unit` so users can keep km distances but pace in mph if they want — but the web preferences page will auto-snap `min_per_km` ↔ `min_per_mi` when the user flips `preferred_unit` so they don't have to update both. Speed formats (`kph`/`mph`) are treated as deliberate choices and are left alone. |
| `weight_unit` | `'kg' \| 'lbs'` | U | `kg` | Display + entry unit for body weight and lift weights (Phase 4 gym/nutrition). **Storage stays canonical kg** — `gym_sets.weight_kg` (and the future `body_metrics`) are always kilograms; this key only changes how the number is shown and parsed on input, the same display-only split as `preferred_unit`. Universal (not `UD`): a per-device weight unit isn't meaningful. Placed in the bag per the [placement rule](#placement-rule--bag-vs-column-f4) — never queried in SQL. **Consumed on web (F19, 2026-06-04):** the Settings → Preferences toggle persists it; the app shell hydrates the `weightUnit` signal in `format/units.svelte.ts` on sign-in; `/gym` + `/gym/[id]` render via `formatWeight` and `GymEditor` parses entry through `parseWeight` (round-trip kg↔lbs in `format/weight.test.ts`). Mobile twin (`Preferences` + `gym_compose_sheet.dart`) is the remaining half, tracked in followups.md. |
| `weekly_mileage_goal_m` | `int` | U | — | Target weekly distance in metres. Displayed on the dashboard progress bar. |
| `week_start_day` | `'monday' \| 'sunday'` | U | `monday` | First day of the week for mileage + plan rollups. |
| `privacy_zones` | `{ lat: number, lng: number, radius_m: number }[]` | U | `[]` | Geofences clipped from the start and end of any track rendered on a public surface (`/share/run/[id]`, `/share/route/[id]`). The list itself is private to the owner via `user_settings` RLS; the clipped output is what the public sees. See `decisions.md § 33` for the algorithm and known v1 gaps. |

### privacy_default detail

Default visibility of new runs. Per-run override still wins. **Onboarding wizards on both web and mobile pre-select `private`** (privacy-by-default for a new runner — persona #56) and write it as an explicit bag value on finish, so a fresh account starts private and that choice roams + isn't overridden by another device's default. The legacy unset-fallback (for accounts that never set the pref and never ran the wizard) stays `followers` to avoid retroactively hiding existing users' runs. **Honoured on every run-creation path (persona #27):** web `createManualRun`/`saveRun` + the Strava/Garmin ZIP importers, and the server-side imports — the `parkrun-import` + `strava-import` Edge Functions and the Go worker's Strava ingest (`InsertStravaRun`). Only an explicit `public` default publishes; `followers`/`private`/unset and any settings-read error fall closed to private, so importing history never silently publishes it. (The deprecated `strava-webhook` EF rollback path defaults private regardless.)

## Client responsibilities

- **On sign-in**: fetch the user's `user_settings` row. If none exists, insert
  one with `prefs = '{}'`.
- **On first launch per device**: mint a stable `device_id` (UUID, stored in
  device-local storage) and upsert a `user_device_settings` row with
  `platform` + a human `label` (e.g. "iPhone 15", "Pixel Watch 2").
- **On settings edit**: write to whichever table matches the key's scope. A
  device that edits a `UD` key writes to `user_device_settings.prefs`
  unless the user is in the universal-settings UI.
- **On read**: merge `user_device_settings.prefs` on top of
  `user_settings.prefs`, fall back to the default in this doc.

## Where it's wired today

- **Dart clients** (`mobile_android`, `mobile_ios`):
  `SettingsService` in [`packages/api_client/lib/src/settings_service.dart`](../../packages/api_client/lib/src/settings_service.dart),
  with string-constant key names in `SettingsKeys` so clients can't drift on
  spellings. Device ID is minted and cached in `Preferences`
  (`mobile_*/lib/preferences.dart`, key `device_id`).
  `SettingsSyncService` lives as a verbatim twin in
  `mobile_android/lib/settings_sync.dart` and `mobile_ios/lib/settings_sync.dart`
  — it pulls both bags on sign-in, overlays `preferred_unit`,
  `voice_feedback_enabled`, and `voice_feedback_interval_km` onto local
  `Preferences`, and exposes `updateUniversal` / `updateDevice`
  passthroughs the settings screen uses for bag-only keys.

  **Offline behaviour**: a `SharedPrefsSettingsCache`
  ([`mobile_*/lib/settings_cache.dart`](../../apps/mobile_android/lib/settings_cache.dart))
  is wired into `SettingsService` in production main.dart. Both bags are
  persisted to `SharedPreferences` after every successful server load
  and after every optimistic local write. On the next cold start the
  cache hydrates `SettingsService` before the network fetch, so the
  Preferences screen renders every bag-backed tile with the correct
  value instantly. A signed-in offline user editing a bag pref applies
  the change to the cache + in-memory state, then if the server push
  fails the change is queued in `PendingSettingsChange` form and
  replayed on the next successful `SettingsService.load()` — the queue
  drain runs the same `applyPrefsChanges` merge on top of the live
  server bag so a concurrent write from another device isn't clobbered.
  Cache keys are user-scoped (and device-scoped for the device bag)
  so a sign-out + sign-in as a different user can't read another
  user's rows. Both mobile
  settings screens edit the full universal + device registry (profile,
  HR, pace, privacy, coach, map style, auto-pause, weekly goal, coach
  personality, Strava auto-share).
- **Web**: [`apps/web/src/lib/settings/settings.ts`](../../apps/web/src/lib/settings/settings.ts).
  Device ID is minted once in `localStorage` (key `run_app.device_id`). The
  account page at `/settings/account` dual-writes `preferred_unit` to both
  `user_profiles.preferred_unit` (legacy column) and the universal bag, and
  owns the editor for `default_activity_type` + `week_start_day`.

  **Offline behaviour**: a `LocalStoragePrefsCache`
  ([`apps/web/src/lib/settings/settings_cache.ts`](../../apps/web/src/lib/settings/settings_cache.ts))
  fronts every `loadSettings` / `updateUniversal` / `updateDevice` call —
  the web mirror of the mobile pattern above. `loadSettings` returns the
  cached bags synchronously when both are populated and fires a
  background refresh that drains any queued offline writes; the cold
  path (no cache) blocks on the server fetch as before, with a soft
  fall-through to empty bags on network failure so a brand-new offline
  visit still loads. Writes apply to the cache first; on push failure
  the change is queued under
  `settings_cache_pending_<userId>_<deviceId>` and replayed against a
  fresh server bag on the next successful refresh. Cache keys are
  user- + device-scoped, and the auth store's `logout()` calls
  `dropUserCache(userId)` so a subsequent sign-in as a different user
  on the same browser can't read or replay against another account.
  This lifts the dashboard's Fitness / Intensity / weekly-goal /
  unit-preference reads off the critical network path on every visit
  after the first.
- **`profiles.preferred_unit`** is dual-read during the transition — newer
  clients prefer the bag and fall back to the column. A follow-up migration
  drops the column once every client has cut over.
- **Not yet wired**: `watch_ios` (Swift), `watch_wear` (Kotlin), and the
  per-device settings editor UI on any client (the DB holds the device
  rows, but no phone-side UI lets the user override a universal value on
  a specific device yet). The DB + registry are ready; adding surfaces on
  those is ~30 min each.

## Adding a new key

1. Add the row to the table above. Pick the scope deliberately — defaulting to
   `UD` is fine but ask whether a per-device override is actually meaningful.
2. Add the default to a shared constants file in each client (TBD — today
   defaults are scattered).
3. Expose the control in the universal settings screen on web + mobile.
4. For `D`/`UD` keys, expose the override in the per-device settings screen.

No DB migration is required. If you ever need server-side validation of a
specific key (e.g. a function that reads `hr_zones` and must reject malformed
shapes), add the check in that function — not as a DB constraint — so the
registry stays the one source of truth.
