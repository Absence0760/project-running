# Firmware — why not Wear OS, and how it integrates with the existing app

> **Status (2026-05-28): superseded by [decisions.md § 80](../architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance).** §80 picked Embassy on Rust on the Nordic nRF52840 over Zephyr on C; the active firmware workspace at [`/apps/custom_watch/`](../../apps/custom_watch/README.md) reflects that decision. This doc remains as the reference for the Zephyr fallback path called out in §80 — taken only if Embassy hits a blocking driver issue that takes more than two weeks to resolve. The "Why not Wear OS" reasoning below still holds in either language; "The right base: Zephyr RTOS" section reflects the original proposal and should be read as the fallback spec, not the active one. For the active firmware spec see the `apps/custom_watch/` README; for where the performance levers actually live see [`performance_path.md`](performance_path.md).

## Why not Wear OS

Wear OS is the wrong base for an ultra watch. Specifically:

- **JVM / managed-runtime overhead.** Even with ART's AOT compilation, the Android runtime carries non-trivial CPU + memory cost vs bare-metal C — typically 2–3x slower on compute-bound work, larger on allocation-heavy or boot paths, and with GC pauses in the 5–50ms range even on small heaps. The aggregate effect on power for a sensor-fusion workload is significant but the exact percentage depends on the specific app — directionally, it's enough that even a perfectly-tuned Wear OS app can't approach the per-fix power budget a bare-metal RTOS can hit.
- **Android scheduler.** Wear OS inherits Android's CFS scheduler with the standard ~10ms tick. A bare-metal RTOS on the same MCU can sleep the CPU between sensor samples and wake on interrupt with microsecond-class latency, which (combined with finer-grained peripheral-clock gating) materially reduces active-state current on a duty-cycled workload.
- **Display stack overhead.** Wear OS draws through Skia + Vulkan + a compositor. An always-on update with a single dirty pixel still walks much of the pipeline. A bare-metal display driver writes pixels directly to the SPI bus, and on a MIP display the per-frame energy is closer to the display's static current (~µA) than to a redraw event (~mA).
- **Google's certification requirements.** Wear OS certified devices must run Play Services, support Google Pay, support Google Assistant — all of which keep the radio + CPU awake more than we'd want. You can run *uncertified* AOSP-Wear without these, but then you also lose Maps, Play Store, and basically the whole reason to be on Wear OS in the first place. Garmin and COROS made this exact calculation years ago and both went RTOS.

**Empirical evidence:** flagship Wear OS watches top out around 24–40hr continuous GPS on 500–600 mAh batteries. COROS Vertix 2 advertises 140hr (single-band GPS) on a comparable cell. Same silicon process, same display family, same GNSS-chip class. The delta is dominated by the software stack — the specific multiple varies by mode but the order of magnitude is what matters.

## The right base: Zephyr RTOS

| Option | Verdict |
|---|---|
| **Zephyr RTOS** | First-class support on both candidate MCUs (Apollo510B per [§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified) + nRF5340). LTS releases. Apache 2.0 licence. Modern device-tree-based BSP. Drivers for every sensor on the BOM already exist upstream. Used by Nordic, Intel, Bose, and a growing share of wearable / IoT projects. **Pick this.** |
| FreeRTOS | Mature, simple, ubiquitous. Widely used in consumer wearables (Garmin and Polar's older firmware lines are FreeRTOS-derived, per public teardowns and job-postings). Smaller community than Zephyr. Driver ecosystem is per-vendor SDK rather than upstream. Reasonable fallback if Zephyr's HAL for the Apollo510B turns out to have gaps |
| MyNewt / RIOT / NuttX | Niche; smaller communities; less reason to pick them over Zephyr unless you have specific licence or architectural concerns |
| MicroPython / CircuitPython | Cute for tier-1 bench prototypes; performance + memory cost rules them out for shipping firmware |
| Custom no-RTOS bare-metal | Possible (this is what 2010-era Garmin did) but gives up the cooperative-multitasking + driver ecosystem that Zephyr provides. Worth +20% battery life maybe, costs 6–12 months of engineering to replicate |

Zephyr's specific wins for this project:

- **Power management primitives are first-class.** Subsystem-level power domains, deferred wake-ups, configurable tick rates. The whole platform is designed for battery-powered devices.
- **Bluetooth host stack is in-tree.** No third-party stack to integrate. ANT+ is harder; will probably need Nordic's S140 SoftDevice if we go nRF5340.
- **File system + flash storage.** LittleFS is in-tree and is the right choice for the 16+ GB of vector-map storage we need.
- **Display + LVGL integration.** Zephyr has a Sharp Memory LCD driver in-tree; LVGL has a Zephyr port for the UI layer.

## Build environment

```
apps/custom_watch/         # tier-1 firmware workspace (would also host the Zephyr fallback per §80)
  zephyr/                  # zephyr workspace, west-managed
  app/                     # our application code
    src/
      main.c               # entry point, scheduler setup
      gps/                 # GNSS NMEA parser, fix management
      hr/                  # optical HR sampling + filtering
      record/              # run recording state machine (mirrors run_recorder package)
      sync/                # BLE GATT server, sync protocol with phone
      ui/                  # LVGL screens, button handling
      maps/                # PMTiles parser + vector tile renderer
    boards/
      ultrawatch_v1/       # board definition: pinmux, sensors, display
    prj.conf               # Kconfig for the application
  west.yml                 # workspace manifest
```

Toolchain: Zephyr SDK 0.16+, west, west build for cross-compiling. Debugger: JLink (Apollo510B per [§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified)) or nRF Connect (nRF5340). CI: GitHub Actions with `zmkfirmware/zephyr-west-action` for build verification.

## Integration with the existing app

The watch is **not** a standalone product — it's a complement to the existing Supabase + Flutter + SvelteKit stack. The integration story:

### Sync protocol

The watch records runs to on-device flash while running, and syncs them over BLE when it is near a paired phone with the app installed. **At tier 1 there is no filesystem**: the store is four 4 KiB internal-flash slots holding 253 records per run, decimating when full (`apps/custom_watch/core/src/flash_store.rs`). LittleFS belongs to the external NAND that arrives with tier 2 — see [`tier2_scope.md`](tier2_scope.md) and [§ 85](../architecture/decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash).

1. **Custom GATT service** — this design-era note said two characteristics: `run_manifest` (list of unsynced run IDs + sizes) and `run_chunk` (binary chunk transfer with offset). What shipped is **nine** on one service (`apps/custom_watch/app/src/tasks/ble.rs`): the per-second status `frame`, `run_manifest` + `run_chunk` as designed, five write-only push characteristics — `settings` (`SET1`), `course` (`CRS1`, chunked), `workout` (`WKT1`, chunked — the structured-workout step list, decisions §354), `screens` (`SCR1`, **unchunked** — the runner's composed data screens, decisions §364; the whole set is 28 bytes, so it fits one ATT write and needs no assembler) and `roadbook` (`RBK1` v2, chunked — the checkpoint + cut-off schedule, which is what makes the Roadbook / CutoffEta / Fuel / SleepStation pages read live data on hardware; v2 added the per-checkpoint target time and its verdict, decisions §1027) — and one read-only answer, `push_status` (`PSH1`), because an ATT write-with-response says only that the SoftDevice stored the value, never that the watch kept it. Every one is encryption-gated (§285). The count is guarded rather than transcribed: `scripts/check_watch_ble_uuids.mjs` parses the table, and every row is claimed by a phone constant.
2. **Phone-side handler** — this design-era note said Flutter `flutter_blue_plus` pulling each run as 512-byte chunks. What shipped is `flutter_reactive_ble` (chosen over `flutter_blue_plus`, decisions §212) behind the injectable `WatchSyncClient` transport seam in `apps/mobile_android/lib/sim_watch_sync.dart`, with a default chunk size of **180** bytes to sit inside a conservative negotiated MTU. It still listens for the service, pulls the manifest, reassembles and `verify_blob`s each run, then hands it to the existing `WatchIngestQueue` → `runFromWatchPayload` → `api.saveRun` path.
3. **Run format on the watch** — this design-era note said "the same gzipped JSON shape the `runs` Storage bucket stores, phone is a pass-through". What shipped is a compact binary blob instead: `header(16) | record[N](16) | footer(20)`, little-endian, magics `TRK1` / `END1`, one 16-byte cell per record with byte 15 the tag — 0 a track point, 1 a closed lap, 2 a settled workout step's outcome, 3 the workout summary carrying the armed `WKT1` frame's CRC (the attribution handle — decisions §356). The phone decodes and reshapes it into the payload `runFromWatchPayload` already ingests, so the backend still sees exactly what it saw before. **Integrity is one CRC32 over the whole blob except the four bytes the CRC itself occupies** — header, records, and the footer's magic and totals alike — so a blob is trusted whole or refused whole; there is no window in which the track checks out while the summary is unverified. That window is wire-format **version 3**'s (decisions §321); **version 4** only added the two workout tags on top of it (decisions §356) and **version 5** only moved a track point's altitude from decimetres to whole metres in the same two bytes (decisions §1026), so a v5 reader still decodes v3 and v4 — resolving the altitude unit against the blob's own header version, since reading a v3 blob as metres is a silent tenfold error. v1 and v2 hashed only the prefix and are rejected outright. Canonical definition: `apps/custom_watch/core/src/run_store.rs`, mirrored in `apps/mobile_android/lib/sim_watch_sync.dart` against golden vectors that are now genuinely shared: `scripts/check_watch_wire_vectors.mjs` reads the vector out of both suites and fails when they disagree (decisions §793).

This means **the watch reuses the existing backend, the existing Storage bucket layout, the existing sync conflict resolution.** Zero schema changes on the Supabase side. The watch is just another device that writes to the same `{user_id}/{run_id}.json.gz` Storage path.

### Course download (reverse direction)

This design-era note said the service would support `course_download`, pushing a course as PMTiles vector data + a polyline into LittleFS, with the off-route logic ported to C from a `route_overlay.dart` that never existed under that path. What shipped is narrower and simpler: the characteristic is named **`course`**, it carries the chunked **`CRS1`** frame (`apps/custom_watch/core/src/course_store.rs` — v3, magic + version + point count + flags + up to 256 points + an optional `i16` per-point elevation series + a mandatory CRC32 trailer, decisions §334/§335), and there is **no PMTiles and no filesystem** at tier 1 — the course lives in RAM plus a flash record. The off-route detection is `watch_core::course`'s `OffCourseAlert`, a Rust port of the mobile run screen's route-overlay thresholds (alert past 40 m, re-arm below 20 m). The phone-side twin of those two numbers is `_offRouteThresholdMetres` in `apps/mobile_android/lib/screens/run_screen.dart`, **not** `off_route_alert.dart` — that module is the sustained-off-route escalation to a trusted contact and deliberately fires at 75 m after 90 s, because a wrist nudge and a contact ping are different claims. The same 40 / 20 pair also lives on the Apple Watch (`RouteNavigator.swift`) and Wear OS (`RunWatchApp.kt`); all four rails are compared by `scripts/check_watch_wire_vectors.mjs` (decisions §793). PMTiles vector rendering on the MCU remains the separate, unstarted [§ 85](../architecture/decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash) commitment.

### Live spectator tracking (stretch)

Watch sends GPS fixes over BLE to the phone, phone forwards them to the existing live-spectator pipeline (Supabase Realtime today, Go live-hub in Phase 3 per [roadmap.md § Phase 3](../product/roadmap.md#phase-3--growth-and-monetisation)). The watch itself never talks to the internet — phone is the bridge.

### Code shared with the existing apps

Approximately zero code is literally portable from the Dart/TS codebase to C/Zephyr. But the **algorithms, state machines, and data formats** all port directly:

- `run_recorder` state machine (idle → recording → paused → finished) — direct port to C
- `route_overlay` off-route detection — direct port (already pure-math)
- `track_projection.ts` ↔ `projectTrack` (Dart) — third port to C, must stay in lockstep with the existing two per the parity rule in `CLAUDE.md`
- Auto-pause derivation (from `run_recording.md`) — direct port
- GPS track gzip + JSON format — already a wire-format spec; the C side just emits the same bytes

The "byte-identical twin" invariant from the mobile apps extends here: the **algorithm** is identical across Dart and C, even though the languages differ. This becomes the *third* language-level parity surface to keep in lockstep (TS, Dart, and now C firmware) — at the cost of every algorithm change needing a third reference port. The existing TS↔Dart parity pairs documented in `CLAUDE.md` would gain a `.c` sibling.

## Open firmware questions

These need real answers before tier 2 starts:

1. **Vector map rendering on a 96MHz Cortex-M4F.** Garmin's Fenix already ships vector topo maps (TopoActive, OSM-derived) — so the technique exists in the segment — but their renderer is closed and tuned over a decade. Open-source vector renderers (MapLibre Native, Mapbox GL Native) assume an MMU-class CPU and tens of MB of RAM; neither runs on a Cortex-M4F unmodified. Realistic options: (a) port a constrained subset of a vector renderer to the MCU (multi-month firmware project), (b) pre-bake vector tiles into a simpler intermediate (compressed line / polygon arrays per zoom level), or (c) punt to raster tiles and accept worse zoom-in quality. The decision needs to happen before we commit to 16GB of flash. **Resolved by [decisions.md § 85](../architecture/decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash):** option (a) — full PMTiles parser + minimal vector renderer on the MCU + 16 GB external SPI NAND flash in the tier-2/3 BOM. Decision driven by [§ 86](../architecture/decisions.md#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins) (end-state quality > engineering convenience).
2. **ANT+ chest strap pairing.** ANT+ requires a radio that speaks the ANT protocol; Nordic's nRF52840 supports this via the S340 multi-protocol SoftDevice (BLE + ANT concurrently). The nRF5340 has a more modern radio but ANT+ support is less mature — verify against current Nordic documentation before committing the SoC choice. The ANT+ standard is owned by Garmin (Dynastream acquisition, 2006); per-device licensing is a small unit fee but the open question is whether Garmin will sell ANT+ adoption rights to a direct competitor. If not, we ship BLE-only HR pairing and live with the smaller compatible-strap market.
3. **Over-the-air firmware updates.** Standard practice but the bootloader + dual-bank flash layout adds ~6 weeks of work. Has to be in v1.0; cannot be added later without bricking shipped units. **Resolved by [decisions.md § 84](../architecture/decisions.md#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default):** deferred to tier-2 with a hard obligation that a production-grade dual-bank bootloader (MCUboot default candidate) ships before any tier-2 prototype reaches a field tester.
4. **Watch face / data screen customisation.** Garmin's Connect IQ is a major part of their moat (third-party watch face marketplace). MicroPython embedded in the firmware is one option; a constrained DSL is another. Almost certainly out of scope for v1.0 but worth designing the UI layer with the customisation hook in mind. **Note the scope of this question, because the roadmap row it gated had bundled two features into it** ([decisions § 363](../architecture/decisions.md)): this is about *third-party* faces — a runtime, a sandbox, a marketplace — and is genuinely a platform problem. Letting the *owner* choose which metrics appear on their own screens is a config problem that needs none of that, and its foundation (`face::Metric`, a closed catalogue of the run view's headline quantities) landed 2026-07-30 without touching this question. The customisation hook this line asks for now exists; what remains open is whether anyone but us ever writes against it.
