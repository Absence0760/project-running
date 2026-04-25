# Android services & stores audit

13 findings across 8 files — one active bug that silently corrupts race-state polling, one broken TTS utterance, one import data-loss path, and ten layered-resilience violations.

---

## High

### H1. `_refresh()` catch swallows the live-race polling loop silently
**File**: `apps/mobile_android/lib/race_controller.dart:141`
**Category**: bug / layered-resilience violation
**Problem**: The periodic 15-second refresh that keeps race participant positions and lap times current is wrapped in `catch (_) {}` with no `debugPrint`. Any Supabase error, network timeout, or deserialization failure leaves the UI frozen on stale state with no diagnostic trace. During an active recording session this violates the layered-resilience contract: an L3 network failure quietly kills all race overlay data.
**Remediation**:
```diff
- } catch (_) {
+ } catch (e) {
+   debugPrint('[RaceController._refresh] $e');
  }
```

---

## Medium

### M1. TTS pace utterance drops "minutes"/"seconds" labels
**File**: `apps/mobile_android/lib/audio_cues.dart:126-129`
**Category**: bug
**Problem**: When a workout-step pace has a non-zero seconds component the spoken string omits the word "minutes" for the minute part: `"5 30 per kilometre"` instead of `"5 minutes 30 seconds per kilometre"`. The zero-seconds branch correctly says `"5 minutes per kilometre"`.
**Remediation**:
```diff
- final paceTail = paceS == 0
-     ? '$paceM minutes per kilometre'
-     : '$paceM $paceS per kilometre';
+ final paceTail = paceS == 0
+     ? '$paceM minutes per kilometre'
+     : '$paceM minutes $paceS seconds per kilometre';
```

### M2. Strava CSV distance column name mismatch causes zero-distance imports
**File**: `apps/mobile_android/lib/strava_importer.dart:52`
**Category**: bug
**Problem**: After header lowercasing the code does `header.indexOf('distance')`. Strava's bulk export uses the column name `Distance (km)`, which lowercases to `'distance (km)'` — that does not match `'distance'`, so `distanceIdx` becomes `-1`. When no GPX/TCX is present (or the file also lacks distance) the imported run gets `distanceMetres: 0`. The web importer explicitly handles this: `find('Distance', 'Distance (km)')`.
**Remediation**:
```diff
- final distanceIdx = header.indexOf('distance');
+ final distanceIdx = header.indexOf('distance (km)') != -1
+     ? header.indexOf('distance (km)')
+     : header.indexOf('distance');
```
If the `(km)` variant is matched, the existing `csvDistance * 1000` multiplication at the use-site is correct (web comment: `// CSV is km`). Verify by confirming the multiplication is only applied when the column was found — it currently is, at the same guarded block.

### M3. `pushPing()` catch swallows without debugPrint
**File**: `apps/mobile_android/lib/race_controller.dart:212`
**Category**: layered-resilience violation
**Problem**: `catch (_) {}` — conventionally best-effort, but conventions require `debugPrint` even for best-effort auxiliary effects so failures are visible in logcat.
**Remediation**:
```diff
- } catch (_) {}
+ } catch (e) {
+   debugPrint('[RaceController.pushPing] $e');
+ }
```

### M4. `submitResult()` catch swallows without debugPrint
**File**: `apps/mobile_android/lib/race_controller.dart:236`
**Category**: layered-resilience violation
**Remediation**:
```diff
- } catch (_) {}
+ } catch (e) {
+   debugPrint('[RaceController.submitResult] $e');
+ }
```

### M5. `submitEventResult` backlink update catch swallows without debugPrint
**File**: `apps/mobile_android/lib/social_service.dart:534`
**Category**: layered-resilience violation
**Problem**: The `runs.update(event_id)` backlink write is best-effort but the silent `catch (_) {}` means a failed write is undetectable in production logs.
**Remediation**:
```diff
- } catch (_) {}
+ } catch (e) {
+   debugPrint('[SocialService.submitEventResult backlink] $e');
+ }
```

### M6. `fetchRaceSession` catch swallows without debugPrint
**File**: `apps/mobile_android/lib/social_service.dart:555`
**Category**: layered-resilience violation
**Remediation**:
```diff
- } catch (_) { return null; }
+ } catch (e) {
+   debugPrint('[SocialService.fetchRaceSession] $e');
+   return null;
+ }
```

### M7. `fetchPlanForWorkout` catch swallows without debugPrint
**File**: `apps/mobile_android/lib/training_service.dart:294`
**Category**: layered-resilience violation
**Remediation**:
```diff
- } catch (_) {
-   return null;
- }
+ } catch (e) {
+   debugPrint('[TrainingService.fetchPlanForWorkout] $e');
+   return null;
+ }
```

### M8. `_decodeTrack()` catch swallows without debugPrint
**File**: `apps/mobile_android/lib/backup.dart:448`
**Category**: layered-resilience violation
**Problem**: A corrupted track in a backup archive silently produces an empty list with no log entry. Restore appears to succeed but the run has no GPS trace.
**Remediation**:
```diff
- } catch (_) {
-   return const [];
- }
+ } catch (e) {
+   debugPrint('[backup._decodeTrack] $e');
+   return const [];
+ }
```

### M9. `mock_data.dart` is dead code with a hardcoded past date
**File**: `apps/mobile_android/lib/mock_data.dart`
**Category**: dead-code
**Problem**: Zero files in `apps/mobile_android/lib/` import this file. It contains `DateTime(2026, 4, 8)` hardcoded as "now" (already 17 days in the past as of audit date). CLAUDE.md describes it as "fallback data when Supabase returns nothing (dev only)" but it is not wired to anything.
**Remediation**: Delete `apps/mobile_android/lib/mock_data.dart`. No callers exist; no stub or replacement needed.

---

## Low

### L1. `recoveryAdvice()` no-data string diverges from web
**File**: `apps/mobile_android/lib/fitness.dart:212`
**Category**: inconsistency
**Problem**: Dart returns `'log a few runs and try again'`; web (`fitness.ts`) returns `'Not enough data yet — log a few runs with HR and try again.'` The web version correctly mentions HR, which is the actual constraint (the function needs HR-bearing runs).
**Remediation**:
```diff
- return 'log a few runs and try again';
+ return 'Not enough data yet — log a few runs with HR and try again.';
```

### L2. `disconnect()` catch swallows without debugPrint
**File**: `apps/mobile_android/lib/ble_heart_rate.dart:136`
**Category**: layered-resilience violation
**Remediation**:
```diff
- } catch (_) {
-   // best-effort
- }
+ } catch (e) {
+   debugPrint('[BleHeartRate.disconnect] $e');
+ }
```

### L3. `_trimToBudget` inner loop catch swallows without debugPrint
**File**: `apps/mobile_android/lib/tile_cache.dart` (inner per-file delete loop)
**Category**: layered-resilience violation
**Problem**: Individual tile-file delete failures are silently ignored inside the trim loop. The outer catch does log, but individual failures within the loop do not, so it's impossible to tell from logs which specific files failed to delete.
**Remediation**: Add `debugPrint('[TileCache._trimToBudget] delete failed: $e')` inside the inner catch block.

---

## Counts: H: 1  M: 8  L: 3
