# Firmware — why not Wear OS, and how it integrates with the existing app

## Why not Wear OS

Wear OS is the wrong base for an ultra watch. Specifically:

- **JVM overhead.** Even with ART AOT compilation, the Android runtime burns 5–10x the CPU cycles of bare-metal C for the same instruction count. Garbage collection pauses are ~5–50ms even on a small heap. For a 1Hz GPS log + 25Hz HR sample + once-per-second UI refresh, that overhead is ~30–50% of the active power budget — not because the work is hard, but because the runtime is fat.
- **Android scheduler.** Wear OS inherits Android's CFS scheduler with the standard 10ms tick. A bare-metal RTOS on the same MCU can sleep the CPU between sensor samples and wake on interrupt with ~50µs latency. The difference shows up as ~3x the active current on the same workload.
- **Display stack overhead.** Wear OS draws through Skia + Vulkan + a compositor. An always-on screen update with a single dirty pixel still walks the whole pipeline. A bare-metal display driver writes the pixel directly to the SPI bus. On a MIP display this is the difference between 100µA always-on and 5mA always-on.
- **Google's certification requirements.** Wear OS certified devices must run Play Services, support Google Pay, support Google Assistant — all of which keep the radio + CPU awake more than we'd want. You can run *uncertified* AOSP-Wear without these, but then you also lose Maps, Play Store, and basically the whole reason to be on Wear OS in the first place. Garmin and COROS made this exact calculation a decade ago and both went RTOS.

**Empirical evidence:** Wear OS watches top out at ~24–40hr GPS on a 500–600 mAh battery. COROS Vertix 2 hits 140hr on a comparable cell. Same silicon process, same display, same GNSS. The 4–6x delta is the software stack.

## The right base: Zephyr RTOS

| Option | Verdict |
|---|---|
| **Zephyr RTOS** | First-class support on both candidate MCUs (Apollo4 + nRF5340). LTS releases. Apache 2.0 licence. Modern device-tree-based BSP. Drivers for every sensor on the BOM already exist upstream. Used by Nordic, Intel, Bose, Garmin (Connect+ generation). **Pick this.** |
| FreeRTOS | Mature, simple, ubiquitous. Used in older Garmin / Polar watches. Smaller community than Zephyr. Driver ecosystem is per-vendor SDK rather than upstream. Reasonable fallback if Zephyr's HAL for the Apollo4 turns out to have gaps |
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
firmware/
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

Toolchain: Zephyr SDK 0.16+, west, west build for cross-compiling. Debugger: JLink (Apollo4) or nRF Connect (nRF5340). CI: GitHub Actions with `zmkfirmware/zephyr-west-action` for build verification.

## Integration with the existing app

The watch is **not** a standalone product — it's a complement to the existing Supabase + Flutter + SvelteKit stack. The integration story:

### Sync protocol

The watch records runs locally to LittleFS while running. When it's near a paired phone with the app installed, it syncs over BLE:

1. **Custom GATT service** — `0000xxxx-...` UUID, two characteristics: `run_manifest` (list of unsynced run IDs + sizes) and `run_chunk` (binary chunk transfer with offset).
2. **Phone-side handler** — Flutter `flutter_blue_plus` listens for the service, pulls the manifest, requests each unsynced run as 512-byte chunks, reconstructs the gzipped GPS track on disk, then hands it to the existing `ApiClient.saveRun` path.
3. **Run format on the watch** — the same gzipped JSON shape that `runs` Storage bucket stores. The phone is a pass-through; it doesn't reformat anything.

This means **the watch reuses the existing backend, the existing Storage bucket layout, the existing sync conflict resolution.** Zero schema changes on the Supabase side. The watch is just another device that writes to the same `{user_id}/{run_id}.json.gz` Storage path.

### Course download (reverse direction)

The same GATT service supports `course_download` — phone pushes a course to the watch as PMTiles vector data + a polyline. The watch stores the course in LittleFS, displays it on the map screen during a run, runs the existing off-route detection logic (ported from `apps/mobile_android/lib/services/route_overlay.dart` to C).

### Live spectator tracking (stretch)

Watch sends GPS fixes over BLE to the phone, phone forwards them to the existing live-spectator pipeline (Supabase Realtime today, Go live-hub in Phase 3 per [roadmap.md § Phase 3](../roadmap.md#phase-3--growth-and-monetisation)). The watch itself never talks to the internet — phone is the bridge.

### Code shared with the existing apps

Approximately zero code is literally portable from the Dart/TS codebase to C/Zephyr. But the **algorithms, state machines, and data formats** all port directly:

- `run_recorder` state machine (idle → recording → paused → finished) — direct port to C
- `route_overlay` off-route detection — direct port (already pure-math)
- `track_projection.ts` ↔ `projectTrack` (Dart) — third port to C, must stay in lockstep with the existing two per the parity rule in `CLAUDE.md`
- Auto-pause derivation (from `run_recording.md`) — direct port
- GPS track gzip + JSON format — already a wire-format spec; the C side just emits the same bytes

The "byte-identical twin" invariant from the mobile apps extends here: the **algorithm** is identical across Dart and C, even though the languages differ. This becomes the *fourth* parity surface to keep in lockstep, joining the existing TS / Dart / future-watch-firmware triangle.

## Open firmware questions

These need real answers before tier 2 starts:

1. **Vector map rendering on a 96MHz Cortex-M4F.** No-one ships this today. Garmin's Fenix uses raster tiles for offline maps. We'd be inventing the technique, or punting to raster and giving up the "vector map" pitch. Either is fine, but the decision needs to happen before we commit to 16GB of flash.
2. **ANT+ chest strap pairing.** Nordic's nRF5340 supports ANT+ via the multi-protocol radio, but the ANT+ protocol stack is licensed per device by Garmin (yes, Garmin owns the ANT+ standard — they bought Dynastream in 2006). Per-device licensing is ~$0.50–1.50 at our volumes; the question is whether Garmin will sell it to a competitor. If not, we ship BLE-only HR pairing and live with the smaller compatible-strap market.
3. **Over-the-air firmware updates.** Standard practice but the bootloader + dual-bank flash layout adds ~6 weeks of work. Has to be in v1.0; cannot be added later without bricking shipped units.
4. **Watch face / data screen customisation.** Garmin's Connect IQ is a major part of their moat (third-party watch face marketplace). MicroPython embedded in the firmware is one option; a constrained DSL is another. Almost certainly out of scope for v1.0 but worth designing the UI layer with the customisation hook in mind.
