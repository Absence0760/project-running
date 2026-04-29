# Data / sync / stores — audit

Files reviewed:
- `apps/mobile_android/lib/local_run_store.dart`
- `apps/mobile_android/lib/local_route_store.dart`
- `apps/mobile_android/lib/sync_service.dart`
- `apps/mobile_android/lib/background_sync.dart`
- `apps/mobile_android/lib/settings_sync.dart`
- `apps/mobile_android/lib/backup.dart`
- `apps/mobile_android/lib/tile_cache.dart`
- `apps/mobile_android/lib/wear_auth_bridge.dart`
- `apps/mobile_android/lib/strava_importer.dart`
- `apps/mobile_android/lib/health_connect_importer.dart`
- `apps/mobile_android/test/local_run_store_test.dart`

Also read for context:
- `packages/api_client/lib/src/api_client.dart`
- `apps/mobile_android/lib/screens/import_screen.dart`

Date: 2026-04-21
Auditor scope: mobile_android persistence + sync

---

## Summary

The persistence layer is structurally sound: the sidecar sync-state file, the newer-wins conflict resolution, the batch-upload path, and the layered resilience in `TileCache` and `WearAuthBridge` are all well-implemented. Four issues are worth fixing. Two are correctness bugs (`unsyncedCount` can go negative; `StravaImporter` and `HealthConnectImporter` emit `external_id` values that don't match the documented format, breaking deduplication). One is a resilience violation (`SettingsSyncService.onSignedIn` has no timeout and will stall the sign-in path indefinitely if the backend is unreachable). One is a silent swallow in `_decodeTrack` that discards the error without a `debugPrint`. Remaining items are low-severity: a stale doc reference, a WHAT comment, and a `CachePolicy.forceCache` note that is deferred by the CLAUDE.md policy.

---

## Findings

### P0 — bugs / data loss / security

**P0.1 — `external_id` prefix missing in both importers — deduplication is broken**

- `apps/mobile_android/lib/strava_importer.dart:169`
- `apps/mobile_android/lib/health_connect_importer.dart:85`

`docs/integrations.md` (§ Deduplication strategy) mandates:
```
strava         → external_id = strava:{activity-id}
healthconnect  → external_id = healthconnect:{hc-uuid}
```

`StravaImporter` sets `externalId: stravaId` where `stravaId` is a bare numeric string from the CSV (e.g. `"12345678"`). `HealthConnectImporter` sets `externalId: point.uuid` — a bare UUID with no prefix.

The server upserts on `external_id`; the partial unique index is `where external_id is not null`. A bare Strava activity ID collides with nothing (no other source writes bare numerics), so re-importing the same Strava ZIP produces duplicate rows rather than updating them. A bare Health Connect UUID has the same problem against any future Health Connect re-import. Both importers are also inconsistent with the `strava-webhook` Edge Function, which writes `strava:{activity.id}` — so a run that arrives via webhook and then via a ZIP import creates two rows for the same activity.

Fix `strava_importer.dart`:
```diff
-      externalId: stravaId,
+      externalId: 'strava:$stravaId',
```

Fix `health_connect_importer.dart`:
```diff
-          externalId: point.uuid,
+          externalId: 'healthconnect:${point.uuid}',
```

Risk: if any user has already imported runs with the old bare IDs, those rows keep the wrong `external_id`. The fix prevents future duplicates; a one-time migration script would be needed to correct existing rows (acceptable for a pre-launch codebase).

Verification: write a unit test in `test/` that instantiates `StravaImporter.importFromZip` with a minimal synthetic ZIP and asserts `result.runs.first.externalId.startsWith('strava:')`. Same for `HealthConnectImporter` with a mocked `Health` instance.

---

**P0.2 — `unsyncedCount` can return a negative value**

- `apps/mobile_android/lib/local_run_store.dart:38`

```dart
int get unsyncedCount => _runs.length - _syncedIds.length;
```

`_syncedIds` is a `Set<String>`. It is populated at startup from the sidecar file. If the sidecar contains IDs for runs whose JSON files have since been deleted from disk (e.g. the user cleared app storage mid-session, or the disk ran out of space while the sidecar was being written after the file delete), `_syncedIds` grows larger than `_runs`. The result is a negative badge count displayed on the Runs screen (`runs_screen.dart:411: Text('$unsyncedCount')`).

More critically, `unsyncedRuns` (line 35–36) is computed correctly via `_runs.where(...)`, so syncing is unaffected — only the count display is wrong. Still, a negative badge is a visible bug.

Fix:
```diff
-  int get unsyncedCount => _runs.length - _syncedIds.length;
+  int get unsyncedCount => unsyncedRuns.length;
```

This is O(n) versus O(1), but `_runs` is bounded by on-disk run count, and the getter is called only on UI rebuilds triggered by `notifyListeners`.

Risk: none — `unsyncedRuns` is the authoritative answer and is already used for the sync-loop input. The old formula was an optimisation that assumed `_syncedIds` is always a subset of `_runs`, which is not guaranteed.

Verification: add a test to `local_run_store_test.dart` — write a `synced_ids.json` sidecar with an ID that has no corresponding `.json` run file, call `init`, assert `unsyncedCount >= 0`.

---

### P1 — resilience violations, correctness

**P1.1 — `SettingsSyncService.onSignedIn` has no timeout — hangs sign-in indefinitely**

- `apps/mobile_android/lib/settings_sync.dart:35–49`

```dart
Future<void> onSignedIn() async {
  try {
    _settings = await SettingsService(...).load();
    ...
  } catch (e) {
    _synced = false;
    _lastError = e.toString();
  }
  notifyListeners();
}
```

This is the same shape as the clubs-screen load that commits 3d3ea75 and a3116ec identified as broken. `SettingsService.load()` hits Supabase; if the backend is unreachable, supabase-dart's HTTP call does not resolve on its own for minutes. `onSignedIn` is called from `main.dart`'s auth-state listener after a successful sign-in — any code that awaits it (or depends on `synced == true`) stalls for the duration.

Apply the reference pattern: wrap `SettingsService(...).load()` with `.timeout(kBackendLoadTimeout)`, catch `TimeoutException` separately, and log with `debugPrint`. The fallback state (`_synced = false`) is already correct — settings just won't roam on this launch, which is acceptable.

```diff
+import 'dart:async';
+import '../widgets/error_state.dart'; // for kBackendLoadTimeout

 Future<void> onSignedIn() async {
   try {
     _settings = await SettingsService(
       deviceId: preferences.deviceId,
       platform: _platformTag(),
       label: _deviceLabel(),
-    ).load();
+    ).load().timeout(kBackendLoadTimeout);
     _applyUniversal(_settings!.universal);
     _synced = true;
     _lastError = null;
+  } on TimeoutException catch (e) {
+    debugPrint('SettingsSyncService.onSignedIn timed out: $e');
+    _settings = null;
+    _synced = false;
+    _lastError = 'Settings sync timed out';
   } catch (e) {
     _settings = null;
     _synced = false;
     _lastError = e.toString();
   }
   notifyListeners();
 }
```

Risk: none — the timeout converts an indefinite hang into a fast degraded state. Settings fall back to local preferences, which is the stated design.

Verification: run the app with the local Supabase stopped, sign in with the seed user. Confirm the app reaches the home screen within 15 s instead of hanging.

---

**P1.2 — `_decodeTrack` silently swallows errors without logging**

- `apps/mobile_android/lib/backup.dart:428–451`

```dart
} catch (_) {
  return const [];
}
```

This is inside `_decodeTrack`, called during `_restoreOffline` for each run in the backup. If a track is corrupt (truncated gzip, wrong encoding, malformed JSON), the catch swallows the error entirely — the run is saved without GPS data and the user has no diagnostic signal. This violates the project convention ("never silently swallow to a lower level") and makes debugging restore failures opaque.

Fix:
```diff
-    } catch (_) {
-      return const [];
+    } catch (e) {
+      debugPrint('BackupService._decodeTrack: failed to decode track for run $runId: $e');
+      return const [];
     }
```

Risk: none — the recovery path (return empty list) is unchanged.

Verification: write a test that passes a backup archive with a deliberately corrupt `tracks/run-id.json.gz` entry and verifies that the run is still imported (with empty track) and that the `debugPrint` is reachable (assert no exception thrown).

---

**P1.3 — `SyncService` and `background_sync` mark all runs as synced even when `saveRunsBatch` partially fails**

- `apps/mobile_android/lib/sync_service.dart:69–70`
- `apps/mobile_android/lib/background_sync.dart:37–38`

```dart
await api.saveRunsBatch(unsynced);
await runStore.markManySynced(unsynced.map((r) => r.id));
```

`saveRunsBatch` in `api_client` uploads tracks in parallel groups and upserts row chunks. If any individual track upload or row upsert throws, `saveRunsBatch` propagates the exception, so `markManySynced` is never reached — no runs are marked synced. That is correct.

However, `saveRunsBatch` does not guarantee transactional success at the granularity of individual rows: if the first chunk of 100 rows upserts successfully but the second chunk fails, the exception causes the function to rethrow, but the first chunk's rows are already in the DB. `markManySynced` is never called (correct), so those 100 runs will be re-uploaded on the next sync. Because the row upsert uses `onConflict: id`, the re-upload is idempotent for the row data. Track uploads use `upsert: true` (`api_client.dart:335`), so they too are safe to repeat.

The current behaviour (retry the full batch) is safe due to idempotent upserts. The issue is that after partial success, every subsequent sync attempt re-uploads the already-synced rows' tracks, wasting bandwidth. This is a mild correctness deficiency, not data loss.

Document this in a short comment above the `markManySynced` call so the next reader doesn't have to reconstruct the reasoning. No code change is required unless granular success tracking is added to `saveRunsBatch`'s return type.

---

### P2 — maintainability, duplication, code smell

**P2.1 — `backup.dart` references a doc that does not exist**

- `apps/mobile_android/lib/backup.dart:17`

```dart
/// See [docs/backup_restore.md](../../../docs/backup_restore.md) for the
/// archive layout.
```

`docs/backup_restore.md` exists as an empty file (the `ls` shows it present but git status shows it as untracked/unknown). Even if non-empty, the doc reference in the Dart source will silently go stale. Either:
- Remove the cross-reference and put the archive layout in the docstring itself (it is short: `manifest.json`, `runs.json`, `routes.json`, `profile.json`, `tracks/<id>.json.gz`).
- Or keep the reference only if the file is fully written.

The CLAUDE.md rule is: "if a doc describes behaviour you just changed, update it." The reverse is also true: don't reference docs that don't exist.

---

**P2.2 — `TileCache` uses `CachePolicy.forceCache` — tiles never re-validate after 30 days**

- `apps/mobile_android/lib/tile_cache.dart:114–116`

```dart
maxStale: const Duration(days: 30),
policy: CachePolicy.forceCache,
```

`CachePolicy.forceCache` serves stale content without ever re-validating against the tile server, regardless of `Cache-Control` headers. Combined with `maxStale: 30 days`, a tile is served from disk for up to 30 days even if MapTiler releases updated imagery. For a running app that re-runs the same roads, this is usually fine. For users in areas with active construction or new development, map tiles can be weeks out of date with no mechanism for refresh.

The correct policy for offline-first with background validation is `CachePolicy.request`, which honours `Cache-Control` headers (tile servers usually set `max-age=86400`). `forceCache` is appropriate for tiles explicitly downloaded for offline use, not for general browsing.

This is a P2 because it is a product-quality issue (stale maps), not a bug or data loss. Change `forceCache` to `request` to restore standard HTTP cache semantics.

Note: CLAUDE.md marks `withOpacity` and similar deprecations as deliberate technical debt — this is different in kind (a wrong cache policy choice, not a deprecated API).

---

**P2.3 — WHAT comment on `_saveImportedRuns` loop (import_screen.dart)**

- `apps/mobile_android/lib/screens/import_screen.dart:65–66`

```dart
/// Common save loop used by both Strava and Health Connect imports.
/// Saves each run locally, then batch-pushes to the cloud if signed in.
```

This is a WHAT comment: it narrates what the code does, which the code already says. The function name and body are self-explanatory. Per `docs/conventions.md § Comments`: "never explain what well-named code already says." Delete both lines.

(Noted because `import_screen.dart` was read as part of cross-referencing the importer callers. It is not in the formal scope, so the implementer should verify relevance before acting.)

---

### P3 — nits

**P3.1 — `local_run_store.dart` inner `catch (_)` on file delete is legitimate but inconsistent**

- `apps/mobile_android/lib/local_run_store.dart:227`

```dart
try {
  await file.delete();
} catch (_) {}
```

This is inside the outer `catch (e)` of `loadInProgress` — it deletes a corrupt in-progress file as a best-effort cleanup. The outer catch already `debugPrint`s the real error. Swallowing the inner delete failure is acceptable (a failed delete just means the corrupt file persists, which will be caught again next launch). However it is inconsistent with the project rule against bare `catch (_) {}`.

Fix: change to `catch (e) { debugPrint('...'); }` for consistency, even though the failure is benign.

```diff
       try {
         await file.delete();
-      } catch (_) {}
+      } catch (e) {
+        debugPrint('Failed to delete corrupt in-progress file: $e');
+      }
```

---

**P3.2 — `background_sync.dart` always returns `true` from the WorkManager task**

- `apps/mobile_android/lib/background_sync.dart:46`

The outer catch at line 43 logs the error and then falls through to `return true` at line 46. WorkManager interprets `true` as success and will not retry the task. If `ApiClient.initialize` or the connectivity check fails (e.g. the `.env.local` file is missing in release builds), the background sync silently stops working until the next scheduled invocation rather than triggering a retry.

This is a deliberate choice with tradeoffs: returning `false` would cause WorkManager to retry with its own backoff, which could be excessive. If a permanent error (missing config) occurs, retrying won't help. Document the reasoning in a short comment at the `return true` site so the next reader doesn't "fix" it:

```dart
// Always return true. Returning false tells WorkManager to retry —
// not useful here because transient network failures will be caught
// on the next hourly invocation anyway, and permanent errors (missing
// env, no session) are not recoverable by retry.
return true;
```

---

## Stats

- P0: 2
- P1: 3
- P2: 3
- P3: 2
