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
| `max_hr_bpm` | `int` | U | — | Max heart rate override. If absent, we fall back to `220 - age`. |
| `date_of_birth` | `YYYY-MM-DD` | U | — | Used for age-based HR max + age-grade calculation. |
| `privacy_default` | `'public' \| 'followers' \| 'private'` | U | `followers` | Default visibility of new runs. Per-run override still wins. |
| `strava_auto_share` | `bool` | U | `false` | Auto-push every new run to Strava (requires connected integration). |
| `coach_personality` | `'supportive' \| 'drill_sergeant' \| 'analytical'` | U | `supportive` | Tone preset for the Claude coach chat. |
| `voice_feedback_enabled` | `bool` | D | `false` | Speak pace/distance callouts during a run. Device-scoped because mic/speaker availability differs. |
| `voice_feedback_interval_km` | `double` | D | `1.0` | Interval in km between spoken callouts. |
| `haptic_feedback_enabled` | `bool` | D | `true` | Vibration on lap + pace-zone changes. Watches only. |
| `auto_pause_enabled` | `bool` | UD | `true` | Stop the clock when the user stops moving. Overridable per-device since auto-pause is less reliable on some hardware. |
| `auto_pause_speed_mps` | `double` | UD | `0.8` | Threshold below which auto-pause engages. |
| `keep_screen_on` | `bool` | D | `true` | Disable OS auto-dim while the running screen is visible. Phones only; watches use ambient mode. |
| `map_style` | `'streets' \| 'satellite' \| 'outdoors' \| 'dark'` | UD | `streets` | MapLibre style for the map view. |
| `units_pace_format` | `'min_per_km' \| 'min_per_mi' \| 'kph' \| 'mph'` | UD | `min_per_km` | Display format for pace. Independent of `preferred_unit` so users can keep km distances but pace in mph if they want. |
| `weekly_mileage_goal_m` | `int` | U | — | Target weekly distance in metres. Displayed on the dashboard progress bar. |
| `week_start_day` | `'monday' \| 'sunday'` | U | `monday` | First day of the week for mileage + plan rollups. |

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
  `SettingsService` in [`packages/api_client/lib/src/settings_service.dart`](../packages/api_client/lib/src/settings_service.dart),
  with string-constant key names in `SettingsKeys` so clients can't drift on
  spellings. Device ID is minted and cached in `Preferences`
  (`mobile_*/lib/preferences.dart`, key `device_id`).
  `SettingsSyncService` lives as a verbatim twin in
  `mobile_android/lib/settings_sync.dart` and `mobile_ios/lib/settings_sync.dart`
  — it pulls both bags on sign-in, overlays `preferred_unit`,
  `voice_feedback_enabled`, and `voice_feedback_interval_km` onto local
  `Preferences`, and exposes `updateUniversal` / `updateDevice`
  passthroughs the settings screen uses for bag-only keys. Both mobile
  settings screens edit the full universal + device registry (profile,
  HR, pace, privacy, coach, map style, auto-pause, weekly goal, coach
  personality, Strava auto-share).
- **Web**: [`apps/web/src/lib/settings.ts`](../apps/web/src/lib/settings.ts).
  Device ID is minted once in `localStorage` (key `run_app.device_id`). The
  account page at `/settings/account` dual-writes `preferred_unit` to both
  `user_profiles.preferred_unit` (legacy column) and the universal bag, and
  owns the editor for `default_activity_type` + `week_start_day`.
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
