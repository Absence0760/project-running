# Screens + UX — audit

Files reviewed:
- `apps/mobile_android/lib/main.dart`
- `apps/mobile_android/lib/screens/home_screen.dart`
- `apps/mobile_android/lib/screens/dashboard_screen.dart`
- `apps/mobile_android/lib/screens/runs_screen.dart`
- `apps/mobile_android/lib/screens/run_detail_screen.dart`
- `apps/mobile_android/lib/screens/routes_screen.dart`
- `apps/mobile_android/lib/screens/route_detail_screen.dart`
- `apps/mobile_android/lib/screens/explore_routes_screen.dart`
- `apps/mobile_android/lib/screens/add_run_screen.dart`
- `apps/mobile_android/lib/screens/onboarding_screen.dart`
- `apps/mobile_android/lib/screens/sign_in_screen.dart`
- `apps/mobile_android/lib/screens/import_screen.dart`
- `apps/mobile_android/lib/screens/period_summary_screen.dart`
- `apps/mobile_android/lib/screens/settings_screen.dart`
- `apps/mobile_android/lib/widgets/collapsible_panel.dart`
- `apps/mobile_android/lib/widgets/error_state.dart`
- `apps/mobile_android/lib/settings_sync.dart`
- `apps/mobile_android/lib/preferences.dart` (subset)
- `apps/mobile_android/test/period_summary_test.dart`
- `apps/mobile_android/test/architecture_guards_test.dart`
- `apps/mobile_android/test/metadata_registry_test.dart`

Reference commits read: `3d3ea75` (clubs offline resilience), `a3116ec` (extend pattern to 6 screens)
Reference docs read: `docs/settings.md`, `docs/conventions.md`, `docs/flows.md`

Date: 2026-04-21
Auditor scope: mobile_android non-recording screens + shared UX widgets

## Summary

The resilience migration from commits `3d3ea75` and `a3116ec` was applied correctly to the screens it targeted (clubs, plans, explore routes, event detail, club detail, plan detail). The shared `ErrorState` widget and `kBackendLoadTimeout` constant are well-factored. However, four screens that perform backend operations are not covered: `routes_screen.dart` (`_fetchRemoteRoutes`) has a silent-swallow catch with no `_error` state, `route_detail_screen.dart` (`_fetchReviews`) has the same shape, and `run_detail_screen.dart` (`_maybeFetchTrack`) has no timeout. None of these was included in the `a3116ec` migration scope, so the omission is a gap rather than a regression, but it is inconsistent with the project's stated resilience contract.

Settings sync has a correctness bug: `audioCues`, `advancedGps`, `splitIntervalMetres`, and `targetPaceSecPerKm` are toggled locally but never pushed to `SettingsService`. The registry in `docs/settings.md` defines `voice_feedback_enabled`, `auto_pause_enabled`, and `auto_pause_speed_mps` as syncable; none of these are wired. Only `preferred_unit` is actually dual-written. This is not a pre-existing known gap — the settings screen claims sync via the subtitle "synced to your other devices" for the unit toggle specifically, but the remaining controls carry no such caveat and a user would reasonably expect them to roam.

Several minor but concrete issues exist: a swallowed delete-error in `runs_screen.dart`, a `withOpacity` usage in `run_detail_screen.dart`, a `catch (_) {}` without a stack trace in `route_detail_screen.dart`, and the `_HeartRateTile` spinner can stay true forever if `pairedName()` throws.

---

## Findings

### P0 — bugs / data loss / security

**P0-1: `runs_screen.dart` silently swallows individual remote-delete errors, leaving the UI inconsistent**

- `apps/mobile_android/lib/screens/runs_screen.dart:287-291`

The batch-delete path calls `api.deleteRun(run)` inside `for (final run in runsToDelete)` with `catch (_) {}`. If the remote delete fails (network error, RLS rejection, stale auth), the loop continues: the local store then deletes the run via `widget.runStore.deleteMany(ids)` at line 293. The run is gone locally but still exists in the cloud. On the next `_fetchRemote` call it re-appears in the user's list. No error is surfaced; no diagnostic is logged.

```dart
      for (final run in runsToDelete) {
        try {
          await api.deleteRun(run);
        } catch (_) {}   // <- silent swallow, no debugPrint, no error state
      }
    }
    await widget.runStore.deleteMany(ids);
```

Replace with `catch (e) { debugPrint('deleteRun failed for ${run.id}: $e'); }` at minimum, and either (a) skip the local delete for that run so the store stays consistent with the remote, or (b) record it in a list and show a snackbar after the loop if any remote delete failed. Silently deleting locally while the remote survives is data-inconsistency, not "best effort".

---

### P1 — resilience violations, correctness

**P1-1: `routes_screen.dart` `_fetchRemoteRoutes` swallows errors silently and has no error state**

- `apps/mobile_android/lib/screens/routes_screen.dart:55-69`

Pattern after `a3116ec` is: `_loading = true; _error = null; try { ... } on TimeoutException ... catch (e, s) { debugPrint ...; setState _error = ...; }`. `_fetchRemoteRoutes` has none of this:

```dart
    try {
      final remote = await api.getRoutes();
      for (final r in remote) {
        await widget.routeStore.save(r);
      }
    } catch (e) {
      debugPrint('Fetch routes failed: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
```

No timeout on `api.getRoutes()` — a hanging request will hold `_syncing = true` indefinitely (no `kBackendLoadTimeout`). No `_error` state, no user-visible retry affordance. The screen just shows whatever is locally cached with no indication that the sync failed.

Apply the standard pattern: add `String? _error`, apply `.timeout(kBackendLoadTimeout)`, catch `TimeoutException` separately, set `_error`, and render `ErrorState(message: _error!, onRetry: _fetchRemoteRoutes)` in the body when `_error != null`.

---

**P1-2: `route_detail_screen.dart` `_fetchReviews` swallows exceptions with no stack trace and no timeout**

- `apps/mobile_android/lib/screens/route_detail_screen.dart:65-88`

```dart
    } catch (_) {      // <- bare catch, no logging, no stack trace
      if (mounted) {
        setState(() {
          _loadingReviews = false;
          _reviewsOffline = true;
        });
      }
    }
```

The `catch (_)` is a project convention violation (conventions.md: "A blanket `try { ... } catch (_) {}` is a bug in waiting"). The actual error reason — whether it was a network timeout, an RLS error, or a Supabase 500 — is discarded. Also, there is no `.timeout(kBackendLoadTimeout)` on `api.getRouteReviews(...)`, so a hanging request holds `_loadingReviews = true` indefinitely and shows a spinner with no retry.

Additionally, `_remove` at line 561 also has `catch (_) { setState(() => _saving = false); }` with the same problem.

Fix `_fetchReviews`: add `catch (e, s) { debugPrint('fetchReviews failed: $e\n$s'); ... }`, add `.timeout(kBackendLoadTimeout)` to the API call, and show a retry button instead of just the "Reviews unavailable offline" message.

Fix `_remove`: change `catch (_)` to `catch (e, s)` with a `debugPrint`.

---

**P1-3: `run_detail_screen.dart` `_maybeFetchTrack` has no timeout — spinner can be permanent**

- `apps/mobile_android/lib/screens/run_detail_screen.dart:68-104`

`api.fetchTrack(run)` has no `.timeout(kBackendLoadTimeout)`. A network failure will resolve eventually with a thrown exception (caught and handled at line 98-100), but a stalled connection will hold `_loadingTrack = true` for minutes. The small card at top-right showing "Loading GPS data..." stays there. There is no retry affordance once `_trackFetchFailed` is set — the user just sees "GPS track unavailable offline" with no way to try again without leaving the screen and re-entering.

```dart
      final track = await api.fetchTrack(run);   // no timeout
```

Add `.timeout(kBackendLoadTimeout)` on the `fetchTrack` call. Add a retry button to the `_trackFetchFailed` overlay card (calling `_maybeFetchTrack` after resetting `_trackFetchFailed = false`).

---

**P1-4: `settings_screen.dart` — `audioCues`, `advancedGps`, `splitIntervalMetres`, `targetPaceSecPerKm` are never pushed to `SettingsService`**

- `apps/mobile_android/lib/screens/settings_screen.dart:359-403`
- `apps/mobile_android/lib/settings_sync.dart:56-63`

`SettingsSyncService.pushPreferredUnit()` is the only push method. It is called from the "Use miles" toggle's `onChanged`. The other four settings controls (`audioCues`, `advancedGps`, `splitIntervalMetres`, `targetPaceSecPerKm`) call only into `prefs` (SharedPreferences) and never call any `settingsSync` method. The settings registry in `docs/settings.md` lists `voice_feedback_enabled`, `voice_feedback_interval_km`, `auto_pause_enabled`, and `auto_pause_speed_mps` as syncable (`D` or `UD`). Neither `audioCues` nor `advancedGps` map to any synced key today.

This means a user who configures audio cues or GPS mode on one Android device and signs in on a second Android device gets the defaults, not their settings. No error is surfaced — this silently fails to sync.

The fix has two parts:
1. Add a `pushAudioCues()` method to `SettingsSyncService` that writes `voice_feedback_enabled` to the per-device bag, and call it from the toggle's `onChanged`.
2. Add a `pushAdvancedGps()` method (or include it in the device bag) and call it from the Advanced GPS toggle.

`splitIntervalMetres` and `targetPaceSecPerKm` have no registry entry in `docs/settings.md` — either add them or document that they are intentionally device-local.

---

**P1-5: `_HeartRateTile` loading spinner is permanent if `pairedName()` throws**

- `apps/mobile_android/lib/screens/settings_screen.dart:479-496`

```dart
  Future<void> _refresh() async {
    final name = await widget.heartRate.pairedName();
    if (!mounted) return;
    setState(() {
      _pairedName = name;
      _loading = false;   // only set here — never set in a catch
    });
  }
```

There is no try/catch. If `BleHeartRate.pairedName()` throws (e.g. the BLE system service is unavailable), `_loading` stays `true` and the tile shows "Checking…" permanently. The tile also drives a scan-sheet that the user can no longer dismiss without restarting the app.

Wrap the body of `_refresh` in try/catch and set `_loading = false` in the catch (and optionally set `_pairedName = null`):

```diff
  Future<void> _refresh() async {
+   try {
      final name = await widget.heartRate.pairedName();
      if (!mounted) return;
      setState(() {
        _pairedName = name;
        _loading = false;
      });
+   } catch (e) {
+     debugPrint('HeartRate.pairedName failed: $e');
+     if (mounted) setState(() => _loading = false);
+   }
  }
```

---

**P1-6: `onboarding_screen.dart` — `setOnboarded(true)` is called even when the user denies both location permissions**

- `apps/mobile_android/lib/screens/onboarding_screen.dart:57-60`

```dart
      await Permission.location.request();
      await Permission.locationAlways.request();
      await widget.preferences.setOnboarded(true);
      widget.onDone();
```

`Permission.request()` returns the new status, but the return values are discarded. If the user denies both, `setOnboarded(true)` is still called and the user is dropped into `HomeScreen` without GPS permission. The run screen will then fail to record and surface the permission error inline — which is tolerable — but there is no re-path back through permission granting without re-installing the app or going to Settings manually.

The fix: check the returned status. If `location` is denied, do not call `setOnboarded(true)` yet — leave the user on the permission page with a message explaining what is needed and a "Try again" button that re-calls `Geolocator.requestPermission()`. Only set `onboarded` after at least `Permission.location` is granted.

---

**P1-7: `period_summary_screen.dart` — week navigation is DST-unsafe**

- `apps/mobile_android/lib/screens/period_summary_screen.dart:229-231`

```dart
        case PeriodType.week:
          _anchor = _anchor.subtract(const Duration(days: 7));
```

`_anchor` is always a local `DateTime`. Subtracting exactly 7 days as wall-clock duration is wrong across a DST boundary: on the night clocks spring forward, 7 × 24 h = 168 h produces an anchor 1 h off midnight, so `periodStart` (which calls `weekStartLocal`) may land on the wrong week. For example, in a UTC-5/UTC-4 spring-forward zone, navigating backward across the boundary yields an anchor of `2026-03-08 23:00` instead of `2026-03-09 00:00`, and `weekStartLocal` of that anchor is a week earlier than intended.

Concrete fix: instead of subtracting 7 days, compute the previous Monday directly:

```diff
        case PeriodType.week:
-         _anchor = _anchor.subtract(const Duration(days: 7));
+         final prevWeekStart = periodStart(PeriodType.week, _anchor)
+             .subtract(const Duration(days: 1));
+         _anchor = periodStart(PeriodType.week, prevWeekStart);
```

This anchors on the previous Monday's midnight in local time regardless of DST. The same issue applies to the `_next` path (`_anchor.add(const Duration(days: 7))`).

---

**P1-8: `add_run_screen.dart` `_save` calls `_formKey.currentState!.validate()` but then redundantly re-parses outside the form validators**

- `apps/mobile_android/lib/screens/add_run_screen.dart:156-161`

```dart
    if (!_formKey.currentState!.validate()) return;
    final distance = _parseDistanceMetres(_distanceCtl.text);
    final duration = _parseDuration();
    if (distance == null || duration == null) return;
```

The `validate()` call runs the form validators, which already call `_parseDistanceMetres` and `_parseDuration`. The `null` check immediately after is therefore redundant — if `validate()` returned true, those parse calls cannot return null. This is not a bug in isolation, but the double-parse makes `_save` resilient to a future change that removes a validator while leaving the null guard, which would silently accept bad input. The correct fix is to capture the parsed values inside the validators and surface them rather than re-parsing:

Either (a) store the parsed distance/duration in state when the validators run (idiomatic Flutter `FormField` approach), or (b) remove the redundant null checks and add a comment that the parsed values are trusted because `validate()` passed. The current shape is a maintenance hazard.

---

### P2 — maintainability, duplication, code smell

**P2-1: `routes_screen.dart` `_fetchRemoteRoutes` missing `dart:async` import for `TimeoutException` when the fix is applied**

- `apps/mobile_android/lib/screens/routes_screen.dart:1`

When P1-1 is fixed and `.timeout(kBackendLoadTimeout)` is added, `TimeoutException` must be caught explicitly. `dart:async` is not yet imported. Add `import 'dart:async';` alongside the fix.

---

**P2-2: `run_detail_screen.dart` split-bar uses `withOpacity` (deprecated)**

- `apps/mobile_android/lib/screens/run_detail_screen.dart:852`

```dart
              : theme.colorScheme.primary.withOpacity(0.5);
```

The project acknowledges `withOpacity` as deprecated tech debt (CLAUDE.md) but has not swept it here. This is a P3 in isolation, promoted to P2 because `run_detail_screen.dart` is the highest-traffic detail screen and the `_ElevationPacePainter` also uses `withOpacity` at lines 1377, 1379, 1381, 1440. All four should become `.withValues(alpha: ...)` in a single sweep. No behaviour change.

```diff
-  theme.colorScheme.primary.withOpacity(0.5)
+  theme.colorScheme.primary.withValues(alpha: 0.5)
```

---

**P2-3: `import_screen.dart` uses `withOpacity` on two icon backgrounds**

- `apps/mobile_android/lib/screens/import_screen.dart:178, 243`

```dart
color: const Color(0xFFFC4C02).withOpacity(0.15),   // line 178
color: theme.colorScheme.primary.withOpacity(0.15),  // line 243
```

Same tech-debt flag as P2-2. Convert to `.withValues(alpha: 0.15)` in the same sweep.

---

**P2-4: `route_detail_screen.dart` `build` method shadows `isOwner` from widget with a local that has different semantics**

- `apps/mobile_android/lib/screens/route_detail_screen.dart:196`

```dart
    final isOwner = widget.apiClient?.userId != null;  // any signed-in user
```

The class-level getter is:
```dart
  bool get _isOwner => widget.isOwner && widget.apiClient?.userId != null;
```

The local `isOwner` (note: no underscore) in `build` only checks whether _a_ user is signed in, not whether this user owns the route. It is used to decide whether to show the public/private toggle and the delete button. This means any signed-in user sees the ownership controls for a route they don't own when the `ExploreRoutesScreen` pushes `RouteDetailScreen` without setting `isOwner: true`.

In practice, `ExploreRoutesScreen` at line 579 calls `RouteDetailScreen(route: ..., isOwner: false [default])`, so `widget.isOwner` is false, and `_isOwner` correctly returns false. But `isOwner` (the local) is true for any authenticated user and gates the appbar `IconButton` and delete action at lines 201-211. The actions are visible but the backend (RLS) will reject the operations — the UX shows controls that don't work.

Replace the local `isOwner` with `_isOwner` throughout `build`:

```diff
-   final isOwner = widget.apiClient?.userId != null;
+   final isOwner = _isOwner;
```

---

**P2-5: `settings_screen.dart` dark-mode toggle does not persist through `Preferences`**

- `apps/mobile_android/lib/screens/settings_screen.dart:387-393`

```dart
          SwitchListTile(
            title: const Text('Dark mode'),
            value: _darkMode,
            onChanged: (v) {
              setState(() => _darkMode = v);
              themeModeNotifier.value = v ? ThemeMode.dark : ThemeMode.light;
            },
          ),
```

`themeModeNotifier` is a file-level `ValueNotifier` in `main.dart` initialised to `ThemeMode.dark`. The toggle changes it in-memory, but there is no `await prefs.setDarkMode(v)` call and no `Preferences` key for dark mode. Restarting the app resets it to dark always. This is a gap: the setting appears permanent to the user but is actually session-only.

Add a `Preferences` key (`dark_mode`) with a getter/setter, read it in `_RunAppState` to initialise `themeModeNotifier`, and write it from the toggle's `onChanged`.

---

**P2-6: `explore_routes_screen.dart` `_loadPopularTags` silently swallows all errors**

- `apps/mobile_android/lib/screens/explore_routes_screen.dart:64-71`

```dart
    try {
      final tags = await api.fetchPopularRouteTags();
      if (mounted) setState(() => _popularTags = tags);
    } catch (_) {}
```

`catch (_) {}` — no `debugPrint`, no stack trace. Per conventions.md this is a banned pattern. Since this is a non-critical UI enhancement (the popular tags row simply doesn't appear), a `debugPrint` is sufficient:

```diff
-   } catch (_) {}
+   } catch (e) { debugPrint('fetchPopularRouteTags failed: $e'); }
```

---

**P2-7: `sign_in_screen.dart` — no form validation before submitting empty credentials**

- `apps/mobile_android/lib/screens/sign_in_screen.dart:31-47`

`_signIn` calls `api.signIn(email: ..., password: ...)` with whatever is in the controllers, including empty strings. An empty email submit hits the network, receives a Supabase auth error, and renders it raw: `"AuthException: Invalid login credentials"`. There is no client-side check that the fields are non-empty before making the network call. This is minor (the network call just fails gracefully) but the UX is poor — the user should see "Email is required" before the round-trip.

Add a simple guard at the top of `_signIn`:

```dart
if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
  setState(() => _error = 'Email and password are required');
  return;
}
```

---

**P2-8: `collapsible_panel.dart` drag-handle touch target is 28px — below the 48dp minimum**

- `apps/mobile_android/lib/widgets/collapsible_panel.dart:65-76`

```dart
              child: SizedBox(
                height: 28,        // 28px
```

The entire interactive drag/tap handle is 28 pixels tall. Android's minimum recommended touch target is 48dp. The visual pill is only 4px tall (`height: 4`) inside the 28px `SizedBox`. A user trying to collapse the panel by tapping the handle has a narrow target, particularly problematic for users with motor impairment. The `GestureDetector` has `behavior: HitTestBehavior.opaque` which helps (the entire 28px area is tappable), but 28px is still below the 48dp recommendation.

Increase the `SizedBox` height to at least 48:

```diff
-               child: SizedBox(
-                 height: 28,
+               child: SizedBox(
+                 height: 48,
```

---

**P2-9: Architecture guard tests for offline-resilience pattern are absent — the migrated screens are unprotected**

- `apps/mobile_android/test/architecture_guards_test.dart` (whole file)

The `architecture_guards_test.dart` file has guards for `run_screen.dart`, `local_run_store.dart`, `sync_service.dart`, and `main.dart`. There are no guards pinning the resilience pattern introduced in `a3116ec`. Currently, a future edit could silently revert any of the migrated screens to a silent-catch shape — the same regression that necessitated `3d3ea75` in the first place — and no test would catch it.

Add guards for the screens changed in `a3116ec`. For each, assert that (1) the source does not contain `catch (_)` (bare swallow), and (2) `kBackendLoadTimeout` is referenced. A minimal guard per screen is sufficient:

```dart
test('clubs_screen uses kBackendLoadTimeout', () {
  final source = File('lib/screens/clubs_screen.dart').readAsStringSync();
  expect(source, contains('kBackendLoadTimeout'));
  expect(source, isNot(contains('catch (_)')));
});
```

The same should cover `plans_screen.dart`, `plan_detail_screen.dart`, `workout_detail_screen.dart`, `club_detail_screen.dart`, `event_detail_screen.dart`, and `explore_routes_screen.dart`.

---

### P3 — nits

**P3-1: `onboarding_screen.dart` uses `withOpacity` on the dot indicator**

- `apps/mobile_android/lib/screens/onboarding_screen.dart:127`

```dart
                      : theme.colorScheme.outline.withOpacity(0.3),
```

Convert to `.withValues(alpha: 0.3)` in the same sweep as P2-2 and P2-3.

---

**P3-2: `run_detail_screen.dart` has an empty line before a closing brace in `_DashboardScreenState`**

- `apps/mobile_android/lib/screens/dashboard_screen.dart:313-314`

```dart
  }


  static String _formatDuration(Duration d) {
```

Double blank line between end of `_isRunActivity` and start of `_formatDuration`. Trivial.

---

**P3-3: `period_summary_screen.dart` `_PeriodShareSheet._shareText` does not use `await`**

- `apps/mobile_android/lib/screens/period_summary_screen.dart:623-625`

```dart
  void _shareText() {
    Share.share(widget.shareText);
  }
```

`Share.share` returns a `Future`. Not awaiting it means any error from the share plugin is silently discarded. Mark the method `async` and `await` the call, or add error handling:

```diff
-  void _shareText() {
-    Share.share(widget.shareText);
-  }
+  Future<void> _shareText() async {
+    try {
+      await Share.share(widget.shareText);
+    } catch (e) {
+      debugPrint('Share.share failed: $e');
+    }
+  }
```

---

**P3-4: `settings_screen.dart` backup subtitle references "web or Android" which may become stale**

- `apps/mobile_android/lib/screens/settings_screen.dart:434`

```dart
              subtitle: const Text(
                'Every run with its GPS trace, plus routes, profile, and preferences. '
                'Restores on web or Android.',
              ),
```

Platform-specific text in a hardcoded string is a maintenance hazard. Not urgent, but worth noting for the next iOS / Watch pass.

---

**P3-5: `_WelcomeEmpty` in `dashboard_screen.dart` is not scrollable on small screens**

- `apps/mobile_android/lib/screens/dashboard_screen.dart:326-356`

`_WelcomeEmpty` is a `Center` with a `Column`. It has no scrolling. On a small-screen device or with a very large system font size, the column can overflow. Wrapping the `Column` in a `SingleChildScrollView` is the correct fix.

---

## Stats
- P0: 1
- P1: 8
- P2: 9
- P3: 5
