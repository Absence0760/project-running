---
description: Verify the L0–L4 try/catch layered-resilience contract on the run-recording stack
---

Verify the L0–L4 layered-resilience contract per `docs/conventions.md` § "Layered resilience" and the L0–L4 table in `docs/run_recording.md` § "Layering".

## What this is

The product contract: basics always work. A failure at a higher layer (L4 auxiliary effect, L3 route overlay, L2 map, etc.) cannot break a lower one (L1 GPS/pedometer distance, L0 clock). Each auxiliary effect (TTS, network ping, platform channel, third-party widget) is wrapped in its own `try/catch + debugPrint`. The pattern is **never widen to a single outer catch, never swallow silently, and never let an auxiliary failure cancel a core `setState`**.

This audit walks the recording stack and confirms each auxiliary effect honors the contract.

## What to check

1. **Run the architecture-guards test first.** Some of this is already test-enforced. `apps/mobile_android/test/architecture_guards_test.dart` has guards for some L0/L1 invariants — start there. New L4 effects added since the last audit may not have been added.
2. **Auxiliary-effect inventory.** Walk `apps/mobile_android/lib/screens/run_screen.dart` + everything it imports. List every:
   - TTS / `flutter_tts` call
   - Haptic / `HapticFeedback.*` call
   - Platform channel invocation (`MethodChannel`)
   - Network ping (live broadcaster, sync triggers, profile updates)
   - Third-party widget that can throw on unusual input (chart libraries, share-plus, share-card capture)
3. **Per-effect contract:** each must be wrapped in its own `try { ... } catch (e) { debugPrint('...'); }` block. The catch must NOT:
   - Swallow silently (no `catch (_) {}` without a debugPrint)
   - Re-throw (would propagate to the snapshot handler and break L1)
   - Skip the surrounding core update (e.g. cancel a `_statsNotifier.value =` because the TTS call failed)
4. **`_onSnapshot` is hot-path.** Per the "Hot-path exception" note in `apps/mobile_android/CLAUDE.md`, `_onSnapshot` does NOT call `setState` directly. Verify auxiliary effects inside it still don't widen to a single outer try/catch — each is its own block.
5. **Web equivalent (`apps/web/src/routes/`)** — looser contract, but live-broadcaster + RunMap have similar concerns. Walk `apps/web/src/lib/components/RunMap.svelte` for unsafe rendering paths.

## Report

- **High** — an auxiliary failure can crash or freeze a core layer.
- **Medium** — silent swallow that masks a regression (e.g. TTS unconditionally fails and we never know).
- **Low** — auxiliary effect with no try/catch but on a path that genuinely cannot throw (rare; document why).

For each: file:line of the effect, the missing or incorrect wrap, the layer it could break.

## Useful starting points

- `docs/conventions.md` § "Layered resilience"
- `docs/run_recording.md` § "Layering" — the L0–L4 table
- `apps/mobile_android/lib/screens/run_screen.dart` — the highest-stakes file
- `apps/mobile_android/CLAUDE.md` § "Hot-path exception"
- `apps/mobile_android/test/architecture_guards_test.dart` — existing guards

Read-only audit.
