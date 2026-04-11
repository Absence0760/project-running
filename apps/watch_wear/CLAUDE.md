# watch_wear — AI session notes

Flutter app targeting Wear OS. **Single-file simulated stub** — the real implementation is Phase 2 work ([../../docs/roadmap.md § Phase 2](../../docs/roadmap.md)). Do not mistake the current state for anything beyond a "hello world" you can actually run on a watch.

## Current state

One Dart file:

- `lib/main.dart` (~240 lines) — `RunWatchScreen` with three states (`preRun`, `running`, `postRun`), start/stop buttons, and **simulated** GPS that generates distance / pace from a `Timer` + random walk. No real `geolocator` calls, no `api_client` integration, no sync.

That's the whole app. No screens directory, no widgets, no stores.

## Why Flutter, not Compose

See [decisions.md § 1](../../docs/decisions.md) — Flutter on Wear OS has viable Compose interop, the Android team already writes Dart, and we get to reuse `core_models` + `api_client` when the real port happens. This is not the same answer as for watchOS, where Flutter was rejected.

## What Phase 2 adds to this app

Per `roadmap.md` § "Phase 2 — watch parity":

- Standalone GPS recording (no phone required)
- Heart-rate sensor integration via Wear OS health services
- Route preview and live navigation on the watch face
- Glanceable tile with active run summary
- Watch Connectivity background sync on reconnect

None of this is written yet. When you implement it, port the GPS / pace / off-route logic from `packages/run_recorder` — don't reimplement — and use `packages/api_client` for the Supabase calls.

## Known constraint: Compose interop

The roadmap calls this "Compose for Wear UI (Kotlin + Flutter hybrid)". Expect that some screens will be rendered via Compose in native Kotlin and embedded into the Flutter view tree. The boundary hasn't been drawn yet — that's a Phase 2 design task. When you start it, add a section here describing how the hybrid works so the next session doesn't have to reverse-engineer it.

## Running it locally

See [../../docs/local_testing_wear_os.md](../../docs/local_testing_wear_os.md). You need a Wear OS emulator or a paired watch.

## Before reporting a task done

- Tick the corresponding Wear OS box in `roadmap.md` § Phase 2.
- If you introduced the Compose interop boundary, document it here.
- If you added real GPS or network code, remove the simulated fallback in `main.dart` — don't leave both paths live.
