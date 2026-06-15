# Treadmill live-mode run-screen toggle — implementation plan

> **Status:** Planned — specced 2026-06-15, not yet built. This is an implementation handoff plan, not a description of shipped behaviour. Tracked in [roadmap.md § Planned features](../product/roadmap.md#planned-features--specced-2026-06-15).

## Goal & user value
A runner on a treadmill can flip "Treadmill mode" on (and off) from the live run
screen so the recorder sources its headline distance from a paired FTMS belt
instead of the pedometer estimate. The reader (`ble_treadmill.dart`), the
Settings pairing tile, and the additive `setTreadmillSample` / `clearTreadmillMode`
seam in `run_recorder` already ship; this is the last unwired piece of parity
backlog #13 (C3). **Mobile-only, no recorder change, no migration.**

## What already exists to build on (verified)
- **Recorder seam (shipped).** `packages/run_recorder/lib/src/run_recorder.dart`:
  - `void setTreadmillSample(double speedMps, {double? totalDistanceMetres})` (line ~613) — first call flips `_treadmillMode = true`; belt distance overrides GPS; wrapped in its own try/catch (L1/L4 contract honoured inside the recorder); no-op until `begin()`; excludes paused advance.
  - `void clearTreadmillMode()` (line ~657) — reverts to the GPS distance path.
  - `bool get treadmillMode` (line ~218) — current mode.
  - On `stop()` the recorder writes `metadata['indoor_source'] = 'treadmill'` + `metadata['distance_source'] = 'treadmill'` — already done, no UI work needed for persistence.
- **BLE reader (shipped).** `apps/mobile_android/lib/ble_treadmill.dart` — `BleTreadmill` with:
  - `Stream<TreadmillSample> get stream` (sample carries `instantaneousSpeedKmh`, `totalDistanceM`).
  - `Stream<BleTreadmillStatus> get statusStream` + `BleTreadmillStatus get status` (`disconnected`/`connecting`/`connected`/`reconnecting`/`connectFailed`).
  - `Future<String?> pairedName()`, `Future<bool> connectCached()`, `Future<bool> reconnect()`, `Future<void> disconnect()`, `Future<void> forget()`, `Future<void> dispose()`.
  - `TreadmillSample` exposes m/s via the same FTMS decode the tile already consumes (tile reads `s.instantaneousSpeedKmh`).
- **HR wiring is the exact pattern to mirror.** `apps/mobile_android/lib/ble_heart_rate.dart` (`BleHeartRate`) is:
  - constructed once in `main.dart` (line 292), `connectCached()` kicked at startup (line 296),
  - threaded as `final BleHeartRate heartRate` into `RunScreen` (constructor line 70/96; passed from `main.dart` line 458 and `home_screen.dart` lines 209/246, and `home_screen` re-exposes it as `widget.heartRate`),
  - subscribed in `run_screen.dart` `_begin()` (lines 968–1031): a `StreamSubscription<int> _hrSub` feeds `_recorder?.setHeartRate(bpm)`, and a `StreamSubscription<BleHrStatus> _hrStatusSub` drives `_showTopBanner` drop/reconnect disclosure; both cancelled in the stop/discard paths.
- **Settings tile (shipped).** `TreadmillTile` in `apps/mobile_android/lib/screens/settings_integrations_screen.dart` (line 595) currently constructs its **own** `final BleTreadmill _treadmill = BleTreadmill()` (line 603). `HeartRateMonitorTile` in the same file instead takes `widget.heartRate` (line 419) — the tile should be converted to the shared-instance pattern (see below).
- **Banner primitive.** `showTopBanner` / `_showTopBanner` (the only allowed in-app notification; `architecture_guards_test.dart` forbids `ScaffoldMessenger`/`showSnackBar` under `lib/screens`).
- **Existing tests:** `apps/mobile_android/test/ble_treadmill_test.dart` (20), `test/treadmill_tile_test.dart` (2), `test/run_screen_test.dart` (RunScreen widget tests).

## Data model / migrations
**None.** No table, no column, no narrow union, no codegen pass. The metadata
flag `runs.metadata.indoor_source = "treadmill"` is already written by the
recorder's `stop()` and already registered in `docs/backend/metadata.md`.
(`gen:types` / `gen_dart_models.dart` are NOT run — there is no schema change.)

## Web implementation (canonical)
**N/A by design.** Web is the canonical *feature* surface, not a *recording*
surface (decisions §24). Treadmill mode is a device-led recording capability —
the explicit physical-exception list in §24 and the `parity.md` Treadmill row
both mark web N/A. Do not add anything to `apps/web`.

## Mobile implementation (Android + iOS twin)
All `lib/` + `test/` edits land in `apps/mobile_android/` **and** are copied
byte-identical to `apps/mobile_ios/` in the same commit (decisions §39; verify
with `diff -rq apps/mobile_android/lib apps/mobile_ios/lib`).

### 1. Shared `BleTreadmill` singleton (mirror HR exactly)
- `apps/mobile_android/lib/main.dart`: construct `final treadmill = BleTreadmill();` next to `final heartRate = BleHeartRate();` (line ~292) and `unawaited(treadmill.connectCached());` next to the HR equivalent (line ~296). Pass `treadmill: treadmill` into the `RunScreen` constructions (line ~458 and the second site ~593).
- `apps/mobile_android/lib/screens/home_screen.dart`: add `final BleTreadmill treadmill;` to the host widget (alongside `heartRate`), require it in the constructor, and pass `treadmill: widget.treadmill` at the two `RunScreen(...)` sites (lines ~209, ~246).
- `apps/mobile_android/lib/screens/settings_integrations_screen.dart`: convert `TreadmillTile` to take a `final BleTreadmill treadmill;` constructor arg (drop the internally-constructed `_treadmill` on line 603; use `widget.treadmill`), matching `HeartRateMonitorTile`. Remove the tile's `dispose()` call to `_treadmill.dispose()` (the singleton outlives the tile now — HR's tile does not dispose `widget.heartRate`). Thread the shared instance from wherever `SettingsScreen` / the integrations screen is built (the same plumbing path `heartRate` already follows into Settings).

  > Rationale (durable, not a patch): a per-tile `BleTreadmill` means the belt the user paired in Settings is a *different* object than any the run screen could read — the run screen would have to construct yet another and re-`connectCached`. One app-lifetime singleton, connected at startup, is the only design where "pair in Settings → mode available on the run screen with zero extra connect" holds. This is exactly why HR is a singleton.

### 2. Run-screen state + subscription (`run_screen.dart`)
Add next to the HR fields (around lines 116–122):
```dart
final BleTreadmill treadmill;            // new constructor field (required)
StreamSubscription<TreadmillSample>? _treadmillSub;
StreamSubscription<BleTreadmillStatus>? _treadmillStatusSub;
bool _treadmillMode = false;             // UI mirror of recorder.treadmillMode
bool _treadmillPaired = false;           // gates whether the toggle even shows
BleTreadmillStatus _treadmillStatus = BleTreadmillStatus.disconnected;
```
- In `initState` (or the existing `_loadPairedDevices`-style init), best-effort `widget.treadmill.pairedName()` → set `_treadmillPaired = name != null`. The toggle only renders when a belt is paired (otherwise it would do nothing — direct the user to Settings → Integrations).
- In `_begin()` (alongside the HR subscription block, ~line 968): subscribe `widget.treadmill.statusStream` to mirror `_treadmillStatus` and disclose drops via `_showTopBanner` (reuse the HR switch shape: `reconnecting` → "Treadmill lost, reconnecting", `connected`-from-`reconnecting` → "Treadmill reconnected", `disconnected`-from-`reconnecting` → "Treadmill lost — distance falling back to GPS/pedometer"). **Do not** auto-start the sample subscription here — treadmill mode is an explicit user opt-in via the toggle (matches the seam's "first call flips mode" contract and avoids hijacking a normal outdoor run from a belt that happens to be in range).
- Cancel `_treadmillSub` + `_treadmillStatusSub` in the same places `_hrSub` / `_hrStatusSub` are cancelled (stop path + `_discard` + `dispose`). Do NOT call `widget.treadmill.disconnect()` — the singleton is shared (mirror: the run screen never disconnects the HR strap).

### 3. The toggle + sample pump
- `_toggleTreadmillMode(bool on)`:
  - `on == true`: subscribe `_treadmillSub = widget.treadmill.stream.listen(...)` with an `onError` that `debugPrint`s (never rethrows — L4). In the listener call `_recorder?.setTreadmillSample(sample.speedMps, totalDistanceMetres: sample.totalDistanceM)`. Set `_treadmillMode = true` via `setState`. If `_treadmillStatus == connectFailed`, offer a one-tap `widget.treadmill.reconnect()` banner action (mirror `_reconnectHeartRate`, line 1071).
  - `on == false`: `await _treadmillSub?.cancel(); _treadmillSub = null; _recorder?.clearTreadmillMode();` and `setState(_treadmillMode = false)`.
  - Wrap the BLE/recorder calls so a failure shows a banner and reverts the toggle — it must never tear down the recording (L4).
- **Layering note (L0–L4 contract, the explicit ask):** the toggle and its subscription are an L4 auxiliary effect layered *on top of* the live recording. The recorder's `setTreadmillSample` already self-guards (own try/catch, drops bad samples, falls back to the L0 clock on a dropped link); the screen-side `onError` + try/catch around `_toggleTreadmillMode` is the second layer. A treadmill failure at any point must leave the L0 clock + L1 distance path intact. Never widen to a single outer catch; each effect (stream listen, status listen, recorder call) gets its own guard + `debugPrint`. Verify against `docs/features/run_recording.md § Layering` (belt distance is layer 14) before finishing.

### 4. UI placement (no nav change; 6-tab ceiling untouched)
Render a `SwitchListTile` / compact chip-toggle inside `_buildLive` (the recording
view begins at `run_screen.dart` line ~2411), shown only when `_treadmillPaired`.
Put it near the existing recording controls (the same region the GPS-lost banner /
manual-pause controls occupy) so it's reachable without leaving the screen. Label
"Treadmill mode" with a subtitle showing the live belt speed when on
(`sample.instantaneousSpeedKmh` formatted via the existing pace/speed helpers in
`run_stats.dart`, unit-aware). When the belt status is `reconnecting` show an
inline "reconnecting…" hint rather than freezing the speed read-out (mirror the HR
readout's nulling behaviour at lines 1006/1016/1021).

## TS↔Dart parity helpers
**None.** No pure cross-platform logic is added — the decode + distance math
already live in `ble_treadmill.dart` (`parseTreadmillData`) and the recorder
seam. This is pure UI wiring against shipped pure code.

## Tests (same commit as the piece)
Flutter widget/unit tests only (mobile has no e2e by design;
`docs/testing/testing.md § What's not covered`). Add to BOTH twins:
- **`apps/mobile_android/test/run_screen_test.dart`** (extend): with a fake/seeded `BleTreadmill` exposing a controllable `stream` + `statusStream` + `pairedName()`:
  1. toggle hidden when no belt paired (`pairedName()` → null);
  2. toggle visible when paired;
  3. turning it on subscribes and pumping a `TreadmillSample` calls `recorder.setTreadmillSample` (assert via a recorder spy / `debugTreadmillMode` getter `treadmillMode` going true, plus the headline distance switching to belt distance);
  4. turning it off calls `clearTreadmillMode` (mode reverts);
  5. a `BleTreadmillStatus.reconnecting` transition shows the disclosure banner;
  6. a sample-stream `onError` does NOT crash the screen (L4 guard).
  - Gotchas to bake in (from CLAUDE.md): store I/O needs `tester.runAsync`; `showTopBanner` leaves a pending timer (pump with a finite duration / `tester.runAsync` + cancel); `pumpAndSettle` hangs on the `LiveRunMap`/cursor animations — pump fixed durations, don't `pumpAndSettle`. Use dialog/region-scoped finders given duplicate labels.
- **`apps/mobile_android/test/treadmill_tile_test.dart`** (update): the 2 existing tests must now pass the shared `BleTreadmill` via the new constructor arg (the tile no longer self-constructs one). Keep the not-paired / paired assertions.
- Run `flutter test` for the package; run `dart analyze` and confirm no new `warning`/`error`.

## i18n keys to add
ARB keys (camelCase) in **all six** locales `app_{en,de,fr,es,ja,pt_BR}.arb`
(+ the `pt` base) under `apps/mobile_android/lib/l10n/` AND the iOS twin
`apps/mobile_ios/lib/l10n/`; real translations (not English placeholders —
`l10n_parity_test.dart` enforces parity + faithful placeholders); then
`flutter gen-l10n` and mirror `lib/l10n/gen/` to the twin. Representative keys:
- `runTreadmillModeLabel` → "Treadmill mode"
- `runTreadmillModeSpeed` (placeholder `{speed}`) → e.g. "Belt {speed}"
- `runTreadmillLostReconnecting` → "Treadmill lost, reconnecting…"
- `runTreadmillReconnected` → "Treadmill reconnected"
- `runTreadmillLostFallback` → "Treadmill lost — distance falling back to GPS"
- `runTreadmillNotFound` → "Couldn't reach the treadmill" (+ reuse `runReconnect` for the action)
No web locales change (web is N/A).

## Docs to update (same/next commit)
- `docs/product/roadmap.md` item 13: flip from "Partial / Deferred: the live run-screen mode toggle" to shipped (remove the deferred clause).
- `docs/product/parity.md` Treadmill row: flip the Android (and iOS) cell to ✓.
- `docs/features/integrations.md § Treadmills (BLE FTMS)`: change the two "Still deferred: the live run-screen mode toggle" lines (the header note ~line 9, the Status block ~line 427, and the "Still deferred" paragraph ~line 446) to reflect that the toggle shipped; keep the watch-BLE follow-up deferred.
- `apps/mobile_android/CLAUDE.md` + `apps/mobile_ios/CLAUDE.md`: update the `ble_treadmill.dart` entry ("Live run-screen wiring is not yet built") to note the toggle shipped; mention the new shared singleton + the `RunScreen.treadmill` constructor arg.
- No `decisions.md` entry strictly required (the design — singleton mirroring HR, opt-in toggle — follows the established HR pattern). Add a one-paragraph ADR only if the reviewer flags the singleton conversion of `TreadmillTile` as non-obvious.

## Gating / compliance
**None.** Not paywalled, no compliance sign-off, no fail-closed flag. The belt
is opt-in by construction (toggle off by default; mode only engages on explicit
user action). No health-data / privacy-boundary change (indoor runs carry no
track, so map/privacy-zone surfaces are already skipped).

## Commit plan (ordered, path-scoped)
1. **Shared singleton + plumbing** — `git commit -- apps/mobile_android/lib/main.dart apps/mobile_android/lib/screens/home_screen.dart apps/mobile_android/lib/screens/settings_integrations_screen.dart apps/mobile_ios/lib/main.dart apps/mobile_ios/lib/screens/home_screen.dart apps/mobile_ios/lib/screens/settings_integrations_screen.dart apps/mobile_android/test/treadmill_tile_test.dart apps/mobile_ios/test/treadmill_tile_test.dart` (tile now takes the shared instance; tests updated in the same commit).
2. **Run-screen toggle + tests + i18n** — `git commit -- apps/mobile_android/lib/screens/run_screen.dart apps/mobile_android/lib/l10n/ apps/mobile_ios/lib/screens/run_screen.dart apps/mobile_ios/lib/l10n/ apps/mobile_android/test/run_screen_test.dart apps/mobile_ios/test/run_screen_test.dart` (the toggle, its L4 guards, the i18n keys, the widget tests — one piece, one commit).
3. **Docs** — `git commit -- docs/product/roadmap.md docs/product/parity.md docs/features/integrations.md apps/mobile_android/CLAUDE.md apps/mobile_ios/CLAUDE.md` (after the code commit it documents).

Path-scope every commit (shared working tree; never `git add -A`).

## Open questions / decisions owed by the user
1. **Convert `TreadmillTile` to the shared singleton?** Recommended (durable; mirrors HR). The alternative — run_screen constructs its own second `BleTreadmill` — re-runs `connectCached` and risks two GATT clients fighting over one belt. Confirm the conversion is in scope.
2. **Should treadmill mode auto-engage if a paired belt is already streaming when a run starts?** Recommended NO (explicit opt-in via toggle) so a belt in range can't hijack an outdoor GPS run. Flag if the product wants auto-engage for a known-indoor context.
3. **Toggle placement** — confirm "near the recording controls in `_buildLive`" vs. surfacing it on the idle pre-run screen too (e.g. "Start on treadmill"). Plan assumes mid-run toggle only (the deferred item's literal scope).

## Sequencing for the implementer
1. Read `run_recording.md § Layering` (belt = layer 14) and the HR wiring in `run_screen.dart` lines 968–1031 + `_reconnectHeartRate` (1071) — that's the template for everything below.
2. Build the shared `BleTreadmill` singleton: `main.dart` (construct + `connectCached`), thread through `home_screen.dart` → `RunScreen`, convert `TreadmillTile` to take it. Update `treadmill_tile_test.dart`. Mirror all to iOS twin. Commit (piece 1). Run `flutter test test/treadmill_tile_test.dart`.
3. Add the run-screen state fields + `_begin` status subscription + cancel-in-stop/discard/dispose. Mirror to twin.
4. Add `_toggleTreadmillMode` + the sample pump + the L4 guards.
5. Add the `SwitchListTile` in `_buildLive`, gated on `_treadmillPaired`, with the live-speed subtitle. Mirror to twin.
6. Add the i18n keys to all six ARBs (both twins), `flutter gen-l10n`, mirror `lib/l10n/gen/`.
7. Write the `run_screen_test.dart` cases (both twins), baking in the pump/timer gotchas. Run `flutter test`; `dart analyze` (no new warning/error). Commit (piece 2).
8. `diff -rq apps/mobile_android/lib apps/mobile_ios/lib` (empty) and the same for `test/`.
9. Update the docs + both per-app CLAUDE.md. Commit (piece 3).
